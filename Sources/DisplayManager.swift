import AppKit
import Foundation

@Observable
class DisplayManager {
    var displays: [ExternalDisplay] = []
    var selectedDisplay: ExternalDisplay?
    var availableModes: [DisplayModeInfo] = []
    var currentMode: DisplayModeInfo?
    var statusMessage: String?
    var isProcessing = false
    var hiDPIActive = false

    // DDC
    var brightness: Int = -1  // -1 = not read yet
    var contrast: Int = -1
    var ddcAvailable = false

    // Night Shift
    var nightShiftEnabled = false
    var nightShiftStrength: Float = 0.5
    var nightShiftAvailable = false

    // HDR
    var hdrEnabled = false
    var hdrAvailable = false

    // Launch at login
    var launchAtLogin = false

    // Hotkeys
    let hotkeyManager = HotkeyManager()

    var externalDisplays: [ExternalDisplay] {
        displays.filter { !$0.isBuiltIn }
    }

    var availableRefreshRates: [Double] {
        let rates = Set(availableModes
            .filter { !$0.isHiDPI && $0.width == (selectedDisplay?.nativeWidth ?? 0) }
            .map { $0.refreshRate })
        return rates.sorted(by: >)
    }

    func refresh() {
        displays = DisplayDetector.detectDisplays()
        hiDPIActive = VirtualDisplayManager.isActive
        launchAtLogin = LaunchAtLogin.isEnabled

        if selectedDisplay == nil {
            selectedDisplay = externalDisplays.first
        }

        if let display = selectedDisplay {
            refreshModes(for: display)

            // Try DDC once on first refresh
            if brightness < 0 {
                readBrightness()
            }
        }

        hdrAvailable = HDRManager.isAvailable
        nightShiftAvailable = NightShiftManager.isAvailable
    }

    func refreshModes(for display: ExternalDisplay) {
        availableModes = DisplayModeService.availableModes(for: display.id)
        currentMode = DisplayModeService.currentMode(for: display.id)
    }

    // MARK: - HiDPI

    func enableHiDPI(for display: ExternalDisplay) {
        isProcessing = true
        statusMessage = nil

        let result = VirtualDisplayManager.enableHiDPI(
            for: display.id,
            logicalWidth: display.nativeWidth,
            logicalHeight: display.nativeHeight
        )

        switch result {
        case .success(let msg):
            statusMessage = msg
            hiDPIActive = true
        case .failure(let error):
            statusMessage = error.localizedDescription
        }

        refresh()
        isProcessing = false
    }

    func disableHiDPI() {
        VirtualDisplayManager.disable()
        hiDPIActive = false
        statusMessage = "HiDPI disabled"
        refresh()
    }

    func toggleHiDPI() {
        guard let display = externalDisplays.first else { return }
        if hiDPIActive { disableHiDPI() } else { enableHiDPI(for: display) }
    }

    // MARK: - DDC Brightness & Contrast

    func readBrightness() {
        guard let display = selectedDisplay else { return }
        if let b = DDCManager.getBrightness(for: display.id) {
            brightness = b
            ddcAvailable = true
        }
        if let c = DDCManager.getContrast(for: display.id) {
            contrast = c
        }
    }

    func setBrightness(_ value: Int) {
        guard let display = selectedDisplay else { return }
        if DDCManager.setBrightness(for: display.id, value: value) {
            brightness = value
        }
    }

    func setContrast(_ value: Int) {
        guard let display = selectedDisplay else { return }
        if DDCManager.setContrast(for: display.id, value: value) {
            contrast = value
        }
    }

    func adjustBrightness(by delta: Int) {
        setBrightness(max(0, min(100, brightness + delta)))
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
        if HDRManager.toggleHDR(for: display.id) {
            hdrEnabled.toggle()
            statusMessage = "HDR \(hdrEnabled ? "enabled" : "disabled")"
        }
    }

    func refreshHDR() {
        guard let display = selectedDisplay else { return }
        if let enabled = HDRManager.isHDREnabled(for: display.id) {
            hdrEnabled = enabled
        }
    }

    // MARK: - Refresh Rate

    func switchRefreshRate(_ hz: Double) {
        guard let display = selectedDisplay else { return }
        let w = display.nativeWidth
        let h = display.nativeHeight

        if let mode = availableModes.first(where: {
            $0.width == w && $0.height == h && !$0.isHiDPI && abs($0.refreshRate - hz) < 1
        }) {
            switchMode(to: mode, for: display)
        }
    }

    func cycleRefreshRate() {
        let rates = availableRefreshRates
        guard !rates.isEmpty, let current = currentMode else { return }
        let currentHz = current.refreshRate
        let nextIdx = (rates.firstIndex(where: { abs($0 - currentHz) < 1 }) ?? 0) + 1
        let nextHz = rates[nextIdx % rates.count]
        switchRefreshRate(nextHz)
    }

    // MARK: - Display Arrangement

    func applyArrangement(_ preset: DisplayArrangement.Preset) {
        guard let display = selectedDisplay else { return }
        if DisplayArrangement.applyPreset(preset, displayID: display.id) {
            statusMessage = "Arrangement: \(preset.rawValue)"
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
            currentMode = mode
            statusMessage = "Switched to \(mode.description)"
        }
    }

    // MARK: - Hotkeys

    func setupHotkeys() {
        hotkeyManager.onToggleHiDPI = { [weak self] in self?.toggleHiDPI() }
        hotkeyManager.onToggleHDR = { [weak self] in self?.toggleHDR() }
        hotkeyManager.onBrightnessUp = { [weak self] in self?.adjustBrightness(by: 10) }
        hotkeyManager.onBrightnessDown = { [weak self] in self?.adjustBrightness(by: -10) }
        hotkeyManager.onRefreshRateCycle = { [weak self] in self?.cycleRefreshRate() }
        hotkeyManager.start()
    }
}
