public enum RoutedIntent: String, CaseIterable, Sendable, Codable {
    case openApp = "open_app"
    case webSearch = "web_search"
    case askClaude = "ask_claude"
    case newClaudeSession = "new_claude_session"
    case volume
    case brightness
    case keyboardLight = "keyboard_light"
    case darkMode = "dark_mode"
    case focus
    case lock
    case screenshot
    case mediaPlayPause = "media_play_pause"
    case mediaNext = "media_next"
    case mediaPrevious = "media_previous"
    case quitApp = "quit_app"
    case hideApp = "hide_app"
    case minimizeWindow = "minimize_window"
    case fullScreen = "full_screen"
    case closeWindow = "close_window"
    case createFolder = "create_folder"
    case createFile = "create_file"
    case findFile = "find_file"
    case openFile = "open_file"
    case revealFile = "reveal_file"
    case typeText = "type_text"
    case addNote = "add_note"
    case addReminder = "add_reminder"
    case startTimer = "start_timer"
    case timerStatus = "timer_status"
    case cancelTimer = "cancel_timer"

    /// Wording for messages like "Maybe open an app or search the web?".
    public var displayName: String {
        switch self {
        case .openApp: "open an app"
        case .webSearch: "search the web"
        case .askClaude: "ask Claude"
        case .newClaudeSession: "start a new Claude session"
        case .volume: "change the volume"
        case .brightness: "change the brightness"
        case .keyboardLight: "change the keyboard light"
        case .darkMode: "switch dark mode"
        case .focus: "change Do Not Disturb"
        case .lock: "lock the screen"
        case .screenshot: "take a screenshot"
        case .mediaPlayPause: "play or pause"
        case .mediaNext: "skip to the next track"
        case .mediaPrevious: "go to the previous track"
        case .quitApp: "quit an app"
        case .hideApp: "hide an app"
        case .minimizeWindow: "minimize the window"
        case .fullScreen: "toggle full screen"
        case .closeWindow: "close the window"
        case .createFolder: "create a folder"
        case .createFile: "create a file"
        case .findFile: "find a file"
        case .openFile: "open a file"
        case .revealFile: "show a file in Finder"
        case .typeText: "type text"
        case .addNote: "save a note"
        case .addReminder: "add a reminder"
        case .startTimer: "start a timer"
        case .timerStatus: "check a timer"
        case .cancelTimer: "cancel a timer"
        }
    }
}

public struct RoutingThresholds: Sendable, Equatable {
    public var gate: Float
    public var choice: Float

    /// `choice` defaults to 0.35: with three options chance is 0.33, and real commands in the phrase set
    /// win with as little as 0.37 (see `make test-routing`).
    public init(gate: Float = 0.5, choice: Float = 0.35) {
        self.gate = gate
        self.choice = choice
    }
}

public struct RoutingDecision: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case intent(RoutedIntent)
        case notACommand
        case ambiguous([RoutedIntent])

        public var logName: String {
            switch self {
            case .intent(let intent): intent.rawValue
            case .notACommand: "not_a_command"
            case .ambiguous: "ambiguous"
            }
        }
    }

    public let outcome: Outcome
    public let gateProbability: Float
    /// Empty when the gate rejected the transcript.
    public let choiceProbabilities: [RoutedIntent: Float]
    public let stateWasTruncated: Bool

    public init(outcome: Outcome, gateProbability: Float, choiceProbabilities: [RoutedIntent: Float], stateWasTruncated: Bool) {
        self.outcome = outcome
        self.gateProbability = gateProbability
        self.choiceProbabilities = choiceProbabilities
        self.stateWasTruncated = stateWasTruncated
    }
}

public enum RoutingError: Error {
    case notPrepared
}

public protocol IntentRouting: Sendable {
    /// Loads the model, reporting human-readable progress. Safe to call more than once.
    func prepare(progress: @escaping @Sendable (String) -> Void) async throws
    func route(_ transcript: String) async throws -> RoutingDecision
    func setThresholds(_ thresholds: RoutingThresholds) async
}
