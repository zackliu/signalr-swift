import Foundation
import Starscream

// MARK: - WebSocketTransport

class WebSocketTransport: NSObject, ITransport, WebSocketDelegate {
    private let logger: ILogger
    private let accessTokenFactory: (() -> String)?
    private let logMessageContent: Bool
    private var webSocket: WebSocket?
    private let httpClient: HttpClient
    private let headers: [String: String]
    private var connectContinuation: CheckedContinuation<Void, Error>?

    var onReceive: ((Data) -> Void)?
    var onClose: ((Error?) -> Void)?

    init(httpClient: HttpClient,
         accessTokenFactory: (() -> String)?,
         logger: ILogger,
         logMessageContent: Bool,
         headers: [String: String]) {
        self.httpClient = httpClient
        self.accessTokenFactory = accessTokenFactory
        self.logger = logger
        self.logMessageContent = logMessageContent
        self.headers = headers
    }

    func connect(url: URL, transferFormat: TransferFormat) async throws {
        self.logger.log(.trace, message: "(WebSockets transport) Connecting.")

        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if urlComponents?.scheme == "http" {
            urlComponents?.scheme = "ws"
        } else if urlComponents?.scheme == "https" {
            urlComponents?.scheme = "wss"
        }

        guard let wsUrl = urlComponents?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: wsUrl)

        if let token = self.accessTokenFactory?() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        for (header, value) in self.headers {
            request.setValue(value, forHTTPHeaderField: header)
        }

        self.webSocket = WebSocket(request: request)
        self.webSocket?.delegate = self
        self.webSocket?.connect()

        // Wait for the connection to be established
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.connectContinuation = continuation
        }
    }

    func send(data: Data) async throws {
        guard let webSocket = self.webSocket, webSocket.isConnected else {
            throw NSError(domain: "WebSocketTransport",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "WebSocket is not in the OPEN state"])
        }

        self.logger.log(.trace, message: "(WebSockets transport) sending data. \(data).")

        webSocket.write(data: data)
    }

    func stop() async {
        if let webSocket = self.webSocket {
            webSocket.disconnect()
            self.webSocket = nil
            self.logger.log(.trace, message: "(WebSockets transport) socket closed.")
            self.onClose?(nil)
        }
    }

    private func close(error: Error?) {
        if let webSocket = self.webSocket {
            webSocket.disconnect()
            self.webSocket = nil
            self.logger.log(.trace, message: "(WebSockets transport) socket closed.")
            self.onClose?(error)
        }
    }

    // MARK: - WebSocketDelegate methods

    func websocketDidConnect(socket: WebSocketClient) {
        self.logger.log(.information, message: "WebSocket connected to \(socket.currentURL).")
        self.connectContinuation?.resume()
        self.connectContinuation = nil
    }

    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        self.logger.log(.information, message: "WebSocket disconnected.")
        if let continuation = self.connectContinuation {
            continuation.resume(throwing: error ?? NSError(domain: "WebSocketTransport",
                                                           code: -1,
                                                           userInfo: [NSLocalizedDescriptionKey: "WebSocket disconnected before connection established."]))
            self.connectContinuation = nil
        } else {
            self.close(error: error)
        }
    }

    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        self.logger.log(.trace, message: "(WebSockets transport) data received. \(text).")
        self.onReceive?(Data(text.utf8))
    }

    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        self.logger.log(.trace, message: "(WebSockets transport) data received. \(data.count) bytes.")
        self.onReceive?(data)
    }
}
