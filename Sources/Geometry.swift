import Foundation

enum OverlayGeometry {
    static let margin: CGFloat = 12
    static let gap: CGFloat = 4

    static func fit(_ frame: CGRect, in screen: CGRect) -> CGRect {
        let area = screen.insetBy(dx: margin, dy: margin)
        let size = CGSize(width: min(frame.width, area.width), height: min(frame.height, area.height))
        return CGRect(
            x: min(max(frame.minX, area.minX), area.maxX - size.width),
            y: min(max(frame.minY, area.minY), area.maxY - size.height),
            width: size.width, height: size.height)
    }

    static func layout(pet: CGRect, terminalSize: CGSize?, in screen: CGRect) -> (pet: CGRect, terminal: CGRect?) {
        var pet = fit(pet, in: screen)
        guard let size = terminalSize else { return (pet, nil) }
        let area = screen.insetBy(dx: margin, dy: margin)
        let terminalSize = CGSize(
            width: min(size.width, area.width),
            height: max(1, min(size.height, area.height - pet.height - gap)))
        pet.origin.y = min(pet.minY, area.maxY - terminalSize.height - gap - pet.height)
        let terminal = fit(
            CGRect(
                x: pet.midX - terminalSize.width / 2, y: pet.maxY + gap,
                width: terminalSize.width, height: terminalSize.height), in: screen)
        return (pet, terminal)
    }

    static func step(from start: CGPoint, toward target: CGPoint, speed: CGFloat, elapsed: TimeInterval) -> CGPoint {
        let dx = target.x - start.x
        let dy = target.y - start.y
        let distance = hypot(dx, dy)
        guard distance > 0 else { return target }
        let travel = min(distance, max(0, speed) * min(max(0, elapsed), 0.1))
        return CGPoint(x: start.x + dx / distance * travel, y: start.y + dy / distance * travel)
    }
}
