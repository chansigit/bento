import Cocoa

UserDefaults.standard.setVolatileDomain(["languageID": "zh-Hans"], forName: UserDefaults.argumentDomain)
import Darwin

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError(message) }
}
func rejects(_ message: String, _ body: () throws -> Void) {
    do { try body(); fatalError(message) } catch { checks += 1 }
}

var sampler = NetworkSampler()
check(sampler.sample(["en0": NetworkCounter(received: 500, sent: 300)], at: 1).download == 0, "first sample")
let rate = sampler.sample(["en0": NetworkCounter(received: 2500, sent: 900), "en1": NetworkCounter(received: 999999, sent: 999999)], at: 3)
check(rate.download == 1000 && rate.upload == 300, "actual elapsed time; new interface must not spike")
check(sampler.sample(["en0": NetworkCounter(received: 1, sent: 1)], at: 4).download == 0, "counter reset")
check(sampler.sample(["en0": NetworkCounter(received: 999999, sent: 999999)], at: 20).download == 0, "wake from sleep")
check(sampler.sample(["en0": NetworkCounter(received: 999999, sent: 999999)], at: 20).download == 0, "zero elapsed time")
var sum = NetworkSampler()
_ = sum.sample(["en0": NetworkCounter(received: 10, sent: 20), "en1": NetworkCounter(received: 100, sent: 200)], at: 0)
let combined = sum.sample(["en0": NetworkCounter(received: 40, sent: 40), "en1": NetworkCounter(received: 140, sent: 250)], at: 1)
check(combined.download == 70 && combined.upload == 70, "physical interface sum")
check(networkRateText(.nan) == "0 B/s" && networkRateText(-1) == "0 B/s", "invalid rate")
check(networkRateText(512) == "512 B/s" && networkRateText(2048) == "2 K/s", "small rates")
check(networkRateText(1572864) == "1.5 M/s" && networkRateText(1073741824) == "1.0 G/s", "large rates")
func message(index: UInt16, flags: Int32 = IFF_UP | IFF_RUNNING) -> Data {
    var value = if_msghdr2()
    value.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.size)
    value.ifm_type = UInt8(RTM_IFINFO2); value.ifm_index = index; value.ifm_flags = flags
    value.ifm_data.ifi_ibytes = 1 << 40; value.ifm_data.ifi_obytes = 1 << 41
    return withUnsafeBytes(of: &value) { Data($0) }
}
let messages = message(index: 1) + message(index: 2) + message(index: 3, flags: IFF_UP)
let parsed = parseNetworkCounters(messages) { [1: "en0", 2: "utun0", 3: "en1"][$0] }
check(parsed?.count == 1 && parsed?["en0"]?.received == 1 << 40 && parsed?["en0"]?.sent == 1 << 41, "64 bit counters, VPN and inactive excluded")
check(parseNetworkCounters(Data([0, 0, 0, 0])) { _ in "en0" } == nil, "zero length cannot loop")
check(parseNetworkCounters(Data(message(index: 1).dropLast())) { _ in "en0" } == nil, "truncated message")
check(parseNetworkCounters(Data([1, 2, 3])) { _ in "en0" } == nil, "short header")
let actual = readNetworkCounters()
check(actual != nil, "read actual interfaces")
print("Network checks passed; active physical interfaces: \(actual!.keys.sorted().joined(separator: ", "))")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let defaults = UserDefaults.standard
let oldArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
defaults.setVolatileDomain(["languageID": "zh-Hans", "capsLock.enabled": true, "capsLock.sound": false, "networkSpeed.enabled": true], forName: UserDefaults.argumentDomain)
let speed = NetworkSpeedController(); speed.start()
let speedImage = speed.statusImage()
check(speedImage?.size.height == 22 && speedImage!.size.width < 80 && speedImage!.isTemplate, "compact two-row template")
speed.stop()
let caps = CapsLockController()
var changes = 0
caps.onChange = { changes += 1 }
caps.update(true)
check(caps.isOn && changes == 1 && caps.panel?.isVisible == true, "Caps on HUD")
check(caps.panel?.ignoresMouseEvents == true && caps.panel?.canBecomeKey == false, "HUD does not interfere with typing or dragging")
caps.update(true)
check(changes == 1, "no duplicate notification")
caps.update(false)
check(!caps.isOn && changes == 2, "Caps off HUD")
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.95))
check(caps.panel?.isVisible == false, "HUD auto dismissal")
caps.update(true); caps.stop()
check(caps.panel?.isVisible == false, "stop hides HUD")
check(NSSound(named: NSSound.Name("Tink")) != nil && NSSound(named: NSSound.Name("Purr")) != nil, "on/off sounds available")
defaults.setVolatileDomain(oldArguments, forName: UserDefaults.argumentDomain)
print("Caps Lock checks passed: state changes, visual HUD, dismissal, pass-through, sound availability")

