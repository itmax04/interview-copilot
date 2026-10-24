import AppKit
import SwiftUI

/// P00: единые цвета, типографика и поверхности ImageGen. Компоненты остаются нативными и доступными.
/// COPILOT-10: у каждого цвета — светлое и темное значение; окно берет нужное по своей теме (Настройки → Основное).
enum IC {
    static let accent = Color.dynamic(light: 0x4C6EF5, dark: 0x6382FF)
    static let green = Color.dynamic(light: 0x2FB344, dark: 0x40C057)
    static let amber = Color.dynamic(light: 0xF59F00, dark: 0xFAB005)
    static let red = Color.dynamic(light: 0xE03131, dark: 0xFA5252)
    /// Основной текст.
    static let ink = Color.dynamic(light: 0x16181D, dark: 0xECEEF3)
    /// Иконки и второстепенный текст строк.
    static let ink2 = Color.dynamic(light: 0x45516C, dark: 0xB4BAC8)
    /// Текст в карточках (ответы, сводка).
    static let body = Color.dynamic(light: 0x343942, dark: 0xD3D7DF)
    static let secondary = Color.dynamic(light: 0x7B849B, dark: 0x9AA1B2)
    static let line = Color.dynamic(light: 0xE5E7EB, dark: 0x30343C)
    static let background = Color.dynamic(light: 0xF5F7FB, dark: 0x15171C)
    static let sidebar = Color.dynamic(light: 0xF0F3FA, dark: 0x1A1D23)
    /// Поверхность карточек, полей и кнопок.
    static let card = Color.dynamic(light: 0xFFFFFF, dark: 0x1F2228)
    /// Подложка переключателей вкладок.
    static let muted = Color.dynamic(light: 0xEDF0F7, dark: 0x24272E)
    /// Реплики собеседника в расшифровке.
    static let bubble = Color.dynamic(light: 0xF0F2F6, dark: 0x262A31)
    static let neutral = Color(hex: 0xA1A1AA)
    static let heroStart = Color.dynamic(light: 0xDCE6FF, dark: 0x1E2A4F)
    static let heroEnd = Color.dynamic(light: 0xF3F6FF, dark: 0x191C24)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255,
                  blue: Double(hex & 255)/255, opacity: 1)
    }

    /// Цвет, который сам выбирает значение по теме окна (светлая / темная).
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

struct ICButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var primary = false
    var destructive = false
    var dark = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(primary || destructive || dark ? Color.white : IC.ink)
            .background(RoundedRectangle(cornerRadius: 10).fill(
                destructive ? IC.red : primary ? IC.accent : dark ? Color.white.opacity(0.08) : IC.card))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(
                primary || destructive ? Color.clear : dark ? Color.white.opacity(0.12) : IC.line))
            .opacity(!enabled ? 0.45 : configuration.isPressed ? 0.72 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ICCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(IC.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(IC.line))
    }
}

struct ICBadge: View {
    let text: String
    var color: Color = IC.accent
    var dot = false
    var body: some View {
        HStack(spacing: 5) {
            if dot { Circle().fill(color).frame(width: 6, height: 6) }
            Text(text).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(color).padding(.horizontal, 9).padding(.vertical, 5)
        .background(color.opacity(0.09), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct ICPageHeader: View {
    let title: String
    var subtitle = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 25, weight: .bold)).foregroundStyle(IC.ink)
            if !subtitle.isEmpty { Text(subtitle).font(.system(size: 13)).foregroundStyle(IC.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ICSidebarRow: View {
    let title: String
    let icon: String
    let selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 17)).frame(width: 22)
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? IC.accent : IC.ink2)
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(selected ? IC.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ICLogo: View {
    var size: CGFloat = 42
    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: size * 0.52, weight: .medium)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Color(hex: 0x4388FF), IC.accent, Color(hex: 0x5144E8)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: size * 0.26))
            .overlay(RoundedRectangle(cornerRadius: size * 0.26).strokeBorder(Color.white.opacity(0.25)))
            .accessibilityHidden(true)
    }
}

struct ICKeycap: View {
    let text: String
    var dark = false
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium))
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 5).padding(.vertical, 3)
            .foregroundStyle(dark ? Color.white.opacity(0.7) : IC.secondary)
            .background(dark ? Color.white.opacity(0.09) : IC.background, in: RoundedRectangle(cornerRadius: 4))
    }
}

struct ICEmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(IC.accent)
                .frame(width: 64, height: 64).background(IC.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(detail).font(.system(size: 13)).foregroundStyle(IC.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
    }
}

struct ICFormattedDocument: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("# ") { Text(String(line.dropFirst(2))).font(.system(size: 22, weight: .bold)).padding(.top, 5) }
                else if line.hasPrefix("## ") { Text(String(line.dropFirst(3))).font(.system(size: 16, weight: .semibold)).padding(.top, 12) }
                else if line.hasPrefix("### ") { Text(String(line.dropFirst(4))).font(.system(size: 14, weight: .semibold)).padding(.top, 8) }
                else if !line.isEmpty { Text(MarkdownText.attributed(line)).font(.system(size: 13)).lineSpacing(4) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
    }
}

// MARK: Темное стекло оверлея (P00, P01–P06)

/// Поверхности оверлея: стекло #16181D 82% поверх размытия, карточки и кнопки — светлые полупрозрачные.
enum ICDark {
    static let glass = Color(hex: 0x16181D).opacity(0.82)
    static let surface = Color.white.opacity(0.05)
    static let raised = Color.white.opacity(0.08)
    static let stroke = Color.white.opacity(0.11)
    static let secondary = Color.white.opacity(0.58)
    static let divider = Color.white.opacity(0.09)
}

/// Кнопка оверлея: иконка, подпись и подсказка клавиши (P01: «Ответ ⌘↩»).
struct ICOverlayButton: View {
    let title: String
    let icon: String
    var keys: String? = nil
    var size: Double = 13
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            // Узкий оверлей: сначала без иконки, затем без подсказки клавиши — подпись не обрезается.
            ViewThatFits(in: .horizontal) {
                label(icon: true, keys: true)
                label(icon: false, keys: true)
                label(icon: true, keys: false)
                label(icon: false, keys: false)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(ICDark.surface, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(ICDark.stroke))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(keys.map { "\(title), \($0)" } ?? title)
    }

    private func label(icon showIcon: Bool, keys showKeys: Bool) -> some View {
        HStack(spacing: 6) {
            if showIcon { Image(systemName: icon).font(.system(size: size - 1)) }
            Text(title).font(.system(size: size - 1, weight: .medium)).lineLimit(1).fixedSize()
            if showKeys, let keys { ICKeycap(text: keys, dark: true) }
        }
    }
}

/// Статусная пилюля с точкой (P00: «Слушаю», «Проверяю», «Ошибка»).
struct ICStatusPill: View {
    let text: String
    let color: Color
    var dark = true
    var spinner = false
    var size: Double = 12
    var body: some View {
        HStack(spacing: 7) {
            if spinner { ProgressView().controlSize(.mini) } else { Circle().fill(color).frame(width: 8, height: 8) }
            Text(text).lineLimit(1)
        }
        .font(.system(size: size, weight: .medium))
        .foregroundStyle(dark ? color.opacity(0.95) : color)
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(color.opacity(dark ? 0.16 : 0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(dark ? 0.28 : 0)))
        .accessibilityElement(children: .combine)
    }
}
