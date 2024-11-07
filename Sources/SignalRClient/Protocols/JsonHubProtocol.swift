import Foundation

class JsonHubProtocol: HubProtocol {
    let name = "json"
    let version = 2
    let transferFormat: TransferFormat = .text

    func parseMessages(input: StringOrData) throws -> [HubMessage] {
        let inputString: String
        switch input {
            case .string(let str):
                inputString = str
            case .data:
                throw NSError(domain: "JsonHubProtocol", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid input for JSON hub protocol. Expected a string."])
        }

        if inputString.isEmpty {
            return []
        }

        let messages = try TextMessageFormat.parse(inputString)
        var hubMessages = [HubMessage]()

        for message in messages {
            guard let data = message.data(using: .utf8) else {
                throw NSError(domain: "JsonHubProtocol", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid message encoding."])
            }
            if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = jsonObject["type"] as? Int {
                    switch type {
                        case 1:
                            let result = try JSONDecoder().decode(InvocationMessage.self, from: data)
                            hubMessages.append(result)
                        case 2:
                            let result = try JSONDecoder().decode(StreamItemMessage.self, from: data)
                            hubMessages.append(result)
                        case 3:
                            let result = try JSONDecoder().decode(CompletionMessage.self, from: data)
                            hubMessages.append(result)
                        case 4:
                            let result = try JSONDecoder().decode(StreamInvocationMessage.self, from: data)
                            hubMessages.append(result)
                        case 5:
                            let result = try JSONDecoder().decode(CancelInvocationMessage.self, from: data)
                            hubMessages.append(result)
                        case 6:
                            let result = try JSONDecoder().decode(PingMessage.self, from: data)
                            hubMessages.append(result)
                        case 7:
                            let result = try JSONDecoder().decode(CloseMessage.self, from: data)
                            hubMessages.append(result)
                        case 8:
                            let result = try JSONDecoder().decode(AckMessage.self, from: data)
                            hubMessages.append(result)
                        case 9:
                            let result = try JSONDecoder().decode(SequenceMessage.self, from: data)
                            hubMessages.append(result)
                        default:
                            // Unknown message type
                            break
                    }
                }
        }

        return hubMessages
    }

    func writeMessage(message: HubMessage) throws -> StringOrData {
        let jsonData = try JSONEncoder().encode(message)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw NSError(domain: "JsonHubProtocol", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert JSON data to string."])
        }
        return .string(TextMessageFormat.write(jsonString))
    }
}