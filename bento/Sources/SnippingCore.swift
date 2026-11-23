import Cocoa

enum SnipTool: String, CaseIterable {
    case selection = "移动", rectangle = "方框", ellipse = "圆圈", arrow = "箭头", pen = "画笔", text = "文字", redact = "遮挡", mosaic = "马赛克"
}
struct SnipMark {
    let tool: SnipTool
    var points: [CGPoint]
    let color: NSColor
    let width: CGFloat
    var text = ""
    var mosaic: CGImage?
}
struct SnipDocument {
    let image: CGImage
    var marks: [SnipMark] = []
    var redoMarks: [SnipMark] = []
    var size: CGSize { CGSize(width: image.width, height: image.height) }
    mutating func append(_ mark: SnipMark) { marks.append(mark); redoMarks.removeAll() }
    mutating func undo() { if let mark = marks.popLast() { redoMarks.append(mark) } }
    mutating func redo() { if let mark = redoMarks.popLast() { marks.append(mark) } }
    func rendered() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for mark in marks { drawSnipMark(mark) }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}
func snipRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
    CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
}
func drawSnipMark(_ mark: SnipMark) {
    guard let first = mark.points.first, let last = mark.points.last else { return }
    let rect = snipRect(first, last)
    mark.color.setStroke(); mark.color.setFill()
    let path: NSBezierPath
    switch mark.tool {
    case .selection: return
    case .text:
        (mark.text as NSString).draw(at: first, withAttributes: [.font: NSFont.systemFont(ofSize: mark.width * 7, weight: .semibold), .foregroundColor: mark.color])
        return
    case .mosaic:
        if let image = mark.mosaic { NSImage(cgImage: image, size: rect.integral.size).draw(in: rect.integral) }
        return
    case .redact:
        NSColor.black.setFill(); rect.fill(); return
    case .rectangle: path = NSBezierPath(rect: rect)
    case .ellipse: path = NSBezierPath(ovalIn: rect)
    case .pen, .arrow:
        path = NSBezierPath(); path.move(to: first)
        for point in mark.points.dropFirst() { path.line(to: point) }
        if mark.tool == .arrow {
            let angle = atan2(last.y - first.y, last.x - first.x), length = mark.width * 5
            for offset in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                path.move(to: last)
                path.line(to: CGPoint(x: last.x - length * cos(angle + offset), y: last.y - length * sin(angle + offset)))
            }
        }
    }
    path.lineWidth = mark.width; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
}
func snipPNG(_ image: CGImage) -> Data? { NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) }
func snipImage(_ image: NSImage) -> CGImage? {
    var rect = CGRect(origin: .zero, size: image.size)
    guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
          cg.width > 0, cg.height > 0, Double(cg.width) * Double(cg.height) <= 40_000_000 else { return nil }
    return cg
}
func snipError(_ message: String) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert(); alert.messageText = L("截图与贴图"); alert.informativeText = message; alert.runModal()
}
@discardableResult func copySnip(_ image: CGImage, pasteboard: NSPasteboard = .general) -> Bool {
    guard let png = snipPNG(image) else { return false }
    pasteboard.clearContents()
    return pasteboard.setData(png, forType: .png)
}
func saveSnip(_ image: CGImage, window: NSWindow?) {
    let panel = NSSavePanel(); panel.allowedFileTypes = ["png"]
    let format = DateFormatter(); format.dateFormat = "yyyy-MM-dd HH.mm.ss"
    panel.nameFieldStringValue = L("Bento 截图 ") + format.string(from: Date()) + ".png"
    func save(_ result: NSApplication.ModalResponse) {
        guard result == .OK, let url = panel.url else { return }
        do {
            guard let data = snipPNG(image) else { throw NSError(domain: "Bento.Snip", code: 1, userInfo: [NSLocalizedDescriptionKey: L("无法生成 PNG 图像。")] ) }
            try data.write(to: url, options: .atomic)
        } catch { snipError(L("保存失败：") + error.localizedDescription) }
    }
    if let window = window { panel.beginSheetModal(for: window, completionHandler: save) }
    else { NSApp.activate(ignoringOtherApps: true); save(panel.runModal()) }
}

// Encoding must not block input. A newer capture or another clipboard copy wins.
final class SnipClipboardWriter {
    private let queue = DispatchQueue(label: "com.sijie.bento.snip-encode", qos: .userInitiated)
    private let pasteboard: NSPasteboard
    private var work: DispatchWorkItem?
    private var generation = 0
    var isPending: Bool { work != nil }
    init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }
    func cancel() { generation += 1; work?.cancel(); work = nil }
    func copy(_ image: CGImage, onFailure: @escaping () -> Void) {
        cancel()
        let request = generation, changeCount = pasteboard.changeCount
        let task = DispatchWorkItem { [weak self] in
            let png = autoreleasepool { snipPNG(image) }
            DispatchQueue.main.async {
                guard let self = self, self.generation == request else { return }
                self.work = nil
                guard self.pasteboard.changeCount == changeCount else { return }
                guard let png = png else { onFailure(); return }
                self.pasteboard.clearContents()
                if !self.pasteboard.setData(png, forType: .png) { onFailure() }
            }
        }
        work = task; queue.async(execute: task)
    }
    deinit { work?.cancel() }
}

