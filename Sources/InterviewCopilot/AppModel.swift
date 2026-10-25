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
    /// Дополнительные ключи (слоты 2, 3…) по провайдерам — значения в UI не попадают (COPILOT-09: несколько аккаунтов).
    private(set) var extraSlots: [ProviderID: [Int]] = [:]
    /// Статус и проверка дополнительного ключа — по имени `groq#2`.
    private(set) var slotStatus: [String: String] = [:]
    private(set) var checkingSlots: Set<String> = []
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
            let accounts = await Task.detached { secrets.accounts() }.value
            let slots = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, secrets.slots($0, in: accounts)) })
            let found = slots.mapValues { !$0.isEmpty }
            extraSlots = slots.mapValues { $0.filter { $0 > 1 } }
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
        ProviderHealth.shared.reset()   // ключи изменились — прежние «лимит» и «недействителен» больше не про них
        refreshKeys()
        onChange?()
    }

    /// Провайдер ответил 400/401/403 — показать «ключ недействителен» у этого ключа в настройках (R-09).
    func markInvalidKey(_ provider: ProviderID, slot: Int = 1, _ error: LLMError) {
        if slot <= 1 {
            keyStatus[provider] = L("Ключ недействителен: %@", error.description)
        } else {
            slotStatus[KeySlots.account(provider, slot)] = L("Ключ недействителен: %@", error.description)
        }
    }

    /// Еще один ключ того же провайдера (другой аккаунт): когда у первого кончается лимит, ответ идет со следующего.
    func addExtraKey(_ value: String, for provider: ProviderID) {
        let secrets = self.secrets
        let slot = secrets.freeExtraSlot(provider)
        do {
            try secrets.set(value, for: provider, slot: slot)
            slotStatus[KeySlots.account(provider, slot)] = "Сохранён"
            Log.llm.info("extra key saved provider=\(provider.rawValue, privacy: .public) slot=\(slot)")
        } catch {
            keyStatus[provider] = "\(error)"
        }
        ProviderHealth.shared.reset()   // ключи изменились — прежние «лимит» и «недействителен» больше не про них
        refreshKeys()
        onChange?()
    }

    /// Удаление любого ключа; остальные перенумеровываются без пропусков (удален основной — его место занимает «Ключ 2»).
    func deleteKey(_ provider: ProviderID, slot: Int) {
        do {
            try secrets.delete(provider, slot: slot)
            try secrets.compactSlots(provider)
            // Номера сдвинулись — прежние статусы относятся к другим ключам.
            for key in slotStatus.keys where KeySlots.slot(of: key, provider: provider) != nil { slotStatus[key] = nil }
            let left = secrets.slots(provider)
            keyStatus[provider] = left.isEmpty ? "Удалён" : (slot == 1 ? "Удалён — основным стал следующий ключ" : nil)
            if left.isEmpty { availableModels[provider] = nil }
        } catch {
            keyStatus[provider] = "\(error)"
        }
        ProviderHealth.shared.reset()   // ключи изменились — прежние «лимит» и «недействителен» больше не про них
        refreshKeys()
        onChange?()
    }

    func checkKey(_ provider: ProviderID, slot: Int) {
        guard slot > 1 else { checkKey(provider); return }
        let account = KeySlots.account(provider, slot)
        guard !checkingSlots.contains(account) else { return }
        checkingSlots.insert(account)
        slotStatus[account] = "Проверяю…"
        let secrets = self.secrets
        Task {
            let read = await Task.detached { () -> Result<String?, Error> in Result { try secrets.get(provider, slot: slot) } }.value
            guard case .success(let value) = read, let key = value else {
                checkingSlots.remove(account)
                slotStatus[account] = "Нет ключа"
                return
            }
            let result = await verifier.verify(provider, key: key)
            checkingSlots.remove(account)
            slotStatus[account] = result.summary
            onChange?()
        }
    }

    func deleteKey(_ provider: ProviderID) { deleteKey(provider, slot: 1) }

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
        return missing.isEmpty ? nil : L("%@: нет модели %@ в списке провайдера", p.displayName, missing.joined(separator: ", "))
    }

    func menuState(listening: ListeningStatus, profileName: String = ProfileLibrary.defaultName, cardCount: Int = 0) -> MenuState {
        // Свой API без адреса и модели в строке «Models: …» не показывается (COPILOT-04 R-06).
        MenuState(listening: listening, mode: settings.mode,
                  chain: settings.chain.filter { $0 != .custom || ChainFactory.customConfigured(settings) }, language: settings.language,
                  profileName: profileName, useProfile: settings.useProfile, bankCardCount: cardCount,
                  strongModelName: settings.strongProvider.displayName)
    }
}
