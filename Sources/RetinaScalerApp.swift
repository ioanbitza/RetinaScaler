import AppKit
import SwiftUI
import os.log

private let appLogger = Logger(subsystem: "com.astralbyte.retinascaler", category: "App")

@main
struct RetinaScalerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let menuBarIcon: NSImage?

    init() {
        let icon = Self.loadMenuBarIcon()
        menuBarIcon = icon
        appLogger.warning("Menu bar icon loaded: \(icon != nil)")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            if let icon = menuBarIcon {
                Image(nsImage: icon)
                    .renderingMode(.template)
            } else {
                Image(systemName: "eye.fill")
                    .font(.system(size: 14))
            }
        }
        .menuBarExtraStyle(.window)
    }

    private static func loadMenuBarIcon() -> NSImage? {
        var dirs: [String] = []

        if let exec = Bundle.main.executableURL {
            dirs.append(exec.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources").path)
            dirs.append(exec.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Assets").path)
        }
        if let rp = Bundle.main.resourcePath { dirs.append(rp) }
        dirs.append(FileManager.default.currentDirectoryPath + "/Assets")

        for dir in dirs {
            let path = dir + "/MenuBarIcon@2x.png"
            let exists = FileManager.default.fileExists(atPath: path)
            appLogger.warning("Icon search: \(path) exists=\(exists)")
            if let img = NSImage(contentsOfFile: path) {
                // Menu bar icons should be 18pt tall, width proportional to aspect
                let rep = img.representations.first
                let pxW = CGFloat(rep?.pixelsWide ?? 36)
                let pxH = CGFloat(rep?.pixelsHigh ?? 18)
                let aspect = pxW / pxH
                img.size = NSSize(width: 18 * aspect, height: 18)
                img.isTemplate = true
                return img
            }
        }
        appLogger.error("Failed to load menu bar icon from any path")
        return nil
    }
}


/// Handles app lifecycle events to ensure virtual display cleanup on quit, crash, and signals.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        installSignalHandlers()
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
