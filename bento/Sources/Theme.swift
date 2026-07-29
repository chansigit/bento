import AppKit

// MARK: - Skins (皮肤)
//
// A skin is a menu appearance (follow-system / light / dark) plus an accent
// color applied to the status-bar title and the times inside the menu.
// Persisted by id in UserDefaults ("skinID").

struct Skin {
    let id: String
    let name: String
    let accent: NSColor?                    // nil = system label color
    let appearanceName: NSAppearance.Name?  // nil = follow system
}

let allSkins: [Skin] = [
    Skin(id: "system", name: "默认(跟随系统)", accent: nil, appearanceName: nil),
    Skin(id: "light", name: "浅色", accent: nil, appearanceName: .aqua),
    Skin(id: "dark", name: "深色", accent: nil, appearanceName: .darkAqua),
    Skin(id: "matcha", name: "🍵 抹茶", accent: NSColor(calibratedRed: 0.33, green: 0.62, blue: 0.36, alpha: 1), appearanceName: nil),
    Skin(id: "seasalt", name: "🌊 海盐", accent: NSColor(calibratedRed: 0.20, green: 0.52, blue: 0.80, alpha: 1), appearanceName: nil),
    Skin(id: "mikan", name: "🍊 蜜柑", accent: NSColor(calibratedRed: 0.92, green: 0.51, blue: 0.15, alpha: 1), appearanceName: nil),
    Skin(id: "sakura", name: "🌸 樱花", accent: NSColor(calibratedRed: 0.88, green: 0.42, blue: 0.57, alpha: 1), appearanceName: nil),
]

func skin(withID id: String?) -> Skin {
    return allSkins.first(where: { $0.id == id }) ?? allSkins[0]
}
