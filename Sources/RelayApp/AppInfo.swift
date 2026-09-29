import Foundation

/// The version and build number from Relay.app's Info.plist (absent when run with `swift run`).
enum AppInfo {
    static var version: String? { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }
    static var build: String? { Bundle.main.infoDictionary?["CFBundleVersion"] as? String }

    static var displayText: String {
        guard let version else { return "Relay (development build)" }
        return build.map { "Relay \(version) (build \($0))" } ?? "Relay \(version)"
    }
}
