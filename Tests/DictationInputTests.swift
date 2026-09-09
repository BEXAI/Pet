import AppKit
import Darwin
import SwiftTerm
import XCTest

@testable import PetTerminal

private final class DictationInputProbe: TerminalViewDelegate {
    var bytes: [UInt8] = []
    var clipboardReads = 0
    var clipboardWrites = 0

    func send(source: TerminalView, data: ArraySlice<UInt8>) { bytes.append(contentsOf: data) }
    func clipboardRead(source: TerminalView) -> Data? {
        clipboardReads += 1
        return Data("not dictation".utf8)
    }
    func clipboardCopy(source: TerminalView, content: Data) { clipboardWrites += 1 }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

private final class DictationProcessProbe: LocalProcessTerminalViewDelegate {
    weak var upstream: LocalProcessTerminalViewDelegate?
    var onTitle: ((String) -> Void)?

    init(upstream: LocalProcessTerminalViewDelegate) { self.upstream = upstream }
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        upstream?.sizeChanged(source: source, newCols: newCols, newRows: newRows)
    }
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        upstream?.setTerminalTitle(source: source, title: title)
        onTitle?(title)
    }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        upstream?.hostCurrentDirectoryUpdate(source: source, directory: directory)
    }
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        upstream?.processTerminated(source: source, exitCode: exitCode)
    }
}

final class DictationInputTests: XCTestCase {
    @MainActor func testDictationUsesInputDelegateWithoutClipboardOrReturn() {
        let terminal = EmberTerminal(frame: CGRect(x: 0, y: 0, width: 560, height: 340))
        let probe = DictationInputProbe()
        let policy = TerminalOutputPolicy(upstream: probe)
        terminal.terminalDelegate = policy

        XCTAssertTrue(terminal.insertDictatedText("  café 👩🏽‍💻\r\n日本語\t e\u{301}  "))
        XCTAssertEqual(String(decoding: probe.bytes, as: UTF8.self), "café 👩🏽‍💻 日本語 e\u{301}")
        XCTAssertFalse(probe.bytes.contains(0x0d))
        XCTAssertFalse(probe.bytes.contains(0x0a))
        XCTAssertEqual(probe.clipboardReads, 0)
        XCTAssertEqual(probe.clipboardWrites, 0)
    }

    @MainActor func testDictationHonorsLiveBracketedPasteMode() {
        let terminal = EmberTerminal(frame: CGRect(x: 0, y: 0, width: 560, height: 340))
        let probe = DictationInputProbe()
        let policy = TerminalOutputPolicy(upstream: probe)
        terminal.terminalDelegate = policy

        terminal.feed(text: "\u{1b}[?2004h")
        XCTAssertTrue(terminal.insertDictatedText("first\nsecond"))
        XCTAssertEqual(String(decoding: probe.bytes, as: UTF8.self), "\u{1b}[200~first second\u{1b}[201~")
        probe.bytes.removeAll()

        terminal.feed(text: "\u{1b}[?2004l")
        XCTAssertTrue(terminal.insertDictatedText("third"))
        XCTAssertEqual(String(decoding: probe.bytes, as: UTF8.self), "third")
        probe.bytes.removeAll()
        XCTAssertFalse(terminal.insertDictatedText(" \r\n\t\u{0} "))
        XCTAssertTrue(probe.bytes.isEmpty)
    }

    func testTranscriptCannotSupplyTerminalControlsOrPasteTerminator() {
        let controls =
            (0...0x1f).map { String(UnicodeScalar($0)!) }.joined()
            + (0x7f...0x9f).map { String(UnicodeScalar($0)!) }.joined()
        let text = DictationInput.singleLine("one" + controls + "two\u{2028}three\u{2029}four")
        XCTAssertEqual(text, "one two three four")
        let escaped = DictationInput.bytes(for: "hello\u{1b}[201~there", bracketedPaste: true)
        XCTAssertEqual(String(decoding: escaped, as: UTF8.self), "\u{1b}[200~hello [201~there\u{1b}[201~")
        XCTAssertEqual(escaped.filter { $0 == 0x1b }.count, 2, "Only application-owned paste markers may contain ESC")
    }

