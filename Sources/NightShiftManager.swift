import Foundation
import os.log

private let logger = Logger(subsystem: "com.astralbyte.retinascaler", category: "NightShift")

/// Controls Night Shift (blue light reduction) via CoreBrightness private API.
enum NightShiftManager {

    private static var _client: NSObject?
    private static var _clientLoaded = false

    private static var client: NSObject? {
        if !_clientLoaded {
            _clientLoaded = true
            if dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
               let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type {
                _client = cls.init()
                logger.info("CBBlueLightClient loaded")
            } else {
                logger.warning("CoreBrightness not available")
            }
        }
        return _client
    }

    struct Status {
        let enabled: Bool
        let strength: Float
    }

    static func getStatus() -> Status? {
        guard let client else { return nil }

        // CBBlueLightClient.getBlueLightStatus: takes a pointer to a
        // CBBlueLightStatus struct. The struct layout is opaque and varies
        // across macOS versions, so we allocate a generous buffer and read
        // the enabled flag at the known offset.
        let sel = NSSelectorFromString("getBlueLightStatus:")
        guard client.responds(to: sel) else { return nil }

        // The status struct is ~32 bytes. Offset 0 = enabled (Int32), offset 4 = mode, etc.
        var statusBuf = [UInt8](repeating: 0, count: 64)
        guard let method = class_getInstanceMethod(type(of: client), sel) else { return nil }

        typealias Fn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        let imp = method_getImplementation(method)
        let fn = unsafeBitCast(imp, to: Fn.self)
        let ok = fn(client, sel, &statusBuf)
        guard ok else { return nil }

        // Byte 0: supported, Byte 1: enabled
        let enabled = statusBuf[1] != 0

        // Strength via separate call
        var strength: Float = 0.5
        let strengthSel = NSSelectorFromString("getStrength:")
        if client.responds(to: strengthSel),
           let sMethod = class_getInstanceMethod(type(of: client), strengthSel) {
            typealias SFn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<Float>) -> Bool
            let sImp = method_getImplementation(sMethod)
            let sFn = unsafeBitCast(sImp, to: SFn.self)
            _ = sFn(client, strengthSel, &strength)
        }

        return Status(enabled: enabled, strength: strength)
    }

    static func setEnabled(_ value: Bool) -> Bool {
        guard let client else { return false }
        let sel = NSSelectorFromString("setEnabled:")
        guard client.responds(to: sel),
              let method = class_getInstanceMethod(type(of: client), sel)
        else { return false }

        typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Bool
        let imp = method_getImplementation(method)
        return unsafeBitCast(imp, to: Fn.self)(client, sel, value)
    }

    static func setStrength(_ value: Float) -> Bool {
        guard let client else { return false }
        let sel = NSSelectorFromString("setStrength:commit:")
        guard client.responds(to: sel),
              let method = class_getInstanceMethod(type(of: client), sel)
        else { return false }

        typealias Fn = @convention(c) (AnyObject, Selector, Float, Bool) -> Bool
        let imp = method_getImplementation(method)
        return unsafeBitCast(imp, to: Fn.self)(client, sel, value, true)
    }

    static var isAvailable: Bool {
        client != nil
    }
}
