import CoreGraphics
import Foundation
import os.log

private let logger = Logger(subsystem: "com.astralbyte.retinascaler", category: "Arrangement")

/// Manages display positioning and arrangement.
enum DisplayArrangement {

    struct Position {
        let displayID: CGDirectDisplayID
        let x: Int32
        let y: Int32
        let width: Int
        let height: Int
    }

    /// Returns current positions of all online displays.
    static func currentArrangement() -> [Position] {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        let result = CGGetOnlineDisplayList(16, &displays, &count)
        guard result == .success else {
            logger.warning("CGGetOnlineDisplayList failed with code \(result.rawValue)")
            return []
        }

        return (0..<Int(count)).map { i in
            let d = displays[i]
            let bounds = CGDisplayBounds(d)
            return Position(
                displayID: d,
                x: Int32(bounds.origin.x),
                y: Int32(bounds.origin.y),
                width: Int(bounds.width),
                height: Int(bounds.height)
            )
        }
    }

    /// Moves a display to a position relative to the primary display.
    static func setPosition(displayID: CGDirectDisplayID, x: Int32, y: Int32) -> Bool {
        var config: CGDisplayConfigRef?
        let beginResult = CGBeginDisplayConfiguration(&config)
        guard beginResult == .success else {
            logger.error("CGBeginDisplayConfiguration failed with code \(beginResult.rawValue)")
            return false
        }

        CGConfigureDisplayOrigin(config, displayID, x, y)

        let completeResult = CGCompleteDisplayConfiguration(config, .permanently)
        if completeResult != .success {
            logger.error("CGCompleteDisplayConfiguration failed with code \(completeResult.rawValue)")
            return false
        }

        logger.info("Display \(displayID) repositioned to (\(x), \(y))")
        return true
    }

    /// Common arrangements relative to primary display.
    enum Preset: String, CaseIterable {
        case leftOf = "Left (centered)"
        case rightOf = "Right (centered)"
        case above = "Above (centered)"
        case below = "Below (centered)"
    }

    static func applyPreset(_ preset: Preset, displayID: CGDirectDisplayID) -> Bool {
        // If virtual display is active and this display is mirrored,
        // move the virtual display (mirror master) instead
        let targetID: CGDirectDisplayID
        if VirtualDisplayManager.isActive {
            let vdID = VirtualDisplayManager.virtualDisplayID
            if vdID != 0 && CGDisplayMirrorsDisplay(displayID) == vdID {
                targetID = vdID
                logger.info("Virtual display active, moving VD \(vdID) instead of physical \(displayID)")
            } else {
                targetID = displayID
            }
        } else {
            targetID = displayID
        }

        let primary = CGMainDisplayID()

        guard targetID != primary else {
            logger.info("Cannot reposition primary display relative to itself")
            return false
        }

        let primaryBounds = CGDisplayBounds(primary)
        let displayMode = CGDisplayCopyDisplayMode(targetID)
        let displayW = Int32(displayMode?.width ?? 1920)
        let displayH = Int32(displayMode?.height ?? 1080)
        let primaryW = Int32(primaryBounds.width)
        let primaryH = Int32(primaryBounds.height)

        let (x, y): (Int32, Int32) = switch preset {
        case .leftOf:
            (-displayW, (primaryH - displayH) / 2)
        case .rightOf:
            (primaryW, (primaryH - displayH) / 2)
        case .above:
            ((primaryW - displayW) / 2, -displayH)
        case .below:
            ((primaryW - displayW) / 2, primaryH)
        }

        return setPosition(displayID: targetID, x: x, y: y)
    }
}
