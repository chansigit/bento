import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
UserDefaults.standard.setVolatileDomain(["languageID": "zh-Hans", "skinID": "lavender"], forName: UserDefaults.argumentDomain)
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1; if !condition() { fatalError(message) }
}
final class Target: NSObject, NSMenuDelegate {
    var fired: [Int] = []
    var observedClosed = false
    weak var presenter: SkinnedMenuController?
    var updates = 0
    var sliderValue: Double?
    @objc func slide(_ slider: NSSlider) { sliderValue = slider.doubleValue }
    @objc func run(_ item: NSMenuItem) { fired.append(item.tag); observedClosed = presenter?.isVisible == false }
    func menuNeedsUpdate(_ menu: NSMenu) { updates += 1 }
}
let target = Target(), controller = SkinnedMenuController()
target.presenter = controller
let menu = NSMenu(); menu.delegate = target
let header = NSMenuItem(title: "Bento", action: nil, keyEquivalent: ""); header.isEnabled = false
menu.addItem(header); menu.addItem(.separator())
let action = NSMenuItem(title: "Copy", action: #selector(Target.run(_:)), keyEquivalent: "c")
action.target = target; action.tag = 42; action.state = .on; menu.addItem(action)
let disabled = NSMenuItem(title: "Disabled", action: #selector(Target.run(_:)), keyEquivalent: "")
disabled.isEnabled = false; disabled.target = target; disabled.tag = 99; menu.addItem(disabled)
let branch = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
let submenu = NSMenu(); submenu.delegate = target
let child = NSMenuItem(title: "Theme", action: #selector(Target.run(_:)), keyEquivalent: "t")
child.target = target; child.tag = 7; submenu.addItem(child); branch.submenu = submenu; menu.addItem(branch)
let slider = NSSlider(value: 30, minValue: 0, maxValue: 100, target: target, action: #selector(Target.slide(_:)))
slider.frame = NSRect(x: 10, y: 5, width: 300, height: 22)
let embedded = NSMenuItem(); embedded.view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 32)); embedded.view!.addSubview(slider)
menu.addItem(embedded)
let area = NSScreen.main!.visibleFrame
let anchor = NSRect(x: area.maxX - 25, y: area.maxY + 1, width: 20, height: 20)
func key(_ code: UInt16, text: String = "", flags: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: controller.pages.last?.panel.windowNumber ?? 0, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
}
func show() { controller.show(menu: menu, anchor: anchor) }
show()
check(target.updates == 1, "root model updates on opening")
var root = controller.pages[0]
check(root.layer?.backgroundColor == skin(withID: "lavender").palette(dark: false).surface.cgColor, "menu uses skin surface")
check(root.layer?.borderColor == root.palette.border.cgColor, "menu uses skin border")
check(root.panel.frame.minX >= area.minX && root.panel.frame.maxX <= area.maxX, "root stays on screen")
check(slider.superview === embedded.view && embedded.view!.superview is SkinnedMenuRow, "native controls retain their view and state")
controller.keyDown(key(48), in: root)
check(root.panel.firstResponder === slider, "Tab enters native slider")
slider.doubleValue = 45
check(slider.sendAction(slider.action!, to: slider.target), "embedded slider retains its target/action")
check(slider.doubleValue > 30 && target.sliderValue == slider.doubleValue && controller.isVisible, "native slider action works without closing menu")
root.panel.sendEvent(key(53))
check(!controller.isVisible, "Escape dismisses even with a native control focused")
show(); root = controller.pages[0]
controller.keyDown(key(125), in: root)
check(root.selected == 2 && root.rows[2].highlighted, "keyboard skips headings and separators")
controller.keyDown(key(124), in: root)
check(target.fired.isEmpty, "right arrow never invokes a leaf action")
controller.keyDown(key(125), in: root)
check(root.selected == 4, "keyboard skips disabled rows")
let updatesBeforeSubmenu = target.updates
controller.keyDown(key(124), in: root)
check(controller.pages.count == 2 && target.updates == updatesBeforeSubmenu + 1, "right arrow opens and updates submenu")
let leafPage = controller.pages[1]
check(leafPage.selected == 0, "keyboard enters first submenu action")
check(leafPage.panel.frame.minX >= area.minX && leafPage.panel.frame.maxX <= area.maxX, "submenu flips at screen edge")
check(leafPage.palette.surface == root.palette.surface, "submenus share skin")
controller.keyDown(key(123), in: leafPage)
check(controller.pages.count == 1 && root.panel.isKeyWindow, "left arrow returns to parent")
controller.hover(root.rows[4], in: root)
// A changed row starts hover dwell; a selected parent keeps its submenu stable.
controller.hover(root.rows[2], in: root); controller.hover(root.rows[4], in: root)
RunLoop.main.run(until: Date().addingTimeInterval(0.25))
check(controller.pages.count == 2, "mouse hover opens submenu after dwell")
controller.hover(root.rows[2], in: root)
check(controller.pages.count == 1 && root.rows[2].highlighted, "hovering sibling removes old submenu")
check(root.rows[2].accessibilityPerformPress(), "accessible menu action")
check(target.fired == [42] && target.observedClosed, "original action receives original NSMenuItem after dismissal")
show(); root = controller.pages[0]
controller.activate(disabled, in: root)
check(target.fired == [42] && controller.isVisible, "disabled actions do not dispatch")
controller.keyDown(key(0, text: "o"), in: root)
check(root.selected == 4, "type-to-select")
check(controller.shortcut(key(8, text: "c", flags: .command)), "menu key equivalent dispatches")
check(target.fired == [42,42], "key equivalent preserves sender")
show(); root = controller.pages[0]
controller.activate(branch, in: root)
submenu.addItem(NSMenuItem(title: String(repeating: "Async Wi-Fi result ", count: 6), action: nil, keyEquivalent: ""))
controller.refresh(menu: submenu)
check(controller.pages.count == 2 && controller.pages[1].rows.count == 2, "async model refresh renders open submenu")
check(controller.pages[1].panel.frame.maxX <= area.maxX, "wider async results remain inside screen")
controller.close(); controller.refresh(menu: submenu)
check(!controller.isVisible, "async refresh cannot resurrect dismissed menus")
show(); controller.dismissIfOutside(anchor.origin)
check(controller.isVisible, "status button click is left for toggle handling")
controller.dismissIfOutside(NSPoint(x: area.minX, y: area.minY))
check(!controller.isVisible, "outside click dismisses")
show(); controller.keyDown(key(53), in: controller.pages[0])
check(!controller.isVisible, "Escape dismisses")
show(); NotificationCenter.default.post(name: .bentoDismissMenu, object: nil)
check(!controller.isVisible, "capture and switcher dismiss menu before presenting")
for skin in allSkins {
    UserDefaults.standard.setVolatileDomain(["languageID": "zh-Hans", "skinID": skin.id], forName: UserDefaults.argumentDomain)
    show(); let page = controller.pages[0]
    let dark = page.panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    check(page.layer?.backgroundColor == skin.palette(dark: dark).surface.cgColor, "skin \(skin.id)")
    controller.close()
}
let long = NSMenu()
for i in 0..<80 { let item = NSMenuItem(title: "Item \(i)", action: #selector(Target.run(_:)), keyEquivalent: ""); item.target = target; long.addItem(item) }
controller.show(menu: long, anchor: anchor)
let longPage = controller.pages[0]
check(longPage.panel.frame.height <= area.height - 12, "long menus scroll within screen")
for _ in 0..<80 { longPage.moveSelection(1) }
check(longPage.selected == 79 && longPage.scroll.contentView.bounds.minY > 0, "keyboard scrolls selected item into view")
controller.close()
print("\(checks) themed menu checks passed: skins, native controls, hover, keyboard, actions, dismissal, async refresh and screen bounds")
