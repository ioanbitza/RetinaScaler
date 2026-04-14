import AppKit
import Carbon.HIToolbox
import Foundation
import os.log

private let logger = Logger(subsystem: "com.astralbyte.retinascaler", category: "Hotkeys")

/// Manages global keyboard shortcuts for display control.
/// Requires Accessibility permissions (System Settings > Privacy > Accessibility).
@Observable
class HotkeyManager {
    var isListening = false

    // Callbacks -- these are dispatched to main thread by DisplayManager.setupHotkeys()
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
        logger.info("Hotkey monitoring started")
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isListening = false
        logger.info("Hotkey monitoring stopped")
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Require Ctrl+Option modifier combination
        let requiredFlags: NSEvent.ModifierFlags = [.control, .option]
        guard event.modifierFlags.contains(requiredFlags) else { return }

        // Ignore if other modifiers (Cmd, Shift) are also pressed to avoid conflicts
        let extraFlags: NSEvent.ModifierFlags = [.command, .shift]
        guard !event.modifierFlags.contains(extraFlags) else { return }

        switch event.keyCode {
        case UInt16(kVK_ANSI_H):
            onToggleHiDPI?()
        case UInt16(kVK_ANSI_R):
            onToggleHDR?()
        case UInt16(kVK_UpArrow):
            onBrightnessUp?()
        case UInt16(kVK_DownArrow):
            onBrightnessDown?()
        case UInt16(kVK_ANSI_F):
            onRefreshRateCycle?()
        default:
            break
        }
    }

    deinit {
        stop()
    }
}
