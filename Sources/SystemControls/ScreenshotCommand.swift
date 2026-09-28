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

    /// Area shots wait for the user to drag, so they get longer than the usual 15 s.
    public static func timeout(for options: ScreenshotOptions) -> Duration {
        options.target == .area ? .seconds(60) : .seconds(15)
    }
}
