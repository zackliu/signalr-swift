import Foundation

/// Specifies a specific HTTP transport type.
struct HttpTransportType: OptionSet {
    let rawValue: Int

    static let none = HttpTransportType([])
    static let webSockets = HttpTransportType(rawValue: 1 << 0)
    static let serverSentEvents = HttpTransportType(rawValue: 1 << 1)
    static let longPolling = HttpTransportType(rawValue: 1 << 2)

    static func from(_ transportString: String) -> HttpTransportType? {
        switch transportString.lowercased() {
            case "websockets":
                return .webSockets
            case "serversentevents":
                return .serverSentEvents
            case "longpolling":
                return .longPolling
            default:
                return nil
        }
    }
}

/// Specifies the transfer format for a connection.
enum TransferFormat: Int, Codable {
    /// Specifies that only text data will be transmitted over the connection.
    case text = 1
    /// Specifies that binary data will be transmitted over the connection.
    case binary = 2

    init?(_ transferFormatString: String) {
        switch transferFormatString.lowercased() {
            case "text":
                self = .text
            case "binary":
                self = .binary
            default:
                return nil
        }
    }
}

/// An abstraction over the behavior of transports.
/// This is designed to support the framework and not intended for use by applications.
protocol ITransport {
    /// Connects to the specified URL with the given transfer format.
    /// - Parameters:
    ///   - url: The URL to connect to.
    ///   - transferFormat: The transfer format to use.
    func connect(url: String, transferFormat: TransferFormat) async throws

    /// Sends data over the transport.
    /// - Parameter data: The data to send.
    func send(_ data: StringOrData) async throws

    /// Stops the transport.
    func stop() async throws

    /// A closure that is called when data is received.
    var onReceive: OnReceiveHandler? { get set }

    /// A closure that is called when the transport is closed.
    var onClose: OnCloseHander? { get set }

    typealias OnReceiveHandler = @Sendable (StringOrData) -> Void

    typealias OnCloseHander = @Sendable (Error?) -> Void
}
