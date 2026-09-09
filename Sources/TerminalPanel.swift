import AppKit
import Darwin
import SwiftTerm

enum DictationInput {
    /// Dictation inserts prose, never terminal controls or an implicit Return.
    static func singleLine(_ text: String) -> String {
        var result = ""
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar)
                || scalar.value < 0x20 || (0x7f...0x9f).contains(scalar.value)
            {
                pendingSpace = !result.isEmpty
                continue
            }
            if pendingSpace { result.append(" ") }
            result.unicodeScalars.append(scalar)
            pendingSpace = false
        }
        return result
    }

    static func bytes(for text: String, bracketedPaste: Bool) -> [UInt8] {
        let text = singleLine(text)
        guard !text.isEmpty else { return [] }
        let bytes = Array(text.utf8)
        return bracketedPaste
            ? EscapeSequences.bracketedPasteStart + bytes + EscapeSequences.bracketedPasteEnd : bytes
    }
}

struct DictationInsertionTarget: Equatable {
    let generation: UInt64
    let shellPID: Int32
    let foregroundGroup: Int32
}

struct DictationInsertionGate {
    private(set) var target: DictationInsertionTarget?

    mutating func begin(target: DictationInsertionTarget) { self.target = target }
    mutating func invalidate() { target = nil }

    /// A capture can insert once, into the same visible, focused terminal job.
    mutating func consume(current: DictationInsertionTarget?, canReceiveInput: Bool) -> Bool {
        guard let target, target == current, canReceiveInput else { return false }
        self.target = nil
        return true
    }
}

enum EmberStyle {
    static var border: NSColor { PetDefinition.current.terminal.border.color }
    static var glow: NSColor { PetDefinition.current.terminal.glow.color }
    static var text: NSColor { PetDefinition.current.terminal.text.color }
    static var background: NSColor { PetDefinition.current.terminal.background.color }
}

final class TerminalPanel: NSPanel {
    var onCancelDictation: (() -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53, onCancelDictation?() == true { return }
        super.sendEvent(event)
    }
}

final class NeonChrome: NSView {
    var resizeFrom: (CGPoint, CGRect)?
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        let rect = bounds.insetBy(dx: 10, dy: 10)
        let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = EmberStyle.glow.withAlphaComponent(0.85)
        glow.shadowBlurRadius = 12
        glow.shadowOffset = .zero
        glow.set()
        EmberStyle.background.setFill()
        path.fill()
        EmberStyle.border.setStroke()
        path.lineWidth = 1.7
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
        EmberStyle.border.withAlphaComponent(0.75).setStroke()
        let line = NSBezierPath()
        line.move(to: CGPoint(x: 24, y: bounds.height - 56))
        line.line(to: CGPoint(x: bounds.width - 24, y: bounds.height - 56))
        line.lineWidth = 0.7
        line.stroke()
        let grip = NSBezierPath()
        grip.move(to: CGPoint(x: bounds.width - 30, y: 18))
        grip.line(to: CGPoint(x: bounds.width - 18, y: 30))
        grip.move(to: CGPoint(x: bounds.width - 24, y: 18))
        grip.line(to: CGPoint(x: bounds.width - 18, y: 24))
        grip.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if p.x > bounds.width - 38 && p.y < 38, let window {
            resizeFrom = (NSEvent.mouseLocation, window.frame)
        } else if p.y > bounds.height - 56 {
            window?.performDrag(with: event)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let (start, frame) = resizeFrom, let window else { return }
        let mouse = NSEvent.mouseLocation
        let w = max(window.minSize.width, frame.width + mouse.x - start.x)
        let h = max(window.minSize.height, frame.height - (mouse.y - start.y))
        window.setFrame(CGRect(x: frame.minX, y: frame.maxY - h, width: w, height: h), display: true)
    }
    override func mouseUp(with event: NSEvent) { resizeFrom = nil }
}

final class EmberTerminal: LocalProcessTerminalView {
    var onToggleDictation: (() -> Void)?

    // macOS shortcuts stay native while ordinary control keys go to the PTY.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.intersection([.command, .shift, .control, .option]) == [.command, .shift],
            event.charactersIgnoringModifiers?.lowercased() == "d", let onToggleDictation
        {
            onToggleDictation()
            return true
        }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c":
                copy(self)
                return true
            case "v":
                paste(self)
                return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    @discardableResult
    func insertDictatedText(_ text: String) -> Bool {
        let bytes = DictationInput.bytes(for: text, bracketedPaste: getTerminal().bracketedPasteMode)
        guard !bytes.isEmpty else { return false }
        send(data: bytes[...])
        return true
    }
}

