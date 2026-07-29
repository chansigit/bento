import AppKit
import CoreGraphics
import Foundation

// MARK: - Display enumeration

struct DockDisplay {
    let id: CGDirectDisplayID
    let name: String
    let bounds: CGRect
    let isMain: Bool
}

func listDockDisplays() -> [DockDisplay] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)

    var names: [CGDirectDisplayID: String] = [:]
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    for screen in NSScreen.screens {
        if let num = (screen.deviceDescription[key] as? NSNumber)?.uint32Value {
            names[num] = screen.localizedName
        }
    }

    return ids.prefix(Int(count)).map { id in
        DockDisplay(id: id, name: names[id] ?? "显示器 \(id)",
                    bounds: CGDisplayBounds(id), isMain: CGDisplayIsMain(id) != 0)
    }
}

/// The Dock's current edge, read from its preferences (in-process; no child process).
func dockOrientationString() -> String {
    CFPreferencesAppSynchronize("com.apple.dock" as CFString)
    let v = CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String
    return v ?? "bottom"
}

/// Which display currently hosts the Dock (needs Screen Recording on newer macOS; nil if unknown).
func currentDockDisplayID() -> CGDirectDisplayID? {
    guard let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
    let displays = listDockDisplays()
    for window in windows {
        guard let owner = window[kCGWindowOwnerName as String] as? String, owner == "Dock",
              let layer = window[kCGWindowLayer as String] as? Int, layer == dockLevel,
              let bd = window[kCGWindowBounds as String] as? [String: Any] else { continue }
        let x = (bd["X"] as? NSNumber)?.doubleValue ?? 0
        let y = (bd["Y"] as? NSNumber)?.doubleValue ?? 0
        let w = (bd["Width"] as? NSNumber)?.doubleValue ?? 0
        let h = (bd["Height"] as? NSNumber)?.doubleValue ?? 0
        let rect = CGRect(x: x, y: y, width: w, height: h)
        // Skip the full-desktop window the Dock process also owns.
        if displays.contains(where: { rect.width >= $0.bounds.width && rect.height >= $0.bounds.height }) {
            continue
        }
        var displayID: CGDirectDisplayID = 0
        var n: UInt32 = 0
        CGGetDisplaysWithRect(rect, 1, &displayID, &n)
        if n > 0 { return displayID }
    }
    return nil
}

// MARK: - Dock pin controller

final class DockPinController {
    private(set) var targetName: String?
    private var targetDisplayID: CGDirectDisplayID = 0
    private var edge: DockEdge = .bottom
    private var monitor: Any?          // NSEvent global mouse monitor (listen-only)
    let zone: CGFloat = 6
    private var snapshot: [(id: CGDirectDisplayID, bounds: CGRect)] = []
    private var mainHeight: CGFloat = 0   // primary display height, for Cocoa→CG y-flip

    init(targetName: String?) { self.targetName = targetName }

    var isActive: Bool { monitor != nil }

    /// Change the pinned display (nil = unpin) and (re)configure.
    @discardableResult
    func setTarget(_ name: String?, promptForPermission: Bool) -> Bool {
        targetName = name
        return reapply()
    }

    /// Re-resolve the current target against live displays/orientation and start or stop.
    @discardableResult
    func reapply() -> Bool {
        edge = dockEdge(from: dockOrientationString())
        let displays = listDockDisplays()
        snapshot = displays.map { ($0.id, $0.bounds) }
        mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        guard let name = targetName,
              let disp = displays.first(where: { $0.name == name }) else {
            stopMonitor()
            return true
        }
        targetDisplayID = disp.id
        // With only the target display connected there's nothing to block.
        guard snapshot.contains(where: { $0.id != disp.id }) else {
            stopMonitor()
            return true
        }
        startMonitor()
        return true
    }

    private func startMonitor() {
        if monitor != nil { return }
        // A listen-only global monitor observes moves WITHOUT sitting in the input path,
        // so it adds no cursor latency (unlike an active CGEventTap). It also needs no
        // Accessibility permission for mouse events.
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] event in
            self?.enforce(cocoaLocation: event.locationInWindow)
        }
    }

    private func stopMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    /// If the pointer is inside a non-target display's true-outer Dock trigger zone,
    /// warp it back out. Pure arithmetic against the cached snapshot — no syscalls.
    private func enforce(cocoaLocation: NSPoint) {
        // Global-monitor events carry screen coordinates in locationInWindow (Cocoa,
        // bottom-left origin). Flip to CG top-left coordinates — no CGEvent allocation
        // or HID query per mouse move.
        let point = CGPoint(x: cocoaLocation.x, y: mainHeight - cocoaLocation.y)
        var bounds: CGRect? = nil
        var isTarget = false
        for d in snapshot where d.bounds.contains(point) {
            bounds = d.bounds
            isTarget = (d.id == targetDisplayID)
            break
        }
        guard let b = bounds, !isTarget else { return }
        guard let clamped = clampedCursor(point: point, displayBounds: b,
                                          isTargetDisplay: false, dockEdge: edge, zone: zone) else { return }
        let probe = edgeProbePoint(point: point, displayBounds: b, dockEdge: edge)
        if snapshot.contains(where: { $0.bounds.contains(probe) }) { return }  // internal boundary
        CGWarpMouseCursorPosition(clamped)
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
