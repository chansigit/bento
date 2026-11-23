import Cocoa

UserDefaults.standard.setVolatileDomain(["languageID": "zh-Hans"], forName: UserDefaults.argumentDomain)

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError(message) }
}
check(snipPixelRect(CGRect(x: 10, y: 20, width: 30, height: 40), viewSize: CGSize(width: 100, height: 100), imageSize: CGSize(width: 200, height: 200)) == CGRect(x: 20, y: 80, width: 60, height: 80), "Retina selection converts bottom-left points to top-left pixels")
check(snipPixelRect(CGRect(x: -10, y: -10, width: 30, height: 30), viewSize: CGSize(width: 100, height: 100), imageSize: CGSize(width: 200, height: 200)) == CGRect(x: 0, y: 160, width: 40, height: 40), "selection clamps to current display")
let app = NSApplication.shared; app.setActivationPolicy(.accessory)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: 320, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, 1])!); ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
ctx.setFillColor(CGColor(colorSpace: space, components: [0.5, 0.5, 0.5, 1])!); ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
let source = ctx.makeImage()!
func rgba(_ image: CGImage, x: Int, y: Int) -> [Int] {
    let bytes = image.dataProvider!.data! as Data
    let offset = y * image.bytesPerRow + x * 4
    return (0..<4).map { Int(bytes[offset + $0]) }
}
var document = SnipDocument(image: source)
let clean = document.rendered()!
check(clean.width == 320 && clean.height == 200 && clean.colorSpace?.name == CGColorSpace.sRGB, "native pixels and sRGB preserved")
check(rgba(clean, x: 5, y: 195).prefix(3).allSatisfy { abs($0 - 128) <= 1 }, "gray survives export without haze")
check(rgba(clean, x: 100, y: 100) == [255,255,255,255], "white survives export")
check(snipRect(CGPoint(x: 80, y: 90), CGPoint(x: 10, y: 20)) == CGRect(x: 10, y: 20, width: 70, height: 70), "reverse drag rectangle")
document.append(SnipMark(tool: .redact, points: [CGPoint(x: 40, y: 40), CGPoint(x: 80, y: 80)], color: .red, width: 3))
check(rgba(document.rendered()!, x: 60, y: 140) == [0,0,0,255], "solid redaction removes source pixels")
check(rgba(document.rendered()!, x: 100, y: 140) == [255,255,255,255], "outside redaction unchanged")
document.undo(); check(document.marks.isEmpty && document.redoMarks.count == 1, "undo")
document.redo(); check(document.marks.count == 1 && document.redoMarks.isEmpty, "redo")
document.undo(); document.append(SnipMark(tool: .arrow, points: [CGPoint(x: 10, y: 100), CGPoint(x: 80, y: 100)], color: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), width: 3))
check(document.redoMarks.isEmpty, "new mark clears redo")
let arrow = rgba(document.rendered()!, x: 45, y: 100)
check(arrow[0] > 250 && arrow[1] < 5, "arrow renders at correct position")
for (index, tool) in [SnipTool.rectangle, .ellipse, .pen, .text].enumerated() {
    document.append(SnipMark(tool: tool, points: [CGPoint(x: 100 + index * 40, y: 30), CGPoint(x: 125 + index * 40, y: 70)], color: .systemBlue, width: 3, text: "字"))
}
let output = document.rendered()!
let png = snipPNG(output)!
let decoded = NSBitmapImageRep(data: png)!
check(decoded.pixelsWide == 320 && decoded.pixelsHigh == 200, "PNG keeps full resolution")
let retina = NSImage(cgImage: source, size: CGSize(width: 160, height: 100))
check(snipImage(retina)?.width == 320, "Retina logical size does not downsample export")
let pasteboard = NSPasteboard.withUniqueName()
check(copySnip(output, pasteboard: pasteboard), "copy PNG")
check(pasteboard.data(forType: .png) == png, "clipboard PNG matches rendered output")
pasteboard.releaseGlobally()

