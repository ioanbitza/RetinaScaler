import SwiftUI

struct MenuBarView: View {
    @State private var manager = DisplayManager()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(manager.displays) { display in
                    DisplaySection(display: display, manager: manager)
                    if display.id != manager.displays.last?.id {
                        Divider().padding(.horizontal, 12)
                    }
                }

                if manager.displays.isEmpty {
                    emptyView
                }

                Divider().padding(.horizontal, 12)
                toolsSection
            }
            .padding(.vertical, 8)
        }
        .frame(width: 340, height: 650)
        .onAppear {
            manager.refresh()
            manager.setupHotkeys()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No displays detected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 1) {
                    MenuRow("Arrangement") {
                        Menu("Position") {
                            ForEach(DisplayArrangement.Preset.allCases, id: \.rawValue) { preset in
                                Button(preset.rawValue) { manager.applyArrangement(preset) }
                            }
                        }
                        .controlSize(.small)
                    }

                    ToggleRow("Launch at login", isOn: manager.launchAtLogin) {
                        manager.toggleLaunchAtLogin()
                    }

                    ToggleRow("Keyboard shortcuts", isOn: manager.hotkeyManager.isListening) {
                        if manager.hotkeyManager.isListening {
                            manager.hotkeyManager.stop()
                        } else {
                            manager.hotkeyManager.start()
                        }
                    }

                    Text("  ^⌥H HiDPI   ^⌥R HDR   ^⌥↑↓ Brightness   ^⌥F Hz")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                }
            } label: {
                Label("Tools", systemImage: "wrench.and.screwdriver")
                    .font(.callout.bold())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            if let msg = manager.statusMessage {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption2)
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }

            Divider().padding(.horizontal, 12)

            Button(action: { manager.refresh() }) {
                Label("Refresh Displays", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)

            Button(action: {
                manager.disableHiDPI()
                manager.hotkeyManager.stop()
                NSApplication.shared.terminate(nil)
            }) {
                Label("Quit RetinaScaler", systemImage: "power")
            }
            .buttonStyle(.plain)
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
        }
    }
}

// MARK: - Per-Display Section

