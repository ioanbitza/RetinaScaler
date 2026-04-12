import CoreGraphics
import Foundation

struct ExternalDisplay: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let vendorID: UInt32
    let productID: UInt32
    let name: String
    let nativeWidth: Int
    let nativeHeight: Int
    let isBuiltIn: Bool

    var vendorHex: String { String(format: "%x", vendorID) }
    var productHex: String { String(format: "%x", productID) }

    var overrideDirPath: String {
        "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-\(vendorHex)"
    }

    var overrideFilePath: String {
        "\(overrideDirPath)/DisplayProductID-\(productHex)"
    }

    var hasOverrideInstalled: Bool {
        FileManager.default.fileExists(atPath: overrideFilePath)
    }
}

struct HiDPIResolution: Identifiable, Hashable {
    let id = UUID()
    let logicalWidth: Int
    let logicalHeight: Int
    let label: String

    var backingWidth: Int { logicalWidth * 2 }
    var backingHeight: Int { logicalHeight * 2 }

    var description: String {
        "\(logicalWidth)×\(logicalHeight) HiDPI (\(backingWidth)×\(backingHeight) backing) — \(label)"
    }
}

struct DisplayModeInfo: Identifiable, Hashable {
    let id = UUID()
    let mode: CGDisplayMode
    let width: Int
    let height: Int
    let isHiDPI: Bool
    let refreshRate: Double

    var description: String {
        let dpi = isHiDPI ? " HiDPI" : ""
        let hz = refreshRate > 0 ? " @\(Int(refreshRate))Hz" : ""
        return "\(width)×\(height)\(dpi)\(hz)"
    }

    static func == (lhs: DisplayModeInfo, rhs: DisplayModeInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum RetinaScalerError: LocalizedError {
    case noDisplayFound
    case overrideInstallFailed(String)
    case overrideRemoveFailed(String)
    case modeSwitchFailed

    var errorDescription: String? {
        switch self {
        case .noDisplayFound: return "No external display found"
        case .overrideInstallFailed(let msg): return "Override install failed: \(msg)"
        case .overrideRemoveFailed(let msg): return "Override remove failed: \(msg)"
        case .modeSwitchFailed: return "Failed to switch display mode"
        }
    }
}
