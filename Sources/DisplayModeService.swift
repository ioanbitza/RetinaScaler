import CoreGraphics
import Foundation
import os.log

private let logger = Logger(subsystem: "com.astralbyte.retinascaler", category: "DisplayModeService")

enum DisplayModeService {

    static func availableModes(for displayID: CGDirectDisplayID) -> [DisplayModeInfo] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary

        guard let cgModes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else {
            logger.warning("CGDisplayCopyAllDisplayModes returned nil for display \(displayID)")
            return []
        }

        return cgModes.map { mode in
            DisplayModeInfo(
                mode: mode,
                width: mode.width,
                height: mode.height,
                isHiDPI: mode.pixelWidth > mode.width,
                refreshRate: mode.refreshRate
            )
        }
        .sorted { a, b in
            if a.width != b.width { return a.width > b.width }
            if a.height != b.height { return a.height > b.height }
            if a.isHiDPI != b.isHiDPI { return a.isHiDPI }
            return a.refreshRate > b.refreshRate
        }
    }

    static func currentMode(for displayID: CGDirectDisplayID) -> DisplayModeInfo? {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else { return nil }
        return DisplayModeInfo(
            mode: mode,
            width: mode.width,
            height: mode.height,
            isHiDPI: mode.pixelWidth > mode.width,
            refreshRate: mode.refreshRate
        )
    }

    static func switchMode(_ mode: DisplayModeInfo, for displayID: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        let beginResult = CGBeginDisplayConfiguration(&config)
        guard beginResult == .success else {
            logger.error("CGBeginDisplayConfiguration failed with code \(beginResult.rawValue) for display \(displayID)")
            return false
        }

        CGConfigureDisplayWithDisplayMode(config, displayID, mode.mode, nil)

        let completeResult = CGCompleteDisplayConfiguration(config, .permanently)
        if completeResult != .success {
            logger.error("CGCompleteDisplayConfiguration failed with code \(completeResult.rawValue) for display \(displayID)")
            return false
        }

        logger.info("Switched display \(displayID) to \(mode.description)")
        return true
    }

    /// Checks if a HiDPI mode matching the native resolution is available
    static func hasNativeHiDPI(for displayID: CGDirectDisplayID) -> Bool {
        let nativeWidth = CGDisplayPixelsWide(displayID)
        let nativeHeight = CGDisplayPixelsHigh(displayID)
        return availableModes(for: displayID).contains {
            $0.isHiDPI && $0.width == nativeWidth && $0.height == nativeHeight
        }
    }
}
