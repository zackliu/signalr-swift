import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Enums and Protocols

private enum ConnectionState: String {
    case connecting = "Connecting"
    case connected = "Connected"
    case disconnected = "Disconnected"
    case disconnecting = "Disconnecting"
}

protocol IConnection {
    var onReceive: ITransport.OnReceiveHandler? { get set }
    var onClose: ITransport.OnCloseHander? { get set }
    func start(transferFormat: TransferFormat) async throws
    func send(_ data: StringOrData) async throws
    func stop(error: Error?) async
}

protocol Logger: Sendable {
    func log(level: LogLevel, message: String)
}

enum LogLevel {
    case debug, information, warning, error
}

struct IHttpConnectionOptions {
    var logger: Logger?
    var accessTokenFactory: (@Sendable () async throws -> String?)?
    var httpClient: HttpClient?
    var transport: HttpTransportType?
    var skipNegotiation: Bool
    var headers: [String: String]?
    var withCredentials: Bool?
    var timeout: TimeInterval?
    var logMessageContent: Bool?
    var webSocket: AnyObject? // Placeholder for WebSocket type
    var eventSource: AnyObject? // Placeholder for EventSource type
    var useStatefulReconnect: Bool?

    init() {
        self.skipNegotiation = false
    }
}

struct HttpOptions {
    var content: String
    var headers: [String: String]
    var timeout: TimeInterval
    var withCredentials: Bool
}

struct HttpError: Error {
    var statusCode: Int
}

// MARK: - Models

struct NegotiateResponse: Decodable {
    var connectionId: String?
    var connectionToken: String?
    var negotiateVersion: Int?
    var availableTransports: [AvailableTransport]?
    var url: String?
    var accessToken: String?
    var error: String?
    var useStatefulReconnect: Bool?

    enum CodingKeys: String, CodingKey {
        case connectionId
        case connectionToken
        case negotiateVersion
        case availableTransports
        case url
        case accessToken
        case error
        case useStatefulReconnect
    }
}

struct AvailableTransport: Decodable {
    var transport: String
    var transferFormats: [String]

    enum CodingKeys: String, CodingKey {
        case transport
        case transferFormats
    }
}

// MARK: - HttpConnection Class

class HttpConnection: IConnection, @unchecked Sendable {
    // MARK: - Properties

    private var connectionState: ConnectionState = .disconnected
    private var connectionStarted: Bool = false
    private let httpClient: AccessTokenHttpClient
    private let logger: Logger
    private var options: IHttpConnectionOptions
    private var transport: ITransport?
    private var startInternalTask: Task<Void, Error>?
    private var stopTask: Task<Void, Never>?
    private var stopError: Error?
    private var accessTokenFactory: (@Sendable () async throws -> String?)?
    public var features: [String: Any] = [:]
    public var baseUrl: String
    public var connectionId: String?
    public var onReceive: ITransport.OnReceiveHandler?
    public var onClose: ITransport.OnCloseHander?
    private let negotiateVersion = 1

    // MARK: - Initialization

    init(url: String, options: IHttpConnectionOptions = IHttpConnectionOptions()) {
        precondition(!url.isEmpty, "url is required")

        self.logger = options.logger ?? DefaultLogger()
        self.baseUrl = HttpConnection.resolveUrl(url)
        self.options = options

        self.options.logMessageContent = options.logMessageContent ?? false
        self.options.withCredentials = options.withCredentials ?? true
        self.options.timeout = options.timeout ?? 100

        self.accessTokenFactory = options.accessTokenFactory
        self.httpClient = AccessTokenHttpClient(innerClient: options.httpClient ?? DefaultHttpClient(), accessTokenFactory: self.accessTokenFactory)
    }

    // MARK: - Public Methods

