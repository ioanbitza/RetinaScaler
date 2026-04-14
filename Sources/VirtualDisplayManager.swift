import CoreGraphics
import Foundation
import os.log

private let logger = Logger(subsystem: "com.astralbyte.retinascaler", category: "VirtualDisplay")

/// Manages CGVirtualDisplay for HiDPI on external monitors.
///
/// Key design: the virtual display is created ONCE and REUSED. When switching
/// between HiDPI resolutions, we call applySettings: to update the modes
/// and then switch the active mode — no destroy/recreate cycle needed.
/// The virtual display is only destroyed when the app quits.
enum VirtualDisplayManager {

    // Store the raw pointer to the CGVirtualDisplay object.
    // We never release this — it lives until process exit.
    // macOS automatically cleans up virtual displays when the process dies.
    private static var vdPointer: UnsafeMutableRawPointer?
    private static var mirroredPhysicalID: CGDirectDisplayID = 0
    private static var cachedClasses: Classes?

    static var isActive: Bool { vdPointer != nil && mirroredPhysicalID != 0 }

    static var virtualDisplayID: CGDirectDisplayID {
        guard let ptr = vdPointer else { return 0 }
        let vd = Unmanaged<NSObject>.fromOpaque(ptr).takeUnretainedValue()
        return vd.value(forKey: "displayID") as? UInt32 ?? 0
    }

    // MARK: - Scaled HiDPI Resolutions

    static func scaledResolutions(nativeWidth: Int, nativeHeight: Int) -> [(logical: (Int, Int), backing: (Int, Int), label: String)] {
        let aspect = Double(nativeWidth) / Double(nativeHeight)

        let targets: [(height: Int, label: String)] = [
            (1440, "Native HiDPI"),
            (1360, "Slightly Scaled"),
            (1280, "Comfortable"),
            (1200, "Medium"),
            (1120, "Compact"),
            (1080, "Most Scaled"),
        ]

        return targets.map { target in
            let logH = target.height
            let logW = Int(round(Double(logH) * aspect / 2.0)) * 2
            return (logical: (logW, logH), backing: (logW * 2, logH * 2), label: target.label)
        }
    }

    // MARK: - Public API

    static func enableHiDPI(
        for physicalDisplayID: CGDirectDisplayID,
        nativeWidth: Int,
        nativeHeight: Int,
        logicalWidth: Int? = nil,
        logicalHeight: Int? = nil
    ) -> Result<String, RetinaScalerError> {

        let targetLogW: Int
        let targetLogH: Int
        if let lw = logicalWidth, let lh = logicalHeight {
            targetLogW = lw
            targetLogH = lh
        } else {
            let scaled = scaledResolutions(nativeWidth: nativeWidth, nativeHeight: nativeHeight)
            guard let res = scaled.first(where: { $0.label == "Comfortable" }) ?? scaled.first else {
                return .failure(.overrideInstallFailed("Could not compute HiDPI resolution"))
            }
            targetLogW = res.logical.0
            targetLogH = res.logical.1
        }

        logger.info("HiDPI requested: \(targetLogW)x\(targetLogH)")

        guard let classes = loadClasses() else {
            return .failure(.overrideInstallFailed("CGVirtualDisplay API not available"))
        }

        let maxHz = maxRefreshRate(for: physicalDisplayID)
        let refreshRates = Array(Set([60.0, 120.0, maxHz])).sorted()
        let allScaled = scaledResolutions(nativeWidth: nativeWidth, nativeHeight: nativeHeight)

        // Build modes for ALL resolutions
        var modeSpecs: [(UInt32, UInt32, Double)] = []
        for res in allScaled {
            for hz in refreshRates {
                modeSpecs.append((UInt32(res.backing.0), UInt32(res.backing.1), hz))
                modeSpecs.append((UInt32(res.logical.0), UInt32(res.logical.1), hz))
            }
        }
        for hz in refreshRates {
            modeSpecs.append((UInt32(nativeWidth * 2), UInt32(nativeHeight * 2), hz))
            modeSpecs.append((UInt32(nativeWidth), UInt32(nativeHeight), hz))
        }

        let modes = modeSpecs.compactMap { classes.makeMode($0.0, $0.1, $0.2) }
        guard !modes.isEmpty else {
            return .failure(.overrideInstallFailed("Failed to create display modes"))
        }

        // If virtual display already exists, REUSE it — just switch mode directly
        if let existingID = existingVirtualDisplayID() {
            logger.info("Reusing existing virtual display \(existingID), switching mode")

            return switchVirtualDisplayMode(
                vDisplayID: existingID, targetLogW: targetLogW, targetLogH: targetLogH,
                physicalDisplayID: physicalDisplayID
            )
        }

        // First time — create the virtual display
        let maxBackW = UInt32(allScaled.map { $0.backing.0 }.max()! )
        let maxBackH = UInt32(allScaled.map { $0.backing.1 }.max()!)

        let physWidth = CGDisplayScreenSize(physicalDisplayID).width
        let physHeight = CGDisplayScreenSize(physicalDisplayID).height
        let size = physWidth > 0
            ? CGSize(width: physWidth, height: physHeight)
            : CGSize(width: 1194, height: 336)

        let desc = classes.descClass.init()
        desc.setValue(DispatchQueue.main, forKey: "queue")
        desc.setValue("RetinaScaler HiDPI", forKey: "name")
        desc.setValue(maxBackW, forKey: "maxPixelsWide")
        desc.setValue(maxBackH, forKey: "maxPixelsHigh")
        desc.setValue(size, forKey: "sizeInMillimeters")
        desc.setValue(UInt32(0x4C2D), forKey: "vendorID")
        desc.setValue(UInt32(0xFFFE), forKey: "productID")
        desc.setValue(UInt32(12345), forKey: "serialNum")

        guard let vd = createVirtualDisplay(classes: classes, descriptor: desc) else {
            return .failure(.virtualDisplayCreationFailed("Failed to create virtual display object"))
        }

        let vDisplayID = vd.value(forKey: "displayID") as? UInt32 ?? 0
        guard vDisplayID != 0 else {
            return .failure(.overrideInstallFailed("Virtual display has no ID"))
        }
        logger.info("Virtual display created with ID \(vDisplayID)")

        // Store as raw pointer — never released, lives until process exit
        vdPointer = Unmanaged.passRetained(vd).toOpaque()

        // Apply HiDPI settings with all modes
        let settings = classes.settingsClass.init()
        settings.setValue(UInt32(1), forKey: "hiDPI")
        settings.setValue(modes, forKey: "modes")
        vd.perform(NSSelectorFromString("applySettings:"), with: settings)

        // Install override plist for the virtual display
        installVirtualOverride(nativeWidth: nativeWidth, nativeHeight: nativeHeight, scaledResolutions: allScaled)

        usleep(500_000)

        return switchVirtualDisplayMode(
            vDisplayID: vDisplayID, targetLogW: targetLogW, targetLogH: targetLogH,
            physicalDisplayID: physicalDisplayID
        )
    }

