import Cocoa
import QuartzCore

func snipPixelRect(_ selection: CGRect, viewSize: CGSize, imageSize: CGSize) -> CGRect {
    guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
    let rect = selection.intersection(CGRect(origin: .zero, size: viewSize))
    guard !rect.isNull, rect.width > 0, rect.height > 0 else { return .zero }
    let sx = imageSize.width / viewSize.width, sy = imageSize.height / viewSize.height
    return CGRect(x: rect.minX * sx, y: (viewSize.height - rect.maxY) * sy, width: rect.width * sx, height: rect.height * sy).integral.intersection(CGRect(origin: .zero, size: imageSize))
}
final class SnipSelectionView: NSView {
    let snapshot: CGImage
    let screenFrame: CGRect
    let windows: [CGRect]
    var selection = CGRect.zero
    var startPoint: CGPoint?
    var windowMode = false
    var finished: ((CGRect?) -> Void)?
    private let snapshotLayer = CALayer()
    private let shadeLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let hintBackground = CALayer()
    private let hint = NSTextField(labelWithString: "")
    override var wantsUpdateLayer: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    init(image: CGImage, screen: NSScreen, windows: [CGRect]) {
        snapshot = image; screenFrame = screen.frame; self.windows = windows
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
        snapshotLayer.contents = image; snapshotLayer.contentsGravity = .resize
        shadeLayer.fillColor = NSColor.black.withAlphaComponent(0.3).cgColor; shadeLayer.fillRule = .evenOdd
        borderLayer.fillColor = nil; borderLayer.strokeColor = NSColor.systemBlue.cgColor; borderLayer.lineWidth = 2
        hintBackground.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor; hintBackground.cornerRadius = 9
        for child in [snapshotLayer, shadeLayer, borderLayer, hintBackground] { layer?.addSublayer(child) }
        hint.font = .systemFont(ofSize: 13, weight: .medium); hint.textColor = .white; hint.alignment = .center
        addSubview(hint)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func updateLayer() {
        // Retain one screen texture; pointer movement changes only the mask and border.
        CATransaction.begin(); CATransaction.setDisableActions(true)
        snapshotLayer.frame = bounds
        shadeLayer.frame = bounds; borderLayer.frame = bounds
        let shade = CGMutablePath(); shade.addRect(bounds)
        let selected = selection.intersection(bounds)
        if !selected.isNull && selected.width > 0 && selected.height > 0 {
            shade.addRect(selected); borderLayer.path = CGPath(rect: selected, transform: nil)
        } else { borderLayer.path = nil }
        shadeLayer.path = shade
        let pixels = snipPixelRect(selection, viewSize: bounds.size, imageSize: CGSize(width: snapshot.width, height: snapshot.height))
        hint.stringValue = L("Bento  ·  %@  ·  空格切换选窗口  ·  Esc 取消", windowMode ? L("点击选择窗口") : L("拖动框选")) + (pixels.width > 0 ? "   \(Int(pixels.width)) × \(Int(pixels.height)) px" : "")
        let width = min(bounds.width - 16, hint.fittingSize.width + 28)
        hintBackground.frame = CGRect(x: max(8, (bounds.width - width) / 2), y: bounds.height - 70, width: width, height: 34)
        hint.frame = hintBackground.frame.insetBy(dx: 10, dy: 8)
        CATransaction.commit()
    }
    private func localPoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(bounds.maxX, max(0, p.x)), y: min(bounds.maxY, max(0, p.y)))
    }
    private func selectWindow(at local: CGPoint) {
        let height = NSScreen.screens[0].frame.height
        let global = CGPoint(x: screenFrame.minX + local.x, y: height - screenFrame.minY - local.y)
        guard let found = windows.first(where: { $0.contains(global) }) else { selection = .zero; needsDisplay = true; return }
        selection = CGRect(x: found.minX - screenFrame.minX, y: height - found.maxY - screenFrame.minY, width: found.width, height: found.height).intersection(bounds)
        needsDisplay = true
    }
    override func mouseMoved(with event: NSEvent) { if windowMode { selectWindow(at: localPoint(event)) } }
    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(self)
        if windowMode { selectWindow(at: localPoint(event)) } else { startPoint = localPoint(event); selection = .zero; needsDisplay = true }
    }
    override func mouseDragged(with event: NSEvent) { if let start = startPoint { selection = snipRect(start, localPoint(event)); needsDisplay = true } }
    override func mouseUp(with event: NSEvent) {
        if let start = startPoint { selection = snipRect(start, localPoint(event)); startPoint = nil }
        let rect = snipPixelRect(selection, viewSize: bounds.size, imageSize: CGSize(width: snapshot.width, height: snapshot.height))
        if rect.width >= 2 && rect.height >= 2 { finished?(selection) }
    }
    override func rightMouseDown(with event: NSEvent) { finished?(nil) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finished?(nil); return }
        if event.keyCode == 49 {
            windowMode.toggle(); startPoint = nil; selection = .zero
            if windowMode { selectWindow(at: convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)) }
            needsDisplay = true; return
        }
        super.keyDown(with: event)
    }
}
struct SnipCapture {
    let snapshot: CGImage
    let screenFrame: CGRect
    let region: CGRect
}
final class SnipSelection {
    var panels: [NSPanel] = []
    var finished: ((SnipCapture?) -> Void)?
    private var generation = 0
    func show(completion: @escaping (Bool) -> Void) {
        generation += 1
        let request = generation
        let displays = NSScreen.screens.compactMap { screen -> (NSScreen, CGDirectDisplayID)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (screen, CGDirectDisplayID(number.uint32Value))
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Finish every snapshot before presenting overlays; never capture our own dimming.
            let lock = NSLock()
            var images = [CGImage?](repeating: nil, count: displays.count)
            DispatchQueue.concurrentPerform(iterations: displays.count) { index in
                let image = CGDisplayCreateImage(displays[index].1)
                lock.lock(); images[index] = image; lock.unlock()
            }
            let snapshots = displays.enumerated().compactMap { index, display in images[index].map { (display.0, $0) } }
            let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            let windows = info.compactMap { entry -> CGRect? in
                guard entry[kCGWindowLayer as String] as? Int == 0, entry[kCGWindowOwnerPID as String] as? Int32 != getpid(),
                      let dictionary = entry[kCGWindowBounds as String] as? NSDictionary else { return nil }
                return CGRect(dictionaryRepresentation: dictionary)
            }
            DispatchQueue.main.async {
                guard let self = self, self.generation == request else { return }
                guard !snapshots.isEmpty else { completion(false); return }
                for (screen, image) in snapshots {
                    let panel = SnipPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                    // The default panel animation scales the entire screen snapshot on entry.
                    panel.animationBehavior = .none
                    panel.title = L("Bento 截图选区"); panel.level = .screenSaver; panel.hasShadow = false; panel.isReleasedWhenClosed = false
                    panel.hidesOnDeactivate = false; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.acceptsMouseMovedEvents = true
                    let view = SnipSelectionView(image: image, screen: screen, windows: windows)
                    view.finished = { [weak self, weak view] region in
                        guard let self = self, let view = view else { return }
                        let capture = region.map { SnipCapture(snapshot: view.snapshot, screenFrame: screen.frame, region: $0) }
                        self.close(); self.finished?(capture)
                    }
                    panel.contentView = view; self.panels.append(panel)
                }
                self.panels.forEach { $0.orderFrontRegardless() }
                let active = self.panels.first { $0.frame.contains(NSEvent.mouseLocation) } ?? self.panels[0]
                active.makeKeyAndOrderFront(nil); active.makeFirstResponder(active.contentView)
                completion(true)
            }
        }
    }
    func close() { generation += 1; for panel in panels { panel.close() }; panels.removeAll() }
}
