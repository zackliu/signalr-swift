import Foundation

struct HandshakeRequestMessage: Codable {
    let `protocol`: String
    let version: Int
}

struct HandshakeResponseMessage: Codable {
    let error: String?
    let minorVersion: Int?
}

// Implement the HandshakeProtocol class
class HandshakeProtocol {
    // Handshake request is always JSON
    func writeHandshakeRequest(handshakeRequest: HandshakeRequestMessage) throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(handshakeRequest)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw SignalRError.failedToEncodeHandshakeRequest
        }
        return TextMessageFormat.write(jsonString)
    }

    func parseHandshakeResponse(data: Any) throws -> (Any?, HandshakeResponseMessage) {
        var messageData: String
        var remainingData: Any?

        if let binaryData = data as? Data {
            // Format is binary but still need to read JSON text from handshake response
            if let separatorIndex = binaryData.firstIndex(of: TextMessageFormat.recordSeparatorCode) {
                let responseLength = separatorIndex + 1
                let responseData = binaryData.subdata(in: 0..<responseLength)
                guard let responseString = String(data: responseData, encoding: .utf8) else {
                    throw SignalRError.failedToDecodeResponseData
                }
                messageData = responseString
                remainingData = (binaryData.count > responseLength) ? binaryData.subdata(in: responseLength..<binaryData.count) : nil
            } else {
                throw SignalRError.incompleteMessage
            }
        } else if let textData = data as? String {
            // Handle text data
            if let separatorIndex = textData.firstIndex(of: Character(TextMessageFormat.recordSeparator)) {
                let responseLength = textData.distance(from: textData.startIndex, to: separatorIndex) + 1
                let messageRange = textData.startIndex..<textData.index(textData.startIndex, offsetBy: responseLength)
                messageData = String(textData[messageRange])
                remainingData = (textData.count > responseLength) ? String(textData[textData.index(textData.startIndex, offsetBy: responseLength)...]) : nil
            } else {
                throw SignalRError.incompleteMessage
            }
        } else {
            throw SignalRError.invalidDataType
        }

        // At this point we should have just the single handshake message
        let messages = try TextMessageFormat.parse(messageData)
        guard let firstMessage = messages.first else {
            throw SignalRError.noHandshakeMessageReceived
        }

        // Parse JSON and check for unexpected "type" field
        guard let jsonData = firstMessage.data(using: .utf8) else {
            throw SignalRError.failedToDecodeResponseData
        }

        let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
        if let jsonObject = jsonObject, jsonObject["type"] != nil {
            throw SignalRError.expectedHandshakeResponse
        }

        // Decode the handshake response message
        let decoder = JSONDecoder()
        let responseMessage = try decoder.decode(HandshakeResponseMessage.self, from: jsonData)

        // Return the remaining data and the response message
        return (remainingData, responseMessage)
    }
}