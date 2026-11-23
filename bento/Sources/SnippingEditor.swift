import Cocoa

func constrainedSnipFrame(_ rect: CGRect, bounds: CGRect) -> CGRect {
    let x = min(max(bounds.minX, bounds.maxX - rect.width), max(min(bounds.minX, bounds.maxX - rect.width), rect.minX))
    let y = min(max(bounds.minY, bounds.maxY - rect.height), max(min(bounds.minY, bounds.maxY - rect.height), rect.minY))
    return CGRect(x: x, y: y, width: rect.width, height: rect.height)
}
private final class SnipEditorBackground: NSView {
    var snapshot: CGImage?
    var dimmed = false
    override func draw(_ dirtyRect: NSRect) {
        if let image = snapshot { NSImage(cgImage: image, size: bounds.size).draw(in: bounds) }
        else { NSColor.windowBackgroundColor.setFill(); bounds.fill() }
        if dimmed { NSColor.black.withAlphaComponent(0.3).setFill(); bounds.fill() }
    }
}

class SnipCanvas: NSView {
    var document: SnipDocument
    var tool: SnipTool = .selection
    var color = NSColor.systemRed
    var draft: SnipMark?
    var onChange: (() -> Void)?
    var onCancel: (() -> Void)?
    var onDisplayChange: ((CGRect) -> Void)?
    var onZoom: ((CGFloat, CGPoint) -> Void)?
    private var dragOrigin: CGPoint?
    private var dragFrame = CGRect.zero
    private var mosaicSource: CGImage?
    var askText: ((CGPoint) -> String?)?
    override var acceptsFirstResponder: Bool { true }
    init(image: CGImage, size: CGSize) { document = SnipDocument(image: image); super.init(frame: CGRect(origin: .zero, size: size)) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    var scale: CGFloat { bounds.width / document.size.width }
    func imagePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(document.size.width, max(0, point.x / scale)), y: min(document.size.height, max(0, point.y / scale)))
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        NSImage(cgImage: document.image, size: document.size).draw(in: bounds)
        NSGraphicsContext.saveGraphicsState()
        let transform = AffineTransform(scale: scale); (transform as NSAffineTransform).concat()
        for mark in document.marks { drawSnipMark(mark) }
        if let draft = draft { drawSnipMark(draft) }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.systemBlue.setStroke(); let border = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1)); border.lineWidth = 2; border.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if tool == .selection {
            dragOrigin = event.locationInWindow; dragFrame = frame
            return
        }
        let point = imagePoint(convert(event.locationInWindow, from: nil))
        let width = 3 / scale
        if tool == .text {
            if let text = askText?(point), !text.isEmpty {
                document.append(SnipMark(tool: .text, points: [point], color: color, width: width, text: text))
                needsDisplay = true; onChange?()
            }
        } else {
            if tool == .mosaic {
                guard let source = document.rendered(), let pixelated = makeSnipMosaic(source, blockSize: max(8, 24 / scale)) else { snipError(L("无法生成马赛克，请缩小图片后重试。")); return }
                mosaicSource = pixelated
            }
            draft = SnipMark(tool: tool, points: [point, point], color: color, width: width)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        if let origin = dragOrigin, let bounds = superview?.bounds {
            onDisplayChange?(constrainedSnipFrame(dragFrame.offsetBy(dx: event.locationInWindow.x - origin.x, dy: event.locationInWindow.y - origin.y), bounds: bounds)); return
        }
        guard var mark = draft else { return }
        let point = imagePoint(convert(event.locationInWindow, from: nil))
        if mark.tool == .pen { mark.points.append(point) } else { mark.points[1] = point }
        if mark.tool == .mosaic, let source = mosaicSource, let first = mark.points.first {
            let rect = snipRect(first, point).integral.intersection(CGRect(origin: .zero, size: document.size))
            if rect.width > 0 && rect.height > 0 {
                mark.mosaic = source.cropping(to: CGRect(x: rect.minX, y: document.size.height - rect.maxY, width: rect.width, height: rect.height))
            }
        }
        draft = mark; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if dragOrigin != nil { mouseDragged(with: event); dragOrigin = nil; return }
        guard var mark = draft else { return }
        if mark.tool == .mosaic {
            guard let patch = mark.mosaic, let compact = SnipDocument(image: patch).rendered() else { draft = nil; mosaicSource = nil; needsDisplay = true; return }
            mark.mosaic = compact; mosaicSource = nil
        }
        if let a = mark.points.first, let b = mark.points.last, hypot(a.x - b.x, a.y - b.y) >= 1 { document.append(mark) }
        draft = nil; needsDisplay = true; onChange?()
    }
    override func scrollWheel(with event: NSEvent) {
        guard draft == nil, dragOrigin == nil, abs(event.scrollingDeltaY) > 0.01 else { return }
        let step = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.01 : 0.08)
        onZoom?(exp(min(0.3, max(-0.3, step))), event.locationInWindow)
    }
    func cancelDraft() { draft = nil; mosaicSource = nil; needsDisplay = true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { if draft != nil { cancelDraft() } else { onCancel?() }; return }
        super.keyDown(with: event)
    }
}

