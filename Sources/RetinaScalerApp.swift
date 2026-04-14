import AppKit
import SwiftUI

@main
struct RetinaScalerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("RetinaScaler", systemImage: "display.2") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}

/// Handles app lifecycle events to ensure virtual display cleanup on quit, crash, and signals.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        installSignalHandlers()
        // Save PID so an external watchdog (or next launch) can detect stale state
        savePIDFile()
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanupVirtualDisplay()
        removePIDFile()
    }

    // MARK: - Signal Handlers

    /// Installs handlers for SIGTERM, SIGINT, and SIGHUP to ensure cleanup on forced termination.
    /// SIGKILL cannot be caught -- that's the one case where ghost displays may remain.
    private func installSignalHandlers() {
        let signals: [Int32] = [SIGTERM, SIGINT, SIGHUP]
        for sig in signals {
            signal(sig) { _ in
                VirtualDisplayManager.disable()
                // Re-raise to allow default behavior (process exit)
                signal(SIGTERM, SIG_DFL)
                raise(SIGTERM)
            }
        }
    }

    // MARK: - PID File

    /// Writes the current PID to a file so the next launch can detect a previous crash.
    /// If a stale PID file exists on launch, we know the previous instance did not exit cleanly.
    private func savePIDFile() {
        let pidPath = pidFilePath
        let pid = ProcessInfo.processInfo.processIdentifier

        // Check for stale PID from a previous crash
        if let oldPIDString = try? String(contentsOfFile: pidPath, encoding: .utf8),
           let oldPID = Int32(oldPIDString.trimmingCharacters(in: .whitespacesAndNewlines)) {
            // Check if old process is still running
            if kill(oldPID, 0) != 0 {
                // Old process is dead -- it crashed. Clean up any ghost virtual display override.
                cleanupStaleVirtualOverride()
            }
        }

        try? "\(pid)".write(toFile: pidPath, atomically: true, encoding: .utf8)
    }

    private func removePIDFile() {
        try? FileManager.default.removeItem(atPath: pidFilePath)
    }

    private var pidFilePath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("RetinaScaler").path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/retinascaler.pid"
    }

    // MARK: - Cleanup

    private func cleanupVirtualDisplay() {
        if VirtualDisplayManager.isActive {
            VirtualDisplayManager.disable()
        }
    }

    /// Removes the virtual display override plist that may have been left behind by a crash.
    private func cleanupStaleVirtualOverride() {
        let overridePath = "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-4c2d/DisplayProductID-fffe"
        if FileManager.default.fileExists(atPath: overridePath) {
            let script = "do shell script \"rm -f '\(overridePath)'\" with administrator privileges"
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
        }
    }
}
