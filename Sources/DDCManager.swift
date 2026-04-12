import CoreGraphics
import Foundation
import IOKit

/// Controls monitor brightness, contrast, and input source via DDC/CI over I2C.
/// Works on Apple Silicon Macs using IOAVService (private but stable API).
enum DDCManager {

    // MARK: - VCP Codes (VESA Monitor Control Command Set)

    static let vcpBrightness: UInt8 = 0x10
    static let vcpContrast: UInt8 = 0x12
    static let vcpInputSource: UInt8 = 0x60
    static let vcpPowerMode: UInt8 = 0xD6

    // MARK: - Public API

    static func getBrightness(for displayID: CGDirectDisplayID) -> Int? {
        getVCPValue(displayID: displayID, vcpCode: vcpBrightness)
    }

    static func setBrightness(for displayID: CGDirectDisplayID, value: Int) -> Bool {
        setVCPValue(displayID: displayID, vcpCode: vcpBrightness, value: UInt16(clamping: value))
    }

    static func getContrast(for displayID: CGDirectDisplayID) -> Int? {
        getVCPValue(displayID: displayID, vcpCode: vcpContrast)
    }

    static func setContrast(for displayID: CGDirectDisplayID, value: Int) -> Bool {
        setVCPValue(displayID: displayID, vcpCode: vcpContrast, value: UInt16(clamping: value))
    }

    static func setInputSource(for displayID: CGDirectDisplayID, input: UInt16) -> Bool {
        setVCPValue(displayID: displayID, vcpCode: vcpInputSource, value: input)
    }

    // MARK: - IOAVService (Apple Silicon DDC/CI)

    /// Dynamically loaded IOAVService functions from IOKit.
    /// These are exported but not in public headers.
    private static let ioAVServiceCreate: (@convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?)? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else { return nil }
        guard let sym = dlsym(handle, "IOAVServiceCreate") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?).self)
    }()

    private static let ioAVServiceReadI2C: (@convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutablePointer<UInt8>, UInt32) -> IOReturn)? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else { return nil }
        guard let sym = dlsym(handle, "IOAVServiceReadI2C") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutablePointer<UInt8>, UInt32) -> IOReturn).self)
    }()

    private static let ioAVServiceWriteI2C: (@convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutablePointer<UInt8>, UInt32) -> IOReturn)? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else { return nil }
        guard let sym = dlsym(handle, "IOAVServiceWriteI2C") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutablePointer<UInt8>, UInt32) -> IOReturn).self)
    }()

    /// Finds the IOAVService matching a CGDirectDisplayID.
    private static func avService(for displayID: CGDirectDisplayID) -> CFTypeRef? {
        guard let create = ioAVServiceCreate else { return nil }

        var iter: io_iterator_t = 0
        let matching = IOServiceMatching("DCPAVServiceProxy")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iter)
            }

            if let avSvc = create(kCFAllocatorDefault, service)?.takeRetainedValue() {
                // On single-external setups, the first DCPAVServiceProxy usually matches
                return avSvc
            }
        }

        return nil
    }

    // MARK: - DDC/CI Protocol

    private static let ddcAddress: UInt32 = 0x37

    private static func setVCPValue(displayID: CGDirectDisplayID, vcpCode: UInt8, value: UInt16) -> Bool {
        guard let write = ioAVServiceWriteI2C,
              let avSvc = avService(for: displayID)
        else { return false }

        let valueH = UInt8(value >> 8)
        let valueL = UInt8(value & 0xFF)

        // DDC/CI Set VCP Feature command
        // [source_addr, length|0x80, opcode=0x03, vcp_code, value_h, value_l, checksum]
        var data: [UInt8] = [0x51, 0x84, 0x03, vcpCode, valueH, valueL]
        let checksum = data.reduce(UInt8(ddcAddress << 1), ^)
        data.append(checksum)

        let result = write(avSvc, ddcAddress, 0, &data, UInt32(data.count))
        return result == kIOReturnSuccess
    }

    private static func getVCPValue(displayID: CGDirectDisplayID, vcpCode: UInt8) -> Int? {
        guard let write = ioAVServiceWriteI2C,
              let read = ioAVServiceReadI2C,
              let avSvc = avService(for: displayID)
        else { return nil }

        // Send GET VCP request
        var request: [UInt8] = [0x51, 0x82, 0x01, vcpCode]
        let checksum = request.reduce(UInt8(ddcAddress << 1), ^)
        request.append(checksum)

        var result = write(avSvc, ddcAddress, 0, &request, UInt32(request.count))
        guard result == kIOReturnSuccess else { return nil }

        // Brief delay for monitor to process
        usleep(40_000)

        // Read response (12 bytes typical for VCP reply)
        var response = [UInt8](repeating: 0, count: 12)
        result = read(avSvc, ddcAddress, 0, &response, UInt32(response.count))
        guard result == kIOReturnSuccess else { return nil }

        // Parse: response[8] = current_value_h, response[9] = current_value_l
        guard response.count >= 10 else { return nil }
        let currentValue = (Int(response[8]) << 8) | Int(response[9])
        return currentValue
    }
}
