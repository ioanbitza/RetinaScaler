import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.astralbyte.retinascaler", category: "DisplayManager")

@Observable
class DisplayManager {
    var displays: [ExternalDisplay] = []
    var selectedDisplay: ExternalDisplay?
    var statusMessage: String?
    var isProcessing = false
    var hiDPIActive = false

    // Per-display state keyed by display ID
    private(set) var perDisplayModes: [CGDirectDisplayID: [DisplayModeInfo]] = [:]
    private(set) var perDisplayCurrentMode: [CGDirectDisplayID: DisplayModeInfo] = [:]

    // Brightness state per display
    private(set) var perDisplayBrightness: [CGDirectDisplayID: Int] = [:]
    private(set) var perDisplayContrast: [CGDirectDisplayID: Int] = [:]
    private(set) var perDisplayBrightnessAvailable: [CGDirectDisplayID: Bool] = [:]
    /// Tracks whether external display uses DDC (true) or gamma fallback (false)
    private(set) var perDisplayUsesDDC: [CGDirectDisplayID: Bool] = [:]

    // Night Shift (system-wide, not per-display)
    var nightShiftEnabled = false
    var nightShiftStrength: Float = 0.5
    var nightShiftAvailable = false

    // HDR per display
    private(set) var perDisplayHDREnabled: [CGDirectDisplayID: Bool] = [:]
    var hdrAvailable = false

    // Launch at login
    var launchAtLogin = false

    // Hotkeys
    let hotkeyManager = HotkeyManager()

    // Display reconfiguration callback token
    private var displayReconfigToken: DisplayReconfigurationToken?

    var externalDisplays: [ExternalDisplay] {
        displays.filter { !$0.isBuiltIn }
    }

    // MARK: - Convenience accessors for selected display (backward compat with UI)

    var availableModes: [DisplayModeInfo] {
        guard let d = selectedDisplay else { return [] }
        return perDisplayModes[d.id] ?? []
    }

    var currentMode: DisplayModeInfo? {
        guard let d = selectedDisplay else { return nil }
        return perDisplayCurrentMode[d.id]
    }

    var brightness: Int {
        guard let d = selectedDisplay else { return -1 }
        return perDisplayBrightness[d.id] ?? -1
    }

    var contrast: Int {
        guard let d = selectedDisplay else { return -1 }
        return perDisplayContrast[d.id] ?? -1
    }

    var brightnessAvailable: Bool {
        guard let d = selectedDisplay else { return false }
        return perDisplayBrightnessAvailable[d.id] ?? false
    }

    var hdrEnabled: Bool {
        guard let d = selectedDisplay else { return false }
        return perDisplayHDREnabled[d.id] ?? false
    }

    var availableRefreshRates: [Double] {
        guard let d = selectedDisplay else { return [] }
        let modes = perDisplayModes[d.id] ?? []
        let rates = Set(modes
            .filter { !$0.isHiDPI && $0.width == d.nativeWidth }
            .map { $0.refreshRate })
        return rates.sorted(by: >)
    }

    // MARK: - Per-display mode/brightness accessors

    func modes(for displayID: CGDirectDisplayID) -> [DisplayModeInfo] {
        perDisplayModes[displayID] ?? []
    }

    func currentMode(for displayID: CGDirectDisplayID) -> DisplayModeInfo? {
        perDisplayCurrentMode[displayID]
    }

    func brightness(for displayID: CGDirectDisplayID) -> Int {
        perDisplayBrightness[displayID] ?? -1
    }

    func contrast(for displayID: CGDirectDisplayID) -> Int {
        perDisplayContrast[displayID] ?? -1
    }

    func isBrightnessAvailable(for displayID: CGDirectDisplayID) -> Bool {
        perDisplayBrightnessAvailable[displayID] ?? false
    }

    func isHDREnabled(for displayID: CGDirectDisplayID) -> Bool {
        perDisplayHDREnabled[displayID] ?? false
    }

    // MARK: - Refresh

