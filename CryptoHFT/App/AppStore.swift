import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: Self.baseURLKey) }
    }
    @Published private(set) var isConnected = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published var notice: String?

    @Published var overview: Overview?
    @Published var markPrice: MarketMarkPrice?
    @Published var klines: [MarketKline] = []
    @Published var aiDecision: AIDecision?
    @Published var aiUsage: AIUsageSummary?
    @Published var wallets: [FuturesWalletBalance] = []
    @Published var positions: [FuturesPosition] = []
    @Published var journalOrders: JournalOrdersResponse?
    @Published var trailingStop: TrailingStopSnapshot?
    @Published var history: PositionHistoryResponse?
    @Published var tradingSettings: TradingSettings?
    @Published var killSwitch: KillSwitchState?
    @Published var chartInterval = "15m"
    @Published private(set) var historyPeriod = "month"

    let symbol = "BTCUSDT"
    /// Deep enough history so the chart can be panned back several sessions.
    private let chartCandleLimit = 500
    private var pollingTask: Task<Void, Never>?
    private static let baseURLKey = "backendBaseURL"

    init() {
        baseURL = UserDefaults.standard.string(forKey: Self.baseURLKey) ?? "https://trading.seqra.space"
    }

    var openPositions: [FuturesPosition] { positions.filter(\.isOpen) }

    func start() async {
        guard pollingTask == nil else { return }
        await refresh()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.refresh()
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func reconnect() async {
        stop()
        errorMessage = nil
        await start()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        guard let api = APIClient(baseURLString: baseURL) else {
            errorMessage = APIError.invalidBaseURL.localizedDescription
            isConnected = false
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        async let healthValue = try? api.health()
        async let overviewValue = try? api.overview()
        async let priceValue = try? api.markPrice(symbol: symbol)
        async let candlesValue = try? api.klines(symbol: symbol, interval: chartInterval, limit: chartCandleLimit)
        async let decisionValue = try? api.aiDecision(symbol: symbol)
        async let usageValue = try? api.aiUsage()
        async let walletsValue = try? api.wallets()
        async let positionsValue = try? api.positions(symbol: symbol)
        async let journalOrdersValue = try? api.journalOrders(symbol: symbol)
        async let trailingStopValue = try? api.trailingStops(symbol: symbol)
        async let historyValue = try? api.positionHistory(symbol: symbol, period: historyPeriod)
        async let killValue = try? api.killSwitch()
        async let settingsValue = try? api.settings()

        let health = await healthValue
        let overviewResult = await overviewValue
        isConnected = health?.status.lowercased() == "ok" || overviewResult != nil
        if let value = overviewResult { overview = value }
        if let value = await priceValue { markPrice = value }
        if let value = await candlesValue { klines = value }
        if let value = await decisionValue { aiDecision = value }
        if let value = await usageValue { aiUsage = value }
        if let value = await walletsValue { wallets = value }
        if let value = await positionsValue { positions = value }
        if let value = await journalOrdersValue { journalOrders = value }
        if let value = await trailingStopValue { trailingStop = value }
        if let value = await historyValue { history = value }
        if let value = await killValue { killSwitch = value }
        if let value = await settingsValue { tradingSettings = value }

        if isConnected {
            errorMessage = nil
            lastUpdated = Date()
        }
    }

    func changeInterval(_ interval: String) async {
        chartInterval = interval
        guard let api = APIClient(baseURLString: baseURL) else { return }
        if let values = try? await api.klines(symbol: symbol, interval: interval, limit: chartCandleLimit) { klines = values }
    }

    func changeHistoryPeriod(_ period: String) async {
        historyPeriod = period
        guard let api = APIClient(baseURLString: baseURL) else { return }
        if let value = try? await api.positionHistory(symbol: symbol, period: period) {
            history = value
        }
    }

    func placeOrder(_ request: ManualOrderRequest) async -> Bool {
        await performAction(success: "Order submitted successfully") { api in
            let result = try await api.placeOrder(request)
            return result.message
        }
    }

    func close(_ position: FuturesPosition) async -> Bool {
        let side: TradeSide = position.positionAmount < 0 ? .short : .long
        let request = ClosePositionRequest(side: side, quantity: abs(position.positionAmount), reason: "Manual close from iOS")
        return await performAction(success: "Position closed successfully") { api in
            let result = try await api.closePosition(request)
            return result.message
        }
    }

    func setKillSwitch(enabled: Bool) async -> Bool {
        await performAction(success: enabled ? "Kill switch enabled" : "Kill switch disabled") { api in
            let state = enabled ? try await api.enableKillSwitch(symbol: self.symbol) : try await api.disableKillSwitch()
            self.killSwitch = state
            return state.message
        }
    }

    func saveSettings(_ settings: TradingSettings) async -> Bool {
        await performAction(success: "Settings saved") { api in
            let updated = try await api.updateSettings(UpdateTradingSettingsRequest(settings: settings))
            self.tradingSettings = updated
            return "Trading settings have been updated."
        }
    }

    func testConnection(_ target: String) async -> Bool {
        await performAction(success: "Connection successful") { api in
            let result = try await api.testConnection(target)
            if !result.connected { throw APIError.server(status: 502, message: result.detail ?? result.message) }
            return result.message
        }
    }

    func registerPushDevice(token: String, environment: String) async {
        guard let api = APIClient(baseURLString: baseURL) else { return }
        let request = PushDeviceRegistrationRequest(deviceToken: token, environment: environment)
        // Registration is best-effort so a backend rollout never blocks the rest of the app.
        _ = try? await api.registerPushDevice(request)
    }

    private func performAction(success: String, operation: (APIClient) async throws -> String) async -> Bool {
        guard let api = APIClient(baseURLString: baseURL) else {
            errorMessage = APIError.invalidBaseURL.localizedDescription
            return false
        }
        do {
            _ = try await operation(api)
            notice = success
            errorMessage = nil
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
