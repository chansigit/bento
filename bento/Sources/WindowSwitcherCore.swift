import Foundation

func switcherWrappedIndex(_ index: Int, delta: Int, count: Int) -> Int {
    guard count > 0 else { return 0 }
    return ((index + delta) % count + count) % count
}

func switcherExcluded(_ bundle: String, rules: String) -> Bool {
    rules.split(whereSeparator: { $0 == "\n" || $0 == "," }).contains {
        let rule = $0.trimmingCharacters(in: .whitespacesAndNewlines)
        return !rule.isEmpty && (bundle == rule || (rule.hasSuffix(".*") && bundle.hasPrefix(String(rule.dropLast()))))
    }
}

let switcherCardGap: CGFloat = 8

struct SwitcherFlowLayout {
    var frames: [CGRect]
    var rows: [Int]
    var width: CGFloat
    var height: CGFloat
}

func switcherFlowLayout(aspects: [CGFloat], height: CGFloat, maxWidth: CGFloat) -> SwitcherFlowLayout {
    var frames: [CGRect] = []
    var rows: [Int] = []
    var x: CGFloat = 0
    var row = 0
    var rowWidths: [CGFloat] = []
    for aspect in aspects {
        let width = min(maxWidth, max(104, (height - 36) * min(2.2, max(0.65, aspect)) + 16))
        if x > 0 && x + width > maxWidth { rowWidths.append(x - switcherCardGap); row += 1; x = 0 }
        frames.append(CGRect(x: x, y: CGFloat(row) * (height + switcherCardGap), width: width, height: height))
        rows.append(row)
        x += width + switcherCardGap
    }
    rowWidths.append(max(0, x - switcherCardGap))
    let width = rowWidths.max() ?? 0
    for i in frames.indices { frames[i].origin.x += (width - rowWidths[rows[i]]) / 2 }
    return SwitcherFlowLayout(frames: frames, rows: rows, width: width, height: CGFloat(row + 1) * (height + switcherCardGap))
}

// Import only switcher preferences once; never overwrite existing Bento settings.
func migrateWindowSwitcherPreferences(into defaults: UserDefaults, legacy: [String: Any]) {
    let marker = "windowSwitcher.didMigrate"
    guard !defaults.bool(forKey: marker) else { return }
    for key in ["theme", "cardSize", "showMinimized", "showHidden", "showWindowless", "excludedApps", "ignoredApps"] {
        let target = "windowSwitcher." + key
        if defaults.object(forKey: target) == nil, let value = legacy[key] {
            defaults.set(value, forKey: target)
        }
    }
    defaults.set(true, forKey: marker)
}
