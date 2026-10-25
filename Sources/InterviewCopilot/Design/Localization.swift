import CopilotCore
import Observation
import SwiftUI
import AppKit

/// Язык интерфейса в окнах (COPILOT-10): меняется сразу. Корень каждого окна перерисовывается целиком — строки-литералы
/// SwiftUI берут перевод по `\.locale`, вычисляемые строки — через `L(…)`.
@MainActor
@Observable
final class UILanguage {
    static let shared = UILanguage()
    private(set) var language: InterfaceLanguage = L10n.language
    /// Заголовки открытых окон: ключ, по которому заголовок переводится заново при смене языка.
    @ObservationIgnored private var titled: [(window: WeakWindow, key: String)] = []
    /// Вызывается после смены языка (меню в строке меню собирается заново).
    @ObservationIgnored var onChange: (() -> Void)?

    func apply(_ setting: InterfaceLanguage) {
        L10n.language = setting
        let resolved = L10n.language
        guard resolved != language else { return }
        language = resolved
        titled.removeAll { $0.window.value == nil }
        for entry in titled { entry.window.value?.title = L10n.t(entry.key) }
        onChange?()
    }

    /// Заголовок окна на языке интерфейса; переводится и при смене языка.
    func setTitle(_ key: String, of window: NSWindow) {
        window.title = L10n.t(key)
        titled.removeAll { $0.window.value == nil || $0.window.value === window }
        titled.append((WeakWindow(value: window), key))
    }
}

struct WeakWindow { weak var value: NSWindow? }

/// Корень окна: локаль для строк-литералов и полная перерисовка при смене языка (состояние экранов — в моделях).
struct LocalizedRoot: ViewModifier {
    @State private var ui = UILanguage.shared

    func body(content: Content) -> some View {
        content
            .environment(\.locale, ui.language == .en ? Locale(identifier: "en") : Locale(identifier: "ru"))
            .id(ui.language)
    }
}

extension View {
    func localizedRoot() -> some View { modifier(LocalizedRoot()) }
}

/// Локальная страница (ИИ-собеседование, тестовый звонок) на языке интерфейса: русская — как есть, английская — по
/// `en.json` рядом со страницей.
func localizedPage(_ data: Data, resources: URL) -> Data {
    guard L10n.isEnglish, let html = String(data: data, encoding: .utf8) else { return data }
    return Data(PageLocalization.localize(html, table: PageLocalization.table(in: resources)).utf8)
}

/// Строка интерфейса, которая собирается в коде (статусы, подписи, меню). Ключ — русский текст.
func L(_ key: String) -> String { L10n.t(key) }

/// Строка с подстановкой: `L("Ключ %lld", slot)`.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L10n.t(key), locale: L10n.locale, arguments: args)
}

// MARK: Строки, которые приходят переменной (статусы, подписи компонентов, заголовки из CopilotCore)
//
// У SwiftUI для `String` — обобщенные инициализаторы с пониженным приоритетом; эти перегрузки — конкретные, поэтому
// для переменной `String` выбираются они и переводят текст. Литералы, как и раньше, идут через `LocalizedStringKey`.
// Текст без перевода (ответы, вопросы, имена) возвращается как есть.

extension Text {
    @_disfavoredOverload
    init(_ content: String) { self.init(verbatim: L10n.t(content)) }
}

extension Button where Label == Text {
    @_disfavoredOverload
    init(_ title: String, action: @escaping () -> Void) { self.init(action: action) { Text(verbatim: L10n.t(title)) } }

    @_disfavoredOverload
    init(_ title: String, role: ButtonRole?, action: @escaping () -> Void) {
        self.init(role: role, action: action) { Text(verbatim: L10n.t(title)) }
    }
}

extension Label where Title == Text, Icon == Image {
    @_disfavoredOverload
    init(_ title: String, systemImage: String) {
        self.init { Text(verbatim: L10n.t(title)) } icon: { Image(systemName: systemImage) }
    }
}

extension Toggle where Label == Text {
    @_disfavoredOverload
    init(_ title: String, isOn: Binding<Bool>) { self.init(isOn: isOn) { Text(verbatim: L10n.t(title)) } }
}

extension Picker where Label == Text {
    @_disfavoredOverload
    init(_ title: String, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.init(selection: selection, content: content) { Text(verbatim: L10n.t(title)) }
    }
}

extension Section where Parent == Text, Content: View, Footer == EmptyView {
    @_disfavoredOverload
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(verbatim: L10n.t(title)) }
    }
}

extension View {
    @_disfavoredOverload
    func help(_ text: String) -> some View { help(Text(verbatim: L10n.t(text))) }

    @_disfavoredOverload
    func accessibilityLabel(_ label: String) -> some View { accessibilityLabel(Text(verbatim: L10n.t(label))) }

    @_disfavoredOverload
    func accessibilityHint(_ hint: String) -> some View { accessibilityHint(Text(verbatim: L10n.t(hint))) }
}
