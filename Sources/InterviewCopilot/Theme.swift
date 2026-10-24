import SwiftUI

/// Семантические цвета (P00, `IC`): прежние имена для экранов COPILOT-09 — один источник цветов.
enum Theme {
    /// Акцент — индиго #4C6EF5.
    static let accent = IC.accent
    /// Слушаю / готово — #2FB344.
    static let ok = IC.green
    /// Проверяю / черновик / предупреждение — #F59F00.
    static let warn = IC.amber
    /// Ошибка / завершить — #E03131.
    static let danger = IC.red

    static let radius: CGFloat = 12
    static let gap: CGFloat = 8
}

/// Карточка-группа в светлых окнах (P00): белая поверхность, контур #E5E7EB, сетка 8 pt.
struct ThemeCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap * 1.5) { content }
            .padding(Theme.gap * 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IC.card, in: RoundedRectangle(cornerRadius: Theme.radius + 2))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius + 2).strokeBorder(IC.line))
    }
}