    /// Disables HiDPI mirroring but keeps the virtual display alive for reuse.
    static func disable() {
        logger.info("Disabling HiDPI mirroring")

        let physID = mirroredPhysicalID

        if physID != 0 {
            // Unmirror AND reposition physical display in one transaction
            // Without repositioning, the physical display stays at the VD's coordinates
            // which can leave the cursor trapped in a tiny area
            let primary = CGMainDisplayID()
            let primaryBounds = CGDisplayBounds(primary)

            var config: CGDisplayConfigRef?
            if CGBeginDisplayConfiguration(&config) == .success {
                // Remove mirror
                CGConfigureDisplayMirrorOfDisplay(config, physID, kCGNullDirectDisplay)

                // Reposition physical display: use saved origin if available,
                // otherwise center above primary
                if let origin = savedOrigin {
                    CGConfigureDisplayOrigin(config, physID, origin.x, origin.y)
                    logger.info("Restored display to saved position (\(origin.x), \(origin.y))")
                } else {
                    // Fallback: center above primary
                    let physMode = CGDisplayCopyDisplayMode(physID)
                    let displayW = Int32(physMode?.width ?? 1920)
                    let displayH = Int32(physMode?.height ?? 1080)
                    let primaryW = Int32(primaryBounds.width)
                    let x = (primaryW - displayW) / 2
                    let y = -displayH
                    CGConfigureDisplayOrigin(config, physID, x, y)
                    logger.info("Repositioned display to centered above (\(x), \(y))")
                }

                CGCompleteDisplayConfiguration(config, .permanently)
            }
            mirroredPhysicalID = 0
        }
        savedOrigin = nil
    }

    /// Force cleanup: unmirrors all displays mirrored to our virtual displays.
    static func forceCleanupOrphanedDisplays() {
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(32, &displays, &count)

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        var changed = false

        for i in 0..<Int(count) {
            let d = displays[i]
            // Check if this display is mirrored to one of our virtual displays
            let mirrorOf = CGDisplayMirrorsDisplay(d)
            if mirrorOf != kCGNullDirectDisplay {
                let mirrorVendor = CGDisplayVendorNumber(mirrorOf)
                let mirrorProduct = CGDisplayModelNumber(mirrorOf)
                if mirrorVendor == 0x4C2D && mirrorProduct == 0xFFFE {
                    CGConfigureDisplayMirrorOfDisplay(config, d, kCGNullDirectDisplay)
                    logger.info("Unmirrored display \(d) from virtual \(mirrorOf)")
                    changed = true
                }
            }
        }

        if changed {
            CGCompleteDisplayConfiguration(config, .forSession)
        } else {
            CGCancelDisplayConfiguration(config)
        }

        mirroredPhysicalID = 0
    }

