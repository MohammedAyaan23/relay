/// Picks the front window of an app from `CGWindowListCopyWindowInfo` output (front-to-back order).
public enum WindowList {
    public static func frontWindowID(pid: Int32, windows: [[String: Any]]) -> Int? {
        windows.first { window in
            (window["kCGWindowOwnerPID"] as? Int).map(Int32.init) == pid
                && (window["kCGWindowLayer"] as? Int) == 0
                && (window["kCGWindowOwnerName"] as? String) != "Relay"
        }?["kCGWindowNumber"] as? Int
    }
}
