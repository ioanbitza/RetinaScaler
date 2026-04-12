import Foundation

enum OverrideManager {

    /// Default HiDPI resolutions for ultrawide 5120×1440 panels.
    /// Add more presets here for other common panel sizes.
    static let defaultUltrawide5120x1440: [HiDPIResolution] = [
        HiDPIResolution(logicalWidth: 5120, logicalHeight: 1440, label: "Native HiDPI — full space, Retina quality"),
        HiDPIResolution(logicalWidth: 4096, logicalHeight: 1152, label: "Slightly larger UI"),
        HiDPIResolution(logicalWidth: 3840, logicalHeight: 1080, label: "Comfortable scaling"),
        HiDPIResolution(logicalWidth: 3200, logicalHeight: 900, label: "Large UI elements"),
        HiDPIResolution(logicalWidth: 2560, logicalHeight: 720, label: "1:1 pixel-perfect, biggest UI"),
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
    ) -> Data {
        var scaleEntries: [Data] = []

        for res in resolutions {
            scaleEntries.append(encodeHiDPIEntry(logicalWidth: res.logicalWidth, logicalHeight: res.logicalHeight))
        }

        let plist: [String: Any] = [
            "DisplayProductID": Int(productID),
            "DisplayVendorID": Int(vendorID),
            "scale-resolutions": scaleEntries,
        ]

        return try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    /// Encodes a single HiDPI resolution entry.
    ///
    /// Format: 16 bytes (big-endian UInt32 × 4)
    ///   [0..3]  backing width  (logical × 2)
    ///   [4..7]  backing height (logical × 2)
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
        let plistData = generateOverridePlist(
            vendorID: display.vendorID,
            productID: display.productID,
            resolutions: resolutions
        )

        let tempFile = NSTemporaryDirectory() + "DisplayProductID-\(display.productHex)"
        try plistData.write(to: URL(fileURLWithPath: tempFile))

        let script = """
        do shell script "mkdir -p '\(display.overrideDirPath)' && cp '\(tempFile)' '\(display.overrideFilePath)'" \
        with administrator privileges
        """

        var errorInfo: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&errorInfo)

        // Clean temp file
        try? FileManager.default.removeItem(atPath: tempFile)

        if let errorInfo {
            let msg = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw RetinaScalerError.overrideInstallFailed(msg)
        }
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
            throw RetinaScalerError.overrideRemoveFailed(msg)
        }
    }
}
