import Foundation

/// Toast copy for the update flow.
public enum UpdateFeedback {
    public static func available(_ info: UpdateInfo) -> Toast {
        Toast(
            kind: .info,
            message: "Cuebar \(info.version) is available",
            detail: "Type “update” to install",
            duration: 5.0
        )
    }

    public static func downloading() -> Toast {
        Toast(kind: .info, message: "Downloading update…", duration: 30.0)
    }

    public static func installing() -> Toast {
        Toast(kind: .info, message: "Installing — Cuebar will relaunch", duration: 30.0)
    }

    public static func upToDate(_ version: AppVersion) -> Toast {
        Toast(kind: .success, message: "Cuebar \(version) is up to date")
    }

    public static func failed(_ error: Error) -> Toast {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return Toast(kind: .error, message: message)
    }
}
