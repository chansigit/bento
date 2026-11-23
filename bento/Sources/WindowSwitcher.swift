import Cocoa
import SwiftUI

final class WindowSwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// This surface only spring-loads windows; it never consumes or copies the dragged file.
final class WindowSwitcherSurface: NSView {
    weak var owner: WindowSwitcherController?
    private var activeOwner: WindowSwitcherController? { owner?.panel?.contentView === self ? owner : nil }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .URL, .string, NSPasteboard.PasteboardType("NSFilenamesPboardType"), NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let window = window {
            activeOwner?.pointerMoved(to: window.convertPoint(toScreen: sender.draggingLocation), dragging: true)
        }
        return []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { activeOwner?.cancelDragHover() }
    override func draggingEnded(_ sender: NSDraggingInfo) { activeOwner?.finish(commit: false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { false }
}

final class WindowSwitcherCard: NSButton {
    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var preview: NSImage?
    var appIcon: NSImage?
    var caption = ""
    var selected = false
    var palette = skin(withID: nil).palette(dark: false)
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: palette.radius, yRadius: palette.radius)
        (selected ? palette.selection : palette.card).setFill()
        path.fill()
        (selected ? palette.accent : palette.border).setStroke()
        path.lineWidth = selected ? 2 : 1
        path.stroke()
        appIcon?.draw(in: NSRect(x: 9, y: bounds.height - 25, width: 16, height: 16))
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
        (caption as NSString).draw(in: NSRect(x: 31, y: bounds.height - 25, width: bounds.width - 40, height: 18), withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
        let area = NSRect(x: 8, y: 8, width: bounds.width - 16, height: bounds.height - 36)
        if let picture = preview ?? appIcon {
            let limit: CGFloat = preview == nil ? min(82, area.height * 0.88) : area.height
            let scale = min(area.width / max(1, picture.size.width), limit / max(1, picture.size.height))
            let size = NSSize(width: picture.size.width * scale, height: picture.size.height * scale)
            let rect = NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.imageInterpolation = .high
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).addClip()
            picture.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

struct SwitcherThumbnail {
    let window: SwitcherWindowEntry
    let image: NSImage
    let capturedAt: TimeInterval
}

final class WindowSwitcherController: NSObject, ObservableObject {
    @Published var permissionSummary = L("尚未检查")
    @Published var shortcutSummary = L("按一次 Cmd+Tab，松开 Cmd，验证实际切换。")
    @Published var checkingPermissions = false
    private var checkResult: [String: Any] = [:]
    private var checkingShortcut = false
    var settings: NSWindow?
    var panel: WindowSwitcherPanel?
    var tap: CFMachPort?
    var tapSource: CFRunLoopSource?
    var cached: [SwitcherWindowEntry] = []
    var entries: [SwitcherWindowEntry] = []
    var selected = 0
    var visible = false
    var demo = false
    var enabled = false
    var refreshing = false
    var columns = 4
    var pageSize = 8
    var images: [CGWindowID: SwitcherThumbnail] = [:]
    var requestedImages = Set<CGWindowID>()
    var pendingImages = Set<CGWindowID>()
    var generation = 0
    var consumed = Set<Int64>()
    var pointerLocation: NSPoint?
    var dragHoverIndex: Int?
    private var dragHoverTimer: Timer?
    private var dragInProgress = false
    private var sessionScreen: NSScreen?
    private var refreshTimer: Timer?
    private var previewMonitor: Any?
    private let defaults = UserDefaults.standard
    var wantsEnabled: Bool { defaults.bool(forKey: "windowSwitcher.enabled") }
    var conflictingApp: String? {
        NSWorkspace.shared.runningApplications.first { ["local.wintab.app", "com.lwouis.alt-tab-macos"].contains($0.bundleIdentifier ?? "") }?.localizedName
    }
    let worker = DispatchQueue(label: "local.wintab.windows", qos: .userInitiated)

    override init() {
        super.init()
        migrateWindowSwitcherPreferences(into: defaults, legacy: defaults.persistentDomain(forName: "local.wintab.app") ?? [:])
        defaults.register(defaults: ["windowSwitcher.enabled": true, "windowSwitcher.showMinimized": true, "windowSwitcher.showHidden": true, "windowSwitcher.showWindowless": true, "windowSwitcher.ignoredApps": "com.apple.ScreenSharing\ncom.microsoft.rdc.macos\ncom.teamviewer.TeamViewer\ncom.parallels.*"])
    }
    func start() {
        previewMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .mouseMoved]) { [weak self] event in
            guard let self = self, self.visible, self.demo else { return event }
            if event.type == .mouseMoved { self.pointerMoved(to: NSEvent.mouseLocation, dragging: false); return event }
            if event.keyCode == 53 || event.keyCode == 36 { self.finish(commit: false); return nil }
            if event.keyCode == 48 {
                self.keyboardSelection()
                self.selected = switcherWrappedIndex(self.selected, delta: event.modifierFlags.contains(.shift) ? -1 : 1, count: 6)
                self.render(); return nil
            }
            return event
        }
        apply()
    }
    func apply() {
        guard wantsEnabled, conflictingApp == nil, hasAccessibilityPermission(prompt: false) else { stop(); return }
        installTap()
        guard enabled, refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }
    func stop() {
        enabled = false
        finish(commit: false)
        generation += 1
        images.removeAll(); pendingImages.removeAll()
        refreshTimer?.invalidate(); refreshTimer = nil
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source = tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; tapSource = nil; consumed.removeAll(); cached.removeAll()
    }
    func shutdown() {
        stop()
        if let monitor = previewMonitor { NSEvent.removeMonitor(monitor) }
        previewMonitor = nil
    }
    func menuItem() -> NSMenuItem {
        apply()
        let root = NSMenuItem(title: L("窗口切换"), action: nil, keyEquivalent: "")
        root.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: nil)
        let menu = NSMenu()
        let toggle = NSMenuItem(title: L("启用 Cmd+Tab 窗口切换"), action: #selector(toggle), keyEquivalent: "")
        toggle.target = self; toggle.state = wantsEnabled ? .on : .off; menu.addItem(toggle)
        let state: String
        if let conflict = conflictingApp { state = L("请先退出 ") + conflict }
        else if !wantsEnabled { state = L("已暂停 · 使用系统 Cmd+Tab") }
        else if !hasAccessibilityPermission(prompt: false) { state = L("需要 Bento 的辅助功能权限") }
        else if !enabled { state = L("快捷键接管失败，请重新检查权限") }
        else { state = CGPreflightScreenCaptureAccess() ? L("已启用 · 窗口缩略图") : L("已启用 · 屏幕录制未授权，显示图标") }
        menu.addItem(NSMenuItem(title: state, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        for (title, action) in [(L("设置…"), #selector(showSettings)), (L("预览界面"), #selector(preview)), (L("检查权限并启用"), #selector(enable))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        root.submenu = menu
        return root
    }
    func refresh() {
        guard enabled, !refreshing, !visible else { return }
        refreshing = true
        worker.async {
            let windows = readSwitcherWindows()
            DispatchQueue.main.async {
                if self.enabled {
                    self.cached = windows
                    self.pruneThumbnails()
                }
                self.refreshing = false
            }
        }
    }
    @objc func toggle() {
        defaults.set(!wantsEnabled, forKey: "windowSwitcher.enabled")
        apply()
    }
    @objc func showSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 555), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = L("Bento 设置"); window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: WindowSwitcherSettingsView(owner: self)); window.center(); settings = window
        }
        settings?.title = L("Bento 设置")
        settings?.appearance = skin(withID: defaults.string(forKey: "skinID")).appearanceName.flatMap { NSAppearance(named: $0) }
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
        checkPermissions()
    }
    @objc func checkPermissions() {
        guard !checkingPermissions else { return }
        apply()
        checkingPermissions = true
        checkingShortcut = true
        shortcutSummary = L("按一次 Cmd+Tab，松开 Cmd，验证实际切换。")
        let accessibility = hasAccessibilityPermission(prompt: false)
        let screenCapture = CGPreflightScreenCaptureAccess()
        let tapActive = tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
        let conflict = conflictingApp
        permissionSummary = L("正在检查 Bento 的权限与真实窗口缩略图…")
        worker.async {
            let windows = accessibility ? readSwitcherWindows() : []
            let ids = Array(windows.filter { !$0.minimized && !$0.app.isHidden }.compactMap { $0.id }.prefix(3))
            let thumbnails = screenCapture ? ids.compactMap { captureSwitcherThumbnail($0) } : []
            let captured = thumbnails.count
            let colorSpaces = Array(Set(thumbnails.map { $0.colorSpace?.name as String? ?? "unknown" })).sorted()
            DispatchQueue.main.async {
                self.checkingPermissions = false
                self.permissionSummary = L("辅助功能：%@ · 屏幕录制：%@\n快捷键监听：%@ · 可访问窗口：%@\n真实缩略图：%@ / %@ 成功", String(describing: accessibility ? L("已授权") : L("未授权")), String(describing: screenCapture ? L("已授权") : L("未授权")), String(describing: tapActive ? L("运行中") : L("未启用")), String(describing: windows.count), String(describing: captured), String(describing: ids.count)) + (conflict.map { L("\n冲突应用：") + $0 } ?? "")
                self.checkResult = ["checkedAt": ISO8601DateFormatter().string(from: Date()), "appPath": Bundle.main.bundlePath, "accessibility": accessibility, "screenCapture": screenCapture, "eventTap": tapActive, "windows": windows.count, "thumbnailAttempts": ids.count, "thumbnailSuccesses": captured, "thumbnailColorSpaces": colorSpaces, "conflict": conflict ?? "", "shortcutReceived": false]
                self.saveCheckResult()
            }
        }
    }
    private func saveCheckResult() {
        // Diagnostic metadata only: no window titles or captured images are written.
        do {
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("com.sijie.gtime")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: checkResult, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("window-switcher-check.json"), options: .atomic)
        } catch { permissionSummary += L("\n检查报告保存失败：") + error.localizedDescription }
    }
    func accessibilitySettings() {
        _ = hasAccessibilityPermission(prompt: true)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func screenSettings() {
        _ = CGRequestScreenCaptureAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    @objc func enable() {
        if let conflict = conflictingApp { message(L("快捷键冲突"), L("请先退出 ") + conflict + L("，再启用 Bento 的窗口切换。")); return }
        guard hasAccessibilityPermission(prompt: false) else { message(L("需要辅助功能权限"), L("请在系统设置中允许 Bento，然后再次点击检查权限并启用。")); return }
        defaults.set(true, forKey: "windowSwitcher.enabled")
        apply()
        if enabled { message(L("Bento 窗口切换已启用"), CGPreflightScreenCaptureAccess() ? L("按住 Cmd，再按 Tab 选择窗口。") : L("允许 Bento 的屏幕录制权限后可显示缩略图。目前使用应用图标。")) }
        else { message(L("无法接管快捷键"), L("请检查 Bento 的辅助功能权限，然后重新打开 Bento。")) }
    }
    func message(_ title: String, _ detail: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail; alert.runModal()
    }
    func installTap() {
        if tap != nil { enabled = true; return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.mouseMoved.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, context in
            guard let context = context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<WindowSwitcherController>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                owner.finish(commit: false)
                if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            return owner.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap = tap else { enabled = false; return }
        tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true); enabled = true
    }
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .mouseMoved || type == .leftMouseDragged {
            if visible { pointerMoved(to: NSEvent.mouseLocation, dragging: type == .leftMouseDragged) }
            return false
        }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp { return consumed.remove(key) != nil }
        if demo { return false }
        guard enabled else { return false }
        if type == .flagsChanged {
            if visible && !demo && !event.flags.contains(.maskCommand) { finish(commit: true) }
            return false
        }
        guard type == .keyDown else { return false }
        if key == 48 && event.flags.contains(.maskCommand) && !event.flags.contains(.maskAlternate) && !event.flags.contains(.maskControl) {
            let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            if !visible && switcherExcluded(bundle, rules: UserDefaults.standard.string(forKey: "windowSwitcher.ignoredApps") ?? "") { return false }
            if !visible {
                entries = cached.filter { !$0.app.isTerminated }
                guard !entries.isEmpty else { refresh(); return false }
                selected = 0; demo = false; visible = true
                beginPointerSession()
                if checkingShortcut {
                    shortcutSummary = L("已收到 Cmd+Tab，等待松键切换。")
                    checkResult["shortcutReceived"] = true
                    saveCheckResult()
                }
            }
            keyboardSelection()
            selected = switcherWrappedIndex(selected, delta: event.flags.contains(.maskShift) ? -1 : 1, count: entries.count)
            render(); capture(); consumed.insert(key); return true
        }
        if visible {
            if [123, 124, 125, 126].contains(key) { keyboardSelection() }
            switch key {
            case 53: finish(commit: false)
            case 36, 76: finish(commit: true)
            case 123: selected = switcherWrappedIndex(selected, delta: -1, count: entries.count); render()
            case 124: selected = switcherWrappedIndex(selected, delta: 1, count: entries.count); render()
            case 125: selected = switcherWrappedIndex(selected, delta: columns, count: entries.count); render()
            case 126: selected = switcherWrappedIndex(selected, delta: -columns, count: entries.count); render()
            default: return false
            }
            capture(); consumed.insert(key); return true
        }
        return false
    }
    @objc func preview() { finish(commit: false); demo = true; visible = true; selected = 1; beginPointerSession(); render() }
    @objc func choose(_ sender: NSButton) {
        guard visible, (demo ? (0..<6).contains(sender.tag) : entries.indices.contains(sender.tag)) else { return }
        selected = sender.tag; finish(commit: true)
    }
    func beginPointerSession() {
        NotificationCenter.default.post(name: .bentoDismissMenu, object: nil)
        pointerLocation = NSEvent.mouseLocation
        sessionScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        dragInProgress = CGEventSource.buttonState(.combinedSessionState, button: .left)
        cancelDragHover()
    }
    func keyboardSelection() {
        pointerLocation = NSEvent.mouseLocation
        cancelDragHover()
    }
    func cancelDragHover() {
        dragHoverTimer?.invalidate(); dragHoverTimer = nil; dragHoverIndex = nil
    }
    func cardIndex(at screenPoint: NSPoint) -> Int? {
        guard let panel = panel, let root = panel.contentView else { return nil }
        let point = root.convert(panel.convertPoint(fromScreen: screenPoint), from: nil)
        return root.subviews.compactMap { $0 as? WindowSwitcherCard }.first { $0.frame.contains(point) }?.tag
    }
    func pointerMoved(to point: NSPoint, dragging: Bool) {
        guard visible else { return }
        let dragChanged = dragInProgress != dragging
        dragInProgress = dragging
        guard pointerLocation != point else { return }
        pointerLocation = point
        guard let index = cardIndex(at: point) else { cancelDragHover(); return }
        guard demo ? (0..<6).contains(index) : entries.indices.contains(index) else { cancelDragHover(); return }
        let selectionChanged = selected != index
        selected = index
        // Keep the native drag destination alive; redraw only cards whose state changed.
        if selectionChanged {
            for case let card as WindowSwitcherCard in panel?.contentView?.subviews ?? [] {
                let highlighted = card.tag == selected
                if card.selected != highlighted {
                    card.selected = highlighted
                    card.setAccessibilityValue(highlighted ? L("已选择") : "")
                    card.needsDisplay = true
                }
            }
        }
        if selectionChanged || dragChanged { updateFooter() }
        guard dragging, !demo else { cancelDragHover(); return }
        if dragHoverIndex != index {
            cancelDragHover(); dragHoverIndex = index
            let timer = Timer(timeInterval: 0.65, repeats: false) { [weak self] _ in
                self?.activateDragHover(at: NSEvent.mouseLocation, buttonDown: CGEventSource.buttonState(.combinedSessionState, button: .left))
            }
            dragHoverTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    func activateDragHover(at point: NSPoint, buttonDown: Bool) {
        guard visible, !demo, buttonDown, let index = dragHoverIndex,
              selected == index, cardIndex(at: point) == index else { cancelDragHover(); return }
        finish(commit: true)
    }
    func updateFooter() {
        guard let footer = panel?.contentView?.subviews.compactMap({ $0 as? NSTextField }).first else { return }
        footer.stringValue = demo ? L("示例卡片 · 移动鼠标选择，点击关闭") :
            (dragInProgress ? L("拖到缩略图停留或松开 ⌘ → 切换后再放下文件") : L("鼠标选择 · 点击 / 松开 ⌘ 确认 · ⇥ 切换 · esc 取消")) + "     \(selected + 1) / \(entries.count)"
    }
    func finish(commit: Bool) {
        let target = visible && !demo && entries.indices.contains(selected) && commit ? entries[selected] : nil
        visible = false; demo = false
        cancelDragHover(); pointerLocation = nil; sessionScreen = nil; dragInProgress = false
        panel?.orderOut(nil); panel?.contentView = nil
        requestedImages.removeAll(); entries.removeAll()
        if let target = target {
            if let index = cached.firstIndex(where: { item in
                guard item.app.processIdentifier == target.app.processIdentifier else { return false }
                if let a = item.element, let b = target.element { return CFEqual(a, b) }
                return item.element == nil && target.element == nil
            }) { cached.insert(cached.remove(at: index), at: 0) }
            focusSwitcherWindow(target)
            if checkingShortcut {
                checkingShortcut = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    let appMatches = NSWorkspace.shared.frontmostApplication?.processIdentifier == target.app.processIdentifier
                    let focused = switcherAttribute(AXUIElementCreateApplication(target.app.processIdentifier), kAXFocusedWindowAttribute)
                    let windowMatches = target.element.map { element in focused.map { CFEqual(element, $0) } ?? false } ?? true
                    let verified = appMatches && windowMatches
                    self.shortcutSummary = verified ? L("已验证：收到 Cmd+Tab，并成功聚焦所选窗口。") : L("已收到 Cmd+Tab，但未确认目标窗口获得焦点。")
                    self.checkResult["focusVerified"] = verified
                    self.saveCheckResult()
                }
            }
        }
    }
    func pruneThumbnails() {
        guard CGPreflightScreenCaptureAccess() else { images.removeAll(); return }
        retainLiveThumbnails()
    }
    func retainLiveThumbnails() {
        images = images.filter { _, thumbnail in
            cached.contains { sameSwitcherWindow($0, thumbnail.window) }
        }
        // Bound retained images to 64 thumbnails, each at most 640 × 640 pixels.
        for id in images.sorted(by: { $0.value.capturedAt > $1.value.capturedAt }).dropFirst(64).map({ $0.key }) {
            images.removeValue(forKey: id)
        }
    }
    func completeCapture(_ entry: SwitcherWindowEntry, image: CGImage?, generation requestGeneration: Int) {
        guard enabled, generation == requestGeneration, let id = entry.id else { return }
        pendingImages.remove(id)
        guard cached.contains(where: { sameSwitcherWindow($0, entry) }), let cg = image else { return }
        let thumbnail = SwitcherThumbnail(window: entry, image: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)), capturedAt: ProcessInfo.processInfo.systemUptime)
        images[id] = thumbnail
        retainLiveThumbnails()
        guard visible, !demo else { return }
        for case let card as WindowSwitcherCard in panel?.contentView?.subviews ?? [] {
            guard entries.indices.contains(card.tag), sameSwitcherWindow(entries[card.tag], entry) else { continue }
            card.preview = thumbnail.image
            card.needsDisplay = true
        }
    }
    func capture() {
        guard visible, !demo else { return }
        guard CGPreflightScreenCaptureAccess() else { images.removeAll(); return }
        let current = generation
        let now = ProcessInfo.processInfo.systemUptime
        let indices = panel?.contentView?.subviews.compactMap { ($0 as? WindowSwitcherCard)?.tag } ?? []
        for index in indices {
            guard entries.indices.contains(index) else { continue }
            let entry = entries[index]
            guard let id = entry.id, !pendingImages.contains(id), !requestedImages.contains(id) else { continue }
            if let thumbnail = images[id], sameSwitcherWindow(thumbnail.window, entry), now - thumbnail.capturedAt < 2 { continue }
            requestedImages.insert(id)
            pendingImages.insert(id)
            worker.async {
                let thumbnail = captureSwitcherThumbnail(id)
                DispatchQueue.main.async { self.completeCapture(entry, image: thumbnail, generation: current) }
            }
        }
    }
    func render() {
        guard visible else { return }
        let screen = sessionScreen ?? NSScreen.main!
        let area = screen.visibleFrame
        let size = UserDefaults.standard.integer(forKey: "windowSwitcher.cardSize")
        let count = demo ? 6 : entries.count
        let aspects: [CGFloat] = demo ? [1.65, 1, 1.7, 1.5, 1.7, 0.9] : entries.map { $0.aspect }
        let maxWidth = min(1100, area.width * 0.78) - 24
        let maxHeight = min(680, area.height * 0.78)
        var height: CGFloat = size == 1 ? 112 : size == 3 ? 180 : 142
        var layout = switcherFlowLayout(aspects: aspects, height: height, maxWidth: maxWidth)
        if size == 0 {
            while layout.height + 42 > maxHeight && height > 92 {
                height -= 5
                layout = switcherFlowLayout(aspects: aspects, height: height, maxWidth: maxWidth)
            }
        }
        let rowsPerPage = max(1, Int((maxHeight - 42) / (height + switcherCardGap)))
        let selectedRow = layout.rows[selected]
        let firstRow = selectedRow / rowsPerPage * rowsPerPage
        let shown = (0..<count).filter { layout.rows[$0] >= firstRow && layout.rows[$0] < firstRow + rowsPerPage }
        let panelWidth = layout.width + 24
        let shownRows = min(rowsPerPage, (layout.rows.last ?? 0) + 1 - firstRow)
        let panelHeight = CGFloat(shownRows) * (height + switcherCardGap) + 42
        columns = max(1, layout.rows.filter { $0 == selectedRow }.count)
        pageSize = max(1, shown.count)
        if panel == nil {
            panel = WindowSwitcherPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel?.acceptsMouseMovedEvents = true
            panel?.title = L("Bento 窗口切换"); panel?.isOpaque = false; panel?.backgroundColor = .clear; panel?.hasShadow = true
            panel?.level = .popUpMenu; panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel?.hidesOnDeactivate = false
        }
        let theme = UserDefaults.standard.integer(forKey: "windowSwitcher.theme")
        panel?.appearance = theme == 0 ? skin(withID: defaults.string(forKey: "skinID")).appearanceName.flatMap { NSAppearance(named: $0) } : NSAppearance(named: theme == 1 ? .aqua : .darkAqua)
        panel?.setFrame(NSRect(x: area.midX - panelWidth / 2, y: area.midY - panelHeight / 2, width: panelWidth, height: panelHeight), display: true)
        let root = WindowSwitcherSurface(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        root.owner = self
        let dark = panel?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let palette = skin(withID: defaults.string(forKey: "skinID")).palette(dark: dark)
        root.wantsLayer = true; root.layer?.cornerRadius = palette.radius + 8
        // A solid surface keeps desktop colors and vibrancy out of window previews.
        root.layer?.backgroundColor = palette.surface.cgColor
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 0.5
        root.layer?.borderColor = palette.border.cgColor
        let canPreview = CGPreflightScreenCaptureAccess()
        let samples = [L("项目 · 访达"), L("设计文档 · 浏览器"), L("代码 · 编辑器"), L("团队消息"), L("终端"), L("备忘录")]
        let symbols = ["folder", "globe", "curlybraces", "bubble.left.and.bubble.right", "terminal", "note.text"]
        for i in shown {
            var frame = layout.frames[i]
            frame.origin.x += 12
            frame.origin.y = panelHeight - 12 - (frame.origin.y - CGFloat(firstRow) * (height + switcherCardGap)) - height
            let card = WindowSwitcherCard(frame: frame)
            card.palette = palette
            card.isBordered = false; card.selected = i == selected; card.tag = i; card.target = self; card.action = #selector(choose(_:))
            if demo {
                card.caption = samples[i]
                if let symbol = NSImage(systemSymbolName: symbols[i], accessibilityDescription: samples[i]) {
                    card.appIcon = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
                        symbol.draw(in: rect)
                        (dark ? NSColor.white : NSColor.black).setFill()
                        rect.fill(using: .sourceIn)
                        return true
                    }
                }
            } else {
                let entry = entries[i]
                card.caption = entry.title + (entry.minimized ? L(" · 已最小化") : "")
                card.appIcon = entry.app.icon
                if canPreview, let id = entry.id, let thumbnail = images[id], sameSwitcherWindow(thumbnail.window, entry) { card.preview = thumbnail.image }
            }
            card.setAccessibilityLabel(card.caption); card.setAccessibilityValue(card.selected ? L("已选择") : "")
            root.addSubview(card)
        }
        let footer = NSTextField(labelWithString: "")
        footer.tag = -1
        footer.font = .systemFont(ofSize: 10); footer.textColor = .secondaryLabelColor
        footer.frame = NSRect(x: 14, y: 9, width: panelWidth - 28, height: 14); root.addSubview(footer)
        panel?.contentView = root
        updateFooter()
        if demo { panel?.makeKeyAndOrderFront(nil) } else { panel?.orderFrontRegardless() }
    }
}
