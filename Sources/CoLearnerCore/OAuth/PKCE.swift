import Foundation
import CryptoKit

public struct PKCEChallenge: Sendable, Equatable {
    public let verifier: String
    public let challenge: String
    public let method = "S256"

    public init(verifier: String, challenge: String) {
        self.verifier = verifier
        self.challenge = challenge
    }
}

public enum PKCE {
    public static func generate() -> PKCEChallenge {
        let verifier = randomVerifier()
        let challenge = challenge(for: verifier)
        return PKCEChallenge(verifier: verifier, challenge: challenge)
    }

    private static func randomVerifier(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "PKCE random byte generation failed")
        return Data(bytes).base64URLEncodedString()
    }

    private static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