let canvas = SnipCanvas(image: source, size: CGSize(width: 160, height: 100))
check(canvas.imagePoint(CGPoint(x: 50, y: 30)) == CGPoint(x: 100, y: 60), "view to pixel mapping")
check(canvas.imagePoint(CGPoint(x: -20, y: 300)) == CGPoint(x: 0, y: 200), "drawing constrained to image")
let editor = SnipEditor(image: source)
editor.canvas.document.append(SnipMark(tool: .rectangle, points: [.zero, CGPoint(x: 40, y: 40)], color: .red, width: 2))
editor.show()
let undoEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: editor.window!.windowNumber, context: nil, characters: "z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6)!
// Button shortcut state follows edits as it does after a real canvas gesture.
editor.canvas.onChange?()
check(editor.window!.performKeyEquivalent(with: undoEvent), "editor Cmd+Z shortcut handled")
check(editor.canvas.document.marks.isEmpty, "editor undo")
editor.redoMark(); check(editor.canvas.document.marks.count == 1, "editor redo")
var pinned: CGImage?
editor.onPin = { pinned = $0 }; editor.pinImage()
check(pinned?.width == 320, "pin uses full resolution annotated image")
let selection = SnipSelectionView(image: source, screen: NSScreen.main!, windows: [])
selection.frame.size = CGSize(width: 160, height: 100)
let selectionWindow = SnipPanel(contentRect: CGRect(x: 0, y: 0, width: 160, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
selectionWindow.isReleasedWhenClosed = false; selectionWindow.contentView = selection
var cropped: CGImage?
selection.finished = { cropped = $0 }
func mouseEvent(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: selectionWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
}
selection.mouseDown(with: mouseEvent(.leftMouseDown, CGPoint(x: 20, y: 20)))
selection.mouseDragged(with: mouseEvent(.leftMouseDragged, CGPoint(x: 60, y: 60)))
selection.mouseUp(with: mouseEvent(.leftMouseUp, CGPoint(x: 60, y: 60)))
check(cropped?.width == 80 && cropped?.height == 80, "selection gesture yields full density crop")
selectionWindow.close()
let display = CGRect(x: -160, y: 200, width: 160, height: 100)
let region = CGRect(x: 20, y: 20, width: 40, height: 40)
let crop = source.cropping(to: snipPixelRect(region, viewSize: display.size, imageSize: CGSize(width: 320, height: 200)))!
let inline = SnipEditor(image: crop, capture: SnipCapture(snapshot: source, screenFrame: display, region: region))
check(!inline.window!.styleMask.contains(.titled), "no separate titled editor")
check(inline.canvas.frame == region, "original selection size and local position")
check(inline.window!.convertToScreen(region) == region.offsetBy(dx: display.minX, dy: display.minY), "original global position on offset display")
let originalPNG = snipPNG(inline.canvas.document.rendered()!)!
let moved = constrainedSnipFrame(region.offsetBy(dx: 500, dy: -500), bounds: CGRect(origin: .zero, size: display.size))
check(moved == CGRect(x: 120, y: 0, width: 40, height: 40), "drag stays reachable without resizing")
inline.changeDisplayFrame(moved)
check(inline.canvas.frame == moved && snipPNG(inline.canvas.document.rendered()!) == originalPNG, "drag moves captured image without recapturing background")
inline.changeDisplayFrame(region)
inline.zoomDisplay(1.5, anchor: CGPoint(x: 40, y: 40))
check(inline.canvas.frame == CGRect(x: 10, y: 10, width: 60, height: 60), "zoom stays anchored to pointer")
check(inline.canvas.document.image.width == 80 && snipPNG(inline.canvas.document.rendered()!) == originalPNG, "zoom leaves original pixels and export unchanged")
inline.zoomDisplay(1 / 1.5, anchor: CGPoint(x: 40, y: 40))
check(abs(inline.canvas.frame.width - 40) < 0.01, "reverse wheel restores size")
inline.zoomDisplay(100, anchor: CGPoint(x: 40, y: 40))
check(inline.canvas.frame.width == 200 && inline.canvas.frame.height == 200, "zoom maximum and aspect ratio")
inline.zoomDisplay(0.00001, anchor: CGPoint(x: 40, y: 40))
check(inline.canvas.frame.width >= 16, "zoom minimum stays usable")
inline.changeDisplayFrame(region)
func inlineMouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: inline.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
}
inline.canvas.mouseDown(with: inlineMouse(.leftMouseDown, CGPoint(x: 30, y: 30)))
inline.canvas.mouseDragged(with: inlineMouse(.leftMouseDragged, CGPoint(x: 40, y: 40)))
inline.canvas.mouseUp(with: inlineMouse(.leftMouseUp, CGPoint(x: 40, y: 40)))
check(inline.canvas.frame.origin == CGPoint(x: 30, y: 30), "mouse gesture moves the captured image")
let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0)!
inline.canvas.scrollWheel(with: NSEvent(cgEvent: wheel)!)
check(inline.canvas.frame.width > 40 && snipPNG(inline.canvas.document.rendered()!) == originalPNG, "wheel event zooms display without touching pixels")
inline.close()
let controller = SnippingController()
controller.finishCapture(SnipCapture(snapshot: source, screenFrame: display, region: region))
check(controller.editor == nil && controller.pins.count == 1, "capture completes directly as sticker without editor overlay")
let sticker = controller.pins[0]
check(sticker.window!.frame == region.offsetBy(dx: display.minX, dy: display.minY), "sticker preserves exact capture position and point size")
check(sticker.image.width == 80 && sticker.image.height == 80 && sticker.window!.frame.size == region.size, "Retina sticker preserves original pixels and logical size")
check(sticker.window?.level == .floating && sticker.window?.isOpaque == false, "sticker is a small floating window, not a full-screen dimming surface")
check(!sticker.editing && sticker.controls?.frame.height == 26, "editing menu starts collapsed")
let stickerFrame = sticker.window!.frame
sticker.toggleEditing()
check(sticker.editing && sticker.controls?.frame.height == 104 && controller.editor == nil, "expand edits on sticker without fullscreen editor")
check(sticker.window!.frame == stickerFrame, "expanding menu does not move or resize image")
sticker.colorPicker.selectItem(at: 4)
check(NSApp.sendAction(sticker.colorPicker.action!, to: sticker.colorPicker.target, from: sticker.colorPicker), "preset color menu action delivered")
check(sticker.canvas.color == NSColor.systemBlue, "color menu updates annotation color")
sticker.colorPicker.selectItem(withTag: -1); sticker.colorPicker.chooseColor()
check(NSColorPanel.shared.isVisible && NSColorPanel.shared.level.rawValue > sticker.window!.level.rawValue, "custom picker opens above sticker")
NSColorPanel.shared.color = NSColor(srgbRed: 0.1, green: 0.8, blue: 0.2, alpha: 1)
sticker.colorPicker.customColorChanged(NSColorPanel.shared)
check(sticker.canvas.color == NSColorPanel.shared.color, "custom picker action updates annotation color")
sticker.colorPicker.dismissPicker()
let originalStickerPNG = snipPNG(sticker.renderedImage()!)!
sticker.canvas.tool = .redact
let number = sticker.window!.windowNumber
func stickerMouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: number, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
}
sticker.canvas.tool = .arrow
sticker.canvas.mouseDown(with: stickerMouse(.leftMouseDown, CGPoint(x: 5, y: 5)))
sticker.canvas.mouseDragged(with: stickerMouse(.leftMouseDragged, CGPoint(x: 25, y: 5)))
sticker.canvas.mouseUp(with: stickerMouse(.leftMouseUp, CGPoint(x: 25, y: 5)))
let colored = rgba(sticker.renderedImage()!, x: 30, y: 70)
check(colored[1] > 190 && colored[0] < 50 && colored[2] < 70, "selected custom color reaches rendered annotation pixels")
sticker.undoMark(); sticker.canvas.tool = .redact
sticker.canvas.mouseDown(with: stickerMouse(.leftMouseDown, CGPoint(x: 5, y: 5)))
sticker.canvas.mouseDragged(with: stickerMouse(.leftMouseDragged, CGPoint(x: 20, y: 20)))
sticker.canvas.mouseUp(with: stickerMouse(.leftMouseUp, CGPoint(x: 20, y: 20)))
let editedStickerPNG = snipPNG(sticker.renderedImage()!)!
check(sticker.canvas.document.marks.count == 1 && originalStickerPNG != editedStickerPNG, "annotation gestures affect sticker exports")
sticker.toggleEditing()
check(!sticker.editing && snipPNG(sticker.renderedImage()!) == editedStickerPNG, "collapse preserves edits")
sticker.toggleEditing(); sticker.undoMark()
check(snipPNG(sticker.renderedImage()!) == originalStickerPNG, "undo survives collapsing and reopening")
sticker.redoMark()
check(snipPNG(sticker.renderedImage()!) == editedStickerPNG, "redo restores sticker annotation")
let controls = sticker.controls!
sticker.hide(); check(!controls.isVisible, "hiding sticker also hides editing menu")
sticker.show(); check(controls.isVisible, "showing sticker restores editing menu")
sticker.close()
check(!controls.isVisible && sticker.controls == nil, "closing sticker cleans up its menu")
controller.finishCapture(nil)
check(controller.editor == nil && controller.pins.isEmpty, "cancellation does not create a sticker")
controller.pin(source)
check(controller.pins.count == 1 && controller.pins[0].window?.isVisible == true, "visible floating pin")
let pin = controller.pins[0]
let originalFrame = pin.window!.frame
pin.zoom(1.5)
check(abs(pin.window!.frame.width / pin.window!.frame.height - 1.6) < 0.001, "pin zoom keeps aspect")
check(abs(pin.window!.frame.width - originalFrame.width * 1.5) < 0.1, "pin zoom changes size")
pin.changeOpacity(-10); check(pin.window?.alphaValue == 0.2, "opacity minimum remains recoverable")
pin.changeOpacity(10); check(pin.window?.alphaValue == 1, "opacity maximum")
check(pin.window?.level == .floating && pin.window?.hidesOnDeactivate == false, "pin stays over other apps")
controller.togglePins(); check(pin.window?.isVisible == false, "hide pins")
controller.togglePins(); check(pin.window?.isVisible == true, "restore pins")
pin.close(); check(controller.pins.isEmpty, "closed pin released")
controller.pin(source); controller.stop(); check(controller.pins.isEmpty, "shutdown cleans up pins")
check(controller.menuItems().count == 3, "menu exposes capture, clipboard pin and controls")
let patternContext = CGContext(data: nil, width: 96, height: 96, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
for x in 0..<96 {
    let c: CGFloat = x % 2 == 0 ? 0 : 1
    patternContext.setFillColor(CGColor(srgbRed: c, green: c, blue: c, alpha: 1)); patternContext.fill(CGRect(x: x, y: 0, width: 1, height: 96))
}
let pattern = patternContext.makeImage()!
let mosaicCanvas = SnipCanvas(image: pattern, size: CGSize(width: 96, height: 96)); mosaicCanvas.tool = .mosaic
mosaicCanvas.mouseDown(with: mouseEvent(.leftMouseDown, CGPoint(x: 16, y: 16)))
mosaicCanvas.mouseDragged(with: mouseEvent(.leftMouseDragged, CGPoint(x: 64, y: 64)))
check(mosaicCanvas.draft?.mosaic != nil, "mosaic shows a live patch while dragging")
mosaicCanvas.mouseUp(with: mouseEvent(.leftMouseUp, CGPoint(x: 64, y: 64)))
let mosaicOutput = mosaicCanvas.document.rendered()!
let pixel = rgba(mosaicOutput, x: 30, y: 50)
check(pixel[0] > 10 && pixel[0] < 245 && pixel[0] == pixel[1] && pixel[3] == 255, "mosaic pixelates original detail rather than painting black")
check(rgba(mosaicOutput, x: 30, y: 50) == rgba(mosaicOutput, x: 31, y: 50), "mosaic produces solid pixel blocks")
check(rgba(mosaicOutput, x: 4, y: 4) == rgba(pattern, x: 4, y: 4), "mosaic leaves outside pixels unchanged")
let mosaicPNG = snipPNG(mosaicOutput)!
mosaicCanvas.document.undo(); check(snipPNG(mosaicCanvas.document.rendered()!) == snipPNG(SnipDocument(image: pattern).rendered()!), "mosaic undo restores original")
mosaicCanvas.document.redo(); check(snipPNG(mosaicCanvas.document.rendered()!) == mosaicPNG, "mosaic redo and export retain pixelation")
mosaicCanvas.mouseDown(with: mouseEvent(.leftMouseDown, CGPoint(x: 80, y: 80)))
mosaicCanvas.mouseDragged(with: mouseEvent(.leftMouseDragged, CGPoint(x: 60, y: 60)))
mosaicCanvas.mouseDragged(with: mouseEvent(.leftMouseDragged, CGPoint(x: 40, y: 40)))
check(mosaicCanvas.draft?.points.first == CGPoint(x: 80, y: 80), "reverse mosaic drag keeps original anchor")
mosaicCanvas.cancelDraft(); check(mosaicCanvas.draft == nil, "cancel discards mosaic preview")
print("\(checks) snipping checks passed: color, resolution, redaction, undo/redo, clipboard, editor, pin lifecycle")

if let screen = NSScreen.main {
    let localizedPin = SnipPin(image: source, screen: screen)
    localizedPin.canvas.color = NSColor(srgbRed: 0.12, green: 0.34, blue: 0.56, alpha: 1)
    localizedPin.canvas.tool = .mosaic
    localizedPin.canvas.document.append(SnipMark(tool: .rectangle, points: [CGPoint(x: 5, y: 5), CGPoint(x: 25, y: 25)], color: .red, width: 2))
    let originalFrame = localizedPin.window!.frame
    let originalPixels = snipPNG(localizedPin.renderedImage()!)!
    localizedPin.toggleEditing()
    for (language, _) in BentoLanguage.choices where language != "system" {
        UserDefaults.standard.setVolatileDomain(["languageID": language], forName: UserDefaults.argumentDomain)
        NotificationCenter.default.post(name: BentoLanguage.changed, object: nil)
        localizedPin.controls?.contentView?.layoutSubtreeIfNeeded()
        check(localizedPin.window!.frame == originalFrame, "language preserves sticker frame: \(language)")
        check(snipPNG(localizedPin.renderedImage()!) == originalPixels, "language preserves document pixels: \(language)")
        check(localizedPin.canvas.tool == .mosaic && localizedPin.canvas.document.marks.count == 1, "language preserves tool and undo history: \(language)")
        check(localizedPin.colorPicker.color == localizedPin.canvas.color, "picker retains current custom color: \(language)")
        check(localizedPin.colorPicker.itemTitles.contains(L("红色")), "color labels update live: \(language)")
        let content = localizedPin.controls!.contentView!
        for row in content.subviews.compactMap({ $0 as? NSStackView }) {
            check(row.frame.maxX <= content.bounds.width + 1, "toolbar row fits: \(language)")
            for control in row.arrangedSubviews {
                let rect = control.alignmentRect(forFrame: control.frame)
                check(rect.minX >= -1 && rect.maxX <= row.bounds.width + 1, "toolbar control fits: \(language)")
            }
        }
    }
    for skin in allSkins {
        UserDefaults.standard.setVolatileDomain(["languageID": "zh-Hans", "skinID": skin.id], forName: UserDefaults.argumentDomain)
        NotificationCenter.default.post(name: .bentoSkinChanged, object: nil)
        check(snipPNG(localizedPin.renderedImage()!) == originalPixels, "skin preserves original image pixels: \(skin.id)")
        let panel = localizedPin.controls!
        let dark = panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        check(panel.contentView!.layer!.backgroundColor == skin.palette(dark: dark).surface.cgColor, "toolbar surface follows skin: \(skin.id)")
    }
    localizedPin.close()
    UserDefaults.standard.setVolatileDomain(["languageID": "zh-Hans"], forName: UserDefaults.argumentDomain)
}
print("\(checks) total snipping checks passed, including live language changes and toolbar bounds")
