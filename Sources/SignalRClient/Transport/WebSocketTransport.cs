import Foundation

// MARK: - WebSocketTransport

class WebSocketTransport: ITransport {
    private let logger: ILogger
    private let accessTokenFactory: (() async throws -> String?)?
    private let logMessageContent: Bool
    private let webSocketConstructor: WebSocket.Type
    private let httpClient: HttpClient
    private var webSocket: WebSocket?
    private var headers: [String: String]
    
    var onReceive: ((String) -> Void)?
    var onClose: ((Error?) -> Void)?
    
    init(httpClient: HttpClient,
         accessTokenFactory: (() async throws -> String?)?,
         logger: ILogger,
         logMessageContent: Bool,
         webSocketConstructor: WebSocket.Type,
         headers: [String: String]) {
        self.httpClient = httpClient
        self.accessTokenFactory = accessTokenFactory
        self.logger = logger
        self.logMessageContent = logMessageContent
        self.webSocketConstructor = webSocketConstructor
        self.headers = headers
    }
    
    func connect(url: String, transferFormat: TransferFormat) async throws {
        precondition(!url.isEmpty, "url is required")
        logger.log(level: .trace, message: "(WebSockets transport) Connecting.")
        
        var token: String? = nil
        if let factory = accessTokenFactory {
            token = try await factory()
        }
        
        var webSocketUrl = url.replacingOccurrences(of: "^http", with: "ws", options: .regularExpression)
        
        if let token = token {
            if var urlComponents = URLComponents(string: webSocketUrl) {
                var queryItems = urlComponents.queryItems ?? []
                queryItems.append(URLQueryItem(name: "access_token", value: token))
                urlComponents.queryItems = queryItems
                webSocketUrl = urlComponents.string ?? webSocketUrl
            }
        }
        
        let request = URLRequest(url: URL(string: webSocketUrl)!)
        let cookies = httpClient.getCookieString(url: webSocketUrl)
        
        var ws: WebSocket
        if let token = token {
            var headers = self.headers
            headers["Authorization"] = "Bearer \(token)"
            if !cookies.isEmpty {
                headers["Cookie"] = cookies
            }
            ws = webSocketConstructor.init(request: request, headers: headers)
        } else {
            ws = webSocketConstructor.init(request: request)
        }
        
        if transferFormat == .binary {
            ws.binaryType = .data
        }
        
        self.webSocket = ws
        var isOpen = false
        
        ws.onOpen = { [weak self] in
            self?.logger.log(level: .information, message: "WebSocket connected to \(webSocketUrl).")
            isOpen = true
        }
        
        ws.onMessage = { [weak self] data in
            guard let self = self else { return }
            self.logger.log(level: .trace, message: "(WebSockets transport) data received.")
            if let onReceive = self.onReceive {
                onReceive(data)
            }
        }
        
        ws.onError = { [weak self] error in
            self?.logger.log(level: .information, message: "(WebSockets transport) \(error.localizedDescription).")
        }
        
        ws.onClose = { [weak self] code, reason, wasClean in
            guard let self = self else { return }
            if isOpen {
                self.close(error: NSError(domain: reason ?? "WebSocket closed", code: code, userInfo: nil))
            } else {
                let error = NSError(domain: "WebSocket failed to connect.", code: code, userInfo: nil)
                self.close(error: error)
            }
        }
        
        ws.connect()
    }
    
    func send(_ data: String) async throws {
        guard let ws = webSocket, ws.readyState == .open else {
            throw NSError(domain: "WebSocket is not in the OPEN state", code: 0)
        }
        
        logger.log(level: .trace, message: "(WebSockets transport) sending data.")
        ws.send(data: data)
    }
    
    func stop() async throws {
        if let ws = webSocket {
            close(error: nil)
        }
    }
    
    private func close(error: Error?) {
        if let ws = webSocket {
            ws.onClose = nil
            ws.onMessage = nil
            ws.onError = nil
            ws.onOpen = nil
            ws.close()
            webSocket = nil
        }
        
        logger.log(level: .trace, message: "(WebSockets transport) socket closed.")
        
        if let onClose = onClose {
            onClose(error)
        }
    }
}

// MARK: - WebSocket Class (Placeholder)

class WebSocket {
    enum ReadyState {
        case connecting, open, closing, closed
    }
    
    var readyState: ReadyState = .connecting
    var binaryType: BinaryType = .data
    
    var onOpen: (() -> Void)?
    var onMessage: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    var onClose: ((Int, String?, Bool) -> Void)?
    
    enum BinaryType {
        case blob, data
    }
    
    required init(request: URLRequest, headers: [String: String]? = nil) {
        // Implement WebSocket initialization with request and headers
    }
    
    func connect() {
        // Implement connection logic
        // On successful connection, set readyState to .open and call onOpen
    }
    
    func send(data: String) {
        // Implement send logic
    }
    
    func close() {
        // Implement close logic
        // On close, set readyState to .closed and call onClose
    }
}