    /// Lists all online virtual displays created by RetinaScaler.
    static func listVirtualDisplays() -> [(id: CGDirectDisplayID, width: Int, height: Int)] {
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(32, &displays, &count)

        var result: [(id: CGDirectDisplayID, width: Int, height: Int)] = []
        for i in 0..<Int(count) {
            let d = displays[i]
            if CGDisplayVendorNumber(d) == 0x4C2D && CGDisplayModelNumber(d) == 0xFFFE {
                result.append((id: d, width: CGDisplayPixelsWide(d), height: CGDisplayPixelsHigh(d)))
            }
        }
        return result
    }

    // MARK: - Private

    private static func existingVirtualDisplayID() -> CGDirectDisplayID? {
        guard vdPointer != nil else { return nil }
        let id = virtualDisplayID
        return id != 0 ? id : nil
    }

    private static func switchVirtualDisplayMode(
        vDisplayID: CGDirectDisplayID, targetLogW: Int, targetLogH: Int,
        physicalDisplayID: CGDirectDisplayID
    ) -> Result<String, RetinaScalerError> {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let vModes = CGDisplayCopyAllDisplayModes(vDisplayID, opts) as? [CGDisplayMode] else {
            return .failure(.overrideInstallFailed("No modes on virtual display"))
        }

        logger.info("Virtual display \(vDisplayID) has \(vModes.count) modes")

        // Find HiDPI mode matching target, prefer highest refresh rate
        let matching = vModes
            .filter { $0.width == targetLogW && $0.height == targetLogH && $0.pixelWidth > $0.width }
            .sorted { $0.refreshRate > $1.refreshRate }

        guard let targetMode = matching.first else {
            // Fallback to any HiDPI mode
            if let fallback = vModes.filter({ $0.pixelWidth > $0.width }).sorted(by: { $0.refreshRate > $1.refreshRate }).first {
                logger.warning("Target \(targetLogW)x\(targetLogH) not found, using \(fallback.width)x\(fallback.height)")
                return applyMode(vDisplayID: vDisplayID, mode: fallback, physicalDisplayID: physicalDisplayID)
            }
            return .failure(.overrideInstallFailed("HiDPI mode \(targetLogW)×\(targetLogH) not available"))
        }

        return applyMode(vDisplayID: vDisplayID, mode: targetMode, physicalDisplayID: physicalDisplayID)
    }

    /// Saved position from before first VD activation, so we can restore it on mode switches
    private static var savedOrigin: (x: Int32, y: Int32)?

    private static func applyMode(
        vDisplayID: CGDirectDisplayID, mode: CGDisplayMode,
        physicalDisplayID: CGDirectDisplayID
    ) -> Result<String, RetinaScalerError> {
        // First time: save the current position of the physical display or VD
        if savedOrigin == nil {
            let bounds: CGRect
            if CGDisplayIsOnline(vDisplayID) != 0 && CGDisplayBounds(vDisplayID) != .zero {
                bounds = CGDisplayBounds(vDisplayID)
            } else {
                bounds = CGDisplayBounds(physicalDisplayID)
            }
            savedOrigin = (x: Int32(bounds.origin.x), y: Int32(bounds.origin.y))
            logger.info("Saved display origin: (\(savedOrigin!.x), \(savedOrigin!.y))")
        }

        let posX = savedOrigin!.x
        let posY = savedOrigin!.y

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else {
            return .failure(.modeSwitchFailed)
        }

        CGConfigureDisplayMirrorOfDisplay(config, physicalDisplayID, vDisplayID)
        CGConfigureDisplayWithDisplayMode(config, vDisplayID, mode, nil)
        CGConfigureDisplayOrigin(config, vDisplayID, posX, posY)

        guard CGCompleteDisplayConfiguration(config, .permanently) == .success else {
            return .failure(.modeSwitchFailed)
        }

        mirroredPhysicalID = physicalDisplayID

        let hz = Int(mode.refreshRate)
        logger.info("HiDPI mode set: \(mode.width)x\(mode.height) @ \(hz)Hz at position (\(posX),\(posY))")
        return .success("\(mode.width)×\(mode.height) HiDPI @ \(hz)Hz active")
    }

    // MARK: - ObjC Runtime Helpers

    /// Finds the best mode for the physical display — native resolution at the target refresh rate.
    private static func bestPhysicalMode(for displayID: CGDirectDisplayID, targetHz: Double) -> CGDisplayMode? {
        let nativeW = CGDisplayPixelsWide(displayID)
        let nativeH = CGDisplayPixelsHigh(displayID)
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, opts) as? [CGDisplayMode] else { return nil }

