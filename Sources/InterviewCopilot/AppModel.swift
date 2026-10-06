import CopilotCore
import Foundation
import os
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

    /// Наличие ключей проверяется в фоне: пока висит системный запрос Связки ключей, любой вызов к ней ждёт,
    /// а главный поток (меню, панель) ждать не должен.
    func refreshKeys() {
        let secrets = self.secrets
        Task {
            let found = await Task.detached { Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, secrets.contains($0)) }) }.value
            if found != hasKey {
                hasKey = found
                onChange?()
            }
            if verifyAfterRefresh {
                verifyAfterRefresh = false
                for p in ProviderID.allCases where hasKey[p] == true { checkKey(p) }
            }
        }
    }

    private var verifyAfterRefresh = false

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

    /// Провайдер ответил 400/401/403 — показать «ключ недействителен» в настройках (R-09).
    func markInvalidKey(_ provider: ProviderID, _ error: LLMError) {
        keyStatus[provider] = "Ключ недействителен: \(error.description)"
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
        checking.insert(provider)
        keyStatus[provider] = "Проверяю…"
        let secrets = self.secrets
        Task {
            // Чтение Связки ключей — не на главном потоке.
            let read = await Task.detached { () -> Result<String?, Error> in Result { try secrets.get(provider) } }.value
            guard case .success(let value) = read, let key = value else {
                checking.remove(provider)
                if case .failure(let error) = read { keyStatus[provider] = "\(error)" } else { keyStatus[provider] = "Нет ключа" }
                return
            }
            let result = await verifier.verify(provider, key: key)
            checking.remove(provider)
            keyStatus[provider] = result.summary
            if case .ok(let models) = result {
                availableModels[provider] = models
                let configured = settings.modelIDs.effective(provider)
                Log.llm.info("model_ids provider=\(provider.rawValue, privacy: .public) configured=\(configured, privacy: .public) present=\(models.contains(configured)) count=\(models.count)")
            }
            onChange?()
        }
    }

    /// Проверка ID моделей по спискам провайдеров (R-09: «ID моделей проверяются по models-эндпоинтам»).
    func verifyModelIDs() {
        verifyAfterRefresh = true
        refreshKeys()
    }

    /// Предупреждение, если настроенный ID отсутствует в списке моделей провайдера.
    func modelWarning(_ p: ProviderID) -> String? {
        guard let models = availableModels[p], !models.isEmpty else { return nil }
        var missing = [settings.modelIDs.effective(p)].filter { !models.contains($0) }
        if p == .gemini, !settings.modelIDs.geminiBackup.isEmpty, !models.contains(settings.modelIDs.geminiBackup) {
            missing.append(settings.modelIDs.geminiBackup)
        }
        return missing.isEmpty ? nil : "\(p.displayName): нет модели \(missing.joined(separator: ", ")) в списке провайдера"
    }

    func menuState(listening: ListeningStatus, profileName: String = "Profile", cardCount: Int = 0) -> MenuState {
        MenuState(listening: listening, mode: settings.mode, chain: settings.chain, language: settings.language,
                  profileName: profileName, bankCardCount: cardCount,
                  strongModelName: settings.strongProvider.displayName)
    }
}
