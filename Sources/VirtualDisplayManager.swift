import CoreGraphics
import Foundation

/// Manages a CGVirtualDisplay to enable true HiDPI on monitors where macOS
/// won't natively offer it (logical resolution == panel resolution).
///
/// The virtual display is kept alive as long as HiDPI is active.
/// When the process exits, macOS automatically destroys it and reverts mirroring.
enum VirtualDisplayManager {

    // The virtual display object must stay alive — stored as a strong reference.
    private static var activeVirtualDisplay: NSObject?
    private static var mirroredPhysicalID: CGDirectDisplayID = 0

    static var isActive: Bool { activeVirtualDisplay != nil }

    // MARK: - Public API

    /// Creates a virtual display, enables HiDPI, mirrors the physical display to it,
    /// and switches to the target HiDPI mode.
    static func enableHiDPI(
        for physicalDisplayID: CGDirectDisplayID,
        logicalWidth: Int = 5120,
        logicalHeight: Int = 1440
    ) -> Result<String, RetinaScalerError> {

        // Don't create a second virtual display
        if isActive { disable() }

        guard let classes = loadClasses() else {
            return .failure(.overrideInstallFailed("CGVirtualDisplay API not available"))
        }

        let backingWidth = UInt32(logicalWidth * 2)
        let backingHeight = UInt32(logicalHeight * 2)

        // Build modes
        let modes = [
            classes.makeMode(backingWidth, backingHeight, 60),
            classes.makeMode(backingWidth, backingHeight, 120),
            classes.makeMode(UInt32(logicalWidth), UInt32(logicalHeight), 60),
            classes.makeMode(UInt32(logicalWidth), UInt32(logicalHeight), 120),
            classes.makeMode(UInt32(logicalWidth * 3/4), UInt32(logicalHeight * 3/4), 60),
            classes.makeMode(UInt32(logicalWidth / 2), UInt32(logicalHeight / 2), 60),
        ]

        // Physical size matching the monitor (~49" ultrawide)
        let physWidth = CGDisplayScreenSize(physicalDisplayID).width
        let physHeight = CGDisplayScreenSize(physicalDisplayID).height
        let size = physWidth > 0
            ? CGSize(width: physWidth, height: physHeight)
            : CGSize(width: 1194, height: 336)

        // Descriptor
        let desc = classes.descClass.init()
        desc.setValue(DispatchQueue.main, forKey: "queue")
        desc.setValue("RetinaScaler HiDPI", forKey: "name")
        desc.setValue(backingWidth, forKey: "maxPixelsWide")
        desc.setValue(backingHeight, forKey: "maxPixelsHigh")
        desc.setValue(size, forKey: "sizeInMillimeters")
        desc.setValue(UInt32(0x4C2D), forKey: "vendorID")
        desc.setValue(UInt32(0xFFFE), forKey: "productID")
        desc.setValue(UInt32(12345), forKey: "serialNum")

        // Allocate + init
        guard let allocated = classes.vdClass
            .perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject,
              let vd = allocated
            .perform(NSSelectorFromString("initWithDescriptor:"), with: desc)?
            .takeUnretainedValue() as? NSObject
        else {
            return .failure(.overrideInstallFailed("Failed to create virtual display"))
        }

        let vDisplayID = vd.value(forKey: "displayID") as? UInt32 ?? 0
        guard vDisplayID != 0 else {
            return .failure(.overrideInstallFailed("Virtual display has no ID"))
        }

        // Apply HiDPI settings
        let settings = classes.settingsClass.init()
        settings.setValue(UInt32(1), forKey: "hiDPI")
        settings.setValue(modes, forKey: "modes")
        vd.perform(NSSelectorFromString("applySettings:"), with: settings)

        // Install override plist for virtual display (ensures HiDPI modes appear)
        installVirtualOverride(logicalWidth: logicalWidth, logicalHeight: logicalHeight)

        // Brief pause for macOS to register the virtual display
        Thread.sleep(forTimeInterval: 0.5)

        // Find the 5120x1440 HiDPI mode on the virtual display
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let vModes = CGDisplayCopyAllDisplayModes(vDisplayID, opts) as? [CGDisplayMode],
              let targetMode = vModes.first(where: {
                  $0.width == logicalWidth && $0.height == logicalHeight && $0.pixelWidth > $0.width
              })
        else {
            return .failure(.overrideInstallFailed(
                "HiDPI mode \(logicalWidth)×\(logicalHeight) not available on virtual display"
            ))
        }

        // Remember the physical display's origin so we can preserve it as main
        let physBounds = CGDisplayBounds(physicalDisplayID)
        let wasMain = CGDisplayIsMain(physicalDisplayID) != 0

        // Mirror + switch in one transaction
        var config: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&config)
        CGConfigureDisplayMirrorOfDisplay(config, physicalDisplayID, vDisplayID)
        CGConfigureDisplayWithDisplayMode(config, vDisplayID, targetMode, nil)

