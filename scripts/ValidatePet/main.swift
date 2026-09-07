import AppKit
import ImageIO

do {
    guard CommandLine.arguments.count == 2 else {
        throw NSError(
            domain: "PetValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Supply a Resources directory."])
    }
    let resources = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let pet = try PetDefinition.load(directory: resources)
    let url = resources.appendingPathComponent(pet.spritesheetPath)
    let atlas = try SpriteAtlas(url: url)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let cg = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fatalError("Atlas decoding failed") }
    let counts = [6, 8, 8, 4, 5, 8, 6, 6, 6, 8, 8]
    for (row, count) in counts.enumerated() {
        for column in 0..<count {
            let bitmap = NSBitmapImageRep(
                cgImage: cg.cropping(to: CGRect(x: column * 192, y: row * 208, width: 192, height: 208))!)
            var visible = false
            var transparent = false
            for y in 0..<208 {
                for x in 0..<192 {
                    let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                    if alpha > 0.1 { visible = true }
                    if alpha == 0 { transparent = true }
                }
            }
            guard visible, transparent else {
                throw NSError(
                    domain: "PetValidation", code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Cell \(row):\(column) must contain a visible pet with a transparent background."
                    ])
            }
        }
    }
    if pet.gazeMode == .visor, !(atlas.rows.flatMap { $0 } + atlas.looks).allSatisfy({ $0.visor != nil }) {
        throw NSError(
            domain: "PetValidation", code: 3,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Visor mode needs compatible screen-face artwork. Use directional mode for other characters."
            ])
    }
    print(
        "Validated \(pet.displayName): 1536×2288 v2 artwork, 73 populated cells, \(pet.gazeMode.rawValue) gaze, RGBA theme."
    )
    print("Visual review is still required for direction meaning, animation continuity, and face fit.")
} catch {
    FileHandle.standardError.write(Data("Pet validation failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
