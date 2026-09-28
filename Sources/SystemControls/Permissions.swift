import ApplicationServices
import CoreGraphics

/// Permission checks, run each time so a newly granted permission works without relaunching Relay.
enum Permissions {
    /// Shows the system Accessibility prompt the first time; throws until the user allows Relay.
    static func requireAccessibility() throws {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { throw SystemControlError.accessibilityDenied }
    }

    static func requireScreenRecording() throws {
        if CGPreflightScreenCaptureAccess() { return }
        _ = CGRequestScreenCaptureAccess()
        throw SystemControlError.screenRecordingDenied
    }
}
