import Foundation

public enum CommandError: Error, LocalizedError, Sendable {
    case noSelection

    public var errorDescription: String? {
        switch self {
        case .noSelection:
            return "Nothing is selected to play."
        }
    }
}

/// Applies a parsed `Command` to a `MusicController`.
///
/// Kept separate from the UI so command behaviour is unit-testable.
public final class CommandExecutor: Sendable {
    private let controller: MusicController

    public init(controller: MusicController) {
        self.controller = controller
    }

    public func execute(_ command: Command, selected: MusicCandidate?) async throws {
        switch command {
        case .play(let term):
            guard !term.isEmpty else {
                try await controller.resume()
                return
            }
            guard let selected else { throw CommandError.noSelection }
            try await controller.play(selected)
        case .pause:
            try await controller.pause()
        case .resume:
            try await controller.resume()
        case .next:
            try await controller.next()
        case .previous:
            try await controller.previous()
        case .shuffle(let action):
            switch action {
            case .toggle: try await controller.toggleShuffle()
            case .on: try await controller.setShuffle(true)
            case .off: try await controller.setShuffle(false)
            }
        }
    }
}
