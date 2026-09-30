import Foundation

/// Files that launch or run something when opened: apps, installers, scripts, and link files that can open any
/// URL. "open <name>" shows these in Finder instead, so a spoken name can never run code.
public enum LaunchableFile {
    static let extensions: Set<String> = [
        // Apps, installers and plug-ins
        "app", "pkg", "mpkg", "prefpane", "saver", "qlgenerator", "mdimporter", "plugin", "bundle", "osax", "xpc", "kext",
        // Scripts and Terminal files
        "command", "tool", "terminal", "sh", "bash", "zsh", "ksh", "csh", "tcsh", "fish", "py", "pyw", "pl", "rb",
        "php", "jar", "scpt", "scptd", "applescript", "workflow", "action", "shortcut",
        // Link files that open any URL
        "webloc", "inetloc", "fileloc", "url",
    ]

    public static func mightRunCode(_ url: URL) -> Bool {
        if extensions.contains(url.pathExtension.lowercased()) { return true }
        // An executable file with no extension (a Unix program) opens in Terminal and runs.
        var isFolder: ObjCBool = false
        return url.pathExtension.isEmpty
            && FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) && !isFolder.boolValue
            && FileManager.default.isExecutableFile(atPath: url.path)
    }
}
