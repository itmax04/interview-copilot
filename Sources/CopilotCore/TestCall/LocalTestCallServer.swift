import Foundation
@preconcurrency import Network

public struct LocalHTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data
}

public struct LocalHTTPResponse: Sendable {
    public let status: Int
    public let body: Data
    public let contentType: String
    public let headers: [String: String]

    public init(status: Int = 200, body: Data, contentType: String = "application/json", headers: [String: String] = [:]) {
        self.status = status; self.body = body; self.contentType = contentType; self.headers = headers
    }
    public static func error(_ status: Int, _ message: String) -> Self {
        Self(status: status, body: (try? JSONEncoder().encode(["error": message])) ?? Data())
    }
}

public enum LocalHTTPParser {
    public enum Result: Sendable {
        case incomplete, invalid
        case request(LocalHTTPRequest)
    }
    public static func parse(_ data: Data) -> Result {
        guard data.count <= 32_768 else { return .invalid }
        let boundary = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: boundary) else { return .incomplete }
        guard let text = String(data: data[..<range.lowerBound], encoding: .utf8) else { return .invalid }
        let lines = text.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count == 3, ["GET", "POST"].contains(String(parts[0])), parts[1].hasPrefix("/"), parts[2] == "HTTP/1.1" else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            let key = String(line[..<colon]).lowercased()
            guard headers[key] == nil else { return .invalid }
            headers[key] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil,
              let count = Int(headers["content-length"] ?? "0"), count >= 0, count <= 8192 else { return .invalid }
        let body = Data(data[range.upperBound...])
        guard body.count >= count else { return .incomplete }
        return .request(LocalHTTPRequest(method: String(parts[0]), path: String(parts[1]), headers: headers, body: Data(body.prefix(count))))
    }
}

/// Доступен только на loopback. Контроллер дополнительно проверяет Host, Origin и токен сеанса.
public final class LocalTestCallServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.itmax04.interviewcopilot.test-call")
    private let handler: @MainActor @Sendable (LocalHTTPRequest) async -> LocalHTTPResponse

    public init(handler: @escaping @MainActor @Sendable (LocalHTTPRequest) async -> LocalHTTPResponse) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        self.handler = handler
    }

    public func start(onReady: @escaping @MainActor @Sendable (UInt16) -> Void,
                      onError: @escaping @MainActor @Sendable (String) -> Void) {
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = self?.listener.port?.rawValue { Task { @MainActor in onReady(port) } }
            case .failed(let error): Task { @MainActor in onError(error.localizedDescription) }
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            connection.start(queue: self.queue)
            self.receive(connection, accumulated: Data())
        }
        listener.start(queue: queue)
    }

    public func stop() { listener.cancel() }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var buffer = accumulated
            if let data { buffer.append(data) }
            switch LocalHTTPParser.parse(buffer) {
            case .request(let request):
                Task { @MainActor in self.send(await self.handler(request), on: connection) }
            case .invalid: self.send(.error(400, "Неверный запрос"), on: connection)
            case .incomplete:
                if complete || error != nil { connection.cancel() }
                else { self.receive(connection, accumulated: buffer) }
            }
        }
    }

    private func send(_ response: LocalHTTPResponse, on connection: NWConnection) {
        let reason = response.status == 200 ? "OK" : response.status == 206 ? "Partial Content" : "Error"
        var header = "HTTP/1.1 \(response.status) \(reason)\r\nContent-Type: \(response.contentType)\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n"
        header += "Content-Security-Policy: default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; media-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'\r\n"
        for (key, value) in response.headers { header += "\(key): \(value)\r\n" }
        connection.send(content: Data((header + "\r\n").utf8) + response.body, completion: .contentProcessed { _ in connection.cancel() })
    }
}
