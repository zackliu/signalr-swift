/// An abstraction over the behavior of transports.
/// This is designed to support the framework and not intended for use by applications.
protocol Transport {
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

    typealias OnReceiveHandler = @Sendable (StringOrData) async -> Void

    typealias OnCloseHander = @Sendable (Error?) async -> Void
}
