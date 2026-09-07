import AppKit

enum EyeTracking {
    // Atlas directions run clockwise from up in 22.5-degree steps.
    static func direction(pointer: CGPoint, face: CGPoint, previous: Int?) -> Int? {
        let dx = pointer.x - face.x
        let dy = pointer.y - face.y
        guard dx.isFinite, dy.isFinite, hypot(dx, dy) > 6 else { return nil }
        let circle = 2 * CGFloat.pi
        let step = circle / 16
        let angle = (atan2(dx, dy) + circle).truncatingRemainder(dividingBy: circle)
        if let previous {
            let difference = abs(atan2(sin(angle - CGFloat(previous) * step), cos(angle - CGFloat(previous) * step)))
            // Keep a pointer on a sector boundary from flickering between poses.
            if difference < step / 2 + .pi / 60 { return previous }
        }
        return Int((angle / step).rounded()) % 16
    }
}

/// The original screen-shaped face, with its eyes and reflections intact.
/// Row spans close the eye-shaped holes in the dark visor component. Mapping
/// between spans keeps the look artwork inside each animated head's aperture.
struct VisorSurface {
    struct Span {
        let left: Int
        let right: Int
    }
    let pixels: [UInt8]
    let spans: [Span]
    let top: Int
    let bounds: CGRect  // Sprite coordinates, measured from the top left.

    init?(image: CGImage) {
        let width = image.width
        let height = image.height
        guard width == 192, height == 208 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard
                let context = CGContext(
                    data: bytes.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var candidates = [Bool](repeating: false, count: width * height)
        for y in 60..<158 {
            for x in 20..<172 {
                let i = (y * width + x) * 4
                candidates[y * width + x] =
                    pixels[i] < 75 && pixels[i + 1] < 45 && pixels[i + 2] < 115 && pixels[i + 3] > 240
            }
        }
        var largest = [Int]()
        for seed in candidates.indices where candidates[seed] {
            var component = [seed]
            var cursor = 0
            candidates[seed] = false
            while cursor < component.count {
                let p = component[cursor]
                cursor += 1
                for next in [p - 1, p + 1, p - width, p + width]
                where next >= 0 && next < candidates.count && candidates[next] {
                    candidates[next] = false
                    component.append(next)
                }
            }
            if component.count > largest.count { largest = component }
        }
        guard largest.count > 500 else { return nil }
        let top = largest.map { $0 / width }.min()!
        let bottom = largest.map { $0 / width }.max()!
        var lefts = [Int](repeating: width, count: bottom - top + 1)
        var rights = [Int](repeating: -1, count: bottom - top + 1)
        for p in largest {
            let y = p / width - top
            let x = p % width
            lefts[y] = min(lefts[y], x)
            rights[y] = max(rights[y], x)
        }
        guard zip(lefts, rights).allSatisfy({ $0 <= $1 }) else { return nil }
        let searchLeft = lefts.min()! - 3
        let searchRight = rights.max()! + 3
        // Include bright eye components that reach past the dark surface edge.
        // Helmet highlights touch the search boundary and are deliberately excluded.
        var bright = Set<Int>()
        for y in top...bottom {
            for x in searchLeft...searchRight {
                let i = (y * width + x) * 4
                if pixels[i] > 190 && pixels[i + 1] > 100 && pixels[i + 2] > 190 && pixels[i + 3] > 240 {
                    bright.insert(y * width + x)
                }
            }
        }
        while let seed = bright.first {
            bright.remove(seed)
            var component = [seed]
            var cursor = 0
            var touchesBoundary = false
            while cursor < component.count {
                let p = component[cursor]
                cursor += 1
                let x = p % width
                let y = p / width
                if x == searchLeft || x == searchRight || y == top || y == bottom { touchesBoundary = true }
                for next in [p - 1, p + 1, p - width, p + width] where bright.remove(next) != nil {
                    component.append(next)
                }
            }
            guard !touchesBoundary, component.count > 6 else { continue }
            for p in component {
                for y in max(top, p / width - 2)...min(bottom, p / width + 2) {
                    lefts[y - top] = min(lefts[y - top], p % width - 2)
                    rights[y - top] = max(rights[y - top], p % width + 2)
                }
            }
        }
        let left = lefts.min()!
        let right = rights.max()!
        // Highlights and eyes can touch an edge. Use the visor's convex outline
        // so those bright features cannot dent the surface or stretch into stripes.
        struct Point: Equatable {
            let x: Int
            let y: Int
        }
        func cross(_ a: Point, _ b: Point, _ c: Point) -> Int {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        var points = [Point]()
        for row in lefts.indices {
            points.append(Point(x: lefts[row], y: row))
            points.append(Point(x: rights[row], y: row))
        }
        points.sort { a, b in a.x == b.x ? a.y < b.y : a.x < b.x }
        var lower = [Point]()
        var upper = [Point]()
        for p in points {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower.last!, p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        for p in points.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper.last!, p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        let hull = Array(lower.dropLast()) + Array(upper.dropLast())
        var outline = [Span]()
        for row in lefts.indices {
            var intersections = [Double]()
            for i in hull.indices {
                let a = hull[i]
                let b = hull[(i + 1) % hull.count]
                guard row >= min(a.y, b.y), row <= max(a.y, b.y) else { continue }
                if a.y == b.y {
                    intersections += [Double(a.x), Double(b.x)]
                } else {
                    intersections.append(Double(a.x) + Double(row - a.y) * Double(b.x - a.x) / Double(b.y - a.y))
                }
            }
            outline.append(Span(left: Int(floor(intersections.min()!)), right: Int(ceil(intersections.max()!))))
        }
        self.pixels = pixels
        self.top = top
        spans = outline
        bounds = CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
    }

    private func sample(u: Double, row: Int, channel: Int) -> Double {
        let span = spans[row]
        let x = Double(span.left) + u * Double(span.right - span.left)
        let x0 = Int(x)
        let x1 = min(span.right, x0 + 1)
        let fraction = x - Double(x0)
        let a = Double(pixels[((top + row) * 192 + x0) * 4 + channel])
        let b = Double(pixels[((top + row) * 192 + x1) * 4 + channel])
        return a + (b - a) * fraction
    }

    func applying(_ look: VisorSurface) -> CGImage? {
        var result = pixels
        for (row, span) in spans.enumerated() {
            let sourceY = Double(row) / Double(max(1, spans.count - 1)) * Double(look.spans.count - 1)
            let y0 = Int(sourceY)
            let y1 = min(look.spans.count - 1, y0 + 1)
            let fraction = sourceY - Double(y0)
            for x in span.left...span.right {
                let u = Double(x - span.left) / Double(max(1, span.right - span.left))
                let i = ((top + row) * 192 + x) * 4
                // A one-pixel blend preserves the original visor's edge lighting.
                let edge = min(x - span.left, span.right - x, row, spans.count - row - 1)
                let blend = edge == 0 ? 0.55 : 1.0
                for channel in 0..<3 {
                    let a = look.sample(u: u, row: y0, channel: channel)
                    let b = look.sample(u: u, row: y1, channel: channel)
                    result[i + channel] = UInt8(
                        (Double(pixels[i + channel]) * (1 - blend) + (a + (b - a) * fraction) * blend).rounded())
                }
                // Alpha stays byte-for-byte identical to the animated sprite.
            }
        }
        guard let provider = CGDataProvider(data: Data(result) as CFData) else { return nil }
        return CGImage(
            width: 192, height: 208, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 192 * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
