import CoreGraphics
import Foundation

enum DisplayModeService {

    static func availableModes(for displayID: CGDirectDisplayID) -> [DisplayModeInfo] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary

        guard let cgModes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else {
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
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        CGConfigureDisplayWithDisplayMode(config, displayID, mode.mode, nil)
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    /// Checks if a 5120×1440 HiDPI mode is available (the main goal for the G9 Neo)
    static func hasNativeHiDPI(for displayID: CGDirectDisplayID) -> Bool {
        availableModes(for: displayID).contains { $0.isHiDPI && $0.width == 5120 && $0.height == 1440 }
    }
}
