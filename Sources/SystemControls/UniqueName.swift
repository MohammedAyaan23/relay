import Foundation

/// The first free name in a folder, numbered like Finder: "invoices", "invoices 2", "todo 2.txt".
public enum UniqueName {
    public static func available(for name: String, in folder: URL) -> URL {
        let fileManager = FileManager.default
        let ext = (name as NSString).pathExtension
        let base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var candidate = folder.appendingPathComponent(name)
        var number = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            number += 1
        }
        return candidate
    }
}