    func refresh() {
        let detectedDisplays = DisplayDetector.detectDisplays()
        displays = detectedDisplays
        hiDPIActive = VirtualDisplayManager.isActive
        launchAtLogin = LaunchAtLogin.isEnabled

        // Clean up per-display state for disconnected displays
        let activeIDs = Set(detectedDisplays.map(\.id))

        // Reset gamma for disconnected displays that were using software brightness
        for (displayID, usesDDC) in perDisplayUsesDDC where !activeIDs.contains(displayID) {
            if !usesDDC { SoftwareBrightnessManager.reset(for: displayID) }
        }

        perDisplayModes = perDisplayModes.filter { activeIDs.contains($0.key) }
        perDisplayCurrentMode = perDisplayCurrentMode.filter { activeIDs.contains($0.key) }
        perDisplayBrightness = perDisplayBrightness.filter { activeIDs.contains($0.key) }
        perDisplayContrast = perDisplayContrast.filter { activeIDs.contains($0.key) }
        perDisplayBrightnessAvailable = perDisplayBrightnessAvailable.filter { activeIDs.contains($0.key) }
        perDisplayUsesDDC = perDisplayUsesDDC.filter { activeIDs.contains($0.key) }
        perDisplayHDREnabled = perDisplayHDREnabled.filter { activeIDs.contains($0.key) }

        // Auto-disable VD if the mirrored physical display was disconnected
        if VirtualDisplayManager.isActive {
            let mirroredID = VirtualDisplayManager.mirroredPhysicalID
            if mirroredID != 0 && !activeIDs.contains(mirroredID) {
                logger.info("Mirrored display \(mirroredID) disconnected, disabling Virtual Display")
                disableHiDPI()
            }
        }

        // If the selected display was disconnected, pick a new one
        if let selected = selectedDisplay, !activeIDs.contains(selected.id) {
            selectedDisplay = externalDisplays.first
            logger.info("Selected display disconnected, switched to \(self.selectedDisplay?.name ?? "none")")
        }

        if selectedDisplay == nil {
            selectedDisplay = externalDisplays.first
        }

        // Refresh per-display data
        for display in detectedDisplays {
            refreshModes(for: display)

            // Read brightness on first refresh (DDC for external, IOKit for built-in)
            if perDisplayBrightness[display.id] == nil {
                readBrightness(for: display)
            }

            // HDR status
            if let enabled = HDRManager.isHDREnabled(for: display.id) {
                perDisplayHDREnabled[display.id] = enabled
            }
        }

        hdrAvailable = HDRManager.isAvailable
        nightShiftAvailable = NightShiftManager.isAvailable
        refreshNightShift()
    }

    func refreshModes(for display: ExternalDisplay) {
        perDisplayModes[display.id] = DisplayModeService.availableModes(for: display.id)
        perDisplayCurrentMode[display.id] = DisplayModeService.currentMode(for: display.id)
    }

    // MARK: - Display Reconfiguration Monitoring

