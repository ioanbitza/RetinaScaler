import CoreGraphics
import Foundation

/// Toggles HDR mode on external displays via CoreDisplay private API.
enum HDRManager {

    // CoreDisplay private functions
    private static let cgDisplaySetHDRMode: (@convention(c) (CGDirectDisplayID, Bool) -> Void)? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY) else { return nil }
        guard let sym = dlsym(handle, "CGDisplaySetHDRMode") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID, Bool) -> Void).self)
    }()

    private static let cgDisplayGetHDRMode: (@convention(c) (CGDirectDisplayID) -> Bool)? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY) else { return nil }
        // Try CoreDisplay_Display_GetHDRModeEnabled
        if let sym = dlsym(handle, "CoreDisplay_Display_GetHDRModeEnabled") {
            return unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID) -> Bool).self)
        }
        return nil
    }()

    static func isHDREnabled(for displayID: CGDirectDisplayID) -> Bool? {
        guard let getter = cgDisplayGetHDRMode else { return nil }
        return getter(displayID)
    }

    static func setHDR(enabled: Bool, for displayID: CGDirectDisplayID) -> Bool {
        guard let setter = cgDisplaySetHDRMode else { return false }
        setter(displayID, enabled)
        return true
    }

    static func toggleHDR(for displayID: CGDirectDisplayID) -> Bool {
        guard let current = isHDREnabled(for: displayID) else { return false }
        return setHDR(enabled: !current, for: displayID)
    }

    static var isAvailable: Bool {
        cgDisplaySetHDRMode != nil
    }
}
