import CopilotCore
import Foundation
import llama

public enum EmbedderError: Error, CustomStringConvertible {
    case modelNotFound(String)
    case loadFailed(String)
    case tokenizeFailed
    case decodeFailed(Int32)
    case noEmbeddings

    public var description: String {
        switch self {
        case .modelNotFound(let p): L10n.f("Модель эмбеддингов не найдена: %@", "\(p)")
        case .loadFailed(let p): L10n.f("Не удалось загрузить модель эмбеддингов: %@", "\(p)")
        case .tokenizeFailed: L10n.t("Ошибка токенизации")
        case .decodeFailed(let c): L10n.f("llama_decode/encode вернул %@", "\(c)")
        case .noEmbeddings: L10n.t("Модель не вернула эмбеддинг")
        }
    }
}

/// Эмбеддинги через llama.cpp (ADR-0001 п. 6). Модели — GGUF из ggml-org, проверены по SHA256 (R-22).
public final class LlamaEmbedder: TextEmbedder, @unchecked Sendable {
    public let identifier: String
    private let model: OpaquePointer
    private let ctx: OpaquePointer
    private let vocab: OpaquePointer
    private let nEmbd: Int
    private let maxTokens: Int
    private let prefix: String
    private let lock = NSLock()

    private static let backendInit: Void = {
        if ProcessInfo.processInfo.environment["INTERVIEWCOPILOT_LLAMA_LOG"] == nil {
            llama_log_set({ _, _, _ in }, nil)
        }
        llama_backend_init()
    }()

    /// `prefix` — подготовка текста под модель (например, «task: sentence similarity | query: » для EmbeddingGemma).
    public init(modelPath: String, prefix: String = "", useGPU: Bool = true) throws {
        guard FileManager.default.fileExists(atPath: modelPath) else { throw EmbedderError.modelNotFound(modelPath) }
        _ = Self.backendInit
        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = useGPU ? 999 : 0
        guard let model = llama_model_load_from_file(modelPath, mparams) else { throw EmbedderError.loadFailed(modelPath) }
        var cparams = llama_context_default_params()
        cparams.embeddings = true
        cparams.n_ctx = 512
        cparams.n_batch = 512
        cparams.n_ubatch = 512
        cparams.n_seq_max = 1
        cparams.n_threads = 4
        cparams.n_threads_batch = 4
        cparams.pooling_type = LLAMA_POOLING_TYPE_UNSPECIFIED // по умолчанию модели
        guard let ctx = llama_init_from_model(model, cparams) else {
            llama_model_free(model)
            throw EmbedderError.loadFailed(modelPath)
        }
        self.model = model
        self.ctx = ctx
        self.vocab = llama_model_get_vocab(model)
        self.nEmbd = Int(llama_model_n_embd_out(model) > 0 ? llama_model_n_embd_out(model) : llama_model_n_embd(model))
        self.maxTokens = 512
        self.prefix = prefix
        self.identifier = (modelPath as NSString).lastPathComponent + "|" + prefix
    }

    deinit {
        llama_free(ctx)
        llama_model_free(model)
    }

    public func embed(_ texts: [String]) throws -> [[Float]] {
        lock.lock()
        defer { lock.unlock() }
        return try texts.map { try embedOne(prefix + $0) }
    }

    private func embedOne(_ text: String) throws -> [Float] {
        let utf8 = Array(text.utf8CString)
        var tokens = [llama_token](repeating: 0, count: maxTokens)
        let n = utf8.withUnsafeBufferPointer { buf in
            llama_tokenize(vocab, buf.baseAddress, Int32(utf8.count - 1), &tokens, Int32(maxTokens), true, true)
        }
        guard n > 0 else { throw EmbedderError.tokenizeFailed }
        if let mem = llama_get_memory(ctx) { llama_memory_clear(mem, true) }

        var batch = llama_batch_init(Int32(n), 0, 1)
        defer { llama_batch_free(batch) }
        for i in 0..<Int(n) {
            batch.token[i] = tokens[i]
            batch.pos[i] = llama_pos(i)
            batch.n_seq_id[i] = 1
            batch.seq_id[i]![0] = 0
            batch.logits[i] = 1
        }
        batch.n_tokens = n
        let rc = llama_model_has_encoder(model) && !llama_model_has_decoder(model)
            ? llama_encode(ctx, batch) : llama_decode(ctx, batch)
        guard rc == 0 else { throw EmbedderError.decodeFailed(rc) }

        let pointer: UnsafeMutablePointer<Float>?
        if llama_pooling_type(ctx) == LLAMA_POOLING_TYPE_NONE {
            pointer = llama_get_embeddings_ith(ctx, n - 1)
        } else {
            pointer = llama_get_embeddings_seq(ctx, 0)
        }
        guard let pointer else { throw EmbedderError.noEmbeddings }
        return Array(UnsafeBufferPointer(start: pointer, count: nEmbd)).normalized()
    }
}

/// Известные модели и подготовка текста (карточки и ход сравниваются как «вопрос ↔ вопрос»).
public enum EmbeddingModels {
    public struct Spec: Sendable {
        public var file: String
        public var prefix: String
    }

    public static let embeddingGemma2 = Spec(file: "embeddinggemma-2-Q8_0.gguf", prefix: "task: sentence similarity | query: ")
    public static let embeddingGemma300M = Spec(file: "embeddinggemma-300M-Q8_0.gguf", prefix: "task: sentence similarity | query: ")
    public static let bgeM3 = Spec(file: "bge-m3-q8_0.gguf", prefix: "")
    public static let all = [embeddingGemma2, embeddingGemma300M, bgeM3]

    public static func spec(for file: String) -> Spec {
        all.first { $0.file == file } ?? Spec(file: file, prefix: "")
    }
}
