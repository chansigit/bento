import Cocoa
import ApplicationServices

func switcherAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

struct SwitcherWindowEntry {
    let app: NSRunningApplication
    let element: AXUIElement?
    let title: String
    let id: CGWindowID?
    let rank: Int
    let minimized: Bool
    let aspect: CGFloat
}

func readSwitcherWindows() -> [SwitcherWindowEntry] {
    guard hasAccessibilityPermission(prompt: false) else { return [] }
    let defaults = UserDefaults.standard
    let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    var result: [SwitcherWindowEntry] = []
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != getpid() {
        if switcherExcluded(app.bundleIdentifier ?? "", rules: defaults.string(forKey: "windowSwitcher.excludedApps") ?? "") { continue }
        if app.isHidden && !defaults.bool(forKey: "windowSwitcher.showHidden") { continue }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.15)
        guard let windows = switcherAttribute(axApp, kAXWindowsAttribute) as? [AXUIElement] else { continue }
        let previousCount = result.count
        for window in windows {
            guard switcherAttribute(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole else { continue }
            let minimized = switcherAttribute(window, kAXMinimizedAttribute) as? Bool ?? false
            if minimized && !defaults.bool(forKey: "windowSwitcher.showMinimized") { continue }
            let title = switcherAttribute(window, kAXTitleAttribute) as? String ?? ""
            var point = CGPoint.zero
            var size = CGSize.zero
            if let value = switcherAttribute(window, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
                AXValueGetValue(value as! AXValue, .cgPoint, &point)
            }
            if let value = switcherAttribute(window, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
                AXValueGetValue(value as! AXValue, .cgSize, &size)
            }
            let candidates = list.enumerated().filter { _, info in
                (info[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier && (info[kCGWindowLayer as String] as? Int) == 0
            }
            let matches = candidates.filter { _, info in
                guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                      let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
                return abs(rect.minX - point.x) < 2 && abs(rect.minY - point.y) < 2 && abs(rect.width - size.width) < 2 && abs(rect.height - size.height) < 2
            }
            let titled = candidates.filter { ($0.element[kCGWindowName as String] as? String) == title && !title.isEmpty }
            // shortcut: ambiguous public-API matches use an icon; use a window-ID API if Apple exposes one.
            let match = matches.count == 1 ? matches.first : (titled.count == 1 ? titled.first : nil)
            result.append(SwitcherWindowEntry(app: app, element: window, title: title.isEmpty ? (app.localizedName ?? "窗口") : title,
                                      id: match?.element[kCGWindowNumber as String] as? UInt32,
                                      rank: match?.offset ?? Int.max, minimized: minimized, aspect: size.height > 0 ? size.width / size.height : 1.5))
        }
        if result.count == previousCount && windows.isEmpty && defaults.bool(forKey: "windowSwitcher.showWindowless") {
            result.append(SwitcherWindowEntry(app: app, element: nil, title: app.localizedName ?? "应用", id: nil, rank: Int.max, minimized: false, aspect: 1))
        }
    }
    return result.sorted { $0.rank < $1.rank }
}

func focusSwitcherWindow(_ entry: SwitcherWindowEntry) {
    guard !entry.app.isTerminated else { NSSound.beep(); return }
    guard let element = entry.element else {
        entry.app.unhide(); entry.app.activate(options: [.activateIgnoringOtherApps]); return
    }
    if entry.minimized {
        guard AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success else { NSSound.beep(); return }
    }
    entry.app.unhide()
    entry.app.activate(options: [.activateIgnoringOtherApps])
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        if AXUIElementPerformAction(element, kAXRaiseAction as CFString) != .success { NSSound.beep() }
    }
}

func captureSwitcherThumbnail(_ id: CGWindowID) -> CGImage? {
    let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution])
    return cg.flatMap { source in
        let scale = min(1, 640.0 / Double(max(source.width, source.height)))
        let width = max(1, Int(Double(source.width) * scale))
        let height = max(1, Int(Double(source.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

func sameSwitcherWindow(_ lhs: SwitcherWindowEntry, _ rhs: SwitcherWindowEntry) -> Bool {
    guard lhs.id == rhs.id, lhs.app.processIdentifier == rhs.app.processIdentifier else { return false }
    if let a = lhs.element, let b = rhs.element { return CFEqual(a, b) }
    return lhs.element == nil && rhs.element == nil
}
