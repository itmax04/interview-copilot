import CopilotCore
import SwiftUI

/// Keys — R-18, R-23: поле ввода, «Проверить», «Удалить»; сохранённое значение не показывается.
struct KeysSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            // Быстрые провайдеры — первыми, как в цепочке (R-36): поле Groq видно без прокрутки.
            ForEach(Self.order, id: \.self) { provider in
                KeyRow(model: model, provider: provider)
            }
            Section {
                Toggle("Ключ Gemini бесплатного тарифа (Free tier, стоимость $0)", isOn: $model.settings.geminiFreeTier)
            } footer: {
                Text("Ключи хранятся только в Связке ключей macOS и после сохранения не показываются.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    static let order: [ProviderID] = [.groq, .custom, .cerebras, .gemini, .deepseek, .anthropic]
        + ProviderID.allCases.filter { ![.groq, .custom, .cerebras, .gemini, .deepseek, .anthropic].contains($0) }
}

private struct KeyRow: View {
    @Bindable var model: AppModel
    let provider: ProviderID
    @State private var input = ""
    @State private var extraInput = ""

    private var title: String {
        switch provider {
        case .gemini: "Gemini"
        case .deepseek: "DeepSeek"
        case .anthropic: "Anthropic"
        case .groq: "Groq — бесплатно, console.groq.com/keys"
        case .cerebras: "Cerebras — пробные кредиты, cloud.cerebras.ai"
        case .custom: "Свой API — любой OpenAI-совместимый (OpenRouter, OpenAI, Together, Mistral, Ollama)"
        }
    }

    var body: some View {
        Section(title) {
            if provider == .custom { CustomEndpointFields(model: model) }
            HStack {
                SecureField(model.hasKey[provider] == true ? "Ключ сохранён — введите новый, чтобы заменить" : "Вставьте ключ",
                            text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                    .accessibilityLabel("Ключ \(title)")
                Button("Сохранить", action: save)
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack {
                Image(systemName: model.hasKey[provider] == true ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(model.hasKey[provider] == true ? .green : .secondary)
                    .accessibilityHidden(true)
                Text(model.keyStatus[provider] ?? (model.hasKey[provider] == true ? "Ключ сохранён" : "Нет ключа"))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                if model.checking.contains(provider) { ProgressView().controlSize(.small) }
                Button("Проверить") { model.checkKey(provider) }
                    .disabled(model.hasKey[provider] != true || model.checking.contains(provider))
                Button("Удалить", role: .destructive) { model.deleteKey(provider) }
                    .disabled(model.hasKey[provider] != true)
            }
            extraKeys
        }
    }

    /// Еще ключи того же провайдера (другие аккаунты): кончился лимит у одного (429) — ответ сразу идет со следующего,
    /// и этот ключ несколько минут не пробуется первым.
    @ViewBuilder private var extraKeys: some View {
        let slots = model.extraSlots[provider] ?? []
        ForEach(slots, id: \.self) { slot in
            let account = KeySlots.account(provider, slot)
            HStack {
                Image(systemName: "key.fill").foregroundStyle(.secondary).accessibilityHidden(true)
                Text("Ключ \(slot)")
                Text(model.slotStatus[account] ?? "Сохранён").foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                if model.checkingSlots.contains(account) { ProgressView().controlSize(.small) }
                Button("Проверить") { model.checkKey(provider, slot: slot) }
                    .disabled(model.checkingSlots.contains(account))
                Button("Удалить", role: .destructive) { model.deleteKey(provider, slot: slot) }
            }
            .accessibilityElement(children: .combine)
        }
        if model.hasKey[provider] == true {
            HStack {
                SecureField("Еще ключ — другого аккаунта", text: $extraInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addExtra)
                    .accessibilityLabel("Дополнительный ключ \(title)")
                Button("Добавить", action: addExtra)
                    .disabled(extraInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Ключей — сколько нужно. Сначала по очереди пробуются все ключи этого провайдера: кончился лимит у одного — ответ сразу идет со следующего; ключ с лимитом ждет сброса и не пробуется первым. Только когда лимит у всех ключей — следующий провайдер из цепочки.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func addExtra() {
        let value = extraInput
        extraInput = ""
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.addExtraKey(value, for: provider)
    }

    private func save() {
        let value = input
        input = ""
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.saveKey(value, for: provider)
    }
}

/// Свой API (COPILOT-04 R-06): адрес и модель; ключ — в общем поле строки ниже (Связка ключей).
private struct CustomEndpointFields: View {
    @Bindable var model: AppModel

    private var urlText: String { model.settings.customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var urlValid: Bool { ProviderEndpoints.customBaseURL(urlText) != nil }
    private var isFirst: Bool { model.settings.chain.first == .custom }

    var body: some View {
        TextField("Адрес API", text: $model.settings.customBaseURL, prompt: Text("https://openrouter.ai/api/v1"))
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Адрес своего API")
        if !urlText.isEmpty && !urlValid {
            Label("Нужен адрес https://… (http — только для этого Mac: http://localhost:11434/v1)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.caption)
        }
        TextField("Модель", text: $model.settings.modelIDs.custom, prompt: Text("openai/gpt-4o-mini"))
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Модель своего API")
        HStack {
            Text(isFirst ? "Свой API — первый в цепочке ответов" : "Место в цепочке — вкладка Models")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Поставить первым в цепочке") {
                model.settings.chain = [.custom] + model.settings.chain.filter { $0 != .custom }
            }
            .disabled(isFirst)
        }
        Text("Примеры адресов: OpenRouter https://openrouter.ai/api/v1 · OpenAI https://api.openai.com/v1 · Together https://api.together.xyz/v1 · Mistral https://api.mistral.ai/v1 · Ollama на этом Mac http://localhost:11434/v1 (ключ — любой текст). Скриншоты сюда не отправляются.")
            .font(.footnote).foregroundStyle(.secondary)
    }
}
