import Foundation
import CryptoKit

/// Verifies a downloaded update against an embedded Ed25519 public key.
public enum ReleaseVerifier {
    /// `signatureBase64` is the base64 of the raw 64-byte Ed25519 signature
    /// (the contents of `Cuebar.zip.sig`); `publicKeyBase64` is the base64 of
    /// the raw 32-byte public key.
    public static func verify(
        data: Data,
        signatureBase64: String,
        publicKeyBase64: String
    ) -> Bool {
        guard !publicKeyBase64.isEmpty else { return false }
        guard let keyData = Data(base64Encoded: publicKeyBase64, options: .ignoreUnknownCharacters),
              let signature = Data(
                  base64Encoded: signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines),
                  options: .ignoreUnknownCharacters
              ),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
            return false
        }
        return key.isValidSignature(signature, for: data)
    }
}

/// The public key baked into this build. Populated by `Scripts/make-update-key.sh`.
public enum UpdateKey {
    /// Base64 of the raw 32-byte Ed25519 public key (empty = not configured).
    public static let publicKeyBase64 = "/nrpCChu+hODQWyA0d/Z3uZDzhPT8eVkkdjZjGfAB5k="

    public static var isConfigured: Bool { !publicKeyBase64.isEmpty }
}