func makeSnipMosaic(_ image: CGImage, blockSize: CGFloat) -> CGImage? {
    guard blockSize.isFinite, blockSize >= 2, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    let w = max(1, Int(ceil(CGFloat(image.width) / blockSize))), h = max(1, Int(ceil(CGFloat(image.height) / blockSize)))
    guard let small = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let large = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    small.interpolationQuality = .high; small.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let reduced = small.makeImage() else { return nil }
    large.interpolationQuality = .none; large.draw(reduced, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return large.makeImage()
}

final class SnipColorPicker: NSPopUpButton {
    private static weak var active: SnipColorPicker?
    static var colors: [(String, NSColor)] { [(L("红色"), .systemRed), (L("橙色"), .systemOrange), (L("黄色"), .systemYellow), (L("绿色"), .systemGreen), (L("蓝色"), .systemBlue), (L("紫色"), .systemPurple), (L("黑色"), .black), (L("白色"), .white)] }
    var onChange: ((NSColor) -> Void)?
    private(set) var color = NSColor.systemRed
    init(color initialColor: NSColor = .systemRed) {
        super.init(frame: CGRect(x: 0, y: 0, width: 90, height: 26), pullsDown: false)
        for (index, entry) in Self.colors.enumerated() {
            addItem(withTitle: entry.0); lastItem?.tag = index; lastItem?.image = swatch(entry.1)
        }
        menu?.addItem(.separator()); addItem(withTitle: L("自定…")); lastItem?.tag = -1
        color = initialColor
        if let index = Self.colors.firstIndex(where: { $0.1 == initialColor }) { selectItem(at: index) }
        else { selectItem(withTag: -1); lastItem?.image = swatch(initialColor) }
        target = self; action = #selector(chooseColor); toolTip = L("标注颜色（影响之后绘制的标注）")
        setAccessibilityLabel(L("标注颜色"))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func swatch(_ color: NSColor) -> NSImage {
        let image = NSImage(size: CGSize(width: 12, height: 12)); image.lockFocus()
        color.setFill(); NSBezierPath(roundedRect: CGRect(x: 1, y: 1, width: 10, height: 10), xRadius: 2, yRadius: 2).fill()
        NSColor.gray.setStroke(); NSBezierPath(rect: CGRect(x: 1, y: 1, width: 10, height: 10)).stroke(); image.unlockFocus()
        return image
    }
    @objc func chooseColor() {
        guard let tag = selectedItem?.tag else { return }
        if tag >= 0 { color = Self.colors[tag].1; onChange?(color); dismissPicker(); return }
        let panel = NSColorPanel.shared
        panel.color = color; panel.showsAlpha = false; panel.isContinuous = true
        Self.active = self
        panel.setTarget(self); panel.setAction(#selector(customColorChanged(_:)))
        panel.level = NSWindow.Level(rawValue: max(NSWindow.Level.floating.rawValue + 2, (window?.level.rawValue ?? 0) + 1))
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
    }
    @objc func customColorChanged(_ panel: NSColorPanel) {
        color = panel.color; lastItem?.image = swatch(color); onChange?(color)
    }
    func dismissPicker() {
        if Self.active === self { NSColorPanel.shared.orderOut(nil); NSColorPanel.shared.setTarget(nil); Self.active = nil }
    }
}

// Fixed-width symbols keep every language usable in the compact sticker toolbar.
func snipToolControl(target: AnyObject, action: Selector, selected: SnipTool) -> NSSegmentedControl {
    let symbols = ["arrow.up.and.down.and.arrow.left.and.right", "rectangle", "circle", "arrow.up.right", "pencil.tip", "textformat", "rectangle.fill", "square.grid.3x3.fill"]
    let control = NSSegmentedControl(labels: SnipTool.allCases.map { L($0.rawValue) }, trackingMode: .selectOne, target: target, action: action)
    for (index, tool) in SnipTool.allCases.enumerated() {
        if let image = NSImage(systemSymbolName: symbols[index], accessibilityDescription: L(tool.rawValue)) {
            control.setLabel("", forSegment: index); control.setImage(image, forSegment: index)
        }
        control.setWidth(30, forSegment: index)
        (control.cell as? NSSegmentedCell)?.setToolTip(L(tool.rawValue), forSegment: index)
    }
    control.selectedSegment = SnipTool.allCases.firstIndex(of: selected) ?? 0
    return control
}
func snipIconButton(_ button: NSButton, symbol: String) {
    button.toolTip = button.title; button.setAccessibilityLabel(button.title)
    if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: button.title) {
        button.image = image; button.imagePosition = .imageOnly
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
    }
}