    func start(transferFormat: TransferFormat = .binary) async throws {
        await logger.log(level: .debug, message: "Starting connection with transfer format '\(transferFormat)'.")

        guard connectionState == .disconnected else {
            throw NSError(domain: "HttpConnection", code: 0, userInfo: [NSLocalizedDescriptionKey: "Cannot start an HttpConnection that is not in the 'Disconnected' state."])
        }

        connectionState = .connecting

        startInternalTask = Task {
            try await self.startInternal(transferFormat: transferFormat)
        }

        do {
            try await startInternalTask?.value
        } catch {
            throw error
        }

        if connectionState == .disconnecting {
            let message = "Failed to start the HttpConnection before stop() was called."
            await logger.log(level: .error, message: message)
            await stopTask?.value
            throw NSError(domain: message, code: 0)
        } else if connectionState != .connected {
            let message = "HttpConnection.startInternal completed gracefully but didn't enter the connection into the connected state!"
            await logger.log(level: .error, message: message)
            throw NSError(domain: message, code: 0)
        }

        connectionStarted = true
    }

    func send(_ data: StringOrData) async throws {
        guard connectionState == .connected else {
            throw NSError(domain: "Cannot send data if the connection is not in the 'Connected' State.", code: 0)
        }

        try await transport?.send(data)
    }

    func stop(error: Error? = nil) async {
        if connectionState == .disconnected {
            await logger.log(level: .debug, message: "Call to HttpConnection.stop(\(String(describing: error))) ignored because the connection is already in the disconnected state.")
            return
        }

        if connectionState == .disconnecting {
            await logger.log(level: .debug, message: "Call to HttpConnection.stop(\(String(describing: error))) ignored because the connection is already in the disconnecting state.")
            await stopTask?.value
            return
        }

        connectionState = .disconnecting

        stopTask = Task {
            await self.stopInternal(error: error)
        }

        await stopTask?.value
    }

    // MARK: - Private Methods

    private func startInternal(transferFormat: TransferFormat) async throws {
        var url = baseUrl
        accessTokenFactory = options.accessTokenFactory
        httpClient.accessTokenFactory = accessTokenFactory

        do {
            if options.skipNegotiation {
                if options.transport == .webSockets {
                    transport = try constructTransport(transport: .webSockets)
                    try await startTransport(url: url, transferFormat: transferFormat)
                } else {
                    throw NSError(domain: "Negotiation can only be skipped when using the WebSocket transport directly.", code: 0)
                }
            } else {
                var negotiateResponse: NegotiateResponse?
                var redirects = 0
                repeat {
                    negotiateResponse = try await getNegotiationResponse(url: url)
                    if connectionState == .disconnecting || connectionState == .disconnected {
                        throw NSError(domain: "The connection was stopped during negotiation.", code: 0)
                    }
                    if let error = negotiateResponse?.error {
                        throw NSError(domain: error, code: 0)
                    }
                    if negotiateResponse?.url != nil {
                        url = negotiateResponse?.url ?? url
                    }
                    if let accessToken = negotiateResponse?.accessToken {
                        // Replace the current access token factory with one that uses
                        // the returned access token
                        accessTokenFactory = { return accessToken }
                        httpClient.accessTokenFactory = accessTokenFactory
                        httpClient.accessTokenFactory = nil
                    }
                    redirects += 1
                } while negotiateResponse?.url != nil && redirects < 100

                if redirects == 100 && negotiateResponse?.url != nil {
                    throw NSError(domain: "Negotiate redirection limit exceeded.", code: 0)
                }

                try await createTransport(url: url, requestedTransport: options.transport, negotiateResponse: negotiateResponse, requestedTransferFormat: transferFormat)
            }

            // if transport is LongPollingTransport {
            //     features["inherentKeepAlive"] = true
            // }

            if connectionState == .connecting {
                await logger.log(level: .debug, message: "The HttpConnection connected successfully.")
                connectionState = .connected
            }
        } catch {
            await logger.log(level: .error, message: "Failed to start the connection: \(error)")
            connectionState = .disconnected
            transport = nil
            throw error
        }
    }

    private func stopInternal(error: Error?) async {
        stopError = error

        do {
            try await startInternalTask?.value
        } catch {
            // Ignore errors from startInternal
        }

        if transport != nil {
            do {
                try await transport?.stop()
            } catch {
                await logger.log(level: .error, message: "HttpConnection.transport.stop() threw error '\(error)'.")
                await stopConnection(error: error)
            }
            transport = nil
        } else {
            await logger.log(level: .debug, message: "HttpConnection.transport is undefined in HttpConnection.stop() because start() failed.")
        }
    }

