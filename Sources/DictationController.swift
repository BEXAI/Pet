import AVFoundation
import AppKit
import Foundation
import Speech

/// Kept separate from microphone hardware so cancellation and delivery can be tested without recording.
@MainActor protocol DictationSession: AnyObject {
    var requestingMicrophonePermission: Bool { get }
    func prepare(
        onStatus: @escaping (String) -> Void,
        onTranscript: @escaping (String) -> Void,
        onFailure: @escaping (Error) -> Void
    ) async throws
    func stopCapture()
    func finish() async throws -> String
    func cancel()
}

extension DictationSession {
    var requestingMicrophonePermission: Bool { false }
}

@MainActor final class DictationController {
    enum State: Equatable {
        case idle, preparing, listening, finalizing, draft
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var transcript = ""
    private(set) var statusText = "Dictate into this terminal"
    var onUpdate: (() -> Void)?
    var onFinalText: ((String) -> Void)?
    var isBusy: Bool { state == .preparing || state == .listening || state == .finalizing }
    var isRequestingMicrophonePermission: Bool { session?.requestingMicrophonePermission ?? false }

    private let makeSession: () throws -> any DictationSession
    private var session: (any DictationSession)?
    private var task: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var generation = UUID()

    init(makeSession: (() throws -> any DictationSession)? = nil) {
        self.makeSession =
            makeSession ?? {
                guard #available(macOS 26.0, *) else {
                    throw DictationFailure("On-device dictation requires macOS 26 or later.")
                }
                return NativeDictationSession()
            }
    }

    deinit {
        task?.cancel()
        timeout?.cancel()
        let recording = session
        Task { @MainActor in recording?.cancel() }
    }

    func start() {
        guard !isBusy else { return }
        invalidate()
        transcript = ""
        state = .preparing
        statusText = "Preparing on-device dictation…"
        onUpdate?()
        let token = generation
        do {
            let recording = try makeSession()
            session = recording
            task = Task { [weak self] in
                do {
                    try await recording.prepare(
                        onStatus: { [weak self] message in
                            guard let self, self.generation == token else { return }
                            self.statusText = message
                            self.onUpdate?()
                        },
                        onTranscript: { [weak self] text in
                            guard let self, self.generation == token else { return }
                            self.transcript = text
                            self.onUpdate?()
                        },
                        onFailure: { [weak self] error in self?.fail(error, token: token) })
                    guard let self, self.generation == token else {
                        recording.cancel()
                        return
                    }
                    self.task = nil
                    self.state = .listening
                    self.statusText = "Listening — click the microphone to stop and insert"
                    self.onUpdate?()
                } catch {
                    recording.cancel()
                    self?.fail(error, token: token)
                }
            }
        } catch { fail(error, token: token) }
    }

    func stopAndInsert() {
        guard state == .listening, let recording = session else { return }
        recording.stopCapture()
        state = .finalizing
        statusText = "Finishing transcription…"
        onUpdate?()
        let token = generation
        // A failed service must not leave the controls stuck in Finalizing.
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            self?.fail(
                DictationFailure("Transcription took too long. Your preview is available as a draft."), token: token)
        }
        task = Task { [weak self] in
            do {
                let text = try await recording.finish()
                guard let self, self.generation == token else { return }
                self.transcript = text
                self.invalidate()
                self.deliver()
            } catch { self?.fail(error, token: token) }
        }
    }

    func cancel() {
        invalidate()
        transcript = ""
        state = .idle
        statusText = "Dictation cancelled"
        onUpdate?()
    }

    /// Interruptions never insert into a terminal that may have changed while recording.
    func interrupt() {
        invalidate()
        state = transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .idle : .draft
        statusText = state == .draft ? "Draft kept — return to the terminal to insert" : "Dictation stopped"
        onUpdate?()
    }

    func insertDraft() {
        guard !isBusy, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        invalidate()
        deliver()
    }

    private func deliver() {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .idle
            statusText = "No speech detected — try again"
            onUpdate?()
            return
        }
        guard let onFinalText else {
            state = .draft
            statusText = "Transcript ready to insert"
            onUpdate?()
            return
        }
        // The destination checks synchronously. It can call interrupt() to retain this draft.
        state = .idle
        onFinalText(transcript)
        if state == .idle {
            transcript = ""
            statusText = "Text inserted — press Return in the terminal when ready"
            onUpdate?()
        }
    }

    private func fail(_ error: Error, token: UUID) {
        guard generation == token else { return }
        invalidate()
        let message = (error as? DictationFailure)?.message ?? "Dictation stopped: \(error.localizedDescription)"
        state = .failed(message)
        statusText = message
        onUpdate?()
    }

    private func invalidate() {
        generation = UUID()
        task?.cancel()
        task = nil
        timeout?.cancel()
        timeout = nil
        session?.cancel()
        session = nil
    }
}

