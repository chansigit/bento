import Cocoa

// The existing NSMenu tree stays the action model; only its presentation changes.
final class SkinnedMenuController: NSObject {
    private(set) var pages: [SkinnedMenuPage] = []
    private var anchor = NSRect.zero
    private var hoverTimer: Timer?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private weak var statusButton: NSStatusBarButton?
    private var search = ""
    private var searchTime = Date.distantPast
    var isVisible: Bool { !pages.isEmpty }

    override init() {
        super.init()
        for name in [Notification.Name.bentoDismissMenu, .bentoSkinChanged, BentoLanguage.changed, NSApplication.didChangeScreenParametersNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(close), name: name, object: nil)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(close), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(close), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }
    func toggle(menu: NSMenu, from button: NSStatusBarButton) {
        if isVisible { close(); return }
        guard let window = button.window else { return }
        show(menu: menu, anchor: window.convertToScreen(button.convert(button.bounds, to: nil)))
        statusButton = button; button.highlight(true)
    }
    func show(menu: NSMenu, anchor: NSRect) {
        close(); self.anchor = anchor
        menu.delegate?.menuNeedsUpdate?(menu)
        openPage(menu, anchor: anchor, parent: nil)
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.dismissIfOutside(NSEvent.mouseLocation); return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in self?.dismissIfOutside(NSEvent.mouseLocation) }
    }
    func dismissIfOutside(_ point: NSPoint) {
        if !anchor.contains(point) && !pages.contains(where: { $0.panel.frame.contains(point) }) { close() }
    }
    @objc func close() {
        statusButton?.highlight(false); statusButton = nil
        hoverTimer?.invalidate(); hoverTimer = nil
        for page in pages.reversed() { page.dispose() }
        pages.removeAll()
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }; localMonitor = nil
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }; globalMonitor = nil
        search = ""
    }
    func closeChildren(of page: SkinnedMenuPage) {
        guard let index = pages.firstIndex(where: { $0 === page }) else { return }
        hoverTimer?.invalidate(); hoverTimer = nil
        for child in pages.dropFirst(index + 1).reversed() { child.dispose() }
        pages = Array(pages.prefix(index + 1))
    }
    private func openPage(_ menu: NSMenu, anchor: NSRect, parent: SkinnedMenuPage?) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main else { return }
        let page = SkinnedMenuPage(menu: menu, owner: self, maxHeight: screen.visibleFrame.height - 12)
        let size = page.panel.frame.size, area = screen.visibleFrame.insetBy(dx: 6, dy: 6)
        var x = parent == nil ? anchor.maxX - size.width : anchor.maxX + 4
        if parent != nil && x + size.width > area.maxX { x = anchor.minX - size.width - 4 }
        x = max(area.minX, min(x, area.maxX - size.width))
        let y = max(area.minY, min((parent == nil ? anchor.minY - 4 : anchor.maxY) - size.height, area.maxY - size.height))
        page.panel.setFrameOrigin(NSPoint(x: x, y: y))
        pages.append(page)
        page.panel.makeKeyAndOrderFront(nil); page.panel.makeFirstResponder(page)
    }
    func hover(_ row: SkinnedMenuRow, in page: SkinnedMenuPage) {
        guard pages.contains(where: { $0 === page }) else { return }
        if page.selected == row.index { return }
        closeChildren(of: page); page.panel.makeKeyAndOrderFront(nil); page.select(row.index)
        guard row.item.submenu != nil, row.item.isEnabled else { return }
        let timer = Timer(timeInterval: 0.18, repeats: false) { [weak self, weak page] _ in
            guard let self = self, let page = page, page.selected == row.index else { return }
            self.activate(row.item, in: page, keyboard: false)
        }
        hoverTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func activate(_ item: NSMenuItem, in page: SkinnedMenuPage, keyboard: Bool = false) {
        guard item.isEnabled, pages.contains(where: { $0 === page }) else { return }
        if let submenu = item.submenu, let row = page.rows.first(where: { $0.item === item }) {
            closeChildren(of: page)
            submenu.delegate?.menuNeedsUpdate?(submenu)
            let rect = page.panel.convertToScreen(row.convert(row.bounds, to: nil))
            openPage(submenu, anchor: NSRect(x: page.panel.frame.minX, y: rect.minY, width: page.panel.frame.width, height: rect.height), parent: page)
            if keyboard { pages.last?.moveSelection(1) }
        } else if let action = item.action {
            close()
            NSApp.sendAction(action, to: item.target, from: item)
        }
    }
    // Wi-Fi finishes asynchronously. Update only the still-open model, never reopen it.
    func refresh(menu: NSMenu) {
        guard let page = pages.first(where: { $0.model === menu }) else { return }
        closeChildren(of: page); page.rebuild()
    }
    func keyDown(_ event: NSEvent, in page: SkinnedMenuPage) {
        switch event.keyCode {
        case 53: close()
        case 125: closeChildren(of: page); page.moveSelection(1)
        case 126: closeChildren(of: page); page.moveSelection(-1)
        case 124:
            if let index = page.selected, page.rows[index].item.submenu != nil { activate(page.rows[index].item, in: page, keyboard: true) }
        case 36, 76, 49:
            if let index = page.selected { activate(page.rows[index].item, in: page, keyboard: true) }
        case 123:
            if let index = pages.firstIndex(where: { $0 === page }), index > 0 {
                let parent = pages[index - 1]; closeChildren(of: parent)
                parent.panel.makeKeyAndOrderFront(nil); parent.panel.makeFirstResponder(parent)
            } else { close() }
        case 48:
            // Tab enters native slider/segmented controls; their arrow keys remain native.
            page.focusControl(backwards: event.modifierFlags.contains(.shift))
        default:
            guard let text = event.characters, !text.isEmpty, !event.modifierFlags.contains(.command), text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return }
            if Date().timeIntervalSince(searchTime) > 1 { search = "" }
            search += text; searchTime = Date()
            let folded = search.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: BentoLanguage.locale)
            if let index = page.rows.firstIndex(where: { $0.selectable && $0.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: BentoLanguage.locale).hasPrefix(folded) }) {
                closeChildren(of: page); page.select(index, scroll: true)
            }
        }
    }
    func shortcut(_ event: NSEvent) -> Bool {
        guard let root = pages.first?.model, let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let mask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard !event.modifierFlags.intersection(mask).isEmpty else { return false }
        func find(_ menu: NSMenu) -> NSMenuItem? {
            for item in menu.items where item.isEnabled {
                if !item.keyEquivalent.isEmpty, item.keyEquivalent.lowercased() == key,
                   item.keyEquivalentModifierMask.intersection(mask) == event.modifierFlags.intersection(mask), item.action != nil { return item }
                if let sub = item.submenu, let match = find(sub) { return match }
            }
            return nil
        }
        guard let item = find(root), let action = item.action else { return false }
        close(); return NSApp.sendAction(action, to: item.target, from: item)
    }
}