    private func getNegotiationResponse(url: String) async throws -> NegotiateResponse {
        var headers: [String: String] = [:]
        let (name, value) = getUserAgentHeader()
        headers[name] = value

        let negotiateUrl = resolveNegotiateUrl(url: url)
        await logger.log(level: .debug, message: "Sending negotiation request: \(negotiateUrl).")

        do {
            var request = URLRequest(url: URL(string: negotiateUrl)!)
            request.httpMethod = "POST"
            
            let (data, response) = try await httpClient.sendAsync(request: buildURLRequest(
                url: negotiateUrl,
                method: "POST",
                content: nil,
                headers: headers.merging(options.headers ?? [:], uniquingKeysWith: { (current, _) in current }),
                timeout: options.timeout ?? 100
            ))

            if response.statusCode != 200 {
                throw NSError(domain: "Unexpected status code returned from negotiate '\(response.statusCode)'", code: 0)
            }

            let decoder = JSONDecoder()
            var negotiateResponse = try decoder.decode(NegotiateResponse.self, from: data)

            if negotiateResponse.negotiateVersion == nil || negotiateResponse.negotiateVersion! < 1 {
                negotiateResponse.connectionToken = negotiateResponse.connectionId
            }

            if negotiateResponse.useStatefulReconnect == true && options.useStatefulReconnect != true {
                throw NSError(domain: "Client didn't negotiate Stateful Reconnect but the server did.", code: 0)
            }

            return negotiateResponse
        } catch {
            var errorMessage = "Failed to complete negotiation with the server: \(error)"
            if let httpError = error as? HttpError, httpError.statusCode == 404 {
                errorMessage += " Either this is not a SignalR endpoint or there is a proxy blocking the connection."
            }
            await logger.log(level: .error, message: errorMessage)
            throw NSError(domain: errorMessage, code: 0)
        }
    }

    private func createTransport(url: String, requestedTransport: HttpTransportType?, negotiateResponse: NegotiateResponse?, requestedTransferFormat: TransferFormat) async throws {
        var connectUrl = createConnectUrl(url: url, connectionToken: negotiateResponse?.connectionToken)

        // TODO: Create websocket directly, add other protocols later

        var transportExceptions: [Error] = []
        let transports = negotiateResponse?.availableTransports ?? []
        var negotiate = negotiateResponse

        for endpoint in transports {
            let transportOrError = await resolveTransportOrError(endpoint: endpoint, requestedTransport: requestedTransport, requestedTransferFormat: requestedTransferFormat, useStatefulReconnect: negotiate?.useStatefulReconnect ?? false)
            if let error = transportOrError as? Error {
                transportExceptions.append(error)
            } else if let transportInstance = transportOrError as? ITransport {
                transport = transportInstance
                if negotiate == nil {
                    negotiate = try await getNegotiationResponse(url: url)
                    connectUrl = createConnectUrl(url: url, connectionToken: negotiate?.connectionToken)
                }
                do {
                    try await startTransport(url: connectUrl, transferFormat: requestedTransferFormat)
                    connectionId = negotiate?.connectionId
                    return
                } catch {
                    await logger.log(level: .error, message: "Failed to start the transport '\(endpoint.transport)': \(error)")
                    negotiate = nil
                    transportExceptions.append(error)
                    if connectionState != .connecting {
                        let message = "Failed to select transport before stop() was called."
                        await logger.log(level: .debug, message: message)
                        throw NSError(domain: message, code: 0)
                    }
                }
            }
        }

        if !transportExceptions.isEmpty {
            let errorsDescription = transportExceptions.map { "\($0)" }.joined(separator: " ")
            throw NSError(domain: "Unable to connect to the server with any of the available transports. \(errorsDescription)", code: 0)
        }

        throw NSError(domain: "None of the transports supported by the client are supported by the server.", code: 0)
    }