private struct DictationFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@available(macOS 26.0, *)
@MainActor private final class NativeDictationSession: DictationSession {
    private static var cleanupTask: Task<Void, Never>?
    private(set) var requestingMicrophonePermission = false
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Error>?
    private var progressTask: Task<Void, Never>?
    private var inputContinuation: AsyncThrowingStream<CapturedAudio, Error>.Continuation?
    private var installationProgress: Progress?
    private var configurationObserver: NSObjectProtocol?
    private var reservedLocale: Locale?
    private var tapInstalled = false
    private var cancelled = false
    private var text = TimedTranscript()

    func prepare(
        onStatus: @escaping (String) -> Void,
        onTranscript: @escaping (String) -> Void,
        onFailure: @escaping (Error) -> Void
    ) async throws {
        do {
            await Self.cleanupTask?.value
            try checkActive()
            guard SpeechTranscriber.isAvailable else {
                throw DictationFailure("On-device speech transcription is unavailable on this Mac.")
            }
            onStatus("Allow microphone access to start dictation…")
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: allowed = true
            case .notDetermined:
                requestingMicrophonePermission = true
                allowed = await AVCaptureDevice.requestAccess(for: .audio)
                requestingMicrophonePermission = false
            default: allowed = false
            }
            try checkActive()
            guard allowed else {
                throw DictationFailure("Enable Pet Terminal in System Settings → Privacy & Security → Microphone.")
            }
            var locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current)
            if locale == nil {
                locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
            }
            try checkActive()
            guard let locale else { throw DictationFailure("No supported speech language is available on this Mac.") }
            let language = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
            onStatus("Preparing \(language) speech model…")
            let transcriber = SpeechTranscriber(
                locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults],
                attributeOptions: [.audioTimeRange])
            let reserved = await AssetInventory.reservedLocales
            if !reserved.contains(locale) {
                if try await AssetInventory.reserve(locale: locale) { reservedLocale = locale }
            }
            try checkActive()
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try checkActive()
                installationProgress = request.progress
                onStatus("Downloading \(language) speech model…")
                progressTask = Task { [weak self] in
                    while !Task.isCancelled {
                        guard self?.cancelled == false else { return }
                        let percent = Int(max(0, min(1, request.progress.fractionCompleted)) * 100)
                        onStatus("Downloading \(language) speech model — \(percent)%")
                        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                    }
                }
                try await request.downloadAndInstall()
                progressTask?.cancel()
                progressTask = nil
                installationProgress = nil
            }
            try checkActive()
            let input = engine.inputNode
            let naturalFormat = input.outputFormat(forBus: 0)
            guard naturalFormat.sampleRate > 0, naturalFormat.channelCount > 0 else {
                throw DictationFailure("No microphone is available. Connect one and try again.")
            }
            guard
                let format = await SpeechAnalyzer.bestAvailableAudioFormat(
                    compatibleWith: [transcriber], considering: naturalFormat)
            else { throw DictationFailure("The microphone audio format is unsupported.") }
            try checkActive()
            let conversion = try AudioConversion(from: naturalFormat, to: format)
            let analyzer = SpeechAnalyzer(
                modules: [transcriber], options: .init(priority: .userInitiated, modelRetention: .whileInUse))
            self.analyzer = analyzer
            onStatus("Starting \(language) dictation…")
            try await analyzer.prepareToAnalyze(in: format)
            try checkActive()
            let (stream, continuation) = AsyncThrowingStream<CapturedAudio, Error>.makeStream(
                bufferingPolicy: .bufferingOldest(64))
            inputContinuation = continuation
            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        try Task.checkCancellation()
                        guard let self, !self.cancelled else { return }
                        self.text.replace(range: result.range, with: result.text)
                        onTranscript(self.text.string)
                    }
                } catch {
                    if !Task.isCancelled { onFailure(error) }
                    throw error
                }
            }
            try await analyzer.start(inputSequence: ConvertedAudioSequence(source: stream, conversion: conversion))
            try checkActive()
            guard NSApp.isActive else {
                throw DictationFailure("Return to the terminal and click the microphone to start dictation.")
            }
            // The tap copies into an explicitly bounded stream. Backlog stops dictation rather
            // than silently dropping words or accumulating an unlimited amount of audio.
            input.installTap(onBus: 0, bufferSize: 1024, format: naturalFormat) { buffer, _ in
                do {
                    let copy = try CapturedAudio(copying: buffer)
                    if case .dropped = continuation.yield(copy) {
                        throw DictationFailure("Audio processing fell behind. Try a shorter dictation.")
                    }
                } catch {
                    continuation.finish(throwing: error)
                    Task { @MainActor in onFailure(error) }
                }
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { _ in
                Task { @MainActor in onFailure(DictationFailure("The microphone changed. Your preview has been kept."))
                }
            }
        } catch {
            cancel()
            throw error
        }
    }

    func stopCapture() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        inputContinuation?.finish()
        inputContinuation = nil
    }

    func finish() async throws -> String {
        stopCapture()
        guard let analyzer else { throw DictationFailure("The dictation session did not start.") }
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await resultsTask?.value
        try checkActive()
        return text.string
    }

    func cancel() {
        cancelled = true
        stopCapture()
        resultsTask?.cancel()
        resultsTask = nil
        progressTask?.cancel()
        progressTask = nil
        installationProgress?.cancel()
        installationProgress = nil
        let analyzer = analyzer
        self.analyzer = nil
        let locale = reservedLocale
        reservedLocale = nil
        let previousCleanup = Self.cleanupTask
        Self.cleanupTask = Task {
            await previousCleanup?.value
            await analyzer?.cancelAndFinishNow()
            if let locale { await AssetInventory.release(reservedLocale: locale) }
        }
    }

    private func checkActive() throws {
        try Task.checkCancellation()
        if cancelled { throw CancellationError() }
    }
}