func hasIcon(_ url: URL) -> Bool {
    var bytes = [UInt8](repeating: 0, count: 32)
    return getxattr(url.path, "com.apple.FinderInfo", &bytes, bytes.count, 0, 0) == 32 && bytes[8] & 0x04 != 0
}
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("Bento-Utilities-" + UUID().uuidString, isDirectory: true)
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
let backups = root.appendingPathComponent("Backups", isDirectory: true)
let colors = FolderColorController(backupDirectory: backups)
let folder = root.appendingPathComponent("Original", isDirectory: true)
try fm.createDirectory(at: folder, withIntermediateDirectories: true)
let payload = Data("unchanged file bytes\n".utf8)
try payload.write(to: folder.appendingPathComponent("file.txt"))
try colors.apply(to: folder, colorIndex: 0)
check(hasIcon(folder), "set Finder custom icon flag")
let backup = try fm.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)[0]
let firstBackup = try Data(contentsOf: backup)
try colors.apply(to: folder, colorIndex: 3)
check(try! Data(contentsOf: backup) == firstBackup, "recolor preserves original backup")
let renamed = root.appendingPathComponent("Renamed", isDirectory: true)
try fm.moveItem(at: folder, to: renamed)
try colors.apply(to: renamed, colorIndex: nil)
check(!hasIcon(renamed), "restore default icon after rename")
check(try! Data(contentsOf: renamed.appendingPathComponent("file.txt")) == payload, "folder contents untouched")
check(!fm.fileExists(atPath: backup.path), "successful restore removes backup")
let custom = NSImage(size: NSSize(width: 512, height: 512))
custom.lockFocus(); NSColor.magenta.setFill(); NSRect(x: 0, y: 0, width: 512, height: 512).fill(); custom.unlockFocus()
check(NSWorkspace.shared.setIcon(custom, forFile: renamed.path, options: []), "prepare original custom icon")
func iconCenter(_ folder: URL) -> NSColor {
    let image = NSWorkspace.shared.icon(forFile: folder.path)
    image.size = NSSize(width: 512, height: 512)
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!.usingColorSpace(.sRGB)!
}
let originalColor = iconCenter(renamed)
rejects("restore without backup must not clear custom icon") { try colors.apply(to: renamed, colorIndex: nil) }
check(hasIcon(renamed), "original untouched without backup")
try colors.apply(to: renamed, colorIndex: 4)
try colors.apply(to: renamed, colorIndex: nil)
check(hasIcon(renamed), "restore original custom icon")
let center = iconCenter(renamed)
check(abs(center.redComponent - originalColor.redComponent) < 0.01 && abs(center.blueComponent - originalColor.blueComponent) < 0.01 && abs(center.greenComponent - originalColor.greenComponent) < 0.01, "custom icon original colors restored")
let link = root.appendingPathComponent("Link")
try fm.createSymbolicLink(at: link, withDestinationURL: renamed)
rejects("symlink must not mutate target") { try colors.apply(to: link, colorIndex: 1) }
rejects("invalid color") { try colors.apply(to: renamed, colorIndex: 999) }
try colors.apply(to: renamed, colorIndex: 1)
let damaged = try fm.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)[0]
try Data("broken backup".utf8).write(to: damaged)
rejects("corrupt backup must not clear icon") { try colors.apply(to: renamed, colorIndex: nil) }
check(hasIcon(renamed) && fm.fileExists(atPath: damaged.path), "preserve icon and corrupt backup for recovery")
let preview = try colors.icon(colorIndex: 0)
let rep = NSBitmapImageRep(data: preview.tiffRepresentation!)!
check(rep.pixelsWide >= 256 && rep.colorAt(x: 0, y: 0)!.alphaComponent == 0, "high resolution, transparent folder icon")
print("Folder checks passed: recolor, original backup, rename, custom restore, file contents, invalid input")
print("\(checks) utility checks passed")
