import Foundation

/// Controls Night Shift (blue light reduction) via CoreBrightness private API.
/// Works on external displays where Apple normally blocks Night Shift.
enum NightShiftManager {

    // Lazy-init: only created when first accessed, not at app launch
    private static var _client: NSObject?
    private static var _clientLoaded = false

    private static var client: NSObject? {
        if !_clientLoaded {
            _clientLoaded = true
            if let handle = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY),
               let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type {
                _client = cls.init()
            }
        }
        return _client
    }

    struct Status {
        let enabled: Bool
        let strength: Float
    }

    static func getStatus() -> Status? {
        guard let client = client else { return nil }

        // Use objc_msgSend typed to avoid perform(_:with:) crashes with non-object params
        var enabled: ObjCBool = false
        let getSel = NSSelectorFromString("getBlueLightStatus:")

        if client.responds(to: getSel) {
            typealias GetStatusFn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<ObjCBool>) -> Bool
            let method = class_getInstanceMethod(type(of: client), getSel)!
            let imp = method_getImplementation(method)
            let fn = unsafeBitCast(imp, to: GetStatusFn.self)
            _ = fn(client, getSel, &enabled)
        }

        var strength: Float = 0.5
        let strengthSel = NSSelectorFromString("getStrength:")
        if client.responds(to: strengthSel) {
            typealias GetStrengthFn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<Float>) -> Bool
            let method = class_getInstanceMethod(type(of: client), strengthSel)!
            let imp = method_getImplementation(method)
            let fn = unsafeBitCast(imp, to: GetStrengthFn.self)
            _ = fn(client, strengthSel, &strength)
        }

        return Status(enabled: enabled.boolValue, strength: strength)
    }

    static func setEnabled(_ value: Bool) -> Bool {
        guard let client = client else { return false }
        let sel = NSSelectorFromString("setEnabled:")
        guard client.responds(to: sel) else { return false }

        typealias SetEnabledFn = @convention(c) (AnyObject, Selector, Bool) -> Bool
        let method = class_getInstanceMethod(type(of: client), sel)!
        let imp = method_getImplementation(method)
        let fn = unsafeBitCast(imp, to: SetEnabledFn.self)
        return fn(client, sel, value)
    }

    static func setStrength(_ value: Float) -> Bool {
        guard let client = client else { return false }
        let sel = NSSelectorFromString("setStrength:commit:")
        guard client.responds(to: sel) else { return false }

        typealias SetStrengthFn = @convention(c) (AnyObject, Selector, Float, Bool) -> Bool
        let method = class_getInstanceMethod(type(of: client), sel)!
        let imp = method_getImplementation(method)
        let fn = unsafeBitCast(imp, to: SetStrengthFn.self)
        return fn(client, sel, value, true)
    }

    static var isAvailable: Bool {
        client != nil
    }
}
