/// "10 minutes", "1 hour 30 minutes", "1 minute 30 seconds". Seconds are left out once there are hours.
public enum DurationText {
    public static func describe(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        var parts: [String] = []
        if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if minutes > 0 { parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes") }
        if remainder > 0, hours == 0 { parts.append(remainder == 1 ? "1 second" : "\(remainder) seconds") }
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: " ")
    }
}
