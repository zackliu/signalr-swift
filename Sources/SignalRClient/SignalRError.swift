import Foundation

// Define error types for better error handling
enum SignalRError: Error {
    case incompleteMessage
    case invalidDataType
    case failedToEncodeHandshakeRequest
    case failedToDecodeResponseData
    case expectedHandshakeResponse
    case noHandshakeMessageReceived

    var localizedDescription: String {
        switch self {
        case .incompleteMessage:
            return "Message is incomplete."
        case .invalidDataType:
            return "Invalid data type."
        case .failedToEncodeHandshakeRequest:
            return "Failed to encode handshake request to JSON string."
        case .failedToDecodeResponseData:
            return "Failed to decode response data."
        case .expectedHandshakeResponse:
            return "Expected a handshake response from the server."
        case .noHandshakeMessageReceived:
            return "No handshake message received."
        }
    }
}