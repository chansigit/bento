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
assert(item.title == "▣ 窗口切换")
assert(item.submenu?.items.first?.state == .off)
assert(item.submenu?.items.contains { $0.title == "设置…" && $0.target === controller } == true)
let tab = CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: true)!
tab.flags = .maskCommand
assert(!controller.handle(.keyDown, tab), "Paused switcher must pass through Cmd+Tab")
assert(!controller.visible)
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