        // Find native resolution mode at highest Hz (ideally matching targetHz)
        return modes
            .filter { $0.width == nativeW && $0.height == nativeH && !($0.pixelWidth > $0.width) }
            .sorted { abs($0.refreshRate - targetHz) < abs($1.refreshRate - targetHz) }
            .first
    }

    private struct Classes {
        let vdClass: NSObject.Type
        let descClass: NSObject.Type
        let modeClass: NSObject.Type
        let settingsClass: NSObject.Type

        func makeMode(_ w: UInt32, _ h: UInt32, _ hz: Double) -> NSObject? {
            guard let alloc = modeClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject else {
                return nil
            }
            let sel = Selector(("initWithWidth:height:refreshRate:"))
            guard let method = class_getInstanceMethod(modeClass, sel) else { return nil }
            typealias F = @convention(c) (AnyObject, Selector, UInt32, UInt32, Double) -> AnyObject?
            let imp = method_getImplementation(method)
            return unsafeBitCast(imp, to: F.self)(alloc, sel, w, h, hz) as? NSObject
        }
    }

    private static func loadClasses() -> Classes? {
        if let c = cachedClasses { return c }
        guard let vd = NSClassFromString("CGVirtualDisplay") as? NSObject.Type,
              let desc = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
              let mode = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type,
              let settings = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type
        else { return nil }
        let c = Classes(vdClass: vd, descClass: desc, modeClass: mode, settingsClass: settings)
        cachedClasses = c
        return c
    }

    private static func maxRefreshRate(for displayID: CGDirectDisplayID) -> Double {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, opts) as? [CGDisplayMode] else { return 60 }
        return modes.map(\.refreshRate).max() ?? 60
    }

    private static func createVirtualDisplay(classes: Classes, descriptor: NSObject) -> NSObject? {
        // Use raw objc_msgSend to avoid ARC interference
        typealias AllocFn = @convention(c) (AnyClass, Selector) -> UnsafeMutableRawPointer?
        typealias InitFn = @convention(c) (UnsafeMutableRawPointer, Selector, AnyObject) -> UnsafeMutableRawPointer?

        let allocSel = NSSelectorFromString("alloc")
        let initSel = NSSelectorFromString("initWithDescriptor:")

        guard let allocImp = class_getClassMethod(classes.vdClass, allocSel).map({ method_getImplementation($0) }),
              let initImp = class_getInstanceMethod(classes.vdClass, initSel).map({ method_getImplementation($0) })
        else {
            logger.error("Could not find alloc/initWithDescriptor:")
            return nil
        }

        let allocFn = unsafeBitCast(allocImp, to: AllocFn.self)
        let initFn = unsafeBitCast(initImp, to: InitFn.self)

        guard let rawAlloc = allocFn(classes.vdClass, allocSel) else {
            logger.error("alloc returned nil")
            return nil
        }

        guard let rawInit = initFn(rawAlloc, initSel, descriptor) else {
            logger.error("initWithDescriptor: returned nil")
            return nil
        }

        // The raw pointer holds a +1 retained object from alloc+init.
        // Convert to NSObject for use — takeUnretainedValue doesn't change retain count.
        return Unmanaged<NSObject>.fromOpaque(rawInit).takeUnretainedValue()
    }

    private static func installVirtualOverride(
        nativeWidth: Int, nativeHeight: Int,
        scaledResolutions: [(logical: (Int, Int), backing: (Int, Int), label: String)]
    ) {
        func encode(_ w: Int, _ h: Int) -> Data {
            var d = Data(count: 16)
            withUnsafeBytes(of: UInt32(w).bigEndian) { d.replaceSubrange(0..<4, with: $0) }
            withUnsafeBytes(of: UInt32(h).bigEndian) { d.replaceSubrange(4..<8, with: $0) }
            withUnsafeBytes(of: UInt32(1).bigEndian) { d.replaceSubrange(8..<12, with: $0) }
            withUnsafeBytes(of: UInt32(0).bigEndian) { d.replaceSubrange(12..<16, with: $0) }
            return d
        }

        var scaleRes: [Data] = scaledResolutions.map { encode($0.backing.0, $0.backing.1) }
        scaleRes.append(encode(nativeWidth * 2, nativeHeight * 2))

        let plist: [String: Any] = [
            "DisplayProductID": 0xFFFE,
            "DisplayVendorID": 0x4C2D,
            "scale-resolutions": scaleRes,
        ]

        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
        let tmp = NSTemporaryDirectory() + "DisplayProductID-fffe"
        guard let _ = try? data.write(to: URL(fileURLWithPath: tmp)) else { return }
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let dir = "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-4c2d"
        let script = "do shell script \"mkdir -p '\(dir)' && cp '\(tmp)' '\(dir)/DisplayProductID-fffe'\" with administrator privileges"
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
    }
}
