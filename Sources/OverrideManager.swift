import CoreGraphics
import Foundation
import os.log

private let logger = Logger(subsystem: "com.astralbyte.retinascaler", category: "OverrideManager")

enum OverrideManager {

    // No hardcoded presets — all resolutions are generated dynamically
    // from the display's native resolution in suggestedResolutions(for:)

    // MARK: - Plist Generation

    static func generateOverridePlist(
        vendorID: UInt32,
        productID: UInt32,
        resolutions: [HiDPIResolution]
    ) -> Data? {
        var scaleEntries: [Data] = []

        for res in resolutions {
            scaleEntries.append(encodeHiDPIEntry(logicalWidth: res.logicalWidth, logicalHeight: res.logicalHeight))
        }

        let plist: [String: Any] = [
            "DisplayProductID": Int(productID),
            "DisplayVendorID": Int(vendorID),
            "scale-resolutions": scaleEntries,
        ]

        do {
            return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        } catch {
            logger.error("Failed to serialize override plist: \(error.localizedDescription)")
            return nil
        }
    }

    /// Encodes a single HiDPI resolution entry.
    ///
    /// Format: 16 bytes (big-endian UInt32 x 4)
    ///   [0..3]  backing width  (logical x 2)
    ///   [4..7]  backing height (logical x 2)
    ///   [8..11] flags — 0x00000001 = HiDPI
    ///   [12..15] reserved — 0x00000000
    private static func encodeHiDPIEntry(logicalWidth: Int, logicalHeight: Int) -> Data {
        var data = Data(count: 16)
        withUnsafeBytes(of: UInt32(logicalWidth * 2).bigEndian) { data.replaceSubrange(0..<4, with: $0) }
        withUnsafeBytes(of: UInt32(logicalHeight * 2).bigEndian) { data.replaceSubrange(4..<8, with: $0) }
        withUnsafeBytes(of: UInt32(1).bigEndian) { data.replaceSubrange(8..<12, with: $0) }
        withUnsafeBytes(of: UInt32(0).bigEndian) { data.replaceSubrange(12..<16, with: $0) }
        return data
    }

    // MARK: - Suggested Resolutions

    /// Generates HiDPI override entries from the display's actual standard modes.
    /// Every standard resolution the monitor supports gets an HiDPI entry in the plist.
    /// Fully dynamic — works with any monitor.
    static func suggestedResolutions(for display: ExternalDisplay) -> [HiDPIResolution] {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(display.id, opts) as? [CGDisplayMode] else { return [] }

        let standard = modes.filter { mode in
            mode.pixelWidth == mode.width && mode.width >= 800 && mode.height >= 400
        }
        let sorted = standard.sorted { $0.width > $1.width }

        var seen = Set<String>()
        var result: [HiDPIResolution] = []
        for mode in sorted {
            let key = "\(mode.width)x\(mode.height)"
            guard seen.insert(key).inserted else { continue }
            let label: String = mode.width == display.nativeWidth ? "Native HiDPI" : "\(mode.width)×\(mode.height)"
            result.append(HiDPIResolution(logicalWidth: mode.width, logicalHeight: mode.height, label: label))
        }
        return result
    }

    // MARK: - Install / Remove

    static func install(for display: ExternalDisplay, resolutions: [HiDPIResolution]) throws {
        guard let plistData = generateOverridePlist(
            vendorID: display.vendorID,
            productID: display.productID,
            resolutions: resolutions
        ) else {
            throw RetinaScalerError.overrideInstallFailed("Failed to generate override plist")
        }

        let tempFile = NSTemporaryDirectory() + "DisplayProductID-\(display.productHex)"
        try plistData.write(to: URL(fileURLWithPath: tempFile))

        defer {
            // Clean temp file regardless of outcome
            try? FileManager.default.removeItem(atPath: tempFile)
        }

        let script = """
        do shell script "mkdir -p '\(display.overrideDirPath)' && cp '\(tempFile)' '\(display.overrideFilePath)'" \
        with administrator privileges
        """

        var errorInfo: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let msg = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            logger.error("Override install failed: \(msg)")
            throw RetinaScalerError.overrideInstallFailed(msg)
        }

        logger.info("Override installed for display \(display.name) at \(display.overrideFilePath)")
    }

    static func remove(for display: ExternalDisplay) throws {
        guard display.hasOverrideInstalled else { return }

        let script = """
        do shell script "rm -f '\(display.overrideFilePath)'" with administrator privileges
        """

        var errorInfo: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let msg = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            logger.error("Override removal failed: \(msg)")
            throw RetinaScalerError.overrideRemoveFailed(msg)
        }

        logger.info("Override removed for display \(display.name)")
    }
}
