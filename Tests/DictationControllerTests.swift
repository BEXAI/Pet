import AVFoundation
import CoreMedia
import Speech
import XCTest

@testable import PetTerminal

@MainActor private final class FakeDictationSession: DictationSession {
    var onTranscript: ((String) -> Void)?
    var onFailure: ((Error) -> Void)?
    var holdPreparation = false
    var holdFinalization = false
    var preparation: CheckedContinuation<Void, Error>?
    var finalization: CheckedContinuation<String, Error>?
    var finalText = "Final words"
    var stopped = false
    var cancelled = false
    var preparing = false
    var finalizing = false

    func prepare(
        onStatus: @escaping (String) -> Void,
        onTranscript: @escaping (String) -> Void,
        onFailure: @escaping (Error) -> Void
    ) async throws {
        self.onTranscript = onTranscript
        self.onFailure = onFailure
        preparing = true
        onStatus("Preparing test session")
        if holdPreparation { try await withCheckedThrowingContinuation { preparation = $0 } }
    }
    func stopCapture() { stopped = true }
    func finish() async throws -> String {
        finalizing = true
        if holdFinalization { return try await withCheckedThrowingContinuation { finalization = $0 } }
        return finalText
    }
    func cancel() {
        cancelled = true
        stopped = true
    }
}

@MainActor final class DictationControllerTests: XCTestCase {
    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("The expected state transition did not occur", file: file, line: line)
    }

    func testPreviewNeverInsertsAndFinalizationDeliversExactlyOnce() async {
        let session = FakeDictationSession()
        let controller = DictationController(makeSession: { session })
        var inserted: [String] = []
        controller.onFinalText = { inserted.append($0) }
        controller.start()
        await eventually { controller.state == .listening }
        session.onTranscript?("Interim words")
        XCTAssertEqual(controller.transcript, "Interim words")
        XCTAssertTrue(inserted.isEmpty)
        controller.stopAndInsert()
        XCTAssertTrue(session.stopped, "Stop must release the microphone synchronously")
        controller.stopAndInsert()
        await eventually { inserted == ["Final words"] }
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.transcript, "")
        session.onTranscript?("Late callback")
        controller.insertDraft()
        XCTAssertEqual(inserted, ["Final words"])
        XCTAssertEqual(controller.transcript, "")
    }

    func testCancelledPreparationCannotResumeOrPublish() async {
        let session = FakeDictationSession()
        session.holdPreparation = true
        let controller = DictationController(makeSession: { session })
        controller.start()
        await eventually { session.preparation != nil }
        controller.cancel()
        session.onTranscript?("Stale words")
        session.onFailure?(NSError(domain: "test", code: 1))
        session.preparation?.resume()
        session.preparation = nil
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.transcript, "")
        XCTAssertTrue(session.cancelled)
    }

    func testInterruptedFinalizationKeepsPreviewWithoutLateInsertion() async {
        let session = FakeDictationSession()
        session.holdFinalization = true
        let controller = DictationController(makeSession: { session })
        var inserted: [String] = []
        controller.onFinalText = { inserted.append($0) }
        controller.start()
        await eventually { controller.state == .listening }
        session.onTranscript?("Keep this draft")
        controller.stopAndInsert()
        await eventually { session.finalization != nil }
        controller.interrupt()
        session.finalization?.resume(returning: "Late final text")
        session.finalization = nil
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(controller.state, .draft)
        XCTAssertEqual(controller.transcript, "Keep this draft")
        XCTAssertTrue(inserted.isEmpty)
        controller.insertDraft()
        controller.insertDraft()
        XCTAssertEqual(inserted, ["Keep this draft"])
    }

    func testDestinationCanRefuseInsertionWithoutLosingTranscript() async {
        let session = FakeDictationSession()
        let controller = DictationController(makeSession: { session })
        controller.onFinalText = { _ in controller.interrupt() }
        controller.start()
        await eventually { controller.state == .listening }
        controller.stopAndInsert()
        await eventually { controller.state == .draft }
        XCTAssertEqual(controller.transcript, "Final words")
        var inserted: [String] = []
        controller.onFinalText = { inserted.append($0) }
        controller.insertDraft()
        XCTAssertEqual(inserted, ["Final words"])
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.transcript, "")
        controller.onFinalText = nil
    }

    func testRecognitionFailureStopsCaptureAndRetainsPreview() async {
        let session = FakeDictationSession()
        let controller = DictationController(makeSession: { session })
        controller.start()
        await eventually { controller.state == .listening }
        session.onTranscript?("Recoverable text")
        session.onFailure?(NSError(domain: "test", code: 2))
        guard case .failed = controller.state else { return XCTFail("Expected a visible error") }
        XCTAssertTrue(session.stopped)
        XCTAssertEqual(controller.transcript, "Recoverable text")
        XCTAssertFalse(controller.isBusy)
        controller.cancel()
        XCTAssertEqual(controller.transcript, "")
    }
}

