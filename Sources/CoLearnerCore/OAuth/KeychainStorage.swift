import Foundation
import Security

public enum KeychainError: Error, LocalizedError {
    case unhandled(OSStatus)
    case decodingFailed
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case let .unhandled(status):
            "Keychain error \(status)"
        case .decodingFailed:
            "Could not decode keychain payload"
        case .encodingFailed:
            "Could not encode keychain payload"
        }
    }
}

public protocol CredentialStoring: Sendable {
    func save(_ credentials: OAuthCredentials, for provider: OAuthProvider) throws
    func load(for provider: OAuthProvider) throws -> OAuthCredentials?
    func delete(for provider: OAuthProvider) throws
}

public struct KeychainCredentialStore: CredentialStoring {
    private let service: String

    public init(service: String = "dev.colearner.oauth") {
        self.service = service
    }

    public func save(_ credentials: OAuthCredentials, for provider: OAuthProvider) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(credentials) else {
            throw KeychainError.encodingFailed
        }

        let query = baseQuery(for: provider)
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandled(addStatus)
            }
        default:
            throw KeychainError.unhandled(updateStatus)
        }
    }

    public func load(for provider: OAuthProvider) throws -> OAuthCredentials? {
        var query = baseQuery(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw KeychainError.decodingFailed
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(OAuthCredentials.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandled(status)
        }
    }

    public func delete(for provider: OAuthProvider) throws {
        let status = SecItemDelete(baseQuery(for: provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    private func baseQuery(for provider: OAuthProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
    }
}

public final class InMemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private var storage = [OAuthProvider: OAuthCredentials]()
    private let lock = NSLock()

    public init() {}

    public func save(_ credentials: OAuthCredentials, for provider: OAuthProvider) throws {
        lock.withLock { storage[provider] = credentials }
    }

    public func load(for provider: OAuthProvider) throws -> OAuthCredentials? {
        lock.withLock { storage[provider] }
    }

    public func delete(for provider: OAuthProvider) throws {
        lock.withLock { _ = storage.removeValue(forKey: provider) }
    }
}

/// File-backed credential store. Stores credentials as one JSON file per provider in
/// `~/Library/Application Support/CoLearner/credentials/<provider>.json`, with file
/// permissions restricted to the owner (0600). This avoids the macOS Keychain ACL
/// prompt loop that happens when an unsigned/ad-hoc-signed binary is rebuilt frequently
/// (each new binary signature looks like a different app to Keychain).
public struct FileCredentialStore: CredentialStoring {
    private let directory: URL
    private let lock = NSLock()

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.directory = appSupport
                .appendingPathComponent("CoLearner", isDirectory: true)
                .appendingPathComponent("credentials", isDirectory: true)
        }
    }

    public func save(_ credentials: OAuthCredentials, for provider: OAuthProvider) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(credentials)

        lock.lock()
        defer { lock.unlock() }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = fileURL(for: provider)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    public func load(for provider: OAuthProvider) throws -> OAuthCredentials? {
        lock.lock()
        defer { lock.unlock() }

        let url = fileURL(for: provider)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(OAuthCredentials.self, from: data)
    }

    public func delete(for provider: OAuthProvider) throws {
        lock.lock()
        defer { lock.unlock() }

        let url = fileURL(for: provider)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func fileURL(for provider: OAuthProvider) -> URL {
        directory.appendingPathComponent("\(provider.rawValue).json")
    }
}
