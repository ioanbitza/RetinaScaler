import Foundation
import os.log

private let logger = Logger(subsystem: "com.astralbyte.retinascaler", category: "LaunchAtLogin")

enum LaunchAtLogin {

    private static let plistPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/LaunchAgents/com.astralbyte.retinascaler.plist"
    }()

    private static var appPath: String {
        Bundle.main.bundlePath
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistPath)
    }

    static func enable() {
        let launchAgentsDir = (plistPath as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create LaunchAgents directory: \(error.localizedDescription)")
            return
        }

        let plist: [String: Any] = [
            "Label": "com.astralbyte.retinascaler",
            "ProgramArguments": ["\(appPath)/Contents/MacOS/RetinaScaler"],
            "RunAtLoad": true,
            "KeepAlive": false,
        ]

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: URL(fileURLWithPath: plistPath))
            logger.info("Launch at login enabled")
        } catch {
            logger.error("Failed to write launch agent plist: \(error.localizedDescription)")
        }
    }

    static func disable() {
        do {
            try FileManager.default.removeItem(atPath: plistPath)
            logger.info("Launch at login disabled")
        } catch {
            logger.warning("Failed to remove launch agent plist: \(error.localizedDescription)")
        }
    }

    static func toggle() {
        if isEnabled { disable() } else { enable() }
    }
}
