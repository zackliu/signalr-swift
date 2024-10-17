import Foundation

class JsonHubProtocol: IHubProtocol {
    let name = "json"
    let version = 2
    let transferFormat: TransferFormat = .text

    func parseMessages(input: StringOrData) throws -> [HubMessage] {
        let inputString: String
        let v: HubInvocationMessage
        switch input {
            case .string(let str):
                inputString = str
            case .data:
                throw NSError(domain: "JsonHubProtocol", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid input for JSON hub protocol. Expected a string."])
        }

        if inputString.isEmpty {
            return []
        }

        let messages = try TextMessageFormat.parse(input: inputString)
        var hubMessages = [HubMessage]()

        for message in messages {
            guard let data = message.data(using: .utf8) else {
                throw NSError(domain: "JsonHubProtocol", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid message encoding."])
            }
            let parsedMessage = try JSONDecoder().decode(HubMessage.self, from: data)
            hubMessages.append(parsedMessage)
        }

        return hubMessages
    }

    func writeMessage(message: HubMessage) throws -> StringOrData {
        let jsonData = try JSONEncoder().encode(message)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw NSError(domain: "JsonHubProtocol", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert JSON data to string."])
        }
        return .string(TextMessageFormat.write(output: jsonString))
    }
}