// Output from a command (including a remote SSH host or an untrusted file) is
// not user consent to read or replace the system clipboard. Keep this proxy
// separate from the native Copy/Paste actions, which remain user initiated.
final class TerminalOutputPolicy: TerminalViewDelegate {
    private weak var upstream: TerminalViewDelegate?

    init(upstream: TerminalViewDelegate) { self.upstream = upstream }

    func clipboardRead(source: TerminalView) -> Data? { nil }
    func clipboardCopy(source: TerminalView, content: Data) {}

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        upstream?.sizeChanged(source: source, newCols: newCols, newRows: newRows)
    }
    func setTerminalTitle(source: TerminalView, title: String) {
        upstream?.setTerminalTitle(source: source, title: title)
    }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        upstream?.hostCurrentDirectoryUpdate(source: source, directory: directory)
    }
    func send(source: TerminalView, data: ArraySlice<UInt8>) { upstream?.send(source: source, data: data) }
    func scrolled(source: TerminalView, position: Double) { upstream?.scrolled(source: source, position: position) }
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        upstream?.requestOpenLink(source: source, link: link, params: params)
    }
    func bell(source: TerminalView) { upstream?.bell(source: source) }
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {
        upstream?.iTermContent(source: source, content: content)
    }
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        upstream?.rangeChanged(source: source, startY: startY, endY: endY)
    }
}

// SwiftTerm's local view uses LocalProcess's default main queue for output and exit callbacks.
@MainActor final class TerminalController: NSObject, @preconcurrency LocalProcessTerminalViewDelegate {
    let panel: TerminalPanel
    let terminal: EmberTerminal
    let heading = NSTextField(labelWithString: "\(PetDefinition.current.displayName) · Terminal")
    let footer = NSTextField(labelWithString: "zsh · local session")
    let pinButton = NSButton(title: "Pin", target: nil, action: nil)
    let dictation = DictationController()
    var onDictationUpdate: (() -> Void)?
    var onHide: (() -> Void)?
    var onPin: (() -> Void)?
    var onFolder: (() -> Void)?
    var onEnd: (() -> Void)?
    var workingDirectory: URL
    private var started = false
    private var stopping = false
    private let outputPolicy: TerminalOutputPolicy
    private let dictationButton = NSButton(title: "Dictate", target: nil, action: nil)
    private let dictationPreview = NSTextField(labelWithString: "")
    private let dictationCancel = NSButton(title: "Cancel", target: nil, action: nil)
    private let dictationInsert = NSButton(title: "Insert", target: nil, action: nil)
    private var sessionGeneration: UInt64 = 0
    private var insertionGate = DictationInsertionGate()
    private var dictationNotice = ""
    private var dictationPreviewVisible = false

