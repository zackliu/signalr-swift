import Foundation

class TextMessageFormat {
    static let recordSeparatorCode: UInt8 = 0x1e
    static let recordSeparator = String(UnicodeScalar(recordSeparatorCode))

    static func write(output: String) -> String {
        return "\(output)\(recordSeparator)"
    }

    static func parse(input: String) throws -> [String] {
        guard input.last == Character(recordSeparator) else {
            throw NSError(domain: "TextMessageFormat", code: 1, userInfo: [NSLocalizedDescriptionKey: "Message is incomplete."])
        }

        var messages = input.split(separator: Character(recordSeparator)).map { String($0) }
        if let last = messages.last, last.isEmpty {
            messages.removeLast()
        }
        return messages
    }
}