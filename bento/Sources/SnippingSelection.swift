import Cocoa

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
    var finished: ((CGImage?) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    init(image: CGImage, screen: NSScreen, windows: [CGRect]) {
        snapshot = image; screenFrame = screen.frame; self.windows = windows
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        let image = NSImage(cgImage: snapshot, size: bounds.size)
        image.draw(in: bounds)
        NSColor.black.withAlphaComponent(0.3).setFill(); bounds.fill()
        if selection.width > 0 && selection.height > 0 {
            NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: selection).addClip(); image.draw(in: bounds); NSGraphicsContext.restoreGraphicsState()
            NSColor.systemBlue.setStroke(); let path = NSBezierPath(rect: selection); path.lineWidth = 2; path.stroke()
        }
        let pixels = snipPixelRect(selection, viewSize: bounds.size, imageSize: CGSize(width: snapshot.width, height: snapshot.height))
        let text = L("Bento  ·  %@  ·  空格切换选窗口  ·  Esc 取消", String(describing: windowMode ? L("点击选择窗口") : L("拖动框选"))) + (pixels.width > 0 ? "   \(Int(pixels.width)) × \(Int(pixels.height)) px" : "")
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        let box = CGRect(x: max(8, (bounds.width - size.width) / 2 - 14), y: bounds.height - 70, width: size.width + 28, height: 34)
        NSColor.black.withAlphaComponent(0.75).setFill(); NSBezierPath(roundedRect: box, xRadius: 9, yRadius: 9).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + 14, y: box.minY + 9), withAttributes: attrs)
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
        if rect.width >= 2 && rect.height >= 2 { finished?(snapshot.cropping(to: rect)) }
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
    func show() -> Bool {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = info.compactMap { entry -> CGRect? in
            guard entry[kCGWindowLayer as String] as? Int == 0, entry[kCGWindowOwnerPID as String] as? Int32 != getpid(),
                  let dictionary = entry[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: dictionary)
        }
        // Capture every screen before showing any overlay so no selection UI enters the image.
        let snapshots = NSScreen.screens.compactMap { screen -> (NSScreen, CGImage)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let image = CGDisplayCreateImage(CGDirectDisplayID(number.uint32Value)) else { return nil }
            return (screen, image)
        }
        guard !snapshots.isEmpty else { return false }
        for (screen, image) in snapshots {
            let panel = SnipPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = L("Bento 截图选区"); panel.level = .screenSaver; panel.hasShadow = false; panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.acceptsMouseMovedEvents = true
            let view = SnipSelectionView(image: image, screen: screen, windows: windows)
            view.finished = { [weak self, weak view] image in
                guard let self = self, let view = view else { return }
                let capture = image.map { _ in SnipCapture(snapshot: view.snapshot, screenFrame: screen.frame, region: view.selection) }
                self.finished?(capture); self.close()
            }
            panel.contentView = view; panels.append(panel)
        }
        for panel in panels { panel.orderFrontRegardless() }
        let active = panels.first { $0.frame.contains(NSEvent.mouseLocation) } ?? panels[0]
        active.makeKeyAndOrderFront(nil); active.makeFirstResponder(active.contentView)
        return true
    }
    func close() { for panel in panels { panel.close() }; panels.removeAll() }
}
