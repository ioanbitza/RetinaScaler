import SwiftUI

// MARK: - Design Tokens

private enum MenuTheme {
    static let panelPadding: CGFloat = 10
    static let sectionSpacing: CGFloat = 10
    static let cardCorner: CGFloat = 10
    static let cardPadding: CGFloat = 10
    static let rowVertical: CGFloat = 5
    static let rowHorizontal: CGFloat = 10

    static let cardBackground = Color.white.opacity(0.04)
    static let cardBorder = Color.white.opacity(0.06)
    static let subtleDivider = Color.white.opacity(0.08)
    static let accentHiDPI = Color.green
    static let accentStandard = Color.blue
    static let accentHDR = Color.orange
    static let accentDanger = Color.red
}

// MARK: - Main Menu Bar View

struct MenuBarView: View {
    @State private var manager = DisplayManager()

    var body: some View {
        ScrollView {
            VStack(spacing: MenuTheme.sectionSpacing) {
                ForEach(manager.displays) { display in
                    DisplaySection(display: display, manager: manager)
                }

                if manager.displays.isEmpty {
                    emptyView
                }

                settingsCard
            }
            .padding(MenuTheme.panelPadding)
        }
        .frame(width: 360, height: 660)
        .onAppear {
            manager.refresh()
            manager.setupHotkeys()
        }
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No displays detected")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Connect a display or click Refresh")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .cardStyle()
    }

    // MARK: - Settings Card

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Settings header
            TappableSection {
                Label("Settings", systemImage: "gear")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            } content: {
                VStack(alignment: .leading, spacing: 0) {
                    SectionDivider()

                    if manager.nightShiftAvailable {
                        ToggleRow("Night Shift", icon: "moon.fill", isOn: manager.nightShiftEnabled) {
                            manager.toggleNightShift()
                        }
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

                    HStack(spacing: 8) {
                        shortcutHint("^⌥H", label: "HiDPI")
                        shortcutHint("^⌥R", label: "HDR")
                        shortcutHint("^⌥↑↓", label: "Bright")
                        shortcutHint("^⌥F", label: "Hz")
                    }
                    .padding(.horizontal, MenuTheme.rowHorizontal)
                    .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, MenuTheme.cardPadding)
            .padding(.vertical, 8)

            // Status message
            if let msg = manager.statusMessage {
                SectionDivider()
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: 10))
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, MenuTheme.cardPadding + 2)
                .padding(.vertical, 8)
            }

            // Virtual Displays management
            let virtualDisplays = VirtualDisplayManager.listVirtualDisplays()
            if !virtualDisplays.isEmpty {
                SectionDivider()

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "display.and.arrow.down")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                        Text("Virtual Displays (\(virtualDisplays.count))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, MenuTheme.rowHorizontal)
                    .padding(.vertical, 4)

                    ForEach(Array(virtualDisplays.enumerated()), id: \.offset) { _, vd in
                        HStack(spacing: 6) {
                            Image(systemName: "display")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text("\(vd.width)×\(vd.height)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("ID: \(vd.id)")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .padding(.horizontal, MenuTheme.rowHorizontal + 4)
                        .padding(.vertical, 2)
                    }

                    ActionRow("Remove All Virtual Displays", icon: "trash", tint: .orange) {
                        VirtualDisplayManager.disable()
                        VirtualDisplayManager.forceCleanupOrphanedDisplays()
                        manager.refresh()
                    }
                }
            }

            SectionDivider()

            // Action buttons
            ActionRow("Refresh Displays", icon: "arrow.clockwise", tint: .primary) {
                manager.refresh()
            }

            ActionRow("Quit RetinaScaler", icon: "power", tint: MenuTheme.accentDanger) {
                manager.disableHiDPI()
                manager.hotkeyManager.stop()
                NSApplication.shared.terminate(nil)
            }
        }
        .cardStyle()
    }

    private func shortcutHint(_ keys: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(keys)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
        }
    }
}

