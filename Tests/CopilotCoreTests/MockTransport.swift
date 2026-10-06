import Foundation
@testable import CopilotCore

/// Подменный транспорт: отвечает заранее заданными ответами и запоминает запросы.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)
    private let handler: Handler
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _requests }

    init(_ handler: @escaping Handler) { self.handler = handler }

    convenience init(status: Int, json: String) {
        self.init { _ in (status, Data(json.utf8)) }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _requests.append(request) }
        let (status, data) = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (data, response)
    }
}
