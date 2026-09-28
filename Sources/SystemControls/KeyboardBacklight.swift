import Foundation

/// The keyboard backlight through Apple's private CoreBrightness framework, the service behind Control
/// Center's keyboard slider. It needs no permission and sets exact levels. Because it's undocumented, every
/// piece is checked: `make()` returns nil if anything is missing, so callers fall back to key presses.
final class KeyboardBacklight {
    private typealias Get = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias Set = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    private let client: NSObject
    private let keyboard: UInt64

    private init(client: NSObject, keyboard: UInt64) {
        self.client = client
        self.keyboard = keyboard
    }

    static func make() -> KeyboardBacklight? {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return nil }
        let client = type.init()
        let ids = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard client.responds(to: ids),
              client.responds(to: NSSelectorFromString("brightnessForKeyboard:")),
              client.responds(to: NSSelectorFromString("setBrightness:forKeyboard:")),
              let keyboard = (client.perform(ids)?.takeRetainedValue() as? [NSNumber])?.first
        else { return nil }
        return KeyboardBacklight(client: client, keyboard: keyboard.uint64Value)
    }

    func level() -> Double {
        let selector = NSSelectorFromString("brightnessForKeyboard:")
        let get = unsafeBitCast(client.method(for: selector), to: Get.self)
        return Double(get(client, selector, keyboard))
    }

    func set(_ level: Double) -> Bool {
        let selector = NSSelectorFromString("setBrightness:forKeyboard:")
        let set = unsafeBitCast(client.method(for: selector), to: Set.self)
        return set(client, selector, Float(min(max(level, 0), 1)), keyboard)
    }
}
