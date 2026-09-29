import Foundation
import Routing

/// UserDefaults keys and the values derived from them.
enum Preferences {
    static let activeProjectPath = "activeProjectPath"
    static let claudePathOverride = "claudePathOverride"
    static let gateThreshold = "gateThreshold"
    static let choiceThreshold = "choiceThreshold"
    static let checkForUpdates = "checkForUpdates"
    static let lastUpdateCheck = "lastUpdateCheck"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [gateThreshold: 0.5, choiceThreshold: 0.35, checkForUpdates: true])
    }

    static var thresholds: RoutingThresholds {
        RoutingThresholds(gate: Float(UserDefaults.standard.double(forKey: gateThreshold)),
                          choice: Float(UserDefaults.standard.double(forKey: choiceThreshold)))
    }

    static var activeProject: URL? {
        UserDefaults.standard.string(forKey: activeProjectPath).map { URL(fileURLWithPath: $0) }
    }
}
