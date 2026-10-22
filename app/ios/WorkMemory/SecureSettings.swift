import Foundation
import Security
import Combine

struct KeychainStore {
    private let service = "app.workmemory.personal.ai"
    private func query(_ endpoint: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: stableHash(endpoint)]
    }
    func read(endpoint: String) throws -> String? {
        var request = query(endpoint)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) else { throw KeychainError(status: status) }
        return key
    }
    func save(_ value: String, endpoint: String) throws {
        let existing = query(endpoint)
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let update = SecItemUpdate(existing as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            let status = SecItemAdd(existing.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
        } else if update != errSecSuccess { throw KeychainError(status: update) }
    }
    func remove(endpoint: String) throws {
        let status = SecItemDelete(query(endpoint) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
struct KeychainError: LocalizedError {
    var status: OSStatus
    var errorDescription: String? { "无法访问 iPhone 安全凭证存储（\(status)）。请解锁手机后重试。" }
}
@MainActor
final class AISettings: ObservableObject {
    @Published private(set) var configuration: ServiceConfiguration
    @Published private(set) var hasKey = false
    private let keychain = KeychainStore()
    private let defaults: UserDefaults
    private let serviceOverride: (() throws -> any MemoryAIService)?
    init(defaults: UserDefaults = .standard, serviceOverride: (() throws -> any MemoryAIService)? = nil) {
        self.defaults = defaults
        self.serviceOverride = serviceOverride
        if let data = defaults.data(forKey: "aiConfiguration"), let saved = try? JSONDecoder().decode(ServiceConfiguration.self, from: data) { configuration = saved }
        else { configuration = ServiceConfiguration() }
        refreshKeyStatus()
        if serviceOverride != nil { hasKey = true }
    }
    private func refreshKeyStatus() {
        hasKey = ((try? keychain.read(endpoint: configuration.baseURL)) ?? nil)?.isEmpty == false
            && ((try? keychain.read(endpoint: configuration.effectiveAnalysisURL)) ?? nil)?.isEmpty == false
    }
    func save(configuration value: ServiceConfiguration, newKey: String, newAnalysisKey: String = "") throws {
        var config = value
        config.baseURL = value.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        config.analysisBaseURL = value.analysisBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        _ = try config.validatedURL()
        let cleaned = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty { try keychain.save(cleaned, endpoint: config.baseURL) }
        let textKey = newAnalysisKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if config.analysisBaseURL != nil, !textKey.isEmpty { try keychain.save(textKey, endpoint: config.effectiveAnalysisURL) }
        defaults.set(try JSONEncoder().encode(config), forKey: "aiConfiguration")
        configuration = config
        refreshKeyStatus()
    }
    func removeKey() throws {
        try keychain.remove(endpoint: configuration.baseURL)
        if configuration.analysisBaseURL != nil { try keychain.remove(endpoint: configuration.effectiveAnalysisURL) }
        refreshKeyStatus()
    }
    func service() throws -> any MemoryAIService {
        if let serviceOverride { return try serviceOverride() }
        return try HTTPMemoryAIService(configuration: configuration, key: keychain.read(endpoint: configuration.baseURL) ?? "", analysisKey: keychain.read(endpoint: configuration.effectiveAnalysisURL))
    }
}