    init(directory: URL, size: CGSize) {
        workingDirectory = directory
        panel = TerminalPanel(
            contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .resizable], backing: .buffered,
            defer: false)
        terminal = EmberTerminal(frame: CGRect(x: 24, y: 42, width: size.width - 48, height: size.height - 108))
        outputPolicy = TerminalOutputPolicy(upstream: terminal)
        super.init()
        terminal.terminalDelegate = outputPolicy
        panel.title = "\(PetDefinition.current.displayName) Terminal"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = CGSize(width: 380, height: 230)
        panel.isMovableByWindowBackground = false
        let chrome = NeonChrome(frame: CGRect(origin: .zero, size: size))
        panel.contentView = chrome
        terminal.autoresizingMask = [.width, .height]
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminal.nativeBackgroundColor = .clear
        terminal.backgroundOpacity = 0
        terminal.nativeForegroundColor = EmberStyle.text
        terminal.caretColor = EmberStyle.text
        terminal.processDelegate = self
        terminal.setAccessibilityLabel("\(PetDefinition.current.displayName) local terminal")
        chrome.addSubview(terminal)
        heading.frame = CGRect(x: 26, y: size.height - 47, width: max(40, size.width - 293), height: 25)
        heading.autoresizingMask = [.width, .minYMargin]
        heading.font = .systemFont(ofSize: 12, weight: .medium)
        heading.textColor = EmberStyle.text
        heading.lineBreakMode = .byTruncatingMiddle
        chrome.addSubview(heading)
        footer.frame = CGRect(x: 26, y: 17, width: size.width - 70, height: 18)
        footer.autoresizingMask = [.width]
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = EmberStyle.text.withAlphaComponent(0.85)
        footer.lineBreakMode = .byTruncatingMiddle
        chrome.addSubview(footer)
        for (index, button) in [
            NSButton(title: "Folder", target: self, action: #selector(folder)), pinButton,
            NSButton(title: "Hide", target: self, action: #selector(hide)),
        ].enumerated() {
            button.frame = CGRect(x: size.width - 216 + CGFloat(index) * 64, y: size.height - 48, width: 60, height: 28)
            button.autoresizingMask = [.minXMargin, .minYMargin]
            button.bezelStyle = .rounded
            button.contentTintColor = EmberStyle.text
            button.isBordered = false
            chrome.addSubview(button)
        }
        pinButton.target = self
        pinButton.action = #selector(pin)
        dictationButton.frame = CGRect(x: size.width - 254, y: size.height - 48, width: 32, height: 28)
        dictationButton.autoresizingMask = [.minXMargin, .minYMargin]
        dictationButton.imagePosition = .imageOnly
        dictationButton.isBordered = false
        dictationButton.contentTintColor = EmberStyle.text
        dictationButton.target = self
        dictationButton.action = #selector(toggleDictation)
        chrome.addSubview(dictationButton)
        dictationPreview.frame = CGRect(x: 26, y: 46, width: max(50, size.width - 192), height: 20)
        dictationPreview.autoresizingMask = [.width]
        dictationPreview.font = .systemFont(ofSize: 11)
        dictationPreview.textColor = EmberStyle.text
        dictationPreview.lineBreakMode = .byTruncatingMiddle
        dictationPreview.setAccessibilityLabel("Dictation preview")
        chrome.addSubview(dictationPreview)
        for (button, offset, action) in [
            (dictationInsert, 154.0, #selector(insertRetainedDictation)),
            (dictationCancel, 90.0, #selector(cancelDictation)),
        ] {
            button.frame = CGRect(x: size.width - CGFloat(offset), y: 41, width: 60, height: 28)
            button.autoresizingMask = [.minXMargin]
            button.isBordered = false
            button.contentTintColor = EmberStyle.text
            button.target = self
            button.action = action
            chrome.addSubview(button)
        }
        terminal.onToggleDictation = { [weak self] in self?.toggleDictation() }
        panel.onCancelDictation = { [weak self] in
            guard let self, self.dictationPreviewVisible else { return false }
            self.cancelDictation()
            return true
        }
        dictation.onUpdate = { [weak self] in self?.updateDictationPresentation() }
        dictation.onFinalText = { [weak self] text in self?.receiveDictatedText(text) }
        updateDictationPresentation()
    }

    func start(shellArguments: [String] = ["-f"]) {
        guard !started else { return }
        sessionGeneration &+= 1
        insertionGate.invalidate()
        started = true
        stopping = false
        var environment = ProcessInfo.processInfo.environment
        for key in environment.keys where key.hasPrefix("DYLD_") || key.hasPrefix("XCTest") {
            environment.removeValue(forKey: key)
        }
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "PetTerminal"
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:" + existingPath
        environment["PS1"] = "\(PetDefinition.current.id) %1~ %# "
        terminal.startProcess(
            executable: "/bin/zsh", args: shellArguments, environment: environment.map { "\($0.key)=\($0.value)" },
            currentDirectory: workingDirectory.path)
        footer.stringValue = "zsh · \(workingDirectory.path)"
        if !terminal.process.running {
            footer.stringValue = "Shell could not start — choose Folder to try again"
            started = false
        }
    }
    func focus() {
        start()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(terminal)
    }
    func stop(completion: @escaping () -> Void) {
        sessionGeneration &+= 1
        interruptDictation()
        guard started, !stopping else {
            completion()
            return
        }
        stopping = true
        let process = terminal.process!
        let pid = process.shellPid
        guard pid > 0 else {
            started = false
            completion()
            return
        }
        let foreground = process.childfd >= 0 ? tcgetpgrp(process.childfd) : -1
        // Only signal groups belonging to this terminal's shell session.
        if foreground > 0, getsid(foreground) == pid { kill(-foreground, SIGHUP) }
        if getpgid(pid) == pid { kill(-pid, SIGHUP) }
        process.terminate()
        DispatchQueue.global(qos: .utility).async {
            var result: Int32 = 0
            for _ in 0..<15 {
                let reaped = waitpid(pid, &result, WNOHANG)
                if reaped == pid || (reaped == -1 && errno == ECHILD) { break }
                Thread.sleep(forTimeInterval: 0.03)
            }
            if waitpid(pid, &result, WNOHANG) == 0 {
                kill(pid, SIGKILL)
                _ = waitpid(pid, &result, 0)
            }
            DispatchQueue.main.async {
                self.started = false
                self.stopping = false
                completion()
            }
        }
    }

    @objc func toggleDictation() {
        if dictation.isBusy {
            // A toolbar click can take first responder under Full Keyboard Access.
            // This is an explicit stop action; asynchronous results never steal focus.
            if panel.isVisible && panel.isKeyWindow && NSApp.isActive { panel.makeFirstResponder(terminal) }
            dictation.stopAndInsert()
            return
        }
        if case .draft = dictation.state {
            insertRetainedDictation()
            return
        }
        guard focusExistingSession(), let target = currentDictationTarget() else {
            dictationNotice = "Open a terminal session before dictating."
            updateDictationPresentation()
            return
        }
        dictationNotice = ""
        insertionGate.begin(target: target)
        dictation.start()
    }

    func interruptDictation() {
        insertionGate.invalidate()
        if dictation.isBusy || !dictation.transcript.isEmpty {
            dictationNotice = "Dictation paused. Return to the terminal to insert the draft."
            dictation.interrupt()
        }
        updateDictationPresentation()
    }

    @objc func cancelDictation() {
        insertionGate.invalidate()
        dictationNotice = ""
        dictation.cancel()
        updateDictationPresentation()
    }

    @objc private func insertRetainedDictation() {
        guard !dictation.isBusy, !dictation.transcript.isEmpty,
            focusExistingSession(), let target = currentDictationTarget()
        else {
            dictationNotice = "Open a terminal session to insert this draft."
            updateDictationPresentation()
            return
        }
        dictationNotice = ""
        insertionGate.begin(target: target)
        dictation.insertDraft()
    }

    private func focusExistingSession() -> Bool {
        guard currentDictationTarget() != nil else { return false }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(terminal)
        return true
    }

    private func currentDictationTarget() -> DictationInsertionTarget? {
        guard started, !stopping, terminal.process.running,
            terminal.process.shellPid > 0, terminal.process.childfd >= 0
        else { return nil }
        let foreground = tcgetpgrp(terminal.process.childfd)
        guard foreground > 0 else { return nil }
        return DictationInsertionTarget(
            generation: sessionGeneration, shellPID: terminal.process.shellPid, foregroundGroup: foreground)
    }

    private func receiveDictatedText(_ text: String) {
        let focused = panel.isVisible && panel.isKeyWindow && NSApp.isActive && panel.firstResponder === terminal
        guard insertionGate.consume(current: currentDictationTarget(), canReceiveInput: focused) else {
            dictationNotice = "Destination changed. Review the terminal, then choose Insert."
            dictation.interrupt()
            updateDictationPresentation()
            return
        }
        if terminal.insertDictatedText(text) {
            dictationNotice = ""
        } else {
            dictationNotice = "No spoken text to insert."
        }
        updateDictationPresentation()
    }

    private func updateDictationPresentation() {
        let busy = dictation.isBusy
        let hasDraft = !dictation.transcript.isEmpty
        let showPreview: Bool
        if case .idle = dictation.state {
            showPreview = !dictationNotice.isEmpty
        } else {
            showPreview = true
        }
        let buttonLabel: String
        let buttonSymbol: String
        switch dictation.state {
        case .draft:
            buttonLabel = "Insert dictation"
            buttonSymbol = "arrow.turn.down.left"
        case .preparing, .listening, .finalizing:
            buttonLabel = "Stop and insert dictation"
            buttonSymbol = "stop.fill"
        case .idle, .failed:
            buttonLabel = "Dictate into terminal"
            buttonSymbol = "mic.fill"
        }
        dictationButton.image = NSImage(systemSymbolName: buttonSymbol, accessibilityDescription: buttonLabel)
        dictationButton.toolTip = "\(buttonLabel) (⇧⌘D)"
        dictationButton.setAccessibilityLabel(buttonLabel)
        switch dictation.state {
        case .preparing, .finalizing: dictationButton.isEnabled = false
        default: dictationButton.isEnabled = true
        }
        dictationPreview.stringValue =
            dictationNotice.isEmpty
            ? (hasDraft ? dictation.transcript : dictation.statusText) : dictationNotice
        dictationPreview.toolTip = [dictationNotice, dictation.transcript, dictation.statusText]
            .filter { !$0.isEmpty }.joined(separator: "\n")
        dictationPreview.isHidden = !showPreview
        dictationCancel.isHidden = !showPreview
        dictationInsert.isHidden = !showPreview || busy || !hasDraft
        if showPreview != dictationPreviewVisible {
            dictationPreviewVisible = showPreview
            let height = panel.contentView?.bounds.height ?? panel.frame.height
            terminal.frame = CGRect(
                x: 24, y: showPreview ? 76 : 42, width: panel.contentView!.bounds.width - 48,
                height: height - (showPreview ? 142 : 108))
        }
        onDictationUpdate?()
    }

    @objc private func hide() { onHide?() }
    @objc private func pin() { onPin?() }
    @objc private func folder() { onFolder?() }
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        heading.stringValue = title.isEmpty ? "\(PetDefinition.current.displayName) · Terminal" : title
    }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        if let directory { footer.stringValue = "zsh · \(directory)" }
    }
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        sessionGeneration &+= 1
        interruptDictation()
        started = false
        if !stopping {
            footer.stringValue = "Session ended · click Folder to start another"
            onEnd?()
        }
    }
}
