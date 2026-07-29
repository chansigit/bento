import Foundation

// MARK: - Wi-Fi signal logic (pure, testable)

struct WifiNetwork {
    let ssid: String
    let rssi: Int          // dBm, typically -30 (great) … -90 (unusable)
    let isCurrent: Bool
}

/// Signal level 1…4 from RSSI (matches the familiar menu-bar fan thresholds).
func wifiLevel(rssi: Int) -> Int {
    if rssi >= -55 { return 4 }
    if rssi >= -65 { return 3 }
    if rssi >= -75 { return 2 }
    return 1
}

/// Bar glyphs for a level, e.g. 3 → "▂▄▆" (the missing top bar reads as weaker).
func wifiBars(level: Int) -> String {
    let bars = ["▂", "▄", "▆", "█"]
    let n = max(1, min(4, level))
    return bars.prefix(n).joined()
}

/// Human verdict for a signal level — tells the user which network is better
/// instead of making them decode dBm.
func wifiQualityLabel(level: Int) -> String {
    switch level {
    case 4: return "极好"
    case 3: return "良好"
    case 2: return "一般"
    default: return "弱"
    }
}

/// Map RSSI to an intuitive 0–100%: -90 dBm → 0%, -30 dBm → 100%, clamped.
func wifiPercent(rssi: Int) -> Int {
    let p = (rssi + 90) * 100 / 60
    return max(0, min(100, p))
}

/// Best RSSI per SSID (APs broadcast the same SSID from multiple radios),
/// current network first, then by descending signal.
func dedupedSortedNetworks(_ nets: [WifiNetwork]) -> [WifiNetwork] {
    var best: [String: WifiNetwork] = [:]
    for n in nets where !n.ssid.isEmpty {
        if let b = best[n.ssid] {
            if n.rssi > b.rssi || (n.isCurrent && !b.isCurrent) {
                best[n.ssid] = WifiNetwork(ssid: n.ssid, rssi: max(n.rssi, b.rssi),
                                           isCurrent: n.isCurrent || b.isCurrent)
            }
        } else {
            best[n.ssid] = n
        }
    }
    return best.values.sorted {
        if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
        return $0.rssi > $1.rssi
    }
}
