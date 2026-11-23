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
