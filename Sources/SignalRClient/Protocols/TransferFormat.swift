import Foundation

/// Specifies a specific HTTP transport type.
enum HttpTransportType: Int, Codable {
    /// Specifies no transport preference.
    case none = 0
    /// Specifies the WebSockets transport.
    case webSockets = 1
    /// Specifies the Server-Sent Events transport.
    case serverSentEvents = 2
    /// Specifies the Long Polling transport.
    case longPolling = 4
}

/// Specifies the transfer format for a connection.
enum TransferFormat: Int, Codable {
    /// Specifies that only text data will be transmitted over the connection.
    case text = 1
    /// Specifies that binary data will be transmitted over the connection.
    case binary = 2
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
    func send(data: Data) async throws

    /// Stops the transport.
    func stop() async throws

    /// A closure that is called when data is received.
    var onReceive: ((Data) -> Void)? { get set }

    /// A closure that is called when the transport is closed.
    var onClose: ((Error?) -> Void)? { get set }
}
