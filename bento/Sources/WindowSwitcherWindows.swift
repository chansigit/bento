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

func isSwitcherWindow(subrole: String?, modal: Bool) -> Bool {
    return subrole == kAXStandardWindowSubrole || (subrole == kAXDialogSubrole && !modal)
}

// Match only windows exposed by Accessibility, including always-on-top document windows.
func matchSwitcherWindow(_ candidates: [(offset: Int, element: [String: Any])], title: String, frame: CGRect) -> (offset: Int, element: [String: Any])? {
    let geometry = candidates.filter { _, info in
        guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
        return frame.width > 0 && frame.height > 0 && abs(rect.minX - frame.minX) < 2 && abs(rect.minY - frame.minY) < 2 && abs(rect.width - frame.width) < 2 && abs(rect.height - frame.height) < 2
    }
    let titled = candidates.filter { !title.isEmpty && ($0.element[kCGWindowName as String] as? String) == title }
    let both = geometry.filter { !title.isEmpty && ($0.element[kCGWindowName as String] as? String) == title }
    if both.count == 1 { return both[0] }
    if geometry.count == 1 { return geometry[0] }
    return titled.count == 1 ? titled[0] : nil
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
        let windows = switcherAttribute(axApp, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let previousCount = result.count
        for window in windows {
            // Finder can expose minimized folder windows as nonmodal AXDialog windows.
            guard isSwitcherWindow(subrole: switcherAttribute(window, kAXSubroleAttribute) as? String,
                                   modal: switcherAttribute(window, kAXModalAttribute) as? Bool ?? false) else { continue }
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
                (info[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier
            }
            let match = matchSwitcherWindow(candidates, title: title, frame: CGRect(origin: point, size: size))
            result.append(SwitcherWindowEntry(app: app, element: window, title: title.isEmpty ? (app.localizedName ?? L("窗口")) : title,
                                      id: match?.element[kCGWindowNumber as String] as? UInt32,
                                      rank: match?.offset ?? Int.max, minimized: minimized, aspect: size.height > 0 ? size.width / size.height : 1.5))
        }
        if result.count == previousCount && windows.isEmpty && defaults.bool(forKey: "windowSwitcher.showWindowless") {
            result.append(SwitcherWindowEntry(app: app, element: nil, title: app.localizedName ?? L("应用程序"), id: nil, rank: Int.max, minimized: false, aspect: 1))
        }
    }
    return result.sorted { $0.rank < $1.rank }
}

private var switcherFocusRequest = 0
func cancelSwitcherFocus() { switcherFocusRequest += 1 }

func focusSwitcherWindow(_ entry: SwitcherWindowEntry) {
    switcherFocusRequest += 1
    let request = switcherFocusRequest
    guard !entry.app.isTerminated else { NSSound.beep(); return }
    let sourcePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    entry.app.unhide()
    guard let element = entry.element else {
        // Activation alone cannot reopen an app whose last window was closed.
        if let url = entry.app.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if error != nil { DispatchQueue.main.async { if request == switcherFocusRequest { NSSound.beep() } } }
            }
        } else { entry.app.activate(options: [.activateIgnoringOtherApps]) }
        return
    }
    let axApp = AXUIElementCreateApplication(entry.app.processIdentifier)
    AXUIElementSetMessagingTimeout(axApp, 0.15)
    AXUIElementSetMessagingTimeout(element, 0.15)
    func raiseWindow() -> AXError {
        // The cached minimized flag can be stale by the time the shortcut is released.
        if switcherAttribute(element, kAXMinimizedAttribute) as? Bool == true {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        return AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }
    func activateApp() {
        entry.app.activate(options: [.activateIgnoringOtherApps])
        AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }
    _ = raiseWindow()
    activateApp()
    // Apps may restore another window during activation or finish unminimizing later.
    for delay in [0.08, 0.22, 0.5] {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard request == switcherFocusRequest, !entry.app.isTerminated else { return }
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            guard front == sourcePID || front == entry.app.processIdentifier else { switcherFocusRequest += 1; return }
            if front == entry.app.processIdentifier,
               let focused = switcherAttribute(axApp, kAXFocusedWindowAttribute), CFEqual(focused, element) { switcherFocusRequest += 1; return }
            guard switcherAttribute(element, kAXRoleAttribute) != nil else { return }
            let raised = raiseWindow()
            activateApp()
            if delay == 0.5 && raised != .success { NSSound.beep() }
        }
    }
}

