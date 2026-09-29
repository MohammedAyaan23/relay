import Foundation

/// Saves the hotkey as a JSON string, and migrates the value the KeyboardShortcuts package used to save.
public enum HotkeyStore {
    public static let key = "hotkey"
    public static let legacyKey = "KeyboardShortcuts_toggleListening"

    private struct Legacy: Decodable {
        let carbonKeyCode: UInt32
        let carbonModifiers: UInt32
    }

    public static func load(from defaults: UserDefaults) -> Hotkey {
        if defaults.object(forKey: key) != nil {
            return decode(Hotkey.self, from: defaults.object(forKey: key)).flatMap { $0.isValid ? $0 : nil } ?? .default
        }
        if let legacy = decode(Legacy.self, from: defaults.object(forKey: legacyKey)) {
            let hotkey = Hotkey(keyCode: legacy.carbonKeyCode, modifiers: legacy.carbonModifiers)
            if hotkey.isValid {
                save(hotkey, to: defaults)
                return hotkey
            }
        }
        return .default
    }

    public static func save(_ hotkey: Hotkey, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(hotkey), let text = String(data: data, encoding: .utf8) else { return }
        defaults.set(text, forKey: key)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from value: Any?) -> T? {
        let data: Data? = switch value {
        case let text as String: text.data(using: .utf8)
        case let data as Data: data
        default: nil
        }
        return data.flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
