import AppKit

/// Opens URLs and app bundles. A protocol so tests don't open real windows.
public protocol URLOpening: Sendable {
    @MainActor func open(_ url: URL) -> Bool
}

public struct WorkspaceOpener: URLOpening {
    public init() {}

    @MainActor public func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}
