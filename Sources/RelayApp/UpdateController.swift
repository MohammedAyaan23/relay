import AppSupport
import Foundation
import Observation

/// Asks GitHub for a newer Relay at most once a day, and on "Check now". Never downloads or installs.
@MainActor @Observable
final class UpdateController {
    struct Available: Equatable {
        let version: String
        let url: URL
    }

    private(set) var available: Available?
    private(set) var manualStatus: String?

    var isConfigured: Bool { !ReleaseInfo.repository.isEmpty }

    func start() {
        guard isConfigured else { return }
        Task {
            try? await Task.sleep(for: .seconds(10))
            while !Task.isCancelled {
                await checkIfDue()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    func checkNow() async {
        manualStatus = "Checking…"
        let result = await check()
        UserDefaults.standard.set(Date.now, forKey: Preferences.lastUpdateCheck)
        apply(result)
        manualStatus = switch result {
        case .upToDate: "You're up to date"
        case .available(let version, _): "Update available: v\(version)"
        case .failed: "Couldn't check. Try again later."
        }
    }

    private func checkIfDue() async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Preferences.checkForUpdates),
              UpdateSchedule.isDue(lastCheck: defaults.object(forKey: Preferences.lastUpdateCheck) as? Date, now: .now)
        else { return }
        defaults.set(Date.now, forKey: Preferences.lastUpdateCheck)
        apply(await check())
    }

    private func check() async -> UpdateResult {
        await UpdateChecker.check(current: AppInfo.version ?? "0.0.0",
                                  feed: GitHubReleaseFeed(repository: ReleaseInfo.repository))
    }

    /// A failed check keeps whatever was known before.
    private func apply(_ result: UpdateResult) {
        switch result {
        case .available(let version, let url): available = Available(version: version, url: url)
        case .upToDate: available = nil
        case .failed: break
        }
    }
}
