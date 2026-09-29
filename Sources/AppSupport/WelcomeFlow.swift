import Foundation

public enum WelcomeStep: Int, CaseIterable, Sendable {
    case meet, setup, tryIt
}

/// Which welcome step is showing, and whether the welcome has been seen.
public struct WelcomeFlow: Equatable, Sendable {
    public static let seenKey = "welcomeSeen"

    public private(set) var step: WelcomeStep

    public init(step: WelcomeStep = .meet) {
        self.step = step
    }

    public var isFirst: Bool { step == WelcomeStep.allCases.first }
    public var isLast: Bool { step == WelcomeStep.allCases.last }

    public mutating func next() {
        step = WelcomeStep(rawValue: step.rawValue + 1) ?? step
    }

    public mutating func back() {
        step = WelcomeStep(rawValue: step.rawValue - 1) ?? step
    }

    public static func shouldShowOnLaunch(_ defaults: UserDefaults) -> Bool {
        !defaults.bool(forKey: seenKey)
    }

    public static func markSeen(_ defaults: UserDefaults) {
        defaults.set(true, forKey: seenKey)
    }
}

public enum PermissionRow {
    public enum State: Equatable, Sendable {
        case granted, notAsked, denied

        public var buttonTitle: String? {
            switch self {
            case .granted: nil
            case .notAsked: "Allow"
            case .denied: "Open Settings"
            }
        }
    }
}
