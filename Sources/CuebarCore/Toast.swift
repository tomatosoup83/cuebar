import Foundation

/// A transient message shown near the palette: playback confirmation or an error.
public struct Toast: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case success
        case error
        case info
    }

    public let id: UUID
    public let kind: Kind
    public let message: String
    public let detail: String?
    public let duration: TimeInterval

    public init(
        id: UUID = UUID(),
        kind: Kind,
        message: String,
        detail: String? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.detail = detail
        self.duration = duration ?? kind.defaultDuration
    }
}

public extension Toast.Kind {
    /// How long the toast stays on screen. Errors linger a little longer.
    var defaultDuration: TimeInterval {
        switch self {
        case .success, .info: return 2.0
        case .error: return 4.0
        }
    }
}
