import Extraction
import Foundation

/// Switches dark mode through System Events (needs Automation permission for System Events).
enum AppearanceScript {
    static func source(for mode: SwitchCommand) -> String {
        let value = switch mode {
        case .on: "true"
        case .off: "false"
        case .toggle: "not dark mode"
        }
        return "tell application \"System Events\" to tell appearance preferences to set dark mode to \(value)"
    }

    @MainActor static func run(_ mode: SwitchCommand) throws {
        var error: NSDictionary?
        NSAppleScript(source: source(for: mode))?.executeAndReturnError(&error)
        guard let error else { return }
        let code = error[NSAppleScript.errorNumber] as? Int ?? 0
        if code == -1743 { throw SystemControlError.automationDenied("System Events") } // errAEEventNotPermitted
        throw SystemControlError.failed(error[NSAppleScript.errorMessage] as? String ?? "AppleScript error \(code)")
    }
}
