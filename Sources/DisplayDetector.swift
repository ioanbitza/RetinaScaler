import CoreGraphics
import Foundation
import IOKit

enum DisplayDetector {

    static func detectDisplays() -> [ExternalDisplay] {
        var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0

        guard CGGetOnlineDisplayList(16, &onlineDisplays, &displayCount) == .success else {
            return []
        }

        let edidNames = readEDIDNames()

        return (0..<Int(displayCount)).compactMap { i in
            let displayID = onlineDisplays[i]
            let vendorID = CGDisplayVendorNumber(displayID)
            let productID = CGDisplayModelNumber(displayID)
            let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0

            // Filter out our virtual display (productID 0xFFFE)
            if vendorID == 0x4C2D && productID == 0xFFFE { return nil }

            let width = CGDisplayPixelsWide(displayID)
            let height = CGDisplayPixelsHigh(displayID)

            let key = DisplayKey(vendorID: vendorID, productID: productID)
            let name = edidNames[key]
                ?? displayNameFromIOKit(displayID: displayID)
                ?? (isBuiltIn ? "Built-in Display" : "Samsung G9 Neo")

            return ExternalDisplay(
                id: displayID,
                vendorID: vendorID,
                productID: productID,
                name: name,
                nativeWidth: width,
                nativeHeight: height,
                isBuiltIn: isBuiltIn
            )
        }
    }

    // MARK: - EDID Name Extraction via IOKit

    private struct DisplayKey: Hashable {
        let vendorID: UInt32
        let productID: UInt32
    }

    private static func readEDIDNames() -> [DisplayKey: String] {
        var result: [DisplayKey: String] = [:]
        var iter: io_iterator_t = 0

        let matching = IOServiceMatching("IODisplayConnect")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            return result
        }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iter)
            }

            guard let infoRef = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName)) else {
                continue
            }
            let info = infoRef.takeRetainedValue() as? [String: Any] ?? [:]

            guard let vendorID = info[kDisplayVendorID] as? UInt32,
                  let productID = info[kDisplayProductID] as? UInt32,
                  let names = info[kDisplayProductName] as? [String: String],
                  let name = names.values.first
            else { continue }

            result[DisplayKey(vendorID: vendorID, productID: productID)] = name
        }

        return result
    }

    /// Fallback: try to get display name directly from IOKit service info
    private static func displayNameFromIOKit(displayID: CGDirectDisplayID) -> String? {
        let vendorID = CGDisplayVendorNumber(displayID)
        let productID = CGDisplayModelNumber(displayID)

        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMobileFramebufferShim"), &iter) == KERN_SUCCESS
                || IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOFramebuffer"), &iter) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iter)
            }
            guard let infoRef = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName)) else { continue }
            let info = infoRef.takeRetainedValue() as? [String: Any] ?? [:]
            if let vid = info[kDisplayVendorID] as? UInt32, vid == vendorID,
               let pid = info[kDisplayProductID] as? UInt32, pid == productID,
               let names = info[kDisplayProductName] as? [String: String],
               let name = names.values.first {
                return name
            }
        }

        // Last resort: known Samsung vendor
        if vendorID == 0x4C2D { return "Samsung Monitor" }
        return nil
    }
}
