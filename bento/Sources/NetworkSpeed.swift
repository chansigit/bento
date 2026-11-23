import Cocoa
import Darwin

struct NetworkCounter {
    let received: UInt64
    let sent: UInt64
}
struct NetworkRate {
    var download: Double = 0
    var upload: Double = 0
}
struct NetworkSampler {
    private var previous: [String: NetworkCounter] = [:]
    private var previousTime: TimeInterval?
    mutating func sample(_ counters: [String: NetworkCounter], at time: TimeInterval) -> NetworkRate {
        defer { previous = counters; previousTime = time }
        guard let last = previousTime, time > last, time - last <= 5 else { return NetworkRate() }
        var rate = NetworkRate()
        for (name, value) in counters {
            guard let old = previous[name] else { continue }
            if value.received >= old.received { rate.download += Double(value.received - old.received) / (time - last) }
            if value.sent >= old.sent { rate.upload += Double(value.sent - old.sent) / (time - last) }
        }
        return rate
    }
}

func networkRateText(_ bytes: Double) -> String {
    guard bytes.isFinite, bytes > 0 else { return "0 B/s" }
    if bytes < 1024 { return "\(Int(bytes)) B/s" }
    if bytes < 1024 * 1024 { return String(format: "%.0f K/s", bytes / 1024) }
    if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f M/s", bytes / (1024 * 1024)) }
    return String(format: "%.1f G/s", bytes / (1024 * 1024 * 1024))
}

func parseNetworkCounters(_ data: Data, nameForIndex: (UInt32) -> String?) -> [String: NetworkCounter]? {
    var counters: [String: NetworkCounter] = [:]
    var offset = 0
    while offset < data.count {
        guard data.count - offset >= 4 else { return nil }
        var length: UInt16 = 0
        _ = withUnsafeMutableBytes(of: &length) { data.copyBytes(to: $0, from: offset..<(offset + 2)) }
        guard length >= 4, Int(length) <= data.count - offset else { return nil }
        if data[offset + 3] == UInt8(RTM_IFINFO2) {
            guard Int(length) >= MemoryLayout<if_msghdr2>.size else { return nil }
            var message = if_msghdr2()
            _ = withUnsafeMutableBytes(of: &message) { data.copyBytes(to: $0, from: offset..<(offset + MemoryLayout<if_msghdr2>.size)) }
            if message.ifm_flags & (IFF_UP | IFF_RUNNING) == (IFF_UP | IFF_RUNNING),
               let name = nameForIndex(UInt32(message.ifm_index)), name.hasPrefix("en"),
               !name.dropFirst(2).isEmpty, name.dropFirst(2).allSatisfy({ $0.isNumber }) {
                // Count physical Wi-Fi/Ethernet only, avoiding VPN/bridge double counting.
                counters[name] = NetworkCounter(received: message.ifm_data.ifi_ibytes, sent: message.ifm_data.ifi_obytes)
            }
        }
        offset += Int(length)
    }
    return counters
}

func readNetworkCounters() -> [String: NetworkCounter]? {
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
    var size = 0
    guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var data = Data(count: size)
    let result = data.withUnsafeMutableBytes { sysctl(&mib, UInt32(mib.count), $0.baseAddress, &size, nil, 0) }
    guard result == 0 else { return nil }
    data.count = size
    return parseNetworkCounters(data) { index in
        var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        guard if_indextoname(index, &name) != nil else { return nil }
        return String(cString: name)
    }
}

final class NetworkSpeedController: NSObject {
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var sampler = NetworkSampler()
    private(set) var rate: NetworkRate?
    var onChange: (() -> Void)?
    var enabled: Bool { defaults.bool(forKey: "networkSpeed.enabled") }
    override init() { super.init(); defaults.register(defaults: ["networkSpeed.enabled": true]) }
    func start() {
        stop()
        guard enabled else { onChange?(); return }
        sample()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
        timer.tolerance = 0.15
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func stop() { timer?.invalidate(); timer = nil; sampler = NetworkSampler(); rate = nil }
    private func sample() {
        if let counters = readNetworkCounters() { rate = sampler.sample(counters, at: ProcessInfo.processInfo.systemUptime) }
        else { sampler = NetworkSampler(); rate = nil }
        onChange?()
    }
    @objc private func toggle() { defaults.set(!enabled, forKey: "networkSpeed.enabled"); start() }
    func menuItem() -> NSMenuItem {
        let root = NSMenuItem(title: L("实时网速"), action: nil, keyEquivalent: "")
        root.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: nil)
        let menu = NSMenu()
        let toggle = NSMenuItem(title: L("在顶栏显示网速"), action: #selector(toggle), keyEquivalent: "")
        toggle.target = self; toggle.state = enabled ? .on : .off; menu.addItem(toggle)
        if enabled {
            for line in [L("下载  ") + (rate.map { networkRateText($0.download) } ?? L("读取中…")), L("上传  ") + (rate.map { networkRateText($0.upload) } ?? L("读取中…"))] {
                menu.addItem(NSMenuItem(title: line, action: nil, keyEquivalent: ""))
            }
        }
        menu.addItem(NSMenuItem(title: L("Wi-Fi / 有线合计 · 每秒更新 · B/s 为字节每秒"), action: nil, keyEquivalent: ""))
        root.submenu = menu; return root
    }
    func statusImage() -> NSImage? {
        guard enabled else { return nil }
        let lines = ["↓" + (rate.map { networkRateText($0.download) } ?? "—"), "↑" + (rate.map { networkRateText($0.upload) } ?? "—")]
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor.black]
        let width = max(49, lines.map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 49)
        let image = NSImage(size: NSSize(width: ceil(width), height: 22))
        image.lockFocus()
        (lines[0] as NSString).draw(at: NSPoint(x: 0, y: 11), withAttributes: attributes)
        (lines[1] as NSString).draw(at: NSPoint(x: 0, y: 0), withAttributes: attributes)
        image.unlockFocus(); image.isTemplate = true
        image.accessibilityDescription = L("下载 ") + (rate.map { networkRateText($0.download) } ?? L("未知")) + L("，上传 ") + (rate.map { networkRateText($0.upload) } ?? L("未知"))
        return image
    }
}
