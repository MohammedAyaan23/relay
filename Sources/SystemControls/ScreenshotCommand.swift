import Extraction
import Foundation

/// `screencapture` arguments for each screenshot variant (spec §3.3).
public enum ScreenshotCommand {
    public static func arguments(for options: ScreenshotOptions, file: URL?, windowID: Int?) -> [String] {
        var arguments = ["-x"]
        if options.toClipboard { arguments.append("-c") }
        switch options.target {
        case .screen: break
        case .window: if let windowID { arguments += ["-l", String(windowID)] }
        case .area: arguments += ["-i", "-s"]
        }
        if !options.toClipboard, let file { arguments.append(file.path) }
        return arguments
    }

    /// What a finished `screencapture` run means. A missing file after success is a cancel; so is a
    /// failed interactive area pick with no error text (Esc can end it with a non-zero status).
    public static func interpret(status: Int32, stderr: String, file: URL?, fileExists: Bool,
                                 target: ScreenshotOptions.Target) throws -> ScreenshotResult {
        guard status == 0 else {
            let reason = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if target == .area, reason.isEmpty, !fileExists { return .cancelled }
            throw SystemControlError.failed(reason.isEmpty ? "screencapture exited \(status)" : reason)
        }
        guard let file else { return .copied }
        return fileExists ? .saved(file) : .cancelled
    }

    /// Area shots wait for the user to drag, so they get longer than the usual 15 s.
    public static func timeout(for options: ScreenshotOptions) -> Duration {
        options.target == .area ? .seconds(60) : .seconds(15)
    }
}
