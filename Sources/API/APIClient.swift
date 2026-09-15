import Foundation

/// 轻量 HTTP 客户端。`async/await` + `URLSession`，带超时、重试与统一错误映射。
///
/// 用法示例（填入真实接口后即可用）：
/// ```swift
/// let client = APIClient(baseURL: URL(string: "https://api.example.com")!) { TokenStore.token }
/// let list: [Device] = try await client.request("/v1/devices", query: ["page": "1"])
/// ```
final class APIClient: @unchecked Sendable {

    enum HTTPMethod: String {
        case get = "GET", post = "POST", put = "PUT", delete = "DELETE"
    }

    let baseURL: URL

    private let session: URLSession
    private let tokenProvider: () -> String?
    private let maxRetries: Int

    init(
        baseURL: URL,
        timeout: TimeInterval = 15,
        maxRetries: Int = 2,
        tokenProvider: @escaping () -> String? = { nil }
    ) {
        self.baseURL = baseURL
        self.maxRetries = maxRetries
        self.tokenProvider = tokenProvider

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - 请求

    func request<T: Decodable>(
        _ path: String,
        method: HTTPMethod = .get,
        query: [String: String] = [:],
        body: (any Encodable)? = nil
    ) async throws -> T {
        let urlRequest = try makeRequest(path: path, method: method, query: query, body: body)

        var lastError: Error = APIError.invalidResponse
        for attempt in 0...maxRetries {
            do {
                let (data, response) = try await session.data(for: urlRequest)
                guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
                guard (200..<300).contains(http.statusCode) else { throw APIError.httpStatus(http.statusCode, data) }
                return try decode(T.self, from: data, fallback: EmptyResponse.self)
            } catch let error as APIError {
                lastError = error
                if !shouldRetry(error) { break }
                try? await Task.sleep(nanoseconds: backoff(attempt))
            } catch {
                lastError = error
                if !shouldRetry(error) { break }
                try? await Task.sleep(nanoseconds: backoff(attempt))
            }
        }
        throw lastError
    }

    /// 不需要解析响应体的场景（只关心是否成功）。
    func send(
        _ path: String,
        method: HTTPMethod = .post,
        query: [String: String] = [:],
        body: (any Encodable)? = nil
    ) async throws {
        let _: EmptyResponse = try await request(path, method: method, query: query, body: body)
    }

    // MARK: - 内部

    private func makeRequest(
        path: String,
        method: HTTPMethod,
        query: [String: String],
        body: (any Encodable)?
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = joined(baseURL.path, path)
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        return request
    }

    private func joined(_ base: String, _ path: String) -> String {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return base.hasSuffix("/") ? base + trimmed : base + "/" + trimmed
    }

    private func decode<T: Decodable, F: Decodable>(_ type: T.Type, from data: Data, fallback: F.Type) throws -> T {
        guard !data.isEmpty else { throw APIError.decoding(DecodingError.empty) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            if T.self == EmptyResponse.self, let empty = try? decoder.decode(F.self, from: data), empty is EmptyResponse {
                guard let result = EmptyResponse() as? T else { throw APIError.decoding(error) }
                return result
            }
            throw APIError.decoding(error)
        }
    }

    private func shouldRetry(_ error: Error) -> Bool {
        if case .httpStatus(let status, _) = error as? APIError { return status >= 500 }
        guard let urlError = error as? URLError else { return false }
        return [.timedOut, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed].contains(urlError.code)
    }

    private func backoff(_ attempt: Int) -> UInt64 {
        UInt64(pow(2.0, Double(attempt))) * 300_000_000
    }
}

// MARK: - 错误

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, Data?)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "请求地址无效"
        case .invalidResponse: return "服务器响应异常"
        case .httpStatus(let status, _): return "请求失败（\(status)）"
        case .decoding: return "数据解析失败"
        }
    }
}

private enum DecodingError: Error { case empty }

/// 空响应占位，用于 `request` 到不需要 body 的接口。
struct EmptyResponse: Decodable {}

/// 把 `any Encodable` 包装成具体类型以满足 Encoder 的类型要求。
private struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void

    init(_ value: any Encodable) {
        self.encode = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}