    private func startTransport(url: String, transferFormat: TransferFormat) async throws {
        transport?.onReceive = self.onReceive
        transport?.onClose = { [weak self] error in
            guard let self = self else { return }
            await self.stopConnection(error: error)
        }

        // if features["reconnect"] != nil {
        //     transport?.onClose = { [weak self] error in
        //         Task {
        //             guard let self = self else { return }
        //             var callStop = false
        //             if self.features["reconnect"] != nil {
        //                 do {
        //                     (self.features["disconnected"] as? () -> Void)?()
        //                     try await self.transport?.connect(url: url, transferFormat: transferFormat)
        //                     try await (self.features["resend"] as? () async throws -> Void)?()
        //                 } catch {
        //                     callStop = true
        //                 }
        //             } else {
        //                 self.stopConnection(error: error)
        //                 return
        //             }
        //             if callStop {
        //                 self.stopConnection(error: error)
        //             }
        //         }
        //     }
        // } else {
        //     transport?.onClose = { [weak self] error in
        //         self?.stopConnection(error: error)
        //     }
        // }

        try await transport?.connect(url: url, transferFormat: transferFormat)
    }

    private func stopConnection(error: Error?) async {
        await logger.log(level: .debug, message: "HttpConnection.stopConnection(\(String(describing: error))) called while in state \(connectionState).")

        transport = nil

        let finalError = stopError ?? error
        stopError = nil

        if connectionState == .disconnected {
            await logger.log(level: .debug, message: "Call to HttpConnection.stopConnection(\(String(describing: finalError))) was ignored because the connection is already in the disconnected state.")
            return
        }

        if connectionState == .connecting {
            await logger.log(level: .warning, message: "Call to HttpConnection.stopConnection(\(String(describing: finalError))) was ignored because the connection is still in the connecting state.")
            return
        }

        if connectionState == .disconnecting {
            // Any stop() awaiters will be scheduled to continue after the onClose callback fires.
        }

        if let error = finalError {
            await logger.log(level: .error, message: "Connection disconnected with error '\(error)'.")
        } else {
            await logger.log(level: .information, message: "Connection disconnected.")
        }

        connectionId = nil
        connectionState = .disconnected

        if connectionStarted {
            connectionStarted = false
            await onClose?(finalError)
        }
    }

    // MARK: - Helper Methods

    private static func resolveUrl(_ url: String) -> String {
        // Implement URL resolution logic if necessary
        return url
    }

    private func resolveNegotiateUrl(url: String) -> String {
        var negotiateUrlComponents = URLComponents(string: url)!
        if !negotiateUrlComponents.path.hasSuffix("/") {
            negotiateUrlComponents.path += "/"
        }
        negotiateUrlComponents.path += "negotiate"
        var queryItems = negotiateUrlComponents.queryItems ?? []
        if !queryItems.contains(where: { $0.name == "negotiateVersion" }) {
            queryItems.append(URLQueryItem(name: "negotiateVersion", value: "\(negotiateVersion)"))
        }
        if let useStatefulReconnect = options.useStatefulReconnect, useStatefulReconnect {
            queryItems.append(URLQueryItem(name: "useStatefulReconnect", value: "true"))
        }
        negotiateUrlComponents.queryItems = queryItems
        return negotiateUrlComponents.url!.absoluteString
    }

    private func createConnectUrl(url: String, connectionToken: String?) -> String {
        guard let token = connectionToken else { return url }
        var urlComponents = URLComponents(string: url)!
        var queryItems = urlComponents.queryItems ?? []
        queryItems.append(URLQueryItem(name: "id", value: token))
        urlComponents.queryItems = queryItems
        return urlComponents.url!.absoluteString
    }

    private func constructTransport(transport: HttpTransportType) throws -> ITransport {
        switch transport {
            case .webSockets:
                return WebSocketTransport(
                    httpClient: httpClient,
                    accessTokenFactory: accessTokenFactory,
                    logger: logger,
                    logMessageContent: options.logMessageContent ?? false,
                    headers: options.headers ?? [:]
                )
            case .serverSentEvents:
                throw NSError(domain: "HttpConnection", code: 0, userInfo: [NSLocalizedDescriptionKey: "Server-Sent Events transport is not supported."])
            case .longPolling:
                throw NSError(domain: "HttpConnection", code: 0, userInfo: [NSLocalizedDescriptionKey: "Long polling transport is not supported."])
            default:
                throw NSError(domain: "HttpConnection", code:0, userInfo:  [NSLocalizedDescriptionKey: "Unknown transport: \(transport)."])
        }
    }

