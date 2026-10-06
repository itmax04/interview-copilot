import Foundation

/// Векторное представление текста для поиска по смыслу (R-07). Реализация на llama.cpp — цель `CopilotEmbeddings`
/// (отдельно от whisper: у обоих фреймворков свои заголовки ggml, в одном модуле Swift они конфликтуют).
public protocol TextEmbedder: AnyObject, Sendable {
    /// Идентификатор модели и способа подготовки текста — ключ кэша эмбеддингов.
    var identifier: String { get }
    /// L2-нормированные векторы.
    func embed(_ texts: [String]) throws -> [[Float]]
}

public extension Array where Element == Float {
    /// Косинусное сходство нормированных векторов.
    func dot(_ other: [Float]) -> Float {
        var s: Float = 0
        for i in 0..<Swift.min(count, other.count) { s += self[i] * other[i] }
        return s
    }

    func normalized() -> [Float] {
        let n = dot(self).squareRoot()
        return n > 0 ? map { $0 / n } : self
    }
}