struct CapturedAudio: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    init(copying source: AVAudioPCMBuffer) throws {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else {
            throw DictationFailure("The microphone buffer could not be allocated.")
        }
        buffer.frameLength = source.frameLength
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for (sourceBuffer, destination) in zip(sourceBuffers, destinationBuffers) {
            guard let sourceData = sourceBuffer.mData, let destinationData = destination.mData else {
                throw DictationFailure("The microphone returned an empty audio buffer.")
            }
            memcpy(destinationData, sourceData, Int(sourceBuffer.mDataByteSize))
        }
        self.buffer = buffer
    }
}

/// Used only by one sequence iterator; AVAudioConverter is never shared between consumers.
final class AudioConversion: @unchecked Sendable {
    let format: AVAudioFormat
    private let converter: AVAudioConverter?
    private let ratio: Double
    init(from source: AVAudioFormat, to destination: AVAudioFormat) throws {
        format = destination
        ratio = destination.sampleRate / source.sampleRate
        if source == destination {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: source, to: destination) else {
                throw DictationFailure("The microphone audio could not be converted for speech recognition.")
            }
            self.converter = converter
        }
    }
    func convert(_ input: AVAudioPCMBuffer?) throws -> AVAudioPCMBuffer? {
        guard let converter else { return input }
        let capacity = input.map { AVAudioFrameCount(ceil(Double($0.frameLength) * ratio)) + 256 } ?? 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw DictationFailure("The speech audio buffer could not be allocated.")
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, status in
            guard let input else {
                status.pointee = .endOfStream
                return nil
            }
            guard !supplied else {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        guard status != .error else { throw DictationFailure("Microphone audio conversion failed.") }
        return output.frameLength > 0 ? output : nil
    }
}

@available(macOS 26.0, *)
struct ConvertedAudioSequence: AsyncSequence, Sendable {
    typealias Element = AnalyzerInput
    let source: AsyncThrowingStream<CapturedAudio, Error>
    let conversion: AudioConversion
    func makeAsyncIterator() -> Iterator { Iterator(source: source.makeAsyncIterator(), conversion: conversion) }
    struct Iterator: AsyncIteratorProtocol {
        var source: AsyncThrowingStream<CapturedAudio, Error>.Iterator
        let conversion: AudioConversion
        var ended = false
        mutating func next() async throws -> AnalyzerInput? {
            while !ended {
                if let audio = try await source.next() {
                    if let converted = try conversion.convert(audio.buffer) { return AnalyzerInput(buffer: converted) }
                } else {
                    ended = true
                }
            }
            // Drain the resampler's final samples after microphone input ends.
            return try conversion.convert(nil).map { AnalyzerInput(buffer: $0) }
        }
    }
}

@available(macOS 26.0, *)
struct TimedTranscript {
    private struct Part {
        var range: CMTimeRange
        var text: AttributedString
    }
    private var parts: [Part] = []
    var string: String { parts.map { String($0.text.characters) }.joined() }

    mutating func replace(range: CMTimeRange, with text: AttributedString) {
        var retained: [Part] = []
        for part in parts {
            let intersection = CMTimeRangeGetIntersection(part.range, otherRange: range)
            guard intersection.duration.seconds > 0 || CMTimeCompare(part.range.start, range.start) == 0 else {
                retained.append(part)
                continue
            }
            // Word timestamps preserve unaffected words if a revision overlaps only part
            // of an earlier result. A final result need not be reissued after a volatile one.
            if let overlap = part.text.rangeOfAudioTimeRangeAttributes(intersecting: range) {
                if overlap.lowerBound > part.text.startIndex {
                    retained.append(
                        Part(
                            range: CMTimeRange(start: part.range.start, end: range.start),
                            text: AttributedString(part.text[..<overlap.lowerBound])))
                }
                if overlap.upperBound < part.text.endIndex {
                    retained.append(
                        Part(
                            range: CMTimeRange(start: range.end, end: part.range.end),
                            text: AttributedString(part.text[overlap.upperBound...])))
                }
            }
        }
        retained.append(Part(range: range, text: text))
        parts = retained.sorted { CMTimeCompare($0.range.start, $1.range.start) < 0 }
    }
}
