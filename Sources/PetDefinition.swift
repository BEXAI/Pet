import AppKit

enum GazeMode: String, Decodable { case visor, directional, off }

struct RGBA: Decodable {
    let values: [Double]
    init(_ values: [Double]) { self.values = values }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let values = try container.decode([Double].self)
        guard values.count == 4, values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Colors need four RGBA numbers between 0 and 1.")
        }
        self.values = values
    }
    var color: NSColor { NSColor(srgbRed: values[0], green: values[1], blue: values[2], alpha: values[3]) }
}

struct TerminalAppearance: Decodable {
    let border: RGBA
    let glow: RGBA
    let text: RGBA
    let background: RGBA
    static let neon = TerminalAppearance(
        border: RGBA([0, 0.9, 1, 1]), glow: RGBA([0.05, 0.65, 1, 1]),
        text: RGBA([1, 0, 1, 1]), background: RGBA([0, 0, 0, 0]))
}

struct PetDefinition: Decodable {
    let id: String
    let displayName: String
    let description: String
    let spriteVersionNumber: Int
    let spritesheetPath: String
    let gazeMode: GazeMode
    let terminal: TerminalAppearance

    static var current = PetDefinition()
    private init() {
        id = "violet-ember"
        displayName = "Violet Ember"
        description = "A neon desktop companion."
        spriteVersionNumber = 2
        spritesheetPath = "spritesheet.webp"
        gazeMode = .visor
        terminal = .neon
    }
    enum CodingKeys: String, CodingKey {
        case id, displayName, description, spriteVersionNumber, spritesheetPath, gazeMode, terminal
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        description = try c.decode(String.self, forKey: .description)
        spriteVersionNumber = try c.decode(Int.self, forKey: .spriteVersionNumber)
        spritesheetPath = try c.decode(String.self, forKey: .spritesheetPath)
        gazeMode = try c.decodeIfPresent(GazeMode.self, forKey: .gazeMode) ?? .directional
        terminal = try c.decodeIfPresent(TerminalAppearance.self, forKey: .terminal) ?? .neon
        guard id.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: c, debugDescription: "Use a lowercase pet id, for example moon-cat.")
        }
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, displayName.count <= 60,
            displayName.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .displayName, in: c,
                debugDescription: "The display name must contain 1–60 printable characters.")
        }
        guard spriteVersionNumber == 2 else {
            throw DecodingError.dataCorruptedError(
                forKey: .spriteVersionNumber, in: c, debugDescription: "This renderer requires spriteVersionNumber 2.")
        }
        guard !spritesheetPath.contains("/"), !spritesheetPath.contains("\\"),
            ["png", "webp"].contains((spritesheetPath as NSString).pathExtension.lowercased())
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .spritesheetPath, in: c,
                debugDescription: "Use a PNG or WebP filename inside Resources, without directory components.")
        }
    }
    static func load(directory: URL) throws -> PetDefinition {
        try JSONDecoder().decode(
            PetDefinition.self, from: Data(contentsOf: directory.appendingPathComponent("pet.json")))
    }
}
