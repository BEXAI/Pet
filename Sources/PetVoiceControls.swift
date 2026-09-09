import AppKit

// A short grace period lets the pointer cross from the sprite to its controls.
// The pet's own window stays exactly the size of its artwork.
struct PetHoverVisibility {
    private(set) var visible = false
    private var hideAfter = 0.0

    mutating func update(petHovered: Bool, controlsHovered: Bool, keepVisible: Bool, dragging: Bool, time: Double) {
        if dragging {
            visible = false
            hideAfter = 0
        } else if petHovered || controlsHovered || keepVisible {
            visible = true
            hideAfter = time + 0.65
        } else if time >= hideAfter {
            visible = false
        }
    }

    mutating func reset() {
        visible = false
        hideAfter = 0
    }
}

enum PetVoiceLayout {
    static func frame(pet: CGRect, size: CGSize, screen: CGRect) -> CGRect {
        let right = CGRect(x: pet.maxX + 6, y: pet.midY - size.height / 2, width: size.width, height: size.height)
        let left = CGRect(x: pet.minX - size.width - 6, y: right.minY, width: size.width, height: size.height)
        let area = screen.insetBy(dx: OverlayGeometry.margin, dy: OverlayGeometry.margin)
        if area.contains(right) { return right }
        if area.contains(left) { return left }
        return OverlayGeometry.fit(
            CGRect(x: pet.midX - size.width / 2, y: pet.minY - size.height - 6, width: size.width, height: size.height),
            in: screen)
    }
}

private final class VoiceActionButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class VoiceControlBackground: NSView {
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 17, yRadius: 17)
        NSColor(srgbRed: 0.07, green: 0.04, blue: 0.12, alpha: 0.97).setFill()
        path.fill()
        EmberStyle.border.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 1.2
        path.stroke()
    }
}

@MainActor
final class PetVoiceControls {
    let panel: PetPanel
    let actionButton: NSButton = VoiceActionButton(title: "Dictate", target: nil, action: nil)
    let cancelButton: NSButton = VoiceActionButton(title: "", target: nil, action: nil)
    var onAction: (() -> Void)?
    var onCancel: (() -> Void)?
    private var hover = PetHoverVisibility()
    private var state: DictationController.State = .idle

    init() {
        panel = PetPanel(
            contentRect: CGRect(x: 0, y: 0, width: 138, height: 38),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Pet voice dictation"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        let content = VoiceControlBackground(frame: CGRect(origin: .zero, size: panel.frame.size))
        panel.contentView = content
        for button in [actionButton, cancelButton] {
            button.isBordered = false
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 12, weight: .semibold)
            button.contentTintColor = EmberStyle.text
            button.target = self
            content.addSubview(button)
        }
        actionButton.action = #selector(performAction)
        actionButton.imagePosition = .imageLeading
        cancelButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Cancel dictation")
        cancelButton.imagePosition = .imageOnly
        cancelButton.action = #selector(cancel)
        cancelButton.toolTip = "Cancel dictation (Esc)"
        cancelButton.setAccessibilityLabel("Cancel dictation")
        setState(.idle)
    }

    func setState(_ next: DictationController.State) {
        state = next
        let title: String
        let symbol: String
        switch next {
        case .idle:
            title = "Dictate"
            symbol = "mic.fill"
        case .preparing:
            title = "Preparing…"
            symbol = "hourglass"
        case .listening:
            title = "Stop & Insert"
            symbol = "stop.circle.fill"
        case .finalizing:
            title = "Finishing…"
            symbol = "hourglass"
        case .draft:
            title = "Insert Text"
            symbol = "text.badge.plus"
        case .failed:
            title = "Retry Dictation"
            symbol = "mic.badge.xmark"
        }
        actionButton.title = title
        actionButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        actionButton.isEnabled = next != .preparing && next != .finalizing
        actionButton.toolTip = next == .idle ? "Dictate into the embedded terminal (⌘⇧D)" : title
        actionButton.setAccessibilityLabel(next == .idle ? "Start voice dictation into terminal" : title)
        cancelButton.isHidden = next == .idle
        let width: CGFloat = next == .idle ? 138 : 204
        panel.setContentSize(CGSize(width: width, height: 38))
        actionButton.frame = CGRect(x: 9, y: 4, width: width - (cancelButton.isHidden ? 18 : 45), height: 30)
        cancelButton.frame = CGRect(x: width - 36, y: 4, width: 28, height: 30)
    }

    @discardableResult
    func update(pointer: CGPoint, petFrame: CGRect, screen: CGRect, petHovered: Bool, dragging: Bool, time: Double)
        -> Bool
    {
        let controlsHovered = panel.isVisible && panel.frame.contains(pointer)
        hover.update(
            petHovered: petHovered, controlsHovered: controlsHovered, keepVisible: state != .idle,
            dragging: dragging, time: time)
        if hover.visible {
            let frame = PetVoiceLayout.frame(pet: petFrame, size: panel.frame.size, screen: screen)
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if panel.isVisible {
            panel.orderOut(nil)
        }
        return hover.visible
    }

    func hide() {
        hover.reset()
        panel.orderOut(nil)
    }

    @objc private func performAction() { onAction?() }
    @objc private func cancel() { onCancel?() }
}
