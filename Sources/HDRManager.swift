import CoreGraphics
import Foundation
import os.log

private let logger = Logger(subsystem: "com.astralbyte.retinascaler", category: "HDR")

/// Toggles HDR mode on displays via CoreDisplay private API.
/// Apple renames these symbols across macOS versions, so we try multiple names.
enum HDRManager {

    // CoreDisplay private functions -- loaded lazily once with fallback symbol names
    private static let coreDisplayHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)
    }()

    private static let setHDRMode: (@convention(c) (CGDirectDisplayID, Bool) -> Void)? = {
        guard let handle = coreDisplayHandle else {
            logger.warning("Failed to load CoreDisplay framework for HDR")
            return nil
        }
        // Try symbol names from newest to oldest
        for name in [
            "CoreDisplay_Display_SetHDRModeEnabled",
            "CGDisplaySetHDRMode",
        ] {
            if let sym = dlsym(handle, name) {
                logger.info("HDR setter loaded via \(name)")
                return unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID, Bool) -> Void).self)
            }
        }
        logger.info("No HDR setter function found in CoreDisplay")
        return nil
    }()

    private static let getHDRMode: (@convention(c) (CGDirectDisplayID) -> Bool)? = {
        guard let handle = coreDisplayHandle else { return nil }
        for name in [
            "CoreDisplay_Display_IsHDRModeEnabled",
            "CoreDisplay_Display_GetHDRModeEnabled",
            "CGDisplayGetHDRMode",
        ] {
            if let sym = dlsym(handle, name) {
                logger.info("HDR getter loaded via \(name)")
                return unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID) -> Bool).self)
            }
        }
        logger.info("No HDR getter function found in CoreDisplay")
        return nil
    }()

    static func isHDREnabled(for displayID: CGDirectDisplayID) -> Bool? {
        guard let getter = getHDRMode else { return nil }
        return getter(displayID)
    }

    static func setHDR(enabled: Bool, for displayID: CGDirectDisplayID) -> Bool {
        guard let setter = setHDRMode else {
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
        setHDRMode != nil && getHDRMode != nil
    }
}
