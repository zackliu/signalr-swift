import Foundation
import WebSocketKit
import NIO

final class WebSocketTransport: ITransport {
    private let logger: ILogger
    private let accessTokenFactory: (() throws -> String)?
    private let logMessageContent: Bool
    private let httpClient: HttpClient
    private let headers: [String: String]
    private var websocket: WebSocket?
    private let eventLoopGroup: EventLoopGroup
    private var transferFormat: TransferFormat = .text

    var onReceive: ((StringOrData) -> Void)?
    var onClose: ((Error?) -> Void)?

    init(httpClient: HttpClient,
         accessTokenFactory: (() throws -> String)?,
         logger: ILogger,
         logMessageContent: Bool,
         headers: [String: String],
         eventLoopGroup: EventLoopGroup? = nil) {
        self.httpClient = httpClient
        self.accessTokenFactory = accessTokenFactory
        self.logger = logger
        self.logMessageContent = logMessageContent
        self.headers = headers
        self.eventLoopGroup = eventLoopGroup ?? MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    func connect(url: String, transferFormat: TransferFormat) async throws {
        self.logger.log(level: .debug, message: "(WebSockets transport) Connecting.")

        self.transferFormat = transferFormat

        var urlComponents = URLComponents(url: URL(string: url)!, resolvingAgainstBaseURL: false)!

        if urlComponents.scheme == "http" {
            urlComponents.scheme = "ws"
        } else if urlComponents.scheme == "https" {
            urlComponents.scheme = "wss"
        }

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

        let accessQueue = DispatchQueue(label: "com.customWebSocketClient.queue")

        let client = WebSocketClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        client.connect(scheme: urlComponents.scheme!, host: urlComponents.host!, port: urlComponents.port!, path: urlComponents.path, query: urlComponents.query, headers: requestHeaders) { [weak self] ws in
            // self?.websocket = ws
            accessQueue.async {
                ws.onText { [weak self] _, text in
                    self?.onReceive?(.string(text))
                }

                ws.onBinary { [weak self] _, buffer in
                    if let data = buffer.getData(at: 0, length: buffer.readableBytes) {
                        self?.onReceive?(.data(data))
                    }
                }
            }
            
        }.whenFailure { error in
            print("Failed to connect: \(error)")
            // mark close
        }

        let promise = self.eventLoopGroup.next().makePromise(of: Void.self)

        WebSocket.connect(to: wsUrl.absoluteString, headers: requestHeaders, on: self.eventLoopGroup) { [weak self] ws in
            guard let self = self else { return }
            self.websocket = ws
            self.logger.log(.information, message: "WebSocket connected to \(wsUrl).")

            // Set up receive handlers
            ws.onText { [weak self] ws, text in
                guard let self = self else { return }
                self.logger.log(.trace, message: "(WebSockets transport) received text.")
                if self.logMessageContent {
                    self.logger.log(.trace, message: "Received text: \(text)")
                }
                var buffer = ws.channel.allocator.buffer(capacity: text.utf8.count)
                buffer.writeString(text)
                self.onReceive?(buffer)
            }

            ws.onBinary { [weak self] ws, data in
                guard let self = self else { return }
                self.logger.log(.trace, message: "(WebSockets transport) received binary data.")
                if self.logMessageContent {
                    self.logger.log(.trace, message: "Received data: \(data.readableBytes) bytes.")
                }
                self.onReceive?(data)
            }

            ws.onClose.whenComplete { [weak self] result in
                guard let self = self else { return }
                self.logger.log(.trace, message: "(WebSockets transport) socket closed.")
                switch result {
                case .success:
                    self.onClose?(nil)
                case .failure(let error):
                    self.onClose?(error)
                }
            }

            promise.succeed(())
        }.whenFailure { [weak self] error in
            self?.logger.log(.error, message: "WebSocket connection failed: \(error)")
            self?.onClose?(error)
            promise.fail(error)
        }

        // Wait for the connection to be established
        try promise.futureResult.wait()
        
    }

    private func receiveMessagesLoop() async {
        guard let webSocketTask = self.webSocketTask, !self.isStopped else {
            return
        }

        while !self.isStopped {
            do {
                let result = try await webSocketTask.receive()
                switch result {
                case .string(let text):
                    if self.logMessageContent {
                        self.logger.log(level: .debug, message: "Received text: \(text)")
                    }
                    self.onReceive?(.string(text))
                case .data(let data):
                    if self.logMessageContent {
                        self.logger.log(level: .debug , message: "Received data: \(data)")
                    }
                    self.onReceive?(.data(data))
                @unknown default:
                    self.logger.log(level: .error, message: "Received unknown message type")
                }
            } catch {
                self.logger.log(level: .error, message: "WebSocket receive error: \(error)")
                self.onClose?(error)
                break
            }
        }
    }

    func send(_ data: StringOrData) async throws {
        guard let webSocketTask = self.webSocketTask else {
            throw NSError(domain: "WebSocketTransport",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "WebSocket is not in the OPEN state"])
        }

        let message: URLSessionWebSocketTask.Message
        switch data {
            case .string(let str):
                message = .string(str)
            case .data(let da):
                message = .data(da)
        }

        self.logger.log(level: .debug, message: "(WebSockets transport) sending data.")

        try await webSocketTask.send(message)
    }

    func stop() async {
        self.isStopped = true
        self.webSocketTask?.cancel(with: .goingAway, reason: nil)
        self.webSocketTask = nil
        self.logger.log(level: .debug, message: "(WebSockets transport) socket closed.")
        self.onClose?(nil)
    }
}