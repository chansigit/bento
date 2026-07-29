import CoreLocation
import CoreWLAN
import Foundation

// MARK: - Wi-Fi scan controller
//
// Scans nearby networks with CoreWLAN. On modern macOS the SSIDs in scan
// results are redacted unless the app has Location permission, so we lazily
// request it the first time the Wi-Fi submenu is opened.

final class WifiController: NSObject {
    private let locationManager = CLLocationManager()
    private(set) var isScanning = false

    func requestLocationIfNeeded() {
        // Only prompts the first time; later calls are no-ops.
        locationManager.requestWhenInUseAuthorization()
    }

    /// Blocking scan (a few seconds) — call on a background queue.
    /// Returns networks plus an optional user-facing hint.
    func scan() -> ([WifiNetwork], String?) {
        isScanning = true
        defer { isScanning = false }
        guard let iface = CWWiFiClient.shared().interface() else {
            return ([], "未找到 Wi-Fi 网卡")
        }
        guard iface.powerOn() else { return ([], "Wi-Fi 已关闭") }
        let currentSSID = iface.ssid()
        do {
            let found = try iface.scanForNetworks(withSSID: nil)
            var redacted = 0
            var nets: [WifiNetwork] = []
            for n in found {
                guard let ssid = n.ssid, !ssid.isEmpty else { redacted += 1; continue }
                nets.append(WifiNetwork(ssid: ssid, rssi: n.rssiValue,
                                        isCurrent: ssid == currentSSID))
            }
            if nets.isEmpty && redacted > 0 {
                return ([], "需要「定位服务」权限才能显示 Wi-Fi 名称(系统设置 → 隐私与安全 → 定位服务)")
            }
            return (dedupedSortedNetworks(nets), nil)
        } catch {
            return ([], "扫描失败:\(error.localizedDescription)")
        }
    }
}
