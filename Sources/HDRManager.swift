import CoreGraphics
import Foundation
import os.log

private let logger = Logger(subsystem: "com.astralbyte.retinascaler", category: "HDR")

/// Toggles HDR mode on external displays via CoreDisplay private API.
enum HDRManager {

    // CoreDisplay private functions -- loaded lazily once
    private static let coreDisplayHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)
    }()

    private static let cgDisplaySetHDRMode: (@convention(c) (CGDirectDisplayID, Bool) -> Void)? = {
        guard let handle = coreDisplayHandle else {
            logger.warning("Failed to load CoreDisplay framework for HDR")
            return nil
        }
        guard let sym = dlsym(handle, "CGDisplaySetHDRMode") else {
            logger.info("CGDisplaySetHDRMode not found in CoreDisplay")
            return nil
        }
        return unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID, Bool) -> Void).self)
    }()

    private static let cgDisplayGetHDRMode: (@convention(c) (CGDirectDisplayID) -> Bool)? = {
        guard let handle = coreDisplayHandle else { return nil }
        // Try CoreDisplay_Display_GetHDRModeEnabled (newer API name)
        if let sym = dlsym(handle, "CoreDisplay_Display_GetHDRModeEnabled") {
            return unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID) -> Bool).self)
        }
        // Fallback to CGDisplayGetHDRMode
        if let sym = dlsym(handle, "CGDisplayGetHDRMode") {
            return unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID) -> Bool).self)
        }
        logger.info("No HDR getter function found in CoreDisplay")
        return nil
    }()

    static func isHDREnabled(for displayID: CGDirectDisplayID) -> Bool? {
        guard let getter = cgDisplayGetHDRMode else { return nil }
        return getter(displayID)
    }

    static func setHDR(enabled: Bool, for displayID: CGDirectDisplayID) -> Bool {
        guard let setter = cgDisplaySetHDRMode else {
            logger.warning("HDR set not available -- CoreDisplay API missing")
            return false
        }
        setter(displayID, enabled)
        logger.info("HDR \(enabled ? "enabled" : "disabled") for display \(displayID)")
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
