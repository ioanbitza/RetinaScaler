import AppKit
import Carbon.HIToolbox
import Foundation

/// Manages global keyboard shortcuts for display control.
/// Requires Accessibility permissions (System Settings → Privacy → Accessibility).
@Observable
class HotkeyManager {
    var isListening = false

    // Callbacks
    var onToggleHiDPI: (() -> Void)?
    var onToggleHDR: (() -> Void)?
    var onBrightnessUp: (() -> Void)?
    var onBrightnessDown: (() -> Void)?
    var onRefreshRateCycle: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// Default shortcuts (Ctrl+Option+...)
    /// - H: Toggle HiDPI
    /// - R: Toggle HDR
    /// - Up: Brightness up
    /// - Down: Brightness down
    /// - F: Cycle refresh rate
    func start() {
        guard !isListening else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }

        isListening = true
    }

    func stop() {
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
        globalMonitor = nil
        localMonitor = nil
        isListening = false
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Require Ctrl+Option (⌃⌥) modifier
        let requiredFlags: NSEvent.ModifierFlags = [.control, .option]
        guard event.modifierFlags.contains(requiredFlags) else { return }

        switch event.keyCode {
        case UInt16(kVK_ANSI_H): // Ctrl+Option+H → Toggle HiDPI
            onToggleHiDPI?()
        case UInt16(kVK_ANSI_R): // Ctrl+Option+R → Toggle HDR
            onToggleHDR?()
        case UInt16(kVK_UpArrow): // Ctrl+Option+Up → Brightness up
            onBrightnessUp?()
        case UInt16(kVK_DownArrow): // Ctrl+Option+Down → Brightness down
            onBrightnessDown?()
        case UInt16(kVK_ANSI_F): // Ctrl+Option+F → Cycle refresh rate
            onRefreshRateCycle?()
        default:
            break
        }
    }

    deinit {
        stop()
    }
}