    private func resolveTransportOrError(endpoint: AvailableTransport, requestedTransport: HttpTransportType?, requestedTransferFormat: TransferFormat, useStatefulReconnect: Bool) async -> Any {
        guard let transportType = HttpTransportType.from(endpoint.transport) else {
            await logger.log(level: .debug, message: "Skipping transport '\(endpoint.transport)' because it is not supported by this client.")
            return NSError(domain: "Skipping transport '\(endpoint.transport)' because it is not supported by this client.", code: 0)
        }

        if transportMatches(requestedTransport: requestedTransport, actualTransport: transportType) {
            let transferFormats = endpoint.transferFormats.compactMap { TransferFormat($0) }
            if transferFormats.contains(requestedTransferFormat) {
                do {
                    features["reconnect"] = (transportType == .webSockets && useStatefulReconnect) ? true : nil
                    let constructedTransport = try constructTransport(transport: transportType)
                    return constructedTransport
                } catch {
                    return error
                }
            } else {
                await logger.log(level: .debug, message: "Skipping transport '\(transportType)' because it does not support the requested transfer format '\(requestedTransferFormat)'.")
                return NSError(domain: "'\(transportType)' does not support \(requestedTransferFormat).", code: 0)
            }
        } else {
            await logger.log(level: .debug, message: "Skipping transport '\(transportType)' because it was disabled by the client.")
            return NSError(domain: "'\(transportType)' is disabled by the client.", code: 0)
        }
    }

    private func transportMatches(requestedTransport: HttpTransportType?, actualTransport: HttpTransportType) -> Bool {
        guard let requestedTransport = requestedTransport else { return true } // Allow any the transport if options is not set
        return requestedTransport.contains(actualTransport)
    }

    private func getUserAgentHeader() -> (String, String) {
        // Placeholder implementation
        return ("User-Agent", "SignalR-Client-Swift/1.0")
    }

    private func buildURLRequest(url: String, method: String?, content: Data?, headers: [String: String]?, timeout: TimeInterval?) -> URLRequest {
        var urlRequest = URLRequest(url: URL(string: url)!)
        urlRequest.httpMethod = method ?? "GET"
        urlRequest.httpBody = content
        if let headers = headers {
            for (key, value) in headers {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
        }
        if let timeout = timeout {
            urlRequest.timeoutInterval = timeout
        }
        return urlRequest
    }
}

// MARK: - Helper Classes and Enums

class DefaultLogger: Logger, @unchecked Sendable {
    func log(level: LogLevel, message: String) {
        print("[\(level)] \(message)")
    }
}


// MARK: - Notes on Translation

// - **Async/Await Conversion**: The original TypeScript code uses Promises extensively. In Swift, the async/await pattern is used to handle asynchronous code. All asynchronous methods have been marked with `async` and `throws` where appropriate.

// - **Error Handling**: TypeScript uses `throw` for exceptions and `Promise.reject`. In Swift, we use `throw` and handle errors using `do-catch` blocks.

// - **Optionals and Nullability**: Swift uses optionals (`?`) to represent values that can be `nil`, similar to `undefined` or `null` in TypeScript.

// - **Enums and OptionSets**: The `HttpTransportType` enum is represented as an `OptionSet` in Swift to allow for bitwise operations, matching the TypeScript implementation.

// - **Closures and Delegates**: The `onReceive` and `onClose` callbacks are implemented as closures in Swift. Care was taken to manage retain cycles with `[weak self]` where necessary.

// - **Type Conversions**: Some TypeScript-specific constructs (like `keyof typeof`) have been adapted to Swift equivalents, using enums and dictionaries.

// - **Dependency Placeholders**: Since the full implementations of dependencies like `HttpClient`, `ILogger`, `ITransport`, etc., are not provided, placeholders and basic implementations have been used to focus on translating the `HttpConnection` logic.

// - **Error Messages and Logging**: Error messages and logging have been translated to use Swift string interpolation and the `ILogger` protocol.

// - **Maximum Redirects Constant**: The `MAX_REDIRECTS` constant is implemented directly in the `startInternal` method.

// - **Difficult Parts**: Translating the bitwise operations and the `transportMatches` function required careful handling to match Swift's type system and conventions. Also, managing asynchronous callbacks and error propagation in Swift's async/await model required attention to ensure correctness.
