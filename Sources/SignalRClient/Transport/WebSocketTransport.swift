import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif


final class WebSocketTransport: ITransport, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let logger: Logger
    private let accessTokenFactory: @Sendable() throws -> String?
    private let logMessageContent: Bool
    private let headers: [String: String]
    private var transferFormat: TransferFormat = .text

    var onReceive: OnReceiveHandler?
    var onClose: OnCloseHander?

    init(httpClient: HttpClient,
         accessTokenFactory: @escaping @Sendable () throws -> String?,
         logger: Logger,
         logMessageContent: Bool,
         headers: [String: String]) {
        self.accessTokenFactory = accessTokenFactory
        self.logger = logger
        self.logMessageContent = logMessageContent
        self.headers = headers
    }

    func connect(url: String, transferFormat: TransferFormat) async throws {
        await self.logger.log(level: .debug, message: "(WebSockets transport) Connecting.")

        self.transferFormat = transferFormat

        var urlComponents = URLComponents(url: URL(string: url)!, resolvingAgainstBaseURL: false)!

        if urlComponents.scheme == "http" {
            urlComponents.scheme = "ws"
        } else if urlComponents.scheme == "https" {
            urlComponents.scheme = "wss"
        }

        let session = URLSession.shared
        var request = URLRequest(url: urlComponents.url!)
        let websocketTask = session.webSocketTask(with: request)

        websocketTask.resume()

        // Prepare headers
        var requestHeaders = HTTPHeaders()
        // Add custom headers
        for (name, value) in self.headers {
            requestHeaders.add(name: name, value: value)
        }

        // Add Authorization header if token is available
        if let token = try self.accessTokenFactory?() {
            requestHeaders.add(name: "Authorization", value: "Bearer \(token)")
        }

        guard let wsUrl = urlComponents.url else {
            throw URLError(.badURL)
        }

        let client = WebSocketClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        client.connect(scheme: urlComponents.scheme!, host: urlComponents.host!, port: urlComponents.port!, path: urlComponents.path, query: urlComponents.query, headers: requestHeaders) { [weak self] ws in
            guard let self = self else {
                return
            }

            self.websocket = ws

            ws.onText {[weak self] _, text in
                self?.onReceive?(.string(text))
            }

            ws.onBinary {[weak self] _, buffer in
                if let data = buffer.getData(at: 0, length: buffer.readableBytes) {
                   self?.onReceive?(.data(data))
                }
            }
        }.whenFailure { error in
            print("Failed to connect: \(error)")
            // mark close
        }
    }

    func send(_ data: StringOrData) async throws {
        guard let ws = self.websocket else {
            throw NSError(domain: "WebSocketTransport",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "WebSocket is not in the OPEN state"])
        }

        switch data {
            case .string(let str):
                try await ws.send(str)
            case .data(let data):
                try await ws.send(raw: data, opcode: .binary)
            default:
                throw NSError(domain: "WebSocketTransport",
                              code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Invalid data type"]) 
        }
    }

    func stop() async throws {
        defer {
            websocket = nil
        }
        do {
            try await websocket?.close()
            onClose?(nil)
        } catch {
            self.logger.log(level: .error, message: "(WebSockets transport) Error closing socket: \(error)")
            onClose?(error)
        } 
    }
}