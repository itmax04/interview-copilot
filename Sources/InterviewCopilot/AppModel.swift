import CopilotCore
import Foundation
import Observation

/// Состояние приложения на главном потоке: настройки, наличие ключей, проверки ключей.
@MainActor
@Observable
final class AppModel {
    private let settingsStore: SettingsStore
    let secrets: SecretStore
    private let verifier: KeyVerifier

    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            let saved = settingsStore.save(settings)
            if saved != settings { settings = saved }
            onChange?()
        }
    }

    /// Есть ли ключ в Связке ключей (само значение в UI не попадает — R-18, R-23).
    private(set) var hasKey: [ProviderID: Bool] = [:]
    private(set) var keyStatus: [ProviderID: String] = [:]
    private(set) var checking: Set<ProviderID> = []
    /// Список моделей, полученный при последней успешной проверке ключа (для сверки ID на P-07).
    private(set) var availableModels: [ProviderID: [String]] = [:]

    /// Вызывается после изменения настроек или ключей (перестройка меню).
    var onChange: (() -> Void)?

    init(settingsStore: SettingsStore = SettingsStore(), secrets: SecretStore = KeychainStore(),
         verifier: KeyVerifier = KeyVerifier()) {
        self.settingsStore = settingsStore
        self.secrets = secrets
        self.verifier = verifier
        self.settings = settingsStore.load()
        refreshKeys()
    }

    func refreshKeys() {
        for p in ProviderID.allCases { hasKey[p] = secrets.contains(p) }
    }

    func saveKey(_ value: String, for provider: ProviderID) {
        do {
            try secrets.set(value, for: provider)
            keyStatus[provider] = "Сохранён"
        } catch {
            keyStatus[provider] = "\(error)"
        }
        refreshKeys()
        onChange?()
    }

    func deleteKey(_ provider: ProviderID) {
        do {
            try secrets.delete(provider)
            keyStatus[provider] = "Удалён"
            availableModels[provider] = nil
        } catch {
            keyStatus[provider] = "\(error)"
        }
        refreshKeys()
        onChange?()
    }

    func checkKey(_ provider: ProviderID) {
        guard !checking.contains(provider) else { return }
        let key: String?
        do { key = try secrets.get(provider) } catch {
            keyStatus[provider] = "\(error)"
            return
        }
        guard let key else {
            keyStatus[provider] = "Нет ключа"
            return
        }
        checking.insert(provider)
        keyStatus[provider] = "Проверяю…"
        Task {
            let result = await verifier.verify(provider, key: key)
            checking.remove(provider)
            keyStatus[provider] = result.summary
            if case .ok(let models) = result { availableModels[provider] = models }
        }
    }

    func menuState(listening: ListeningStatus) -> MenuState {
        MenuState(listening: listening, mode: settings.mode, chain: settings.chain, language: settings.language,
                  strongModelName: settings.strongProvider.displayName)
    }
}
