import Foundation

enum APIError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case server(status: Int, message: String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: "The backend address is invalid."
        case .invalidResponse: "The backend response is invalid."
        case .server(let status, let message): "Backend \(status): \(message)"
        case .decoding: "The backend data format is incompatible with the app."
        }
    }
}

private struct ProblemDetails: Decodable {
    let title: String?
    let detail: String?
}

struct APIClient {
    let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init?(baseURLString: String, session: URLSession = .shared) {
        var value = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        guard let url = URL(string: value), url.scheme != nil, url.host != nil else { return nil }
        baseURL = url
        self.session = session
        decoder = JSONDecoder()
        encoder = JSONEncoder()
    }

    func health() async throws -> HealthResponse { try await get("/health") }
    func overview() async throws -> Overview { try await get("/api/overview") }
    func markPrice(symbol: String) async throws -> MarketMarkPrice {
        try await get("/api/market/mark-price", query: ["symbol": symbol])
    }
    func klines(symbol: String, interval: String, limit: Int = 120) async throws -> [MarketKline] {
        try await get("/api/market/klines", query: ["symbol": symbol, "interval": interval, "limit": String(limit)])
    }
    func aiDecision(symbol: String) async throws -> AIDecision? {
        let request = try makeRequest(path: "/api/ai/decision", method: "GET", query: ["symbol": symbol])
        return try await performOptional(request)
    }
    func aiUsage() async throws -> AIUsageSummary { try await get("/api/ai/usage") }
    func wallets() async throws -> [FuturesWalletBalance] { try await get("/api/account/wallet") }
    func positions(symbol: String) async throws -> [FuturesPosition] {
        try await get("/api/account/positions", query: ["symbol": symbol])
    }
    func journalOrders(symbol: String, limit: Int = 30) async throws -> JournalOrdersResponse {
        try await get("/api/journal/orders", query: ["symbol": symbol, "limit": String(limit)])
    }
    func trailingStops(symbol: String) async throws -> TrailingStopSnapshot {
        try await get("/api/account/trailing-stops", query: ["symbol": symbol])
    }
    func positionHistory(symbol: String, period: String = "month") async throws -> PositionHistoryResponse {
        try await get("/api/positions/history", query: ["symbol": symbol, "period": period, "limit": "500"])
    }
    func settings() async throws -> TradingSettings { try await get("/api/settings/trading") }
    func killSwitch() async throws -> KillSwitchState { try await get("/api/kill-switch") }
    func registerPushDevice(_ request: PushDeviceRegistrationRequest) async throws -> PushDeviceRegistrationResponse {
        try await send("/api/notifications/devices", method: "POST", body: request)
    }

    func placeOrder(_ request: ManualOrderRequest) async throws -> TradeOrderResult {
        try await send("/api/manual/order", method: "POST", body: request)
    }
    func closePosition(_ request: ClosePositionRequest) async throws -> TradeOrderResult {
        try await send("/api/manual/close", method: "POST", body: request)
    }
    func enableKillSwitch(symbol: String) async throws -> KillSwitchState {
        try await send("/api/kill-switch/enable", method: "POST", body: KillSwitchRequest(symbol: symbol, countdownTimeMs: 120_000, heartbeatIntervalMs: 30_000))
    }
    func disableKillSwitch() async throws -> KillSwitchState {
        try await sendWithoutBody("/api/kill-switch/disable", method: "POST")
    }
    func updateSettings(_ request: UpdateTradingSettingsRequest) async throws -> TradingSettings {
        try await send("/api/settings/trading", method: "PUT", body: request)
    }
    func testConnection(_ target: String) async throws -> ConnectionTestResult {
        try await sendWithoutBody("/api/settings/test/\(target)", method: "POST")
    }

    private func get<Response: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> Response {
        let request = try makeRequest(path: path, method: "GET", query: query)
        return try await perform(request)
    }

    private func send<Response: Decodable, Body: Encodable>(_ path: String, method: String, body: Body) async throws -> Response {
        var request = try makeRequest(path: path, method: method)
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    private func sendWithoutBody<Response: Decodable>(_ path: String, method: String) async throws -> Response {
        try await perform(makeRequest(path: path, method: method))
    }

    private func makeRequest(path: String, method: String, query: [String: String] = [:]) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidBaseURL
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidBaseURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let problem = try? decoder.decode(ProblemDetails.self, from: data)
            let raw = String(data: data, encoding: .utf8)
            throw APIError.server(status: http.statusCode, message: problem?.detail ?? problem?.title ?? raw ?? "Request failed")
        }
        do { return try decoder.decode(Response.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    private func performOptional<Response: Decodable>(_ request: URLRequest) async throws -> Response? {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 204 { return nil }
        guard 200..<300 ~= http.statusCode else {
            let problem = try? decoder.decode(ProblemDetails.self, from: data)
            let raw = String(data: data, encoding: .utf8)
            throw APIError.server(status: http.statusCode, message: problem?.detail ?? problem?.title ?? raw ?? "Request failed")
        }
        do { return try decoder.decode(Response.self, from: data) }
        catch { throw APIError.decoding(error) }
    }
}
