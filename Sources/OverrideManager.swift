import Foundation
import os.log

private let logger = Logger(subsystem: "com.astralbyte.retinascaler", category: "OverrideManager")

enum OverrideManager {

    /// Default HiDPI resolutions for ultrawide 5120x1440 panels.
    /// Includes fine-grained steps between 1080p and 1440p height for user preference.
    static let defaultUltrawide5120x1440: [HiDPIResolution] = [
        // Full range from native down to 1080p, maintaining 32:9 aspect ratio
        HiDPIResolution(logicalWidth: 5120, logicalHeight: 1440, label: "Native HiDPI"),
        HiDPIResolution(logicalWidth: 4836, logicalHeight: 1360, label: "Slightly Scaled"),
        HiDPIResolution(logicalWidth: 4552, logicalHeight: 1280, label: "Comfortable"),
        HiDPIResolution(logicalWidth: 4266, logicalHeight: 1200, label: "Medium"),
        HiDPIResolution(logicalWidth: 3982, logicalHeight: 1120, label: "Compact"),
        HiDPIResolution(logicalWidth: 3840, logicalHeight: 1080, label: "1080p HiDPI"),
        // Below 1080p
        HiDPIResolution(logicalWidth: 3360, logicalHeight: 946, label: "Large UI"),
        HiDPIResolution(logicalWidth: 3200, logicalHeight: 900, label: "Larger UI"),
        HiDPIResolution(logicalWidth: 3008, logicalHeight: 846, label: "Extra Large"),
        HiDPIResolution(logicalWidth: 2560, logicalHeight: 720, label: "1:1 Retina"),
    ]

    /// Common presets for other panel resolutions
    static let default4K3840x2160: [HiDPIResolution] = [
        HiDPIResolution(logicalWidth: 3840, logicalHeight: 2160, label: "Native HiDPI"),
        HiDPIResolution(logicalWidth: 3008, logicalHeight: 1692, label: "Default scaled"),
        HiDPIResolution(logicalWidth: 2560, logicalHeight: 1440, label: "More space"),
        HiDPIResolution(logicalWidth: 1920, logicalHeight: 1080, label: "1:1 Retina, biggest UI"),
    ]

    static let default1440p2560x1440: [HiDPIResolution] = [
        HiDPIResolution(logicalWidth: 2560, logicalHeight: 1440, label: "Native HiDPI"),
        HiDPIResolution(logicalWidth: 1920, logicalHeight: 1080, label: "Comfortable HiDPI"),
        HiDPIResolution(logicalWidth: 1280, logicalHeight: 720, label: "1:1 Retina, biggest UI"),
    ]

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

    static func suggestedResolutions(for display: ExternalDisplay) -> [HiDPIResolution] {
        let w = display.nativeWidth
        let h = display.nativeHeight

        // Match known panel sizes
        if w == 5120 && h == 1440 { return defaultUltrawide5120x1440 }
        if w == 3840 && h == 2160 { return default4K3840x2160 }
        if w == 2560 && h == 1440 { return default1440p2560x1440 }

        // Generic: offer native HiDPI + a few scaled options
        var resolutions = [HiDPIResolution(logicalWidth: w, logicalHeight: h, label: "Native HiDPI")]
        let scales: [(Double, String)] = [(0.8, "Slightly larger UI"), (0.6, "Large UI"), (0.5, "1:1 Retina")]
        for (scale, label) in scales {
            let sw = Int(Double(w) * scale / 2) * 2  // keep even
            let sh = Int(Double(h) * scale / 2) * 2
            resolutions.append(HiDPIResolution(logicalWidth: sw, logicalHeight: sh, label: label))
        }
        return resolutions
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
