import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - HttpRequest and HttpResponse

// class CancellationToken {
//     private var isCancelled = false
//     private let lock = NSLock()
    
//     func cancel() {
//         lock.lock()
//         defer { lock.unlock() }
//         isCancelled = true
//     }
    
//     func throwIfCancelled() throws {
//         lock.lock()
//         defer { lock.unlock() }
//         if isCancelled {
//             throw CancellationError()
//         }
//     }
    
//     var isCancellationRequested: Bool {
//         lock.lock()
//         defer { lock.unlock() }
//         return isCancelled
//     }
// }

struct CancellationError: Error {}

public struct HttpRequest {
    var method: String?
    var url: String?
    var content: Data?
    var headers: [String: String]?
    var responseType: URLResponse?
    var timeout: TimeInterval?
    var withCredentials: Bool?
}


public class HttpResponse {
    public let statusCode: Int
    public let statusText: String?
    public let content: Data?
    
    public init(statusCode: Int, statusText: String? = nil, content: Data? = nil) {
        self.statusCode = statusCode
        self.statusText = statusText
        self.content = content
    }
}

// MARK: - HttpClient Protocol

public protocol HttpClient {
    func get(url: URL) async throws -> (Data, URLResponse)
    func post(url: URL, content: Data) async throws -> (Data, URLResponse)
    func delete(url: URL) async throws -> (Data, URLResponse)
    func sendAsync(request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension HttpClient {
    func get(url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await sendAsync(request: request)
    }
    
    func post(url: URL, content: Data) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = content
        return try await sendAsync(request: request)
    }
    
    func delete(url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        return try await sendAsync(request: request)
    }
    
    func getCookieString(url: String) -> String {
        // Implement cookie retrieval if necessary
        return ""
    }
}

class DefaultHttpClient: HttpClient {
    public init() {}
    
    public func sendAsync(request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let session = URLSession.shared
        let (data, response) = try await session.data(for: request);
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "HttpClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
        }
        return (data, httpResponse)
    }
}

class AccessTokenHttpClient: HttpClient {
    var accessTokenFactory: (() async throws -> String?)?
    var accessToken: String?
    private let innerClient: HttpClient
    
    
    public init(innerClient: HttpClient, accessTokenFactory: (() async throws -> String?)?) {
        self.innerClient = innerClient
        self.accessTokenFactory = accessTokenFactory
    }
    
    public func sendAsync(request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var mutableRequest = request
        var allowRetry = true
        
        if let factory = accessTokenFactory, (accessToken == nil || (request.url?.absoluteString.contains("/negotiate?") ?? false)) {
            // Don't retry if the request is a negotiate or if we just got a potentially new token from the access token factory
            allowRetry = false
            accessToken = try await factory()
        }
        
        setAuthorizationHeader(request: &mutableRequest)
        
        var (data, response) = try await innerClient.sendAsync(request: mutableRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "HttpClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
        }
        
        if allowRetry && httpResponse.statusCode == 401, let factory = accessTokenFactory {
            accessToken = try await factory()
            setAuthorizationHeader(request: &mutableRequest)
            (data, response) = try await innerClient.sendAsync(request: mutableRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "HttpClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
            }

            return (data, httpResponse)
        }
        
        return (data, httpResponse)
    }
    
    private func setAuthorizationHeader(request: inout URLRequest) {
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if accessTokenFactory != nil {
            request.setValue(nil, forHTTPHeaderField: "Authorization")
        }
    }
    
    public func getCookieString(url: String) -> String {
        return innerClient.getCookieString(url: url)
    }
}
