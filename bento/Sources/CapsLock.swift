import Cocoa

final class CapsLockController: NSObject {
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var dismiss: Timer?
    private(set) var panel: NSPanel?
    private(set) var isOn = false
    var onChange: (() -> Void)?
    var enabled: Bool { defaults.bool(forKey: "capsLock.enabled") }
    var soundEnabled: Bool { defaults.bool(forKey: "capsLock.sound") }
    override init() {
        super.init()
        defaults.register(defaults: ["capsLock.enabled": true, "capsLock.sound": true])
    }
    func start() {
        stop()
        isOn = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
        guard enabled else { onChange?(); return }
        // Read only the lock bit: no keystrokes are intercepted or recorded.
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.update(CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift))
        }
        timer.tolerance = 0.05
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        onChange?()
    }
    func stop() { timer?.invalidate(); timer = nil; dismiss?.invalidate(); dismiss = nil; panel?.orderOut(nil) }
    func update(_ value: Bool) {
        guard enabled, value != isOn else { return }
        isOn = value
        showHUD()
        if soundEnabled { NSSound(named: NSSound.Name(isOn ? "Tink" : "Purr"))?.play() }
        onChange?()
    }
    private func showHUD() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        if panel == nil {
            let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = L("Bento 大写锁定提示")
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
            window.level = .statusBar; window.ignoresMouseEvents = true; window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = window
        }
        let frame = screen.visibleFrame
        panel?.setFrame(NSRect(x: frame.midX - 90, y: frame.minY + 80, width: 180, height: 96), display: false)
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 180, height: 96))
        root.material = .hudWindow; root.state = .active; root.wantsLayer = true
        root.layer?.cornerRadius = 16; root.layer?.masksToBounds = true
        let icon = NSTextField(labelWithString: "⇪")
        icon.font = .systemFont(ofSize: 36, weight: .medium); icon.alignment = .center
        icon.frame = NSRect(x: 0, y: 38, width: 180, height: 48); root.addSubview(icon)
        let text = NSTextField(labelWithString: isOn ? L("大写锁定已开启") : L("大写锁定已关闭"))
        text.alignment = .center; text.frame = NSRect(x: 0, y: 16, width: 180, height: 20); root.addSubview(text)
        panel?.contentView = root; panel?.orderFrontRegardless()
        dismiss?.invalidate()
        let timer = Timer(timeInterval: 0.8, repeats: false) { [weak self] _ in self?.panel?.orderOut(nil) }
        dismiss = timer; RunLoop.main.add(timer, forMode: .common)
    }
    @objc private func toggle() { defaults.set(!enabled, forKey: "capsLock.enabled"); start() }
    @objc private func toggleSound() { defaults.set(!soundEnabled, forKey: "capsLock.sound") }
    func menuItem() -> NSMenuItem {
        let root = NSMenuItem(title: L("大写锁定提示"), action: nil, keyEquivalent: "")
        root.image = NSImage(systemSymbolName: "capslock", accessibilityDescription: nil)
        let menu = NSMenu()
        for (title, action, on) in [(L("启用大写锁定提示"), #selector(toggle), enabled), (L("播放提示音"), #selector(toggleSound), soundEnabled)] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self; item.state = on ? .on : .off; menu.addItem(item)
        }
        menu.addItem(NSMenuItem(title: isOn ? L("当前：大写锁定开启") : L("当前：大写锁定关闭"), action: nil, keyEquivalent: ""))
        root.submenu = menu; return root
    }
}
