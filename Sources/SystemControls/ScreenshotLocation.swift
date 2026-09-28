import Foundation

/// Where and under what name screenshots are saved, matching macOS's own screenshot tool.
public enum ScreenshotLocation {
    /// `defaultsValue` is `com.apple.screencapture`'s `location`; unset or blank means the Desktop.
    public static func folder(defaultsValue: String?, home: URL) -> URL {
        guard let value = defaultsValue?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return home.appendingPathComponent("Desktop")
        }
        if value == "~" { return home }
        if value.hasPrefix("~/") { return home.appendingPathComponent(String(value.dropFirst(2))) }
        return URL(fileURLWithPath: value)
    }

    public static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: date)).png"
    }
}