    func testCaptureCanOnlyInsertOnceIntoMatchingFocusedJob() {
        let target = DictationInsertionTarget(generation: 7, shellPID: 101, foregroundGroup: 103)
        var gate = DictationInsertionGate()
        gate.begin(target: target)

        XCTAssertFalse(gate.consume(current: nil, canReceiveInput: true))
        XCTAssertFalse(gate.consume(current: target, canReceiveInput: false))
        XCTAssertFalse(
            gate.consume(
                current: DictationInsertionTarget(generation: 7, shellPID: 101, foregroundGroup: 104),
                canReceiveInput: true))
        XCTAssertFalse(
            gate.consume(
                current: DictationInsertionTarget(generation: 8, shellPID: 101, foregroundGroup: 103),
                canReceiveInput: true), "A replaced session must be rejected even if macOS reuses its process IDs")
        XCTAssertFalse(
            gate.consume(
                current: DictationInsertionTarget(generation: 7, shellPID: 102, foregroundGroup: 103),
                canReceiveInput: true))
        XCTAssertTrue(gate.consume(current: target, canReceiveInput: true))
        XCTAssertFalse(
            gate.consume(current: target, canReceiveInput: true), "Duplicate completion must not insert twice")
    }

    func testInterruptedCaptureRequiresExplicitNewInsertionTarget() {
        let old = DictationInsertionTarget(generation: 2, shellPID: 201, foregroundGroup: 201)
        let replacement = DictationInsertionTarget(generation: 3, shellPID: 301, foregroundGroup: 301)
        var gate = DictationInsertionGate()
        gate.begin(target: old)
        gate.invalidate()
        XCTAssertFalse(gate.consume(current: old, canReceiveInput: true))
        XCTAssertFalse(gate.consume(current: replacement, canReceiveInput: true))
        gate.begin(target: replacement)
        XCTAssertFalse(gate.consume(current: old, canReceiveInput: true))
        XCTAssertTrue(gate.consume(current: replacement, canReceiveInput: true))
    }

    @MainActor func testDictatedCommandWaitsForExplicitReturnInRealPTY() {
        let controller = TerminalController(
            directory: URL(fileURLWithPath: "/private/tmp"), size: CGSize(width: 560, height: 340))
        let probe = DictationProcessProbe(upstream: controller)
        controller.terminal.processDelegate = probe
        controller.start(shellArguments: ["-f"])
        let pid = controller.terminal.process.shellPid
        XCTAssertGreaterThan(pid, 0)
        defer {
            let stopped = expectation(description: "isolated dictation shell reaped")
            controller.stop { stopped.fulfill() }
            wait(for: [stopped], timeout: 3)
            XCTAssertEqual(kill(pid, 0), -1)
        }

        let ready = expectation(description: "isolated shell is ready")
        let premature = expectation(description: "dictated command must not execute without Return")
        premature.isInverted = true
        let executed = expectation(description: "command executes after explicit Return")
        var sentReturn = false
        var sawReady = false
        var sawExecution = false
        probe.onTitle = { title in
            if title == "DICTATION-READY", !sawReady {
                sawReady = true
                ready.fulfill()
            }
            if title == "DICTATION-EXECUTED", !sawExecution {
                sawExecution = true
                if sentReturn { executed.fulfill() } else { premature.fulfill() }
            }
        }
        // A title escape emitted by printf proves execution without reading or logging
        // terminal contents, and cannot be confused with the shell echoing the command.
        controller.terminal.send(txt: "printf '\\033]0;DICTATION-READY\\007'\r")
        wait(for: [ready], timeout: 5)
        XCTAssertTrue(controller.terminal.insertDictatedText("printf '\\033]0;DICTATION-EXECUTED\\007'"))
        wait(for: [premature], timeout: 0.4)
        XCTAssertFalse(sawExecution)
        sentReturn = true
        controller.terminal.send(txt: "\r")
        wait(for: [executed], timeout: 5)
    }
}
