import Cocoa
import Carbon

final class SnipPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
final class SnipPinView: SnipCanvas {
    weak var owner: SnipPin?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if owner?.editing == true && tool != .selection { super.mouseDown(with: event); return }
        if event.clickCount == 2 { owner?.close(); return }
        window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(self)
        window?.performDrag(with: event)
    }
    override func mouseDragged(with event: NSEvent) { if draft != nil { super.mouseDragged(with: event) } }
    override func mouseUp(with event: NSEvent) { if draft != nil { super.mouseUp(with: event) } }
    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > 0.01 else { return }
        if event.modifierFlags.contains(.command) { owner?.changeOpacity(event.scrollingDeltaY > 0 ? 0.05 : -0.05) }
        else { owner?.zoom(event.scrollingDeltaY > 0 ? 1.05 : 1 / 1.05) }
    }
    private func copyShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "c",
              window?.firstResponder === self, let owner = owner else { return false }
        owner.copyImage(); return true
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if copyShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if copyShortcut(event) { return }
        if event.keyCode == 53 && owner?.editing == true { owner?.toggleEditing(); return }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "z" { if event.modifierFlags.contains(.shift) { owner?.redoMark() } else { owner?.undoMark() }; return }
        if event.keyCode == 53 || (event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "w") { owner?.close(); return }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "s" { owner?.saveImage(); return }
        if event.characters == "+" || event.characters == "=" { owner?.zoom(1.1); return }
        if event.characters == "-" { owner?.zoom(1 / 1.1); return }
        super.keyDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? { owner?.contextMenu() }
}
final class SnipPin: NSWindowController, NSWindowDelegate {
    var image: CGImage { canvas.document.image }
    let canvas: SnipPinView
    private(set) var editing = false
    private(set) var controls: NSPanel?
    private var toggleButton: NSButton!
    private var toolRow: NSStackView!
    private var actionRow: NSStackView!
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private(set) var colorPicker: SnipColorPicker!
    var onClose: (() -> Void)?
    private let baseSize: CGSize
    init(image: CGImage, screen: NSScreen, frame originalFrame: CGRect? = nil) {
        let frame = screen.visibleFrame
        let scale = min(1 / screen.backingScaleFactor, min(frame.width * 0.7 / CGFloat(image.width), frame.height * 0.7 / CGFloat(image.height)))
        baseSize = originalFrame?.size ?? CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        canvas = SnipPinView(image: image, size: baseSize)
        let centeredFrame = CGRect(x: frame.midX - baseSize.width / 2, y: frame.midY - baseSize.height / 2, width: baseSize.width, height: baseSize.height)
        let panel = SnipPanel(contentRect: originalFrame ?? centeredFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = L("Bento 贴图"); panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.level = .floating; panel.hasShadow = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel); panel.delegate = self
        canvas.owner = self
        canvas.toolTip = L("拖动移动 · 滚轮缩放 · 下边缘展开编辑")
        canvas.setAccessibilityLabel(L("Bento 悬浮贴图")); panel.contentView = canvas
        canvas.onChange = { [weak self] in self?.updateUndo() }
        canvas.askText = { [weak self] _ in self?.textPrompt() }
        makeControls(); positionControls()
        NotificationCenter.default.addObserver(self, selector: #selector(updateLanguage), name: BentoLanguage.changed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateLanguage), name: .bentoSkinChanged, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show() { window?.orderFrontRegardless(); controls?.orderFrontRegardless() }
    func hide() { controls?.orderOut(nil); window?.orderOut(nil) }
    func windowWillClose(_ notification: Notification) {
        if let controls = controls { window?.removeChildWindow(controls); controls.close() }; controls = nil
        colorPicker?.dismissPicker(); onClose?()
    }
    func windowDidMove(_ notification: Notification) { positionControls() }
    func windowDidResize(_ notification: Notification) { positionControls() }
    @objc private func updateLanguage() {
        let visible = window?.isVisible == true
        colorPicker?.dismissPicker()
        if let old = controls { window?.removeChildWindow(old); old.close() }
        makeControls()
        toggleButton.title = editing ? L("收起 ﹀") : L("编辑 ﹀")
        window?.title = L("Bento 贴图")
        canvas.toolTip = L("拖动移动 · 滚轮缩放 · 下边缘展开编辑")
        canvas.setAccessibilityLabel(L("Bento 悬浮贴图"))
        positionControls()
        if !visible { controls?.orderOut(nil) }
    }
    private func makeControls() {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = L("Bento 贴图编辑菜单"); panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let skin = skin(withID: UserDefaults.standard.string(forKey: "skinID"))
        panel.appearance = skin.appearanceName.flatMap { NSAppearance(named: $0) }
        let palette = skin.palette(dark: panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        let root = NSView(); root.wantsLayer = true
        root.layer?.backgroundColor = palette.surface.cgColor
        root.layer?.borderWidth = 1; root.layer?.borderColor = palette.border.cgColor
        root.layer?.cornerRadius = palette.radius; root.layer?.masksToBounds = true; panel.contentView = root
        toggleButton = NSButton(title: L("编辑 ﹀"), target: self, action: #selector(toggleEditing)); toggleButton.bezelStyle = .rounded
        root.addSubview(toggleButton)
        let tools = snipToolControl(target: self, action: #selector(changeTool(_:)), selected: canvas.tool)
        colorPicker = SnipColorPicker(color: canvas.color); colorPicker.onChange = { [weak self] color in self?.canvas.color = color }
        colorPicker.widthAnchor.constraint(equalToConstant: max(100, colorPicker.fittingSize.width)).isActive = true
        undoButton = NSButton(title: L("撤销"), target: self, action: #selector(undoMark)); undoButton.bezelStyle = .rounded
        redoButton = NSButton(title: L("重做"), target: self, action: #selector(redoMark)); redoButton.bezelStyle = .rounded
        snipIconButton(undoButton, symbol: "arrow.uturn.backward"); snipIconButton(redoButton, symbol: "arrow.uturn.forward")
        toolRow = NSStackView(views: [tools, undoButton, redoButton]); toolRow.spacing = 7
        let copy = NSButton(title: L("复制"), target: self, action: #selector(copyImage)); copy.bezelStyle = .rounded
        let save = NSButton(title: L("保存 PNG…"), target: self, action: #selector(saveImage)); save.bezelStyle = .rounded
        let close = NSButton(title: L("关闭贴图"), target: self, action: #selector(dismiss)); close.bezelStyle = .rounded
        snipIconButton(copy, symbol: "doc.on.doc"); snipIconButton(save, symbol: "square.and.arrow.down"); snipIconButton(close, symbol: "xmark")
        actionRow = NSStackView(views: [colorPicker!, copy, save, close]); actionRow.spacing = 8
        root.addSubview(toolRow); root.addSubview(actionRow)
        controls = panel; window?.addChildWindow(panel, ordered: .above); updateUndo()
    }
    private func positionControls() {
        guard let window = window, let controls = controls else { return }
        let screen = window.screen ?? NSScreen.main!
        let collapsedWidth = max(76, toggleButton.fittingSize.width)
        let expandedWidth = max(400, max(toolRow.fittingSize.width, actionRow.fittingSize.width) + 20)
        let visible = screen.visibleFrame, size = CGSize(width: editing ? min(expandedWidth, visible.width) : collapsedWidth, height: editing ? 104 : 26)
        let frame = CGRect(x: max(visible.minX, min(visible.maxX - size.width, window.frame.midX - size.width / 2)), y: max(visible.minY, window.frame.minY - size.height - 3), width: size.width, height: size.height)
        controls.setFrame(frame, display: true)
        toggleButton.frame = CGRect(x: editing ? 8 : 0, y: size.height - 26, width: collapsedWidth, height: 26)
        toolRow.frame = CGRect(x: 10, y: 41, width: size.width - 20, height: 30)
        actionRow.frame = CGRect(x: 10, y: 7, width: size.width - 20, height: 28)
        toolRow.isHidden = !editing; actionRow.isHidden = !editing
    }
    @objc func toggleEditing() {
        editing.toggle(); if !editing { colorPicker.dismissPicker() }; canvas.cancelDraft()
        toggleButton.title = editing ? L("收起 ﹀") : L("编辑 ﹀")
        positionControls()
        window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(canvas)
    }
    @objc private func changeTool(_ sender: NSSegmentedControl) { canvas.tool = SnipTool.allCases[sender.selectedSegment] }
    private func updateUndo() { undoButton?.isEnabled = !canvas.document.marks.isEmpty; redoButton?.isEnabled = !canvas.document.redoMarks.isEmpty }
    @objc func undoMark() { canvas.document.undo(); canvas.needsDisplay = true; updateUndo() }
    @objc func redoMark() { canvas.document.redo(); canvas.needsDisplay = true; updateUndo() }
    private func textPrompt() -> String? {
        let alert = NSAlert(); alert.messageText = L("添加文字"); alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 300, height: 26)); alert.accessoryView = field
        alert.addButton(withTitle: L("添加")); alert.addButton(withTitle: L("取消")); alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
    func renderedImage() -> CGImage? {
        let result = canvas.document.rendered()
        if result == nil { snipError(L("无法生成标注图像，请关闭部分贴图后重试。")) }
        return result
    }

    func zoom(_ factor: CGFloat) {
        guard let window = window else { return }
        let frame = window.frame
        let minimumScale = max(0.1, 16 / max(baseSize.width, baseSize.height))
        let scale = min(5, max(minimumScale, frame.width * factor / baseSize.width))
        let width = baseSize.width * scale, height = baseSize.height * scale
        window.setFrame(CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height), display: true)
        window.contentView?.needsDisplay = true; positionControls()
    }
    func changeOpacity(_ delta: CGFloat) { if let window = window { window.alphaValue = min(1, max(0.2, window.alphaValue + delta)) } }
    @objc func copyImage() { if let image = renderedImage(), !copySnip(image) { snipError(L("无法复制图像。")) } }
    @objc func saveImage() { if let image = renderedImage() { saveSnip(image, window: window) } }
    @objc private func reset() {
        guard let window = window else { return }
        let frame = window.frame; window.alphaValue = 1
        window.setFrame(CGRect(x: frame.midX - baseSize.width / 2, y: frame.midY - baseSize.height / 2, width: baseSize.width, height: baseSize.height), display: true)
    }
    @objc private func dismiss() { close() }
    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        for (title, action) in [(editing ? L("收起编辑菜单") : L("展开编辑菜单"), #selector(toggleEditing)), (L("复制图像"), #selector(copyImage)), (L("保存 PNG…"), #selector(saveImage)), (L("恢复大小与不透明度"), #selector(reset)), (L("关闭贴图"), #selector(dismiss))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("滚轮缩放 · ⌘滚轮调透明度"), action: nil, keyEquivalent: ""))
        return menu
    }
}

final class SnippingController: NSObject {
    private(set) var editor: SnipEditor?
    private(set) var pins: [SnipPin] = []
    private var selection: SnipSelection?
    private let clipboardWriter = SnipClipboardWriter()
    private var handler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []
    private var hotKeyError = false
    private var pinsHidden = false
    private var stopped = false
    private var pendingCapture = false
    var hotKeysEnabled: Bool { UserDefaults.standard.bool(forKey: "snipping.hotKeys") }
    override init() { super.init(); UserDefaults.standard.register(defaults: ["snipping.hotKeys": true]) }
    func start() {
        stopped = false; unregisterKeys(); hotKeyError = false
        guard hotKeysEnabled else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetEventDispatcherTarget(), { _, event, data in
            guard let event = event, let data = data else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr, id.signature == 0x42534E50 else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<SnippingController>.fromOpaque(data).takeUnretainedValue()
            DispatchQueue.main.async { [weak owner] in
                guard let owner = owner, !owner.stopped else { return }
                if id.id == 1 { owner.capture() } else if id.id == 2 { owner.pinClipboard() } else { owner.togglePins() }
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else { hotKeyError = true; return }
        for (key, id, modifiers) in [(kVK_ANSI_1, 1, cmdKey), (kVK_ANSI_P, 2, controlKey | optionKey), (kVK_ANSI_P, 3, controlKey | optionKey | shiftKey)] {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(key), UInt32(modifiers), EventHotKeyID(signature: 0x42534E50, id: UInt32(id)), GetEventDispatcherTarget(), 0, &reference)
            if status == noErr, let reference = reference { hotKeys.append(reference) } else { hotKeyError = true }
        }
    }
    private func unregisterKeys() {
        hotKeys.forEach { UnregisterEventHotKey($0) }; hotKeys.removeAll()
        if let handler = handler { RemoveEventHandler(handler) }; handler = nil
    }
    func stop() {
        stopped = true; unregisterKeys(); clipboardWriter.cancel()
        selection?.close(); selection = nil
        editor?.close(); editor = nil
        for pin in pins { pin.onClose = nil; pin.close() }; pins.removeAll()
    }
    @objc func capture() {
        NotificationCenter.default.post(name: .bentoDismissMenu, object: nil)
        guard !pendingCapture, selection == nil else { return }
        if let editor = editor { editor.show(); return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            let alert = NSAlert(); alert.messageText = L("Bento 需要屏幕录制权限")
            alert.informativeText = L("请在系统设置中允许 /Applications/Bento.app，重启 Bento 后再截图。")
            alert.addButton(withTitle: L("打开系统设置")); alert.addButton(withTitle: L("取消"))
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }
            return
        }
        pendingCapture = true
        // Allow one display frame for the status menu to disappear before capturing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self = self else { return }
            self.pendingCapture = false
            guard !self.stopped else { return }
            self.beginCapture()
        }
    }
    private func beginCapture() {
        let selection = SnipSelection(); self.selection = selection
        selection.finished = { [weak self] capture in self?.finishCapture(capture) }
        selection.show { [weak self, weak selection] success in
            guard let self = self, let selection = selection, self.selection === selection else { return }
            if !success { self.selection = nil; snipError(L("无法读取屏幕。请检查 Bento 的屏幕录制权限后重试。")) }
        }
    }
    func finishCapture(_ capture: SnipCapture?) {
        selection?.close(); selection = nil
        guard let capture = capture else { return }
        let rect = snipPixelRect(capture.region, viewSize: capture.screenFrame.size, imageSize: CGSize(width: capture.snapshot.width, height: capture.snapshot.height))
        // Detach the small crop from the full-display buffer before retaining it as a sticker.
        guard rect.width * rect.height <= 40_000_000, let cropped = capture.snapshot.cropping(to: rect),
              let image = SnipDocument(image: cropped).rendered() else { snipError(L("无法生成贴图，请缩小截图区域后重试。")); return }
        pin(image, frame: capture.region.offsetBy(dx: capture.screenFrame.minX, dy: capture.screenFrame.minY))
        clipboardWriter.copy(image) { snipError(L("无法复制图像。")) }
    }
    func edit(_ image: CGImage, capture: SnipCapture? = nil) {
        guard Double(image.width) * Double(image.height) <= 40_000_000 else { snipError(L("图像超过 4000 万像素，请缩小截图区域。")); return }
        guard editor == nil else { editor?.show(); return }
        let editor = SnipEditor(image: image, capture: capture); self.editor = editor
        editor.onPin = { [weak self] image in self?.pin(image) }
        editor.onClose = { [weak self] in self?.editor = nil }
        editor.show()
    }
    @objc func pinClipboard() {
        guard let image = NSImage(pasteboard: .general), let cg = snipImage(image) else { snipError(L("剪贴板里没有可贴出的图像，或图像超过 4000 万像素。请先复制一张图片。")); return }
        pin(cg)
    }
    func pin(_ image: CGImage, frame: CGRect? = nil) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let pin = SnipPin(image: image, screen: screen, frame: frame)
        pin.onClose = { [weak self, weak pin] in self?.pins.removeAll { $0 === pin } }
        pins.append(pin); pinsHidden = false
        pins.forEach { $0.show() }
        // The new capture owns shortcuts immediately; showing old pins must not steal focus.
        NSApp.activate(ignoringOtherApps: true)
        pin.window?.makeKeyAndOrderFront(nil); pin.window?.makeFirstResponder(pin.canvas)
    }
    @objc func togglePins() { pinsHidden.toggle(); for pin in pins { if pinsHidden { pin.hide() } else { pin.show() } } }
    @objc private func closePins() { for pin in pins { pin.onClose = nil; pin.close() }; pins.removeAll(); pinsHidden = false }
    @objc private func toggleKeys() { UserDefaults.standard.set(!hotKeysEnabled, forKey: "snipping.hotKeys"); start() }
    func menuItems() -> [NSMenuItem] {
        func item(_ title: String, _ action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; return item
        }
        let capture = item(L("截图并贴到桌面…     ⌘1"), #selector(capture))
        capture.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil)
        let paste = item(L("剪贴板贴图       ⌃⌥P"), #selector(pinClipboard))
        paste.image = NSImage(systemSymbolName: "pin", accessibilityDescription: nil)
        let more = NSMenuItem(title: L("贴图与快捷键"), action: nil, keyEquivalent: "")
        let menu = NSMenu()
        let hide = item(pinsHidden ? L("显示全部贴图     ⌃⌥⇧P") : L("隐藏全部贴图     ⌃⌥⇧P"), #selector(togglePins)); hide.isEnabled = !pins.isEmpty
        menu.addItem(hide)
        let close = item(L("关闭全部贴图（%@）", String(describing: pins.count)), #selector(closePins)); close.isEnabled = !pins.isEmpty; menu.addItem(close)
        menu.addItem(.separator())
        let keys = item(L("启用截图与贴图快捷键"), #selector(toggleKeys)); keys.state = hotKeysEnabled ? .on : .off; menu.addItem(keys)
        if IsSecureEventInputEnabled() { menu.addItem(NSMenuItem(title: L("系统安全输入开启，快捷键可能暂不可用"), action: nil, keyEquivalent: "")) }
        if hotKeyError { menu.addItem(NSMenuItem(title: L("部分快捷键已被占用，可从菜单操作"), action: nil, keyEquivalent: "")) }
        menu.addItem(NSMenuItem(title: L("截图时：空格选窗口 · Esc 取消"), action: nil, keyEquivalent: ""))
        more.submenu = menu; return [capture, paste, more]
    }
}