        // Keep the virtual display at the same origin as the physical was,
        // so the dock/main display stays on the Samsung
        if wasMain {
            CGConfigureDisplayOrigin(config, vDisplayID, Int32(physBounds.origin.x), Int32(physBounds.origin.y))
        }

        let result = CGCompleteDisplayConfiguration(config, .forSession)

        guard result == .success else {
            return .failure(.modeSwitchFailed)
        }

        // Store references to keep alive
        activeVirtualDisplay = vd
        mirroredPhysicalID = physicalDisplayID

        let hz = Int(targetMode.refreshRate)
        return .success("\(logicalWidth)×\(logicalHeight) HiDPI @ \(hz)Hz active")
    }

    /// Disables HiDPI by destroying the virtual display and reverting mirroring.
    static func disable() {
        if mirroredPhysicalID != 0 {
            // Undo mirroring
            var config: CGDisplayConfigRef?
            CGBeginDisplayConfiguration(&config)
            CGConfigureDisplayMirrorOfDisplay(config, mirroredPhysicalID, kCGNullDirectDisplay)
            CGCompleteDisplayConfiguration(config, .forSession)
        }

        activeVirtualDisplay = nil
        mirroredPhysicalID = 0
    }

    // MARK: - Private

    private struct Classes {
        let vdClass: NSObject.Type
        let descClass: NSObject.Type
        let modeClass: NSObject.Type
        let settingsClass: NSObject.Type

        func makeMode(_ w: UInt32, _ h: UInt32, _ hz: Double) -> NSObject {
            let alloc = modeClass.perform(NSSelectorFromString("alloc"))!.takeUnretainedValue() as! NSObject
            typealias F = @convention(c) (AnyObject, Selector, UInt32, UInt32, Double) -> AnyObject?
            let sel = Selector(("initWithWidth:height:refreshRate:"))
            let imp = method_getImplementation(class_getInstanceMethod(modeClass, sel)!)
            return unsafeBitCast(imp, to: F.self)(alloc, sel, w, h, hz) as! NSObject
        }
    }

    private static func loadClasses() -> Classes? {
        guard let vd = NSClassFromString("CGVirtualDisplay") as? NSObject.Type,
              let desc = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
              let mode = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type,
              let settings = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type
        else { return nil }
        return Classes(vdClass: vd, descClass: desc, modeClass: mode, settingsClass: settings)
    }

    private static func installVirtualOverride(logicalWidth: Int, logicalHeight: Int) {
        func encode(_ w: Int, _ h: Int) -> Data {
            var d = Data(count: 16)
            withUnsafeBytes(of: UInt32(w * 2).bigEndian) { d.replaceSubrange(0..<4, with: $0) }
            withUnsafeBytes(of: UInt32(h * 2).bigEndian) { d.replaceSubrange(4..<8, with: $0) }
            withUnsafeBytes(of: UInt32(1).bigEndian) { d.replaceSubrange(8..<12, with: $0) }
            withUnsafeBytes(of: UInt32(0).bigEndian) { d.replaceSubrange(12..<16, with: $0) }
            return d
        }

        let plist: [String: Any] = [
            "DisplayProductID": 0xFFFE,
            "DisplayVendorID": 0x4C2D,
            "scale-resolutions": [
                encode(logicalWidth, logicalHeight),
                encode(logicalWidth * 3/4, logicalHeight * 3/4),
                encode(logicalWidth / 2, logicalHeight / 2),
            ],
        ]

        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
        let tmp = NSTemporaryDirectory() + "DisplayProductID-fffe"
        try? data.write(to: URL(fileURLWithPath: tmp))

        let dir = "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-4c2d"
        let script = "do shell script \"mkdir -p '\(dir)' && cp '\(tmp)' '\(dir)/DisplayProductID-fffe'\" with administrator privileges"
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        try? FileManager.default.removeItem(atPath: tmp)
    }
}