final class SkinnedMenuPanel: NSPanel {
    weak var page: SkinnedMenuPage?
    override var canBecomeKey: Bool { true }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, [48, 53].contains(event.keyCode), let page = page {
            page.owner?.keyDown(event, in: page); return
        }
        super.sendEvent(event)
    }
    override func keyDown(with event: NSEvent) { if let page = page { page.owner?.keyDown(event, in: page) } }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if page?.owner?.shortcut(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}
private final class MenuDocument: NSView { override var isFlipped: Bool { true } }

final class SkinnedMenuPage: NSView {
    let model: NSMenu
    weak var owner: SkinnedMenuController?
    let panel = SkinnedMenuPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let scroll = NSScrollView()
    private let document = MenuDocument()
    private let maxHeight: CGFloat
    private(set) var rows: [SkinnedMenuRow] = []
    private(set) var selected: Int?
    private(set) var palette: SkinPalette
    override var acceptsFirstResponder: Bool { true }
    init(menu: NSMenu, owner: SkinnedMenuController, maxHeight: CGFloat) {
        self.model = menu; self.owner = owner; self.maxHeight = maxHeight
        let skin = skin(withID: UserDefaults.standard.string(forKey: "skinID"))
        panel.appearance = skin.appearanceName.flatMap { NSAppearance(named: $0) }
        palette = skin.palette(dark: panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        super.init(frame: .zero)
        panel.page = self; panel.isReleasedWhenClosed = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .popUpMenu; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        wantsLayer = true; layer?.backgroundColor = palette.surface.cgColor
        layer?.cornerRadius = palette.radius; layer?.borderColor = palette.border.cgColor; layer?.borderWidth = 1
        layer?.masksToBounds = true
        scroll.drawsBackground = false; scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.scrollerKnobStyle = panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .light : .dark
        scroll.documentView = document; addSubview(scroll)
        document.setAccessibilityRole(.menu)
        panel.contentView = self
        rebuild()
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(didScroll), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func keyDown(with event: NSEvent) { owner?.keyDown(event, in: self) }
    @objc private func didScroll() { owner?.closeChildren(of: self) }
    func dispose() { panel.orderOut(nil); panel.contentView = nil; panel.page = nil; panel.close() }
    func rebuild() {
        let top = panel.frame.maxY
        selected = nil; rows.removeAll(); document.subviews.forEach { $0.removeFromSuperview() }
        let font = NSFont.menuFont(ofSize: 13)
        let preferred = model.items.map { item -> CGFloat in
            if let view = item.view { return view.frame.width + 24 }
            let text = item.attributedTitle?.string ?? item.title
            return (text as NSString).size(withAttributes: [.font: font]).width + 88
        }.max() ?? 350
        let width = min(520, max(360, preferred))
        var y: CGFloat = 4
        for (index, item) in model.items.enumerated() {
            let row = SkinnedMenuRow(item: item, index: index, page: self, width: width - 16)
            row.frame.origin.y = y; document.addSubview(row); rows.append(row); y += row.frame.height
        }
        document.frame = NSRect(x: 0, y: 0, width: width - 16, height: y + 4)
        let height = min(maxHeight, y + 16)
        panel.setContentSize(NSSize(width: width, height: height))
        if panel.isVisible, let area = panel.screen?.visibleFrame.insetBy(dx: 6, dy: 6) {
            panel.setFrameOrigin(NSPoint(x: max(area.minX, min(panel.frame.minX, area.maxX - width)), y: max(area.minY, min(top - height, area.maxY - height))))
        }
        frame.size = NSSize(width: width, height: height)
        scroll.frame = bounds.insetBy(dx: 8, dy: 6)
        scroll.contentView.scroll(to: .zero)
        panel.recalculateKeyViewLoop()
    }
    func select(_ index: Int, scroll shouldScroll: Bool = false) {
        guard rows.indices.contains(index) else { return }
        selected = index
        for row in rows { row.highlighted = row.index == index && row.selectable; row.needsDisplay = true }
        if shouldScroll { document.scrollToVisible(rows[index].frame) }
    }
    func focusControl(backwards: Bool) {
        func controls(_ view: NSView) -> [NSControl] {
            if let control = view as? NSControl, control.isEnabled, control.acceptsFirstResponder { return [control] }
            return view.subviews.flatMap { controls($0) }
        }
        let candidates = controls(document)
        guard !candidates.isEmpty else { return }
        let current = candidates.firstIndex(where: { $0 === panel.firstResponder }) ?? (backwards ? 0 : -1)
        let next = candidates[(current + (backwards ? -1 : 1) + candidates.count) % candidates.count]
        next.scrollToVisible(next.bounds); panel.makeFirstResponder(next)
    }
    func moveSelection(_ delta: Int) {
        let candidates = rows.indices.filter { rows[$0].selectable }
        guard !candidates.isEmpty else { return }
        let index = selected.flatMap { candidates.firstIndex(of: $0) } ?? (delta > 0 ? -1 : 0)
        select(candidates[(index + delta + candidates.count) % candidates.count], scroll: true)
    }
}

final class SkinnedMenuRow: NSView {
    let item: NSMenuItem
    let index: Int
    weak var page: SkinnedMenuPage?
    var highlighted = false
    var title: String { item.attributedTitle?.string ?? item.title }
    var selectable: Bool { item.isEnabled && !item.isSeparatorItem && item.view == nil && (item.submenu != nil || item.action != nil) }
    private let text: NSAttributedString
    override var isFlipped: Bool { true }
    init(item: NSMenuItem, index: Int, page: SkinnedMenuPage, width: CGFloat) {
        self.item = item; self.index = index; self.page = page
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
        let plain = item.title.isEmpty ? " " : item.title
        let attributed = item.attributedTitle ?? NSAttributedString(string: plain, attributes: [.font: NSFont.menuFont(ofSize: 13), .foregroundColor: item.isEnabled ? NSColor.labelColor : .secondaryLabelColor, .paragraphStyle: paragraph])
        text = attributed
        let height = item.isSeparatorItem ? 9 : (item.view.map { $0.frame.height + 6 } ?? max(28, min(78, ceil(attributed.boundingRect(with: NSSize(width: width - 66, height: 200), options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 10)))
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        toolTip = title
        if let view = item.view {
            view.frame.origin = NSPoint(x: (width - view.frame.width) / 2, y: 3); addSubview(view)
            setAccessibilityElement(false)
        } else if !item.isSeparatorItem {
            setAccessibilityElement(true); setAccessibilityRole(selectable ? .menuItem : .staticText)
            setAccessibilityLabel(title); setAccessibilityEnabled(item.isEnabled)
            setAccessibilityValue(item.state == .on ? "✓" : "")
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { if let page = page { page.owner?.hover(self, in: page) } }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(page) }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)), let page = page { page.owner?.activate(item, in: page) }
    }
    override func accessibilityPerformPress() -> Bool {
        guard selectable, let page = page else { return false }
        page.owner?.activate(item, in: page, keyboard: true); return true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let palette = page?.palette else { return }
        if item.isSeparatorItem {
            palette.border.setFill(); NSRect(x: 10, y: bounds.midY, width: bounds.width - 20, height: 0.5).fill(); return
        }
        let rect = bounds.insetBy(dx: 1, dy: 1)
        if highlighted || item.view != nil {
            (highlighted ? palette.selection : palette.card).setFill()
            let path = NSBezierPath(roundedRect: rect, xRadius: max(4, palette.radius - 5), yRadius: max(4, palette.radius - 5))
            path.fill()
            if highlighted { palette.accent.setStroke(); path.lineWidth = 1; path.stroke() }
        }
        guard item.view == nil else { return }
        let ink = NSColor.labelColor
        let glyphAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 12), .foregroundColor: ink]
        if item.state != .off { (item.state == .on ? "✓" : "−" as NSString).draw(at: NSPoint(x: 5, y: bounds.midY - 8), withAttributes: glyphAttrs) }
        if let image = item.image {
            let iconRect = NSRect(x: 19, y: bounds.midY - 8, width: 16, height: 16)
            if image.isTemplate {
                let tinted = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                    image.draw(in: rect); ink.setFill(); rect.fill(using: .sourceIn); return true
                }
                tinted.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            } else { image.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
        }
        let x: CGFloat = item.image == nil ? 23 : 41
        let textRect = NSRect(x: x, y: 5, width: bounds.width - x - 28, height: bounds.height - 10)
        text.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        if item.submenu != nil { ("›" as NSString).draw(at: NSPoint(x: bounds.width - 20, y: bounds.midY - 9), withAttributes: glyphAttrs) }
    }
}
