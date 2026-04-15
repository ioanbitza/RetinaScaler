import CoreGraphics
import Foundation
import os.log

private let logger = Logger(subsystem: "com.astralbyte.retinascaler", category: "SoftwareBrightness")

/// Fallback brightness control using gamma curve adjustment.
/// Works on any display without DDC or special permissions.
/// Does NOT change the physical backlight — adjusts perceived brightness via gamma max values.
enum SoftwareBrightnessManager {

    /// Tracks the last brightness value we applied per display.
    /// Gamma has no "read current brightness" — we only know what we set.
    private static var appliedBrightness: [CGDirectDisplayID: Int] = [:]

    /// Returns the current software brightness (0–100), or nil if never set.
    /// Defaults to 100 (no dimming) on first access.
    static func getBrightness(for displayID: CGDirectDisplayID) -> Int {
        if let cached = appliedBrightness[displayID] {
            return cached
        }
        // Read current gamma to detect if something else already dimmed this display
        var rMin: CGGammaValue = 0, rMax: CGGammaValue = 0, rGamma: CGGammaValue = 0
        var gMin: CGGammaValue = 0, gMax: CGGammaValue = 0, gGamma: CGGammaValue = 0
        var bMin: CGGammaValue = 0, bMax: CGGammaValue = 0, bGamma: CGGammaValue = 0

        let result = CGGetDisplayTransferByFormula(displayID,
            &rMin, &rMax, &rGamma,
            &gMin, &gMax, &gGamma,
            &bMin, &bMax, &bGamma)

        guard result == .success else { return 100 }

        // Use the average of max values as the current brightness
        let avgMax = (rMax + gMax + bMax) / 3.0
        let brightness = Int(round(Double(avgMax) * 100))
        appliedBrightness[displayID] = brightness
        return brightness
    }

    /// Sets software brightness (0–100) by adjusting the gamma curve max values.
    /// 100 = full brightness (no dimming), 0 = black.
    static func setBrightness(for displayID: CGDirectDisplayID, value: Int) -> Bool {
        let clamped = max(0, min(100, value))
        let maxVal = CGGammaValue(clamped) / 100.0

        let result = CGSetDisplayTransferByFormula(displayID,
            0, maxVal, 1.0,  // Red: min=0, max=brightness, gamma=1
            0, maxVal, 1.0,  // Green
            0, maxVal, 1.0)  // Blue

        if result == .success {
            appliedBrightness[displayID] = clamped
            return true
        }

        logger.warning("CGSetDisplayTransferByFormula failed for display \(displayID): \(result.rawValue)")
        return false
    }

    /// Resets display to default gamma (full brightness).
    static func reset(for displayID: CGDirectDisplayID) {
        CGDisplayRestoreColorSyncSettings()
        appliedBrightness.removeValue(forKey: displayID)
    }
}
