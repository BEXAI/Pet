import AppKit
import ImageIO

final class SpriteAtlas {
    struct Frame {
        let image: NSImage
        let bitmap: NSBitmapImageRep
        let visor: VisorSurface?
    }
    let rows: [[Frame]]
    let looks: [Frame]
    private var gazeCache: [Int: NSImage] = [:]
    private var cacheOrder: [Int] = []
    static let durations: [[Double]] = [
        [0.28, 0.11, 0.11, 0.14, 0.14, 0.32],
        [0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.22],
        [0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.22],
        [0.14, 0.14, 0.14, 0.28],
    ]
    init(url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            image.width == 1536, image.height == 2288
        else {
            throw NSError(
                domain: "VioletEmber", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The Violet Ember v2 spritesheet could not be loaded."])
        }
        func frame(row: Int, column: Int) throws -> Frame {
            guard let cg = image.cropping(to: CGRect(x: column * 192, y: row * 208, width: 192, height: 208)) else {
                throw NSError(domain: "VioletEmber", code: 2)
            }
            return Frame(
                image: NSImage(cgImage: cg, size: NSSize(width: 192, height: 208)),
                bitmap: NSBitmapImageRep(cgImage: cg), visor: VisorSurface(image: cg))
        }
        rows = try [6, 8, 8, 4].enumerated().map { row, count in
            try (0..<count).map { try frame(row: row, column: $0) }
        }
        looks = try (0..<16).map { try frame(row: 9 + $0 / 8, column: $0 % 8) }
    }

    func image(row: Int, column: Int, gaze: Int?, mode: GazeMode = PetDefinition.current.gazeMode) -> NSImage {
        let original = rows[row][column]
        if mode == .off { return original.image }
        if mode == .directional, let gaze { return looks[gaze].image }
        // Keep Ember's original short blinks; his gaze continues updating while shut.
        guard let gaze, !(row == 0 && (column == 2 || column == 3)),
            let face = original.visor, let look = looks[gaze].visor
        else { return original.image }
        let key = (row * 8 + column) * 16 + gaze
        if let cached = gazeCache[key] { return cached }
        guard let cg = face.applying(look) else { return original.image }
        let image = NSImage(cgImage: cg, size: NSSize(width: 192, height: 208))
        if cacheOrder.count == 64 { gazeCache.removeValue(forKey: cacheOrder.removeFirst()) }
        cacheOrder.append(key)
        gazeCache[key] = image
        return image
    }
}

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PetView: NSView {
    let atlas: SpriteAtlas
    var onDrag: ((CGPoint) -> Void)?
    var onDragState: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    var onMenu: (() -> NSMenu)?
    private var origin = CGPoint.zero
    private var cursor = CGPoint.zero
    private var dragged = false
    private(set) var dragging = false
    private var row = 0, column = 0
    private var lastFrame = 0.0
    private(set) var gaze: Int?

    init(atlas: SpriteAtlas) {
        self.atlas = atlas
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(PetDefinition.current.displayName) — click for terminal, drag to move")
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    func animate(row next: Int, time: Double, reduced: Bool) {
        let next = reduced ? 0 : next
        if row != next {
            row = next
            column = 0
            lastFrame = time
            needsDisplay = true
        }
        if reduced {
            if column != 0 {
                column = 0
                needsDisplay = true
            }
        } else if time - lastFrame >= SpriteAtlas.durations[row][column] {
            column = (column + 1) % atlas.rows[row].count
            lastFrame = time
            needsDisplay = true
        }
    }

    func trackMouse(at screenPoint: CGPoint) {
        guard let window, bounds.width > 0, bounds.height > 0 else { return }
        let point = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        let face =
            PetDefinition.current.gazeMode == .visor
            ? (atlas.rows[row][column].visor?.bounds ?? CGRect(x: 59, y: 78, width: 74, height: 59))
            : CGRect(x: 76, y: 84, width: 40, height: 40)
        let next = EyeTracking.direction(
            pointer: CGPoint(x: point.x / bounds.width * 192, y: point.y / bounds.height * 208),
            face: CGPoint(x: face.midX, y: 208 - face.midY), previous: gaze)
        if next != gaze {
            gaze = next
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        atlas.image(row: row, column: column, gaze: gaze).draw(
            in: bounds, from: .zero, operation: .sourceOver, fraction: 1,
            respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
    func hasPixel(at screenPoint: CGPoint) -> Bool {
        guard let window else { return false }
        let point = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        guard bounds.contains(point) else { return false }
        let x = min(191, max(0, Int(point.x / bounds.width * 192)))
        let y = min(207, max(0, 207 - Int(point.y / bounds.height * 208)))
        let frame =
            PetDefinition.current.gazeMode == .directional
            ? gaze.map { atlas.looks[$0] } ?? atlas.rows[row][column] : atlas.rows[row][column]
        return (frame.bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.08
    }
    override func mouseDown(with event: NSEvent) {
        cursor = NSEvent.mouseLocation
        origin = window?.frame.origin ?? .zero
        dragged = false
        dragging = true
        onDragState?(true)
    }
    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        if hypot(p.x - cursor.x, p.y - cursor.y) > 3 { dragged = true }
        onDrag?(CGPoint(x: origin.x + p.x - cursor.x, y: origin.y + p.y - cursor.y))
    }
    override func mouseUp(with event: NSEvent) {
        dragging = false
        onDragState?(false)
        if !dragged { onClick?() }
    }
    override func rightMouseDown(with event: NSEvent) {
        if let menu = onMenu?() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
}