final class DictationAudioTests: XCTestCase {
    func testCapturedAudioOwnsItsSamples() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let source = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128))
        source.frameLength = 128
        source.floatChannelData![0][0] = 0.5
        let captured = try CapturedAudio(copying: source)
        source.floatChannelData![0][0] = -0.5
        XCTAssertEqual(captured.buffer.floatChannelData![0][0], 0.5)
        XCTAssertEqual(captured.buffer.frameLength, 128)
    }

    func testResamplingDrainsAndFiniteInputReachesEOF() async throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("SpeechAnalyzer requires macOS 26") }
        let sourceFormat = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let targetFormat = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let (stream, continuation) = AsyncThrowingStream<CapturedAudio, Error>.makeStream(
            bufferingPolicy: .bufferingOldest(8))
        for chunk in 0..<4 {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 480))
            buffer.frameLength = 480
            for index in 0..<480 {
                buffer.floatChannelData![0][index] = sin(Float(chunk * 480 + index) * 0.05) * 0.1
            }
            continuation.yield(try CapturedAudio(copying: buffer))
        }
        continuation.finish()
        var iterator = ConvertedAudioSequence(
            source: stream, conversion: try AudioConversion(from: sourceFormat, to: targetFormat)
        ).makeAsyncIterator()
        var totalFrames: UInt32 = 0
        var outputBuffers = 0
        while let input = try await iterator.next() {
            totalFrames += input.buffer.frameLength
            outputBuffers += 1
            XCTAssertEqual(input.buffer.format.sampleRate, 16_000)
            XCTAssertGreaterThan(input.buffer.frameLength, 0)
            if outputBuffers > 20 {
                XCTFail("The converter never reached EOF")
                break
            }
        }
        XCTAssertLessThanOrEqual(abs(Int(totalFrames) - 640), 4)
        let end = try await iterator.next()
        XCTAssertNil(end)
    }

    func testTimedRevisionsReplaceTextWithoutDroppingUnchangedVolatileResults() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("SpeechAnalyzer requires macOS 26") }
        var transcript = TimedTranscript()
        let first = CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 1000))
        let second = CMTimeRange(start: first.end, duration: first.duration)
        transcript.replace(range: first, with: AttributedString("Wrong"))
        transcript.replace(range: first, with: AttributedString("Hello"))
        transcript.replace(range: second, with: AttributedString(" world"))
        XCTAssertEqual(transcript.string, "Hello world")
        transcript.replace(range: second, with: AttributedString(" world!"))
        XCTAssertEqual(transcript.string, "Hello world!")
    }

    func testPartialTimedRevisionPreservesEarlierWords() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("SpeechAnalyzer requires macOS 26") }
        let firstRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 1000))
        let secondRange = CMTimeRange(start: firstRange.end, duration: firstRange.duration)
        var first = AttributedString("Hello ")
        first.audioTimeRange = firstRange
        var second = AttributedString("world")
        second.audioTimeRange = secondRange
        var revised = AttributedString("universe")
        revised.audioTimeRange = secondRange
        var transcript = TimedTranscript()
        transcript.replace(range: CMTimeRange(start: .zero, end: secondRange.end), with: first + second)
        transcript.replace(range: secondRange, with: revised)
        XCTAssertEqual(transcript.string, "Hello universe")
    }
}
