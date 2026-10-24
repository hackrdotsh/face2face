#if canImport(Security)
    import Foundation
    import Security

    public actor KeychainTokenStore: TokenStore {
        private let service = "sh.hackr.face2face.session"
        private let account: String

        public init(server: URL) {
            account = server.absoluteString
        }

        public func load() throws -> String? {
            var query = identity
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = result as? Data,
                let token = String(data: data, encoding: .utf8)
            else { throw KeychainError(status: status) }
            return token
        }

        public func save(_ token: String?) throws {
            guard let token else {
                let status = SecItemDelete(identity as CFDictionary)
                guard status == errSecSuccess || status == errSecItemNotFound else {
                    throw KeychainError(status: status)
                }
                return
            }
            let data = Data(token.utf8)
            let status = SecItemUpdate(
                identity as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var item = identity
                item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                let added = SecItemAdd(item as CFDictionary, nil)
                guard added == errSecSuccess else { throw KeychainError(status: added) }
            } else if status != errSecSuccess {
                throw KeychainError(status: status)
            }
        }

        private var identity: [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
        }
    }

    private struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "Could not access the saved session. Unlock your iPhone and try again."
        }
    }
#endif