    func startMonitoringDisplayChanges() {
        guard displayReconfigToken == nil else { return }
        displayReconfigToken = DisplayReconfigurationToken { [weak self] displayID, flags in
            guard let self else { return }
            // CGDisplayReconfigurationCallBack fires on the main thread
            if flags.contains(.addFlag) || flags.contains(.removeFlag) {
                logger.info("Display reconfiguration detected (display \(displayID), flags \(flags.rawValue))")
                // Slight delay to let macOS settle after reconfiguration
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.refresh()
                }
            }
        }
    }

    func stopMonitoringDisplayChanges() {
        displayReconfigToken = nil
    }

    // MARK: - HiDPI

    func enableHiDPI(for display: ExternalDisplay, logicalWidth: Int? = nil, logicalHeight: Int? = nil) {
        guard !isProcessing else { return }
        isProcessing = true
        statusMessage = "Switching HiDPI..."

        let displayID = display.id
        let nativeW = display.nativeWidth
        let nativeH = display.nativeHeight

        DispatchQueue.global(qos: .userInitiated).async {
            let result = VirtualDisplayManager.enableHiDPI(
                for: displayID,
                nativeWidth: nativeW,
                nativeHeight: nativeH,
                logicalWidth: logicalWidth,
                logicalHeight: logicalHeight
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let msg):
                    self.statusMessage = msg
                    self.hiDPIActive = true
                case .failure(let error):
                    self.statusMessage = error.localizedDescription
                    logger.error("Failed to enable HiDPI: \(error.localizedDescription)")
                }
                self.refresh()
                self.isProcessing = false
            }
        }
    }

    func disableHiDPI() {
        VirtualDisplayManager.disable()
        hiDPIActive = false
        statusMessage = "HiDPI disabled"
        // Delay refresh to let macOS settle display configuration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }

    func toggleHiDPI() {
        guard let display = externalDisplays.first else { return }
        if hiDPIActive { disableHiDPI() } else { enableHiDPI(for: display) }
    }

    // MARK: - Brightness & Contrast (routes built-in vs external)

    func readBrightness(for display: ExternalDisplay) {
        if display.isBuiltIn {
            // Built-in: DisplayServices framework
            if let b = BuiltInBrightnessManager.getBrightness(for: display.id) {
                perDisplayBrightness[display.id] = b
                perDisplayBrightnessAvailable[display.id] = true
            }
        } else {
            // External: try DDC first, fall back to gamma
            if let b = DDCManager.getBrightness(for: display.id) {
                perDisplayBrightness[display.id] = b
                perDisplayBrightnessAvailable[display.id] = true
                perDisplayUsesDDC[display.id] = true
                if let c = DDCManager.getContrast(for: display.id) {
                    perDisplayContrast[display.id] = c
                }
            } else {
                // Gamma fallback — always available
                let b = SoftwareBrightnessManager.getBrightness(for: display.id)
                perDisplayBrightness[display.id] = b
                perDisplayBrightnessAvailable[display.id] = true
                perDisplayUsesDDC[display.id] = false
            }
        }
    }

    func readBrightness() {
        guard let display = selectedDisplay else { return }
        readBrightness(for: display)
    }

    func setBrightness(for displayID: CGDirectDisplayID, value: Int) {
        let clamped = max(0, min(100, value))
        let isBuiltIn = displays.first(where: { $0.id == displayID })?.isBuiltIn ?? false

        let success: Bool
        if isBuiltIn {
            success = BuiltInBrightnessManager.setBrightness(for: displayID, value: clamped)
        } else if perDisplayUsesDDC[displayID] == true {
            success = DDCManager.setBrightness(for: displayID, value: clamped)
        } else {
            success = SoftwareBrightnessManager.setBrightness(for: displayID, value: clamped)
        }

        if success {
            perDisplayBrightness[displayID] = clamped
        }
    }

    func setBrightness(_ value: Int) {
        guard let display = selectedDisplay else { return }
        setBrightness(for: display.id, value: value)
    }

    func setContrast(for displayID: CGDirectDisplayID, value: Int) {
        let clamped = max(0, min(100, value))
        if DDCManager.setContrast(for: displayID, value: clamped) {
            perDisplayContrast[displayID] = clamped
        }
    }

    func setContrast(_ value: Int) {
        guard let display = selectedDisplay else { return }
        setContrast(for: display.id, value: value)
    }

    func adjustBrightness(by delta: Int) {
        guard let display = selectedDisplay else { return }
        let current = perDisplayBrightness[display.id] ?? 50
        setBrightness(for: display.id, value: current + delta)
    }

    // MARK: - Night Shift

    func refreshNightShift() {
        guard NightShiftManager.isAvailable else { return }
        if let status = NightShiftManager.getStatus() {
            nightShiftEnabled = status.enabled
            nightShiftStrength = status.strength
            nightShiftAvailable = true
        }
    }

    func toggleNightShift() {
        nightShiftEnabled.toggle()
        _ = NightShiftManager.setEnabled(nightShiftEnabled)
    }

    func setNightShiftStrength(_ strength: Float) {
        nightShiftStrength = strength
        _ = NightShiftManager.setStrength(strength)
    }

    // MARK: - HDR

    func toggleHDR() {
        guard let display = selectedDisplay else { return }
        toggleHDR(for: display)
    }

    func toggleHDR(for display: ExternalDisplay) {
        if HDRManager.toggleHDR(for: display.id) {
            let newState = !(perDisplayHDREnabled[display.id] ?? false)
            perDisplayHDREnabled[display.id] = newState
            statusMessage = "HDR \(newState ? "enabled" : "disabled")"
        }
    }

    func refreshHDR() {
        for display in displays {
            if let enabled = HDRManager.isHDREnabled(for: display.id) {
                perDisplayHDREnabled[display.id] = enabled
            }
        }
    }

    // MARK: - Refresh Rate

    func switchRefreshRate(_ hz: Double) {
        guard let display = selectedDisplay else { return }
        switchRefreshRate(hz, for: display)
    }

    func switchRefreshRate(_ hz: Double, for display: ExternalDisplay) {
        let w = display.nativeWidth
        let h = display.nativeHeight
        let modes = perDisplayModes[display.id] ?? []

        if let mode = modes.first(where: {
            $0.width == w && $0.height == h && !$0.isHiDPI && abs($0.refreshRate - hz) < 1
        }) {
            switchMode(to: mode, for: display)
        }
    }

    func cycleRefreshRate() {
        guard let display = selectedDisplay else { return }
        let modes = perDisplayModes[display.id] ?? []
        let rates = Array(Set(modes
            .filter { !$0.isHiDPI && $0.width == display.nativeWidth }
            .map { $0.refreshRate }))
            .sorted(by: >)
        guard !rates.isEmpty, let current = perDisplayCurrentMode[display.id] else { return }
        let currentHz = current.refreshRate
        let nextIdx = (rates.firstIndex(where: { abs($0 - currentHz) < 1 }) ?? 0) + 1
        let nextHz = rates[nextIdx % rates.count]
        switchRefreshRate(nextHz, for: display)
    }

    // MARK: - Display Arrangement

    func applyArrangement(_ preset: DisplayArrangement.Preset) {
        guard let display = selectedDisplay else { return }
        applyArrangement(preset, for: display)
    }

    func applyArrangement(_ preset: DisplayArrangement.Preset, for display: ExternalDisplay) {
        if DisplayArrangement.applyPreset(preset, displayID: display.id) {
            statusMessage = "Arrangement: \(preset.rawValue)"
        }
    }

    func setAsMainDisplay(for display: ExternalDisplay) {
        if DisplayArrangement.setAsMainDisplay(display.id) {
            statusMessage = "\(display.name) set as main display"
            refresh()
        }
    }

    // MARK: - Launch at Login

    func toggleLaunchAtLogin() {
        LaunchAtLogin.toggle()
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    // MARK: - Mode Switch

    func switchMode(to mode: DisplayModeInfo, for display: ExternalDisplay) {
        if DisplayModeService.switchMode(mode, for: display.id) {
            perDisplayCurrentMode[display.id] = mode
            statusMessage = "Switched to \(mode.description)"
        } else {
            statusMessage = "Failed to switch to \(mode.description)"
            logger.error("Failed to switch display \(display.id) to mode \(mode.description)")
        }
    }

    // MARK: - Hotkeys

    func setupHotkeys() {
        hotkeyManager.onToggleHiDPI = { [weak self] in
            DispatchQueue.main.async { self?.toggleHiDPI() }
        }
        hotkeyManager.onToggleHDR = { [weak self] in
            DispatchQueue.main.async { self?.toggleHDR() }
        }
        hotkeyManager.onBrightnessUp = { [weak self] in
            DispatchQueue.main.async { self?.adjustBrightness(by: 10) }
        }
        hotkeyManager.onBrightnessDown = { [weak self] in
            DispatchQueue.main.async { self?.adjustBrightness(by: -10) }
        }
        hotkeyManager.onRefreshRateCycle = { [weak self] in
            DispatchQueue.main.async { self?.cycleRefreshRate() }
        }
        hotkeyManager.start()
        startMonitoringDisplayChanges()
    }
}

// MARK: - Display Reconfiguration Token

/// RAII wrapper for CGDisplayRegisterReconfigurationCallback / CGDisplayRemoveReconfigurationCallback.
/// Automatically unregisters when deallocated.
private final class DisplayReconfigurationToken {
    private let callback: CGDisplayReconfigurationCallBack
    // Must retain the closure so it stays alive for the C callback
    private let closure: (CGDirectDisplayID, CGDisplayChangeSummaryFlags) -> Void

    init(handler: @escaping (CGDirectDisplayID, CGDisplayChangeSummaryFlags) -> Void) {
        self.closure = handler

        // We need a C-compatible function pointer. Store `self` in user data via a pointer.
        // Since we control the lifetime via this token, this is safe.
        let callback: CGDisplayReconfigurationCallBack = { displayID, flags, userInfo in
            guard let userInfo else { return }
            let token = Unmanaged<DisplayReconfigurationToken>.fromOpaque(userInfo).takeUnretainedValue()
            token.closure(displayID, flags)
        }
        self.callback = callback

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(callback, selfPtr)
    }

    deinit {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRemoveReconfigurationCallback(callback, selfPtr)
    }
}