final class SnipEditor: NSWindowController, NSWindowDelegate {
    let canvas: SnipCanvas
    var onPin: ((CGImage) -> Void)?
    var onClose: (() -> Void)?
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private let initialSize: CGSize
    private let toolbar = SnipEditorBackground()
    private var previousColorLevel: NSWindow.Level?
    init(image: CGImage, capture: SnipCapture? = nil) {
        let screen = capture?.screenFrame ?? NSScreen.main!.frame
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        let size = CGSize(width: min(screen.width, CGFloat(image.width) / scale), height: min(screen.height, CGFloat(image.height) / scale))
        let region = capture?.region ?? CGRect(x: (screen.width - size.width) / 2, y: (screen.height - size.height) / 2, width: size.width, height: size.height)
        initialSize = region.size
        canvas = SnipCanvas(image: image, size: region.size); canvas.frame = region
        let window = SnipPanel(contentRect: screen, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.animationBehavior = .none
        window.title = L("Bento 原位截图标注"); window.isReleasedWhenClosed = false; window.hasShadow = false
        window.level = .screenSaver; window.hidesOnDeactivate = false; window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: window); window.delegate = self
        let root = SnipEditorBackground(frame: CGRect(origin: .zero, size: screen.size)); root.snapshot = capture?.snapshot; root.dimmed = true; window.contentView = root
        root.addSubview(canvas)
        toolbar.wantsLayer = true; toolbar.layer?.cornerRadius = 9; toolbar.layer?.masksToBounds = true
        // An opaque native toolbar remains readable above either a bright or dark screenshot.
        toolbar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        root.addSubview(toolbar)
        let tools = snipToolControl(target: self, action: #selector(changeTool(_:)), selected: canvas.tool)
        let color = SnipColorPicker(); color.onChange = { [weak self] value in self?.canvas.color = value }
        color.widthAnchor.constraint(equalToConstant: 90).isActive = true
        undoButton = button(L("撤销"), #selector(undoMark), "z")
        redoButton = button(L("重做"), #selector(redoMark), "Z"); redoButton.keyEquivalentModifierMask = [.command, .shift]
        let first = NSStackView(views: [tools, color, undoButton, redoButton]); first.spacing = 8
        let cancel = button(L("取消"), #selector(cancelEditing), "\u{1b}"); cancel.keyEquivalentModifierMask = []
        let second = NSStackView(views: [button(L("复制"), #selector(copyImage), "c"), button(L("保存 PNG…"), #selector(saveImage), "s"), button(L("贴到屏幕"), #selector(pinImage), "t"), cancel]); second.spacing = 8
        for view in [first, second] { view.translatesAutoresizingMaskIntoConstraints = false; toolbar.addSubview(view) }
        NSLayoutConstraint.activate([
            first.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 10), first.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 10),
            second.topAnchor.constraint(equalTo: first.bottomAnchor, constant: 8), second.leadingAnchor.constraint(equalTo: first.leadingAnchor)
        ])
        canvas.onChange = { [weak self] in self?.updateUndo() }
        canvas.onCancel = { [weak self] in self?.close() }
        canvas.onDisplayChange = { [weak self] frame in self?.changeDisplayFrame(frame) }
        canvas.onZoom = { [weak self] factor, anchor in self?.zoomDisplay(factor, anchor: anchor) }
        canvas.toolTip = L("拖动移动图片 · 滚轮缩放 · 导出保留原图分辨率")
        canvas.askText = { [weak self] _ in self?.textPrompt() }
        updateUndo(); positionToolbar()
    }
    private func positionToolbar() {
        guard let bounds = window?.contentView?.bounds else { return }
        let rect = canvas.frame, size = CGSize(width: min(600, bounds.width - 16), height: 82)
        let y: CGFloat
        if rect.minY >= size.height + 8 { y = rect.minY - size.height - 8 }
        else if bounds.maxY - rect.maxY >= size.height + 8 { y = rect.maxY + 8 }
        else { y = max(8, min(bounds.maxY - size.height - 8, rect.minY + 8)) }
        toolbar.frame = CGRect(x: max(8, min(bounds.maxX - size.width - 8, rect.maxX - size.width)), y: y, width: size.width, height: size.height)
    }
    func changeDisplayFrame(_ frame: CGRect) {
        guard let bounds = window?.contentView?.bounds else { return }
        canvas.frame = constrainedSnipFrame(frame, bounds: bounds); canvas.needsDisplay = true
        positionToolbar()
    }
    func zoomDisplay(_ factor: CGFloat, anchor: CGPoint) {
        guard factor.isFinite, factor > 0 else { return }
        let old = canvas.frame
        let minimum = max(0.1, 16 / max(initialSize.width, initialSize.height))
        let zoom = min(5, max(minimum, old.width / initialSize.width * factor))
        let size = CGSize(width: initialSize.width * zoom, height: initialSize.height * zoom)
        let x = min(1, max(0, (anchor.x - old.minX) / old.width)), y = min(1, max(0, (anchor.y - old.minY) / old.height))
        changeDisplayFrame(CGRect(x: anchor.x - size.width * x, y: anchor.y - size.height * y, width: size.width, height: size.height))
    }
    @objc private func cancelEditing() { close() }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func button(_ title: String, _ action: Selector, _ key: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: action); button.bezelStyle = .rounded
        button.keyEquivalent = key; button.keyEquivalentModifierMask = .command; return button
    }
    func show() { if previousColorLevel == nil { previousColorLevel = NSColorPanel.shared.level }; NSColorPanel.shared.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1); NSApp.activate(ignoringOtherApps: true); showWindow(nil); window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(canvas) }
    func windowWillClose(_ notification: Notification) {
        if let level = previousColorLevel { NSColorPanel.shared.orderOut(nil); NSColorPanel.shared.level = level; previousColorLevel = nil }
        onClose?()
    }
    private func updateUndo() { undoButton.isEnabled = !canvas.document.marks.isEmpty; redoButton.isEnabled = !canvas.document.redoMarks.isEmpty }
    private func textPrompt() -> String? {
        let alert = NSAlert(); alert.messageText = L("添加文字"); alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 26)); field.placeholderString = L("输入标注")
        alert.accessoryView = field; alert.addButton(withTitle: L("添加")); alert.addButton(withTitle: L("取消"))
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
    @objc private func changeTool(_ sender: NSSegmentedControl) { canvas.tool = SnipTool.allCases[sender.selectedSegment]; canvas.needsDisplay = true }
    @objc func undoMark() { canvas.document.undo(); canvas.needsDisplay = true; updateUndo() }
    @objc func redoMark() { canvas.document.redo(); canvas.needsDisplay = true; updateUndo() }
    private func rendered() -> CGImage? {
        let image = canvas.document.rendered()
        if image == nil { snipError(L("图像处理失败，请关闭部分贴图后重试。")) }
        return image
    }
    @objc func copyImage() { if let image = rendered() { if copySnip(image) { close() } else { snipError(L("无法复制图像。")) } } }
    @objc func saveImage() { if let image = rendered() { saveSnip(image, window: window) } }
    @objc func pinImage() { if let image = rendered() { onPin?(image); close() } }
}
