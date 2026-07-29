import Foundation
import IOKit.pwr_mgt

// MARK: - Keep-awake (caffeine) controller
//
// Holds an IOPM power assertion while enabled. Deliberately NOT persisted:
// preventing sleep is a temporary state and must not survive a relaunch.

final class CaffeineController {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isActive = false

    /// Toggle keep-awake. Returns the new state.
    @discardableResult
    func toggle() -> Bool {
        setActive(!isActive)
        return isActive
    }

    func setActive(_ on: Bool) {
        if on == isActive { return }
        if on {
            // PreventUserIdleDisplaySleep keeps both the display and the system
            // awake (what people expect from "防休眠" during a long task or demo).
            let ok = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Bento 防休眠" as CFString,
                &assertionID)
            isActive = (ok == kIOReturnSuccess)
        } else {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            isActive = false
        }
    }

    deinit { setActive(false) }
}
