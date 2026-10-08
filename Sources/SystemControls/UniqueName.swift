import Darwin
import Foundation

/// The first free name in a folder, numbered like Finder: "invoices", "invoices 2", "todo 2.txt".
public enum UniqueName {
    public static func available(for name: String, in folder: URL) -> URL {
        candidates(for: name, in: folder).first { !exists($0) }!
    }

    /// Creates a new file or folder at the first free name, never replacing anything: each name is created
    /// exclusively (O_EXCL / mkdir, not following symlinks), so a name that appears meanwhile, or a symlink
    /// even one pointing nowhere, just moves on to the next number.
    public static func create(_ name: String, in folder: URL, folder isFolder: Bool) throws -> URL {
        for candidate in candidates(for: name, in: folder).prefix(10_000) where !exists(candidate) {
            let result = isFolder
                ? mkdir(candidate.path, 0o755)
                : open(candidate.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o644)
            if result >= 0 {
                if !isFolder { close(result) }
                return candidate
            }
            guard errno == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        throw POSIXError(.EEXIST)
    }

    static func candidates(for name: String, in folder: URL) -> some Sequence<URL> {
        let ext = (name as NSString).pathExtension
        let base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        return (1...).lazy.map { number in
            number == 1 ? folder.appendingPathComponent(name)
                : folder.appendingPathComponent(ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
        }
    }

    /// Exists in any form, including a symlink whose target is missing (lstat, not stat).
    static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }
}
