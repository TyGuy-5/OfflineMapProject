import Foundation

/// A URLProtocol subclass for deterministic, offline interception of network requests.
/// Used to intercept Overpass API requests and simulate successful GeoJSON responses,
/// HTTP error codes (429, 500, 504), network timeouts, and offline airplane mode.
public final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    
    public struct RecordedRequest: Sendable {
        public let url: URL
        public let httpMethod: String?
        public let allHTTPHeaderFields: [String: String]?
        public let httpBody: Data?
        public let timestamp: Date
    }
    
    // Thread-safe lock for static state
    private static let lock = NSLock()
    private static var _responseHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    private static var _recordedRequests: [RecordedRequest] = []
    private static var _shouldInterceptAllRequests: Bool = true
    
    public static var responseHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _responseHandler
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _responseHandler = newValue
        }
    }
    
    public static var recordedRequests: [RecordedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _recordedRequests
    }
    
    public static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _recordedRequests.count
    }
    
    public static func reset() {
        lock.lock()
        defer { lock.unlock() }
        _responseHandler = nil
        _recordedRequests.removeAll()
        _shouldInterceptAllRequests = true
    }
    
    public static func record(request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        if let url = request.url {
            _recordedRequests.append(RecordedRequest(
                url: url,
                httpMethod: request.httpMethod,
                allHTTPHeaderFields: request.allHTTPHeaderFields,
                httpBody: request.httpBody,
                timestamp: Date()
            ))
        }
    }
    
    public override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        lock.lock()
        let interceptAll = _shouldInterceptAllRequests
        lock.unlock()
        
        if interceptAll { return true }
        let host = url.host?.lowercased() ?? ""
        return host.contains("overpass-api.de") || host.contains("openstreetmap.org")
    }
    
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    public override func startLoading() {
        Self.record(request: request)
        
        guard let handler = Self.responseHandler else {
            // Default response: offline error (airplane mode simulation)
            let error = URLError(.notConnectedToInternet, userInfo: [
                NSLocalizedDescriptionKey: "Airplane mode active: no network connection available."
            ])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    public override func stopLoading() {}
    
    // MARK: - Factory Helpers for Common Scenarios
    
    /// Configures MockURLProtocol with a mock URLSessionConfiguration.
    public static func makeMockSessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return config
    }
    
    /// Creates a URLSession backed exclusively by MockURLProtocol.
    public static func makeMockSession() -> URLSession {
        return URLSession(configuration: makeMockSessionConfiguration())
    }
    
    /// Configures standard 200 OK canned Overpass response.
    public static func mockSuccessfulResponse(with jsonString: String, url: URL = URL(string: "https://overpass-api.de/api/interpreter")!) {
        let data = jsonString.data(using: .utf8) ?? Data()
        responseHandler = { req in
            let resp = HTTPURLResponse(url: req.url ?? url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            return (resp, data)
        }
    }
    
    /// Configures rate limit (429 Too Many Requests) response.
    public static func mockRateLimitError(url: URL = URL(string: "https://overpass-api.de/api/interpreter")!) {
        let data = "Rate_limit exceeded".data(using: .utf8)!
        responseHandler = { req in
            let resp = HTTPURLResponse(url: req.url ?? url, statusCode: 429, httpVersion: "HTTP/1.1", headerFields: ["Retry-After": "60"])!
            return (resp, data)
        }
    }
    
    /// Configures gateway timeout (504 Gateway Timeout) response.
    public static func mockGatewayTimeout(url: URL = URL(string: "https://overpass-api.de/api/interpreter")!) {
        let data = "Gateway Timeout".data(using: .utf8)!
        responseHandler = { req in
            let resp = HTTPURLResponse(url: req.url ?? url, statusCode: 504, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, data)
        }
    }
}
