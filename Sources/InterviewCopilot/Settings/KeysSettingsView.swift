import CopilotCore
import SwiftUI

/// Keys — R-18, R-23: поле ввода, «Проверить», «Удалить»; сохранённое значение не показывается.
struct KeysSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            ForEach(ProviderID.allCases, id: \.self) { provider in
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
}

private struct KeyRow: View {
    @Bindable var model: AppModel
    let provider: ProviderID
    @State private var input = ""

    private var title: String {
        switch provider {
        case .gemini: "Gemini"
        case .deepseek: "DeepSeek"
        case .anthropic: "Anthropic"
        }
    }

    var body: some View {
        Section(title) {
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
        }
    }

    private func save() {
        let value = input
        input = ""
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.saveKey(value, for: provider)
    }
}
