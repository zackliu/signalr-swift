import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif


final class WebSocketTransport: NSObject, ITransport, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let logger: Logger
    private let accessTokenFactory: (@Sendable() async throws -> String?)?
    private let logMessageContent: Bool
    private let headers: [String: String]
    private var transferFormat: TransferFormat = .text
    private var websocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    var onReceive: OnReceiveHandler?
    var onClose: OnCloseHander?

    init(httpClient: HttpClient,
         accessTokenFactory: (@Sendable () async throws -> String?)?,
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

        let urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue()) 
        var request = URLRequest(url: urlComponents.url!)
        let websocket = urlSession.webSocketTask(with: request)

        websocket.resume()

        Task {
            await receiveMessage()
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
                try await ws.send(URLSessionWebSocketTask.Message.string(str))
            case .data(let data):
                try await ws.send(URLSessionWebSocketTask.Message.data(data))
            default:
                throw NSError(domain: "WebSocketTransport",
                              code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Invalid data type"]) 
        }
    }

    func stop() async throws {
        websocket?.cancel()
        urlSession?.finishTasksAndInvalidate()
        await onClose?(nil)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        self.logger.log(level: .debug, message: "WebSocket closed.")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        self.logger.log(level: .debug, message: "WebSocket opened.")
    }

    private func receiveMessage() async {
        guard let websocket = websocket else { return }
        
        do {
            while true {
                let message = try await websocket.receive()

                switch message {
                    case .string(let text):
                        await onReceive?(.string(text))
                    case .data(let data):
                        await onReceive?(.data(data))
                }
            }
        } catch {
            print("Failed to receive message: \(error)")
            // You might want to handle reconnection logic here if needed
        }
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }
}