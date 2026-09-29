import Foundation
import Combine

/// Holds the toast currently on screen and dismisses it after its duration.
///
/// The shell observes `current`: a non-nil value shows the toast panel, nil
/// hides it. Timing is injectable so auto-dismiss is testable without waiting.
@MainActor
public final class ToastCenter: ObservableObject {
    @Published public private(set) var current: Toast?

    private let dismissDelay: @Sendable (TimeInterval) async -> Void
    private var dismissTask: Task<Void, Never>?

    public init(dismissDelay: (@Sendable (TimeInterval) async -> Void)? = nil) {
        self.dismissDelay = dismissDelay ?? { seconds in
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            } catch {
                // Cancelled: the caller checks Task.isCancelled.
            }
        }
    }

    /// Shows `toast`, replacing any toast already on screen.
    public func show(_ toast: Toast) {
        dismissTask?.cancel()
        current = toast

        let id = toast.id
        let duration = toast.duration
        dismissTask = Task { [weak self] in
            await self?.dismissDelay(duration)
            guard !Task.isCancelled else { return }
            guard let self, self.current?.id == id else { return }
            self.current = nil
        }
    }

    public func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
    }

    deinit {
        dismissTask?.cancel()
    }
}
