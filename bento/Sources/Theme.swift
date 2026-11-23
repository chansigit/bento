import AppKit

// MARK: - Skins (皮肤)
//
// A skin is a menu appearance (follow-system / light / dark) plus an accent
// color applied to the status-bar title and the times inside the menu.
// Persisted by id in UserDefaults ("skinID").

struct Skin {
    let id: String
    let nameKey: String
    var name: String { L(nameKey) }
    let accent: NSColor?                    // nil = system label color
    let appearanceName: NSAppearance.Name?  // nil = follow system
}

let allSkins: [Skin] = [
    Skin(id: "system", nameKey: "默认(跟随系统)", accent: nil, appearanceName: nil),
    Skin(id: "light", nameKey: "浅色", accent: nil, appearanceName: .aqua),
    Skin(id: "dark", nameKey: "深色", accent: nil, appearanceName: .darkAqua),
    Skin(id: "matcha", nameKey: "🍵 抹茶", accent: NSColor(calibratedRed: 0.33, green: 0.62, blue: 0.36, alpha: 1), appearanceName: nil),
    Skin(id: "seasalt", nameKey: "🌊 海盐", accent: NSColor(calibratedRed: 0.20, green: 0.52, blue: 0.80, alpha: 1), appearanceName: nil),
    Skin(id: "mikan", nameKey: "🍊 蜜柑", accent: NSColor(calibratedRed: 0.92, green: 0.51, blue: 0.15, alpha: 1), appearanceName: nil),
    Skin(id: "sakura", nameKey: "🌸 樱花", accent: NSColor(calibratedRed: 0.88, green: 0.42, blue: 0.57, alpha: 1), appearanceName: nil),
    Skin(id: "lavender", nameKey: "🪻 薰衣草", accent: NSColor(srgbRed: 0.55, green: 0.38, blue: 0.82, alpha: 1), appearanceName: .aqua),
    Skin(id: "rose", nameKey: "🌹 玫瑰", accent: NSColor(srgbRed: 0.78, green: 0.25, blue: 0.40, alpha: 1), appearanceName: .aqua),
    Skin(id: "sand", nameKey: "🏖️ 沙丘", accent: NSColor(srgbRed: 0.57, green: 0.40, blue: 0.23, alpha: 1), appearanceName: .aqua),
    Skin(id: "mint", nameKey: "🌿 薄荷", accent: NSColor(srgbRed: 0.12, green: 0.53, blue: 0.43, alpha: 1), appearanceName: .aqua),
    Skin(id: "midnight", nameKey: "🌌 午夜", accent: NSColor(srgbRed: 0.45, green: 0.65, blue: 1, alpha: 1), appearanceName: .darkAqua),
    Skin(id: "aurora", nameKey: "✨ 极光", accent: NSColor(srgbRed: 0.38, green: 0.88, blue: 0.68, alpha: 1), appearanceName: .darkAqua),
    Skin(id: "ember", nameKey: "🔥 余烬", accent: NSColor(srgbRed: 1, green: 0.64, blue: 0.36, alpha: 1), appearanceName: .darkAqua),
    Skin(id: "grape", nameKey: "🍇 葡萄", accent: NSColor(srgbRed: 0.76, green: 0.60, blue: 1, alpha: 1), appearanceName: .darkAqua),
]

func skin(withID id: String?) -> Skin {
    return allSkins.first(where: { $0.id == id }) ?? allSkins[0]
}

extension Notification.Name { static let bentoSkinChanged = Notification.Name("BentoSkinChanged") }

struct SkinPalette {
    let surface: NSColor
    let card: NSColor
    let border: NSColor
    let selection: NSColor
    let accent: NSColor
    let radius: CGFloat
}

extension Skin {
    func palette(dark: Bool) -> SkinPalette {
        // Backgrounds are opaque: the desktop never tints captured window pixels.
        let tones: (UInt32, UInt32, CGFloat)
        switch id {
        case "matcha": tones = (0xE8EEDC, 0x1B251C, 12)
        case "seasalt": tones = (0xE4F1F8, 0x172835, 14)
        case "mikan": tones = (0xFFF0DE, 0x30231A, 12)
        case "sakura": tones = (0xFBE9EF, 0x301E2A, 18)
        case "lavender": tones = (0xEDE7F6, 0x252036, 18)
        case "rose": tones = (0xF8E3E7, 0x321D25, 12)
        case "sand": tones = (0xF2E8D7, 0x2D261C, 7)
        case "mint": tones = (0xE2F3EC, 0x172C27, 14)
        case "midnight": tones = (0xE3EAF8, 0x101D36, 14)
        case "aurora": tones = (0xE2F3ED, 0x102B29, 20)
        case "ember": tones = (0xFBEADD, 0x332019, 8)
        case "grape": tones = (0xEDE5F6, 0x291A3D, 20)
        default: tones = (0xF1F2F4, 0x202124, 12)
        }
        let hex = dark ? tones.1 : tones.0
        let surface = NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                              green: CGFloat((hex >> 8) & 255) / 255,
                              blue: CGFloat(hex & 255) / 255, alpha: 1)
        let accent = self.accent ?? .systemBlue
        let card = surface.blended(withFraction: dark ? 0.07 : 0.72, of: .white) ?? surface
        let border = surface.blended(withFraction: dark ? 0.22 : 0.18, of: dark ? .white : .black) ?? .separatorColor
        let selection = card.blended(withFraction: dark ? 0.24 : 0.16, of: accent) ?? card
        return SkinPalette(surface: surface, card: card, border: border, selection: selection, accent: accent, radius: tones.2)
    }
}

extension Notification.Name { static let bentoDismissMenu = Notification.Name("BentoDismissMenu") }
