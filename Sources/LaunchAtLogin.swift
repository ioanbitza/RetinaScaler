import Foundation

enum LaunchAtLogin {

    private static let plistPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/LaunchAgents/com.astralbyte.retinascaler.plist"
    }()

    private static let appPath: String = {
        Bundle.main.bundlePath
    }()

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistPath)
    }

    static func enable() {
        let launchAgentsDir = (plistPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": "com.astralbyte.retinascaler",
            "ProgramArguments": ["\(appPath)/Contents/MacOS/RetinaScaler"],
            "RunAtLoad": true,
            "KeepAlive": false,
        ]

        let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try? data?.write(to: URL(fileURLWithPath: plistPath))
    }

    static func disable() {
        try? FileManager.default.removeItem(atPath: plistPath)
    }

    static func toggle() {
        if isEnabled { disable() } else { enable() }
    }
}