struct DisplaySection: View {
    let display: ExternalDisplay
    @Bindable var manager: DisplayManager
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 1) {
                if display.isBuiltIn {
                    builtInControls
                } else {
                    externalControls
                }
            }
        } label: {
            displayHeader
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Header

    private var displayHeader: some View {
        HStack {
            Text(display.name)
                .font(.callout.bold())
            Spacer()
            if !display.isBuiltIn && manager.hiDPIActive {
                Text("HiDPI")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.15), in: Capsule())
            }
        }
    }

    // MARK: - Built-in Display

    private var builtInControls: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let mode = currentBuiltInMode {
                InfoRow("Resolution", value: "\(mode.width)×\(mode.height)")
            }
        }
    }

    private var currentBuiltInMode: DisplayModeInfo? {
        DisplayModeService.currentMode(for: display.id)
    }

    // MARK: - External Display

    private var externalControls: some View {
        VStack(alignment: .leading, spacing: 1) {
            // Current mode info
            if let current = manager.currentMode {
                InfoRow("Resolution", value: "\(current.width)×\(current.height)\(current.isHiDPI ? " HiDPI" : "")")
                InfoRow("Refresh Rate", value: "\(Int(current.refreshRate))Hz")
            }

            Divider().padding(.vertical, 4)

            // HiDPI toggle
            if manager.hiDPIActive {
                MenuButton("Disable HiDPI", icon: "xmark.circle", tint: .red) {
                    manager.disableHiDPI()
                }
            } else {
                MenuButton("Enable HiDPI", icon: "sparkles", tint: .blue) {
                    manager.enableHiDPI(for: display)
                }
            }

            Divider().padding(.vertical, 4)

            // Resolution picker
            resolutionPicker

            Divider().padding(.vertical, 4)

            // Refresh Rate
            refreshRatePicker

            // HDR
            if manager.hdrAvailable {
                ToggleRow("HDR Mode", isOn: manager.hdrEnabled) {
                    manager.toggleHDR()
                }
            }

            // Night Shift
            if manager.nightShiftAvailable {
                ToggleRow("Night Shift", isOn: manager.nightShiftEnabled) {
                    manager.toggleNightShift()
                }
            }

            // DDC Brightness
            if manager.ddcAvailable {
                Divider().padding(.vertical, 4)
                brightnessSlider
                contrastSlider
            }
        }
    }

    // MARK: - Resolution Picker

    private var resolutionPicker: some View {
        let hiDPIModes = deduplicate(manager.availableModes
            .filter { $0.isHiDPI && $0.width >= 2560 }
            .sorted { $0.width > $1.width })

        let stdModes = deduplicate(manager.availableModes
            .filter { !$0.isHiDPI && $0.width >= 2560 && $0.height >= 720 }
            .sorted { $0.width > $1.width })

        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 0) {
                if !hiDPIModes.isEmpty {
                    Text("HiDPI")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                    ForEach(hiDPIModes) { mode in
                        resolutionRow(mode)
                    }
                }
                if !stdModes.isEmpty {
                    Text("Standard")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                    ForEach(stdModes.prefix(8)) { mode in
                        resolutionRow(mode)
                    }
                }
            }
        } label: {
            Label("Resolutions", systemImage: "rectangle.split.3x1")
                .font(.callout)
        }
    }

    private func resolutionRow(_ mode: DisplayModeInfo) -> some View {
        let isCurrent = manager.currentMode?.width == mode.width
            && manager.currentMode?.height == mode.height
            && manager.currentMode?.isHiDPI == mode.isHiDPI

        return Button {
            manager.switchMode(to: mode, for: display)
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: "\(mode.width)×\(mode.height)")
                    .font(.system(size: 12, design: .monospaced))
                if mode.isHiDPI {
                    Text("HiDPI")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.yellow.opacity(0.15), in: Capsule())
                }
                Text(verbatim: "@\(Int(mode.refreshRate))Hz")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(isCurrent ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Refresh Rate

    private var refreshRatePicker: some View {
        RefreshRateRow(manager: manager, display: display)
    }

    // MARK: - Brightness / Contrast

    private var brightnessSlider: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.min")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Slider(
                value: Binding(
                    get: { Double(max(0, manager.brightness)) },
                    set: { manager.setBrightness(Int($0)) }
                ),
                in: 0...100, step: 1
            )
            Image(systemName: "sun.max.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)
                .frame(width: 14)
            Text(verbatim: "\(max(0, manager.brightness))%")
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private var contrastSlider: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Slider(
                value: Binding(
                    get: { Double(max(0, manager.contrast)) },
                    set: { manager.setContrast(Int($0)) }
                ),
                in: 0...100, step: 1
            )
            Image(systemName: "circle.righthalf.filled")
                .font(.caption2)
                .frame(width: 14)
            Text(verbatim: "\(max(0, manager.contrast))%")
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func deduplicate(_ modes: [DisplayModeInfo]) -> [DisplayModeInfo] {
        var seen = Set<String>()
        return modes.filter { mode in
            let key = "\(mode.width)x\(mode.height)_\(mode.isHiDPI)"
            return seen.insert(key).inserted
        }
    }
}

// MARK: - Reusable Row Components

struct MenuRow<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.callout)
            Spacer()
            content
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value)
                .font(.system(size: 12, design: .monospaced))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}

struct ToggleRow: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    init(_ label: String, isOn: Bool, action: @escaping () -> Void) {
        self.label = label
        self.isOn = isOn
        self.action = action
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.callout)
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { _ in action() }))
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}

struct RefreshRateRow: View {
    let manager: DisplayManager
    let display: ExternalDisplay

    var body: some View {
        let rates = availableRates
        if !rates.isEmpty {
            rateButtons(rates: rates)
        }
    }

    private func rateButtons(rates: [Double]) -> some View {
        let currentHz: Double = manager.currentMode?.refreshRate ?? 0
        return HStack {
            Text("Refresh Rate")
                .font(.callout)
            Spacer()
            ForEach(rates, id: \.self) { hz in
                rateButton(hz: hz, isActive: abs(currentHz - hz) < 1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func rateButton(hz: Double, isActive: Bool) -> some View {
        Button("\(Int(hz))Hz") {
            manager.switchRefreshRate(hz)
        }
        .buttonStyle(.bordered)
        .tint(isActive ? .blue : .gray)
        .controlSize(.mini)
    }

    private var availableRates: [Double] {
        Array(Set(manager.availableModes
            .filter { !$0.isHiDPI && $0.width == display.nativeWidth }
            .map { $0.refreshRate }))
            .sorted(by: >)
    }
}

struct MenuButton: View {
    let label: String
    let icon: String
    let tint: Color
    let action: () -> Void

    init(_ label: String, icon: String, tint: Color = .blue, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}