// MARK: - Per-Display Section

struct DisplaySection: View {
    let display: ExternalDisplay
    @Bindable var manager: DisplayManager
    @State private var expanded = true
    @State private var displayModes: [DisplayModeInfo] = []
    @State private var displayCurrentMode: DisplayModeInfo?
    /// Cached physical display modes — captured before VD activation, used for
    /// HiDPI Native and VD lists so they don't change when VD is active
    @State private var physicalModes: [DisplayModeInfo] = []

    private var displayIcon: String {
        display.isBuiltIn ? "laptopcomputer" : "display"
    }

    private var accentColor: Color {
        display.isBuiltIn ? .blue : .purple
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Display Header
            displayHeader
                .padding(.horizontal, MenuTheme.cardPadding)
                .padding(.top, MenuTheme.cardPadding)
                .padding(.bottom, 6)

            if expanded {
                SectionDivider()

                VStack(alignment: .leading, spacing: 0) {
                    displayControls
                }
                .padding(.bottom, 4)
            }
        }
        .cardStyle()
        .onAppear { refreshDisplayModes() }
        .onChange(of: manager.hiDPIActive) { refreshDisplayModes() }
        .onChange(of: manager.statusMessage) { refreshDisplayModes() }
        .onChange(of: manager.isProcessing) { if !manager.isProcessing { refreshDisplayModes() } }
    }

    private func refreshDisplayModes() {
        displayModes = DisplayModeService.availableModes(for: display.id)

        // Cache physical modes when VD is NOT active — these represent the
        // real display capabilities, unaffected by VD mirror modes
        if !VirtualDisplayManager.isActive || physicalModes.isEmpty {
            physicalModes = displayModes
        }

        // When VD is active, read current mode from VD (mirror master)
        if !display.isBuiltIn && VirtualDisplayManager.isActive {
            let vdID = VirtualDisplayManager.virtualDisplayID
            if vdID != 0 {
                displayCurrentMode = DisplayModeService.currentMode(for: vdID)
                return
            }
        }
        displayCurrentMode = DisplayModeService.currentMode(for: display.id)
    }

    // MARK: - Header

    private var displayHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                // Display icon with accent
                Image(systemName: displayIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(accentColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(display.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    if let current = displayCurrentMode {
                        Text("\(current.width)x\(current.height) @ \(Int(current.refreshRate))Hz")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // Status badges
                HStack(spacing: 4) {
                    if !display.isBuiltIn && manager.hiDPIActive {
                        StatusBadge("HiDPI", color: MenuTheme.accentHiDPI)
                    }
                    if display.isBuiltIn {
                        StatusBadge("Built-in", color: .secondary)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Display Controls

    @ViewBuilder
    private var displayControls: some View {
        // HiDPI section (external only)
        if !display.isBuiltIn {
            hiDPISection

            SectionDivider()
        }

        // Resolution picker
        resolutionPicker

        SectionDivider()

        // Refresh Rate
        refreshRatePicker

        // HDR (external only)
        if !display.isBuiltIn && manager.hdrAvailable {
            ToggleRow("HDR Mode", icon: "sun.max.trianglebadge.exclamationmark", isOn: manager.hdrEnabled) {
                manager.toggleHDR()
            }
        }


        // Brightness & Contrast
        if manager.isDDCAvailable(for: display.id) {
            SectionDivider()
            brightnessSlider
            if manager.perDisplayUsesDDC[display.id] == true {
                contrastSlider
            }
        }

        // Per-display tools
        SectionDivider()
        displayToolsSection
    }

    // MARK: - HiDPI Section

    @ViewBuilder
    private var hiDPISection: some View {
        // Use physicalModes (cached before VD activation) for stable lists
        let modesForLists = physicalModes.isEmpty ? displayModes : physicalModes

        // Native HiDPI = modes where the physical display already supports HiDPI
        let nativeHiDPI = deduplicate(modesForLists
            .filter { $0.isHiDPI && $0.width >= 1920 && $0.height >= 540 }
            .sorted { $0.width > $1.width })

        // Virtual Display = standard modes that DON'T have a native HiDPI counterpart
        let nativeHiDPIWidths = Set(nativeHiDPI.map { $0.width })
        let virtualResolutions = deduplicate(modesForLists
            .filter { !$0.isHiDPI && $0.width >= display.nativeWidth / 2 && $0.height >= 540
                && !nativeHiDPIWidths.contains($0.width) }
            .sorted { $0.width > $1.width })
            .map { mode -> (logical: (Int, Int), backing: (Int, Int), label: String) in
                let pct = Int(round(Double(mode.height) / Double(display.nativeHeight) * 100))
                let label = mode.width == display.nativeWidth ? "Native HiDPI" : "\(pct)% scaled"
                return (logical: (mode.width, mode.height), backing: (mode.width * 2, mode.height * 2), label: label)
            }

        // Disable HiDPI button when virtual display is active
        if manager.hiDPIActive {
            MenuButton("Disable Virtual HiDPI", icon: "xmark.circle", tint: MenuTheme.accentDanger) {
                manager.disableHiDPI()
                refreshDisplayModes()
            }
        }

        // Native HiDPI section
        if !nativeHiDPI.isEmpty {
            TappableSection {
                HStack(spacing: 6) {
                    Label("HiDPI Native", systemImage: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                    Text("@240Hz")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.12), in: Capsule())
                }
            } content: {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(nativeHiDPI) { mode in
                        hiDPIRow(mode, isVirtual: false)
                    }
                }
            }
            .padding(.horizontal, MenuTheme.rowHorizontal)
            .padding(.vertical, MenuTheme.rowVertical)
        }

        // Virtual Display HiDPI section (higher resolutions)
        if !virtualResolutions.isEmpty {
            SectionDivider()

            TappableSection {
                HStack(spacing: 6) {
                    Label("HiDPI Virtual Display", systemImage: "display.and.arrow.down")
                        .font(.system(size: 12, weight: .medium))
                    if manager.hiDPIActive {
                        Text("Active")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.15), in: Capsule())
                    }
                }
            } content: {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(virtualResolutions.enumerated()), id: \.offset) { _, res in
                        virtualHiDPIRow(logW: res.logical.0, logH: res.logical.1, label: res.label)
                    }
                }
            }
            .padding(.horizontal, MenuTheme.rowHorizontal)
            .padding(.vertical, MenuTheme.rowVertical)
        }

        // Fallback if no HiDPI modes at all
        if nativeHiDPI.isEmpty && virtualResolutions.isEmpty {
            MenuButton("Install HiDPI Overrides", icon: "sparkles", tint: MenuTheme.accentHiDPI) {
                manager.enableHiDPI(for: display)
                refreshDisplayModes()
            }
        }
    }

    private func hiDPIRow(_ mode: DisplayModeInfo, isVirtual: Bool) -> some View {
        // Native HiDPI rows should only show checkmark when VD is NOT active
        // Virtual HiDPI rows should only show checkmark when VD IS active
        let resolutionMatches = displayCurrentMode?.width == mode.width
            && displayCurrentMode?.height == mode.height
            && displayCurrentMode?.isHiDPI == mode.isHiDPI
        let isCurrent = resolutionMatches && !manager.hiDPIActive

        return Button {
            // Disable VD first if active — user chose a native mode
            if manager.hiDPIActive {
                manager.disableHiDPI()
            }
            manager.switchMode(to: mode, for: display)
            refreshDisplayModes()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isCurrent ? "circle.inset.filled" : "circle")
                    .font(.system(size: 10))
                    .foregroundStyle(isCurrent ? MenuTheme.accentHiDPI : Color.gray)

                Text(verbatim: "\(mode.width)×\(mode.height)")
                    .font(.system(size: 12, design: .monospaced))

                Text("HiDPI")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.green.opacity(0.15), in: Capsule())

                Text(verbatim: "@\(Int(mode.refreshRate))Hz")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer()

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.caption2.bold())
                        .foregroundStyle(MenuTheme.accentHiDPI)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isCurrent ? MenuTheme.accentHiDPI.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private func virtualHiDPIRow(logW: Int, logH: Int, label: String) -> some View {
        let isActive = manager.hiDPIActive
            && displayCurrentMode?.width == logW
            && displayCurrentMode?.height == logH

        return Button {
            manager.enableHiDPI(for: display, logicalWidth: logW, logicalHeight: logH)
            refreshDisplayModes()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isActive ? "circle.inset.filled" : "circle")
                    .font(.system(size: 10))
                    .foregroundStyle(isActive ? Color.purple : Color.gray)

                Text(verbatim: "\(logW)×\(logH)")
                    .font(.system(size: 12, design: .monospaced))

                Text("HiDPI")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.purple.opacity(0.15), in: Capsule())

                Text(verbatim: label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer()

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.caption2.bold())
                        .foregroundStyle(.purple)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isActive ? Color.purple.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Per-Display Tools

    private var displayToolsSection: some View {
        TappableSection {
            Label("Tools", systemImage: "wrench.and.screwdriver")
                .font(.system(size: 12, weight: .medium))
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if CGDisplayIsMain(display.id) != 0 {
                    MenuRow("Main Display") {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    }
                } else {
                    ActionRow("Set as Main Display", icon: "display", tint: .blue) {
                        manager.setAsMainDisplay(for: display)
                    }
                }

                if !display.isBuiltIn {
                    MenuRow("Arrangement") {
                        Menu("Position") {
                            ForEach(DisplayArrangement.Preset.allCases, id: \.rawValue) { preset in
                                Button(preset.rawValue) { manager.applyArrangement(preset, for: display) }
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(.horizontal, MenuTheme.cardPadding)
        .padding(.vertical, 6)
    }

    // MARK: - Resolution Picker

    private var resolutionPicker: some View {
        let minWidth = display.isBuiltIn ? 1024 : 2560
        let minHeight = display.isBuiltIn ? 640 : 720

        // On external displays, HiDPI modes are handled by the dedicated HiDPI section
        // so only show standard (non-HiDPI) modes here.
        // On built-in displays, show both since there's no virtual display involved.
        let showHiDPI = display.isBuiltIn

        let modesForList = physicalModes.isEmpty ? displayModes : physicalModes

        let hiDPIModes = showHiDPI ? deduplicate(modesForList
            .filter { $0.isHiDPI && $0.width >= minWidth }
            .sorted { $0.width > $1.width }) : []

        let stdModes = deduplicate(modesForList
            .filter { !$0.isHiDPI && $0.width >= minWidth && $0.height >= minHeight }
            .sorted { $0.width > $1.width })

        return TappableSection {
            Label("Resolutions", systemImage: "rectangle.split.3x1")
                .font(.system(size: 12, weight: .medium))
        } content: {
            VStack(alignment: .leading, spacing: 2) {
                if !hiDPIModes.isEmpty {
                    resolutionGroupHeader("HiDPI", color: MenuTheme.accentHiDPI, icon: "sparkles")
                    ForEach(hiDPIModes) { mode in
                        resolutionRow(mode)
                    }
                }
                if !stdModes.isEmpty {
                    if !hiDPIModes.isEmpty {
                        SectionDivider()
                            .padding(.vertical, 2)
                    }
                    resolutionGroupHeader("Standard", color: MenuTheme.accentStandard, icon: "rectangle.on.rectangle")
                    ForEach(stdModes.prefix(10)) { mode in
                        resolutionRow(mode)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .padding(.horizontal, MenuTheme.cardPadding)
        .padding(.vertical, 6)
    }

    private func resolutionGroupHeader(_ title: String, color: Color, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private func resolutionRow(_ mode: DisplayModeInfo) -> some View {
        let isCurrent = displayCurrentMode?.width == mode.width
            && displayCurrentMode?.height == mode.height
            && displayCurrentMode?.isHiDPI == mode.isHiDPI

        return Button {
            if manager.hiDPIActive {
                manager.disableHiDPI()
            }
            manager.switchMode(to: mode, for: display)
            refreshDisplayModes()
        } label: {
            HStack(spacing: 6) {
                // Active indicator
                Circle()
                    .fill(isCurrent ? (mode.isHiDPI ? MenuTheme.accentHiDPI : MenuTheme.accentStandard) : .clear)
                    .frame(width: 5, height: 5)

                Text(verbatim: "\(mode.width) x \(mode.height)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(isCurrent ? .primary : .secondary)

                if mode.isHiDPI {
                    Text("HiDPI")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(MenuTheme.accentHiDPI)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(MenuTheme.accentHiDPI.opacity(0.12), in: Capsule())
                }

                Spacer()

                Text(verbatim: "\(Int(mode.refreshRate))Hz")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(mode.isHiDPI ? MenuTheme.accentHiDPI : MenuTheme.accentStandard)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrent ? (mode.isHiDPI ? MenuTheme.accentHiDPI : MenuTheme.accentStandard).opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Refresh Rate

    @ViewBuilder
    private var refreshRatePicker: some View {
        let rates = availableRates
        if !rates.isEmpty {
            rateButtons(rates: rates)
        }
    }

    private func rateButtons(rates: [Double]) -> some View {
        let currentHz: Double = displayCurrentMode?.refreshRate ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            Text("Refresh Rate")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, MenuTheme.rowHorizontal)

            HStack(spacing: 6) {
                ForEach(rates, id: \.self) { hz in
                    let isActive = abs(currentHz - hz) < 1
                    Button {
                        switchRefreshRate(hz)
                    } label: {
                        Text("\(Int(hz))Hz")
                            .font(.system(size: 11, weight: isActive ? .bold : .regular, design: .monospaced))
                            .foregroundStyle(isActive ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isActive ? MenuTheme.accentStandard : Color.white.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(isActive ? MenuTheme.accentStandard.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, MenuTheme.rowHorizontal)
        }
        .padding(.vertical, 6)
    }

    private var availableRates: [Double] {
        let targetWidth = display.nativeWidth
        return Array(Set(displayModes
            .filter { !$0.isHiDPI && $0.width == targetWidth }
            .map { $0.refreshRate }))
            .sorted(by: >)
    }

    private func switchRefreshRate(_ hz: Double) {
        let w = display.nativeWidth
        let h = display.nativeHeight

        if let mode = displayModes.first(where: {
            $0.width == w && $0.height == h && !$0.isHiDPI && abs($0.refreshRate - hz) < 1
        }) {
            manager.switchMode(to: mode, for: display)
            refreshDisplayModes()
        }
    }

    // MARK: - Brightness / Contrast

    private var brightnessSlider: some View {
        let b = manager.brightness(for: display.id)
        return SliderRow(
            iconMin: "sun.min",
            iconMax: "sun.max.fill",
            iconMaxColor: .yellow,
            value: Binding(
                get: { Double(max(0, b)) },
                set: { manager.setBrightness(for: display.id, value: Int($0)) }
            ),
            range: 0...100,
            displayValue: "\(max(0, b))%"
        )
    }

    private var contrastSlider: some View {
        let c = manager.contrast(for: display.id)
        return SliderRow(
            iconMin: "circle.lefthalf.filled",
            iconMax: "circle.righthalf.filled",
            iconMaxColor: .primary,
            value: Binding(
                get: { Double(max(0, c)) },
                set: { manager.setContrast(for: display.id, value: Int($0)) }
            ),
            range: 0...100,
            displayValue: "\(max(0, c))%"
        )
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

// MARK: - Reusable Components

/// Card-style container modifier
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: MenuTheme.cardCorner)
                    .fill(MenuTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MenuTheme.cardCorner)
                    .strokeBorder(MenuTheme.cardBorder, lineWidth: 0.5)
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
}

/// Subtle section divider within cards
struct SectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(MenuTheme.subtleDivider)
            .frame(height: 0.5)
            .padding(.horizontal, MenuTheme.cardPadding)
    }
}

/// Status badge (HiDPI, Built-in, etc.)
struct StatusBadge: View {
    let label: String
    let color: Color

    init(_ label: String, color: Color) {
        self.label = label
        self.color = color
    }

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// Row with label and trailing content
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
                .font(.system(size: 12))
                .foregroundStyle(.primary)
            Spacer()
            content
        }
        .padding(.horizontal, MenuTheme.rowHorizontal)
        .padding(.vertical, MenuTheme.rowVertical)
    }
}

/// Info label-value row
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
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, MenuTheme.rowHorizontal)
        .padding(.vertical, 3)
    }
}

/// Toggle row with optional icon
struct ToggleRow: View {
    let label: String
    let icon: String?
    let isOn: Bool
    let action: () -> Void

    init(_ label: String, icon: String? = nil, isOn: Bool, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.isOn = isOn
        self.action = action
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            Text(label)
                .font(.system(size: 12))
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { _ in action() }))
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, MenuTheme.rowHorizontal)
        .padding(.vertical, MenuTheme.rowVertical)
    }
}

/// Standalone refresh rate row (kept for compatibility)
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
                .font(.system(size: 12))
            Spacer()
            ForEach(rates, id: \.self) { hz in
                rateButton(hz: hz, isActive: abs(currentHz - hz) < 1)
            }
        }
        .padding(.horizontal, MenuTheme.rowHorizontal)
        .padding(.vertical, MenuTheme.rowVertical)
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

/// Primary action button (Enable HiDPI, etc.)
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
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .foregroundStyle(tint == MenuTheme.accentDanger ? .white : tint)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(tint.opacity(tint == MenuTheme.accentDanger ? 0.2 : 0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, MenuTheme.rowHorizontal)
        .padding(.vertical, 4)
    }
}

/// Bottom-section action row (Refresh, Quit)
struct ActionRow: View {
    let label: String
    let icon: String
    let tint: Color
    let action: () -> Void

    init(_ label: String, icon: String, tint: Color = .primary, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundStyle(tint)
            .padding(.horizontal, MenuTheme.cardPadding)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Reusable slider row for brightness/contrast
struct SliderRow: View {
    let iconMin: String
    let iconMax: String
    let iconMaxColor: Color
    @Binding var value: Double
    let range: ClosedRange<Double>
    let displayValue: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconMin)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 14)
            Slider(value: $value, in: range)
                .controlSize(.small)
            Image(systemName: iconMax)
                .font(.system(size: 10))
                .foregroundStyle(iconMaxColor)
                .frame(width: 14)
            Text(verbatim: displayValue)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, MenuTheme.rowHorizontal)
        .padding(.vertical, 4)
    }
}

// MARK: - Tappable Disclosure Group

/// A DisclosureGroup where tapping anywhere on the header toggles expansion,
/// not just the tiny chevron.
struct TappableSection<Label: View, Content: View>: View {
    @State private var isExpanded: Bool
    let label: Label
    let content: () -> Content

    init(expanded: Bool = false, @ViewBuilder label: () -> Label, @ViewBuilder content: @escaping () -> Content) {
        _isExpanded = State(initialValue: expanded)
        self.label = label()
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    label
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .padding(.top, 4)
            }
        }
    }
}
