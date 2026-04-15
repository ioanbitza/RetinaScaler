import CoreGraphics
import Foundation
import os.log

private let logger = Logger(subsystem: "com.astralbyte.retinascaler", category: "BuiltInBrightness")

/// Controls brightness on the built-in (MacBook) display via the private DisplayServices framework.
/// Apple Silicon Macs no longer expose IODisplayConnect services, so IODisplayGetFloatParameter
/// doesn't work. DisplayServices is what macOS System Settings uses internally.
enum BuiltInBrightnessManager {

    // MARK: - DisplayServices (private framework, loaded lazily)

    private static let displayServicesHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    }()

    private static let dsGetBrightness: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32)? = {
        guard let handle = displayServicesHandle else {
            logger.warning("Failed to load DisplayServices framework")
            return nil
        }
        guard let sym = dlsym(handle, "DisplayServicesGetBrightness") else {
            logger.info("DisplayServicesGetBrightness not found")
            return nil
        }
        return unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32).self)
    }()

    private static let dsSetBrightness: (@convention(c) (CGDirectDisplayID, Float) -> Int32)? = {
        guard let handle = displayServicesHandle else { return nil }
        guard let sym = dlsym(handle, "DisplayServicesSetBrightness") else {
            logger.info("DisplayServicesSetBrightness not found")
            return nil
        }
        return unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID, Float) -> Int32).self)
    }()

    private static let dsCanChangeBrightness: (@convention(c) (CGDirectDisplayID) -> Bool)? = {
        guard let handle = displayServicesHandle else { return nil }
        guard let sym = dlsym(handle, "DisplayServicesCanChangeBrightness") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID) -> Bool).self)
    }()

    // MARK: - Public API

    /// Whether DisplayServices is available on this system.
    static var isAvailable: Bool {
        dsGetBrightness != nil && dsSetBrightness != nil
    }

    /// Whether this display supports brightness control via DisplayServices.
    static func canChangeBrightness(for displayID: CGDirectDisplayID) -> Bool {
        dsCanChangeBrightness?(displayID) ?? false
    }

    /// Returns display brightness as 0–100, or nil if unavailable.
    static func getBrightness(for displayID: CGDirectDisplayID) -> Int? {
        guard let getter = dsGetBrightness else { return nil }

        var brightness: Float = 0
        let result = getter(displayID, &brightness)
        guard result == 0 else {
            logger.info("DisplayServicesGetBrightness failed for display \(displayID), result: \(result)")
            return nil
        }

        return Int(round(brightness * 100))
    }

    /// Sets display brightness (0–100). Returns true on success.
    static func setBrightness(for displayID: CGDirectDisplayID, value: Int) -> Bool {
        guard let setter = dsSetBrightness else { return false }

        let brightness = Float(max(0, min(100, value))) / 100.0
        let result = setter(displayID, brightness)
        if result != 0 {
            logger.warning("DisplayServicesSetBrightness failed for display \(displayID), result: \(result)")
        }
        return result == 0
    }
}
