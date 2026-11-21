import Cocoa

// Volatile arguments isolate this check from the user's saved Bento preferences.
let defaults = UserDefaults.standard
let originalArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
defaults.setVolatileDomain(["windowSwitcher.enabled": false, "windowSwitcher.didMigrate": true], forName: UserDefaults.argumentDomain)
let app = NSApplication.shared
let controller = WindowSwitcherController()
controller.start()
assert(!controller.enabled && controller.tap == nil)
let item = controller.menuItem()
assert(item.title == "窗口切换")
assert(item.submenu?.items.first?.state == .off)
assert(item.submenu?.items.contains { $0.title == "设置…" && $0.target === controller } == true)
let tab = CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: true)!
tab.flags = .maskCommand
assert(!controller.handle(.keyDown, tab), "Paused switcher must pass through Cmd+Tab")
assert(!controller.visible)
// Known gray/color/alpha patches must survive resizing without losing their profile.
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let swatches = CGContext(data: nil, width: 1280, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let colors: [[CGFloat]] = [[0,0,0,1], [0.5,0.5,0.5,1], [1,1,1,1], [1,0,0,1], [0,0,1,1], [1,0,0,0.5], [0,0,0,0], [0,1,0,1]]
for (index, components) in colors.enumerated() {
    swatches.setFillColor(CGColor(colorSpace: srgb, components: components)!)
    swatches.fill(CGRect(x: index * 160, y: 0, width: 160, height: 64))
}
let resized = makeSwitcherThumbnail(swatches.makeImage()!)!
assert(resized.width == 640 && resized.height == 32)
assert(resized.colorSpace?.name == CGColorSpace.sRGB, "Thumbnail must carry an explicit sRGB profile")
let pixels = resized.dataProvider!.data! as Data
for (index, components) in colors.enumerated() {
    let offset = 16 * resized.bytesPerRow + (index * 80 + 40) * 4
    for channel in 0..<4 {
        let value = components[channel] * (channel == 3 ? 1 : components[3])
        assert(abs(Int(pixels[offset + channel]) - Int((value * 255).rounded())) <= 1, "Thumbnail changed gray/color/alpha patch")
    }
}
// A non-sRGB source must be converted, not merely relabeled as sRGB.
let linearSpace = CGColorSpace(name: CGColorSpace.linearSRGB)!
let linear = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                       space: linearSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
linear.setFillColor(CGColor(colorSpace: linearSpace, components: [0.5, 0.5, 0.5, 1])!)
linear.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
let converted = makeSwitcherThumbnail(linear.makeImage()!)!
assert(converted.width == 2 && converted.height == 2, "Small thumbnails must not be enlarged")
let convertedData = converted.dataProvider!.data! as Data
let gray = Int(convertedData[0])
assert((186...189).contains(gray), "Linear 50% gray must convert to approximately 188 in sRGB")
print("Thumbnail color checks passed: gray, colors, alpha, color conversion and size")

// Cached thumbnails survive closing, and asynchronous updates must not rebuild the panel.
let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let pixelImage = context.makeImage()!
func testWindow(_ id: CGWindowID) -> SwitcherWindowEntry {
    SwitcherWindowEntry(app: NSRunningApplication.current, element: nil, title: "Test", id: id, rank: 0, minimized: false, aspect: 1)
}
let first = testWindow(42)
controller.enabled = true
controller.cached = [first]
controller.entries = [first]
controller.visible = true
controller.panel = WindowSwitcherPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 150), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
let root = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 150))
let card = WindowSwitcherCard(frame: root.bounds)
card.tag = 0; card.selected = true
root.addSubview(card); controller.panel?.contentView = root
let epoch = controller.generation
controller.completeCapture(first, image: pixelImage, generation: epoch)
assert(controller.panel?.contentView === root, "Loading a thumbnail must not replace the panel")
assert(card.preview != nil && card.selected, "Only the image changes, selection remains intact")
let previousImage = controller.images[42]!.image
controller.completeCapture(first, image: nil, generation: epoch)
assert(controller.images[42]!.image === previousImage, "Failed refresh keeps the last good thumbnail")
controller.finish(commit: false)
assert(controller.images[42]!.image === previousImage, "Closing must retain thumbnails for the next Cmd+Tab")
assert(controller.generation == epoch, "Closing must not invalidate in-flight captures")
controller.completeCapture(first, image: pixelImage, generation: epoch)
assert(controller.images[42] != nil, "Capture finishing after close still warms the cache")
controller.cached = []
controller.retainLiveThumbnails()
assert(controller.images.isEmpty, "Closed windows must not retain screenshots")
controller.completeCapture(first, image: pixelImage, generation: epoch)
assert(controller.images.isEmpty, "Late capture must not resurrect a closed window")
controller.cached = (0..<65).map { testWindow(CGWindowID($0)) }
for window in controller.cached {
    controller.images[window.id!] = SwitcherThumbnail(window: window, image: previousImage, capturedAt: Double(window.id!))
}
controller.retainLiveThumbnails()
assert(controller.images.count == 64 && controller.images[0] == nil, "Cache evicts the oldest thumbnail at its bound")
controller.stop()
controller.enabled = true
controller.cached = [first]
controller.completeCapture(first, image: pixelImage, generation: epoch)
assert(controller.images.isEmpty, "Callbacks from before stop cannot repopulate the cache")
controller.shutdown()
assert(controller.tap == nil && controller.tapSource == nil)
assert(controller.cached.isEmpty && controller.images.isEmpty)
defaults.setVolatileDomain(originalArguments, forName: UserDefaults.argumentDomain)
print("Switcher integration passed: menu, paused shortcut pass-through, lifecycle cleanup, warm cache, in-place refresh, eviction, stale callbacks")
