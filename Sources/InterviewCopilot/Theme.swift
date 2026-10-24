import SwiftUI

/// Токены целевого стиля редизайна (docs/design/redesign/research.pdf, «Общий стиль»): новые экраны COPILOT-09 сразу
/// в нём, старые переводятся на этапе редизайна. Цвета — семантические, а не «красивые».
enum Theme {
    /// Акцент — индиго #4C6EF5.
    static let accent = Color(red: 0x4C / 255, green: 0x6E / 255, blue: 0xF5 / 255)
    /// Слушаю / готово — #2FB344.
    static let ok = Color(red: 0x2F / 255, green: 0xB3 / 255, blue: 0x44 / 255)
    /// Проверяю / черновик / предупреждение — #F59F00.
    static let warn = Color(red: 0xF5 / 255, green: 0x9F / 255, blue: 0x00 / 255)
    /// Ошибка / завершить — #E03131.
    static let danger = Color(red: 0xE0 / 255, green: 0x31 / 255, blue: 0x31 / 255)

    static let radius: CGFloat = 12
    static let gap: CGFloat = 8
}

/// Карточка-группа в светлых окнах: мягкий фон, скругление, отступы по сетке 8 pt.
struct ThemeCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap * 1.5) { content }
            .padding(Theme.gap * 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.primary.opacity(0.08)))
    }
}