func captureSwitcherThumbnail(_ id: CGWindowID) -> CGImage? {
    let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution])
    return cg.flatMap(makeSwitcherThumbnail)
}

func makeSwitcherThumbnail(_ source: CGImage) -> CGImage? {
    let scale = min(1, 640.0 / Double(max(source.width, source.height)))
    let width = max(1, Int(Double(source.width) * scale))
    let height = max(1, Int(Double(source.height) * scale))
    // Keep a defined profile through capture, resizing and AppKit display on either screen.
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.interpolationQuality = .high
    context.setBlendMode(.copy)
    context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

func sameSwitcherWindow(_ lhs: SwitcherWindowEntry, _ rhs: SwitcherWindowEntry) -> Bool {
    guard lhs.id == rhs.id, lhs.app.processIdentifier == rhs.app.processIdentifier else { return false }
    if let a = lhs.element, let b = rhs.element { return CFEqual(a, b) }
    return lhs.element == nil && rhs.element == nil
}

// Track actual focus, not Window Server stacking (raising an app can raise several windows).
final class SwitcherRecency {
    private var recent: [(pid: pid_t, window: AXUIElement?)] = []
    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var activationToken: NSObjectProtocol?
    var onChange: (() -> Void)?
    private func matches(_ pid: pid_t, _ window: AXUIElement?, _ other: (pid: pid_t, window: AXUIElement?)) -> Bool {
        guard pid == other.pid else { return false }
        if let a = window, let b = other.window { return CFEqual(a, b) }
        return window == nil && other.window == nil
    }
    func record(pid: pid_t, window: AXUIElement?) {
        if let first = recent.first, matches(pid, window, first) { return }
        recent.removeAll { matches(pid, window, $0) }
        recent.insert((pid, window), at: 0)
        recent = Array(recent.prefix(256))
        onChange?()
    }
    func ordered(_ windows: [SwitcherWindowEntry]) -> [SwitcherWindowEntry] {
        let indexed = windows.enumerated().map { item in
            (offset: item.offset, entry: item.element,
             rank: recent.firstIndex { matches(item.element.app.processIdentifier, item.element.element, $0) } ?? Int.max)
        }
        // Preserve the supplied order among windows that have not been used this session.
        return indexed.sorted { $0.rank == $1.rank ? $0.offset < $1.offset : $0.rank < $1.rank }.map { $0.entry }
    }
    func start() {
        guard activationToken == nil else { return }
        activationToken = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.observeFrontmost() }
        observeFrontmost()
    }
    func observeFrontmost() {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return }
        let pid = app.processIdentifier
        if observedPID != pid {
            removeObserver()
            let ax = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(ax, 0.05)
            var created: AXObserver?
            if AXObserverCreate(pid, { _, _, _, context in
                guard let context = context else { return }
                Unmanaged<SwitcherRecency>.fromOpaque(context).takeUnretainedValue().readFocus()
            }, &created) == .success, let created = created {
                let status = AXObserverAddNotification(created, ax, kAXFocusedWindowChangedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
                if status == .success {
                    observer = created; observedPID = pid
                    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
                }
            }
        }
        readFocus()
    }
    func readFocus() {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.05)
        let value = switcherAttribute(ax, kAXFocusedWindowAttribute)
        let window = value.flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
        record(pid: app.processIdentifier, window: window)
    }
    private func removeObserver() {
        if let observer = observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; observedPID = nil
    }
    func stop() {
        removeObserver()
        if let token = activationToken { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        activationToken = nil; recent.removeAll()
    }
    deinit { stop() }
}
