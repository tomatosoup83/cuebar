import Foundation
import AppKit

/// An error surfaced by `NSAppleScript` execution.
public struct AppleScriptError: Error, LocalizedError, Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }

    /// Automation permission was denied by the user (-1743) or reported as
    /// inaccessible. The UI can present actionable guidance for these.
    public var isPermissionDenied: Bool {
        code == -1743 || code == -10003
    }

    public var errorDescription: String? {
        if isPermissionDenied {
            return "Cuebar needs permission to control the Music app. Enable it in System Settings › Privacy & Security › Automation."
        }
        return message
    }
}

/// Serializes all AppleScript execution onto one queue and bridges the
/// completion-based `NSAppleScript` API into async/await.
///
/// `NSAppleScript` is not thread-safe, so every call creates and uses its own
/// script instance on the same serial queue.
public final class AppleScriptRunner: @unchecked Sendable {
    public static let shared = AppleScriptRunner()

    private let queue = DispatchQueue(label: "com.cuebar.applescript", qos: .userInitiated)

    public init() {}

    /// Executes `source`, discarding any result.
    public func run(_ source: String) async throws {
        _ = try await raw(source)
    }

    /// Executes `source` and returns its textual result.
    public func string(_ source: String) async throws -> String {
        let descriptor = try await raw(source)
        return descriptor.stringValue ?? ""
    }

    /// Executes `source` and returns raw bytes (for example artwork data).
    public func data(_ source: String) async throws -> Data {
        let descriptor = try await raw(source)
        return descriptor.data
    }

    private func raw(_ source: String) async throws -> NSAppleEventDescriptor {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(throwing: AppleScriptError(
                        code: -1,
                        message: "Could not compile AppleScript."
                    ))
                    return
                }
                let result = script.executeAndReturnError(&error)
                if let error {
                    let code = error["NSAppleScriptErrorNumber"] as? Int ?? -1
                    let message = (error["NSAppleScriptErrorMessage"] as? String)
                        ?? (error["NSAppleScriptErrorBriefMessage"] as? String)
                        ?? "Unknown AppleScript error."
                    continuation.resume(throwing: AppleScriptError(code: code, message: message))
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }
}
