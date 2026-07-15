import Foundation

struct HealthResponse: Codable {
    let status: String
    let service: String
    let time: String
}

struct PushDeviceRegistrationRequest: Encodable {
    let deviceToken: String
    let environment: String
    let platform = "ios"
}

struct PushDeviceRegistrationResponse: Decodable {
    let registered: Bool
    let environment: String
}

struct Overview: Codable {
    let symbol: String
    let mode: String
    let walletBalance: Double
    let availableBalance: Double
    let dailyPnl: Double
    let weeklyPnl: Double
    let monthlyPnl: Double
    let winRate: Double
    let profitFactor: Double
    let sharpeRatio: Double
    let maxDrawdown: Double
}

struct MarketMarkPrice: Codable {
    let symbol: String
    let markPrice: Double
    let markPriceMovingAverage: Double
    let indexPrice: Double
    let estimatedSettlePrice: Double
    let fundingRate: Double
    let nextFundingTime: String
    let time: String
}

struct MarketKline: Codable, Identifiable {
    let symbol: String
    let interval: String
    let openTime: String
    let closeTime: String
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
    let quoteVolume: Double
    let numberOfTrades: Int
    let takerBuyBaseVolume: Double
    let takerBuyQuoteVolume: Double
    let isClosed: Bool
    let eventTime: String

    var id: String { "\(openTime)-\(interval)" }
    var date: Date { Date.fromISO8601(openTime) }
    var isUp: Bool { close >= open }
}

struct AIDecision: Codable {
    let symbol: String
    let action: Int
    let confidence: Double
    let confidenceBuy: Double
    let confidenceSell: Double
    let confidenceHold: Double
    let probabilityOfSuccess: Double
    let regime: Int
    let entryPrice: Double
    let stopLoss: Double
    let takeProfit: Double
    let trailingStopPercent: Double
    let riskReward: Double
    let positionSizeQuantity: Double
    let leverage: Int
    let shouldTrade: Bool
    let noTradeReason: String
    let cautions: [String]?
    let scores: [String: Double]
    let weights: [String: Double]
    let components: [AIDecisionComponent]?
    let reasons: [String]
    let llm: AILLMValidation
    let time: String
    let volumeProfileNote: String?

    var actionLabel: String {
        [
            1: "Strong Sell", 2: "Sell", 3: "Weak Sell", 4: "No Trade",
            5: "Weak Buy", 6: "Buy", 7: "Strong Buy"
        ][action] ?? "Unknown"
    }

    var regimeLabel: String {
        [
            0: "Trending", 1: "Ranging", 2: "High Volatility",
            3: "Low Volatility", 4: "Trending Up", 5: "Trending Down"
        ][regime] ?? "Unknown"
    }

    var direction: AIDecisionDirection {
        if action <= 3 { return .sell }
        if action >= 5 { return .buy }
        return .hold
    }

    var date: Date { Date.fromISO8601(time) }
}

enum AIDecisionDirection {
    case buy, sell, hold
}

struct AIDecisionComponent: Codable, Identifiable {
    let name: String
    let score: Double
    let weight: Double
    let reason: String
    var id: String { name }
}

struct AILLMValidation: Codable {
    let confirmed: Bool
    let adjustedConfidence: Double
    let narrative: String
    let risks: [String]
    let used: Bool
    let sizeMultiplier: Double?
    let leverage: Int?
    let stopLoss: Double?
    let takeProfit: Double?
}

struct AIUsageSummary: Codable {
    let callsToday: Int
    let callsTotal: Int
    let costTodayUsd: Double
    let costTotalUsd: Double
    let inputTokensTotal: Int
    let outputTokensTotal: Int
    let lastModel: String?
    let lastCallAt: String?

    var lastCallDate: Date? {
        guard let lastCallAt else { return nil }
        return Date.fromISO8601(lastCallAt)
    }
}

struct FuturesWalletBalance: Codable, Identifiable {
    let accountAlias: String
    let asset: String
    let balance: Double
    let crossWalletBalance: Double
    let crossUnrealizedPnl: Double
    let availableBalance: Double
    let maxWithdrawAmount: Double
    let isMarginAvailable: Bool
    let updateTime: String

    var id: String { asset }
}

struct FuturesPosition: Codable, Identifiable {
    let symbol: String
    let positionSide: String
    let positionAmount: Double
    let entryPrice: Double
    let breakEvenPrice: Double
    let markPrice: Double
    let unrealizedProfit: Double
    let liquidationPrice: Double
    let leverage: Double
    let maxNotionalValue: Double
    let marginType: String
    let isolatedMargin: Double
    let isAutoAddMargin: Bool
    let updateTime: String

    var id: String { "\(symbol)-\(positionSide)" }
    var isOpen: Bool { abs(positionAmount) > 0.00000001 }
    var direction: String { positionAmount < 0 ? "SHORT" : "LONG" }
    var notional: Double { abs(positionAmount * markPrice) }
    var pnlPercent: Double {
        guard entryPrice > 0 else { return 0 }
        let movement = (markPrice - entryPrice) / entryPrice * 100
        return positionAmount < 0 ? -movement * leverage : movement * leverage
    }
}

struct JournalOrdersResponse: Codable {
    let orders: [JournalOrder]
}

struct JournalOrder: Codable, Identifiable {
    let id: String
    let symbol: String
    let side: String
    let kind: String
    let status: String
    let stopPrice: Double?
    let reduceOnly: Bool
}

struct TrailingStopSnapshot: Codable {
    let symbol: String
    let positionSide: Int?
    let entryPrice: Double?
    let initialStopLoss: Double?
    let currentStopLoss: Double?
    let events: [TrailingStopEvent]

    var sideLabel: String {
        switch positionSide {
        case 1: "LONG"
        case 2: "SHORT"
        default: "—"
        }
    }
}

struct TrailingStopEvent: Codable, Identifiable {
    let previousStopLoss: Double?
    let newStopLoss: Double
    let profitR: Double
    let markPrice: Double
    let ratchetedAt: String

    var id: String { ratchetedAt }
    var date: Date { Date.fromISO8601(ratchetedAt) }
}

struct PositionHistoryResponse: Codable {
    let summary: PositionHistorySummary
    let daily: [PositionPnlBucket]
    let monthly: [PositionPnlBucket]
    let positions: [PositionHistoryItem]
}

struct PositionHistorySummary: Codable {
    let totalRealizedPnl: Double
    let totalTrades: Int
    let winRate: Double
    let bestTrade: Double
    let worstTrade: Double
}

struct PositionPnlBucket: Codable, Identifiable {
    let label: String
    let periodStart: String
    let realizedPnl: Double
    let trades: Int
    var id: String { periodStart }
    var date: Date { Date.fromISO8601(periodStart) }
}

struct PositionHistoryItem: Codable, Identifiable {
    let id: UUID
    let symbol: String
    let side: String
    let quantity: Double
    let entryPrice: Double
    let margin: Double
    let leverage: Int
    let takeProfit: Double?
    let stopLoss: Double?
    let closeReason: FlexibleString?
    let realizedPnl: Double
    let roi: Double
    let openedAt: String
    let closedAt: String

    var openedDate: Date { Date.fromISO8601(openedAt) }
    var closedDate: Date { Date.fromISO8601(closedAt) }
}

enum FlexibleString: Codable, CustomStringConvertible {
    case string(String)
    case number(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .string(value) }
        else { self = .number(try container.decode(Int.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        }
    }

    var description: String {
        switch self {
        case .string(let value): value
        case .number(let value): [0: "Unknown", 1: "Take Profit", 2: "Stop Loss", 3: "Auto Close", 4: "Manual", 5: "Trailing Stop"][value] ?? "Code \(value)"
        }
    }
}

struct KillSwitchState: Codable {
    let symbol: String
    let enabled: Bool
    let countdownTimeMs: Int
    let heartbeatIntervalMs: Int
    let lastHeartbeatAt: String?
    let nextHeartbeatAt: String?
    let isPaper: Bool
    let message: String
}

struct TradingSettings: Codable, Equatable {
    var paperTradingOnly: Bool
    var autoTradingEnabled: Bool
    var maxDailyLossPercent: Double
    var riskPerTradePercent: Double
    var maxExposurePercent: Double
    var defaultLeverage: Int
    var targetMarginUsdt: Double
    var autoSizingMode: Int
    var targetLeverage: Int
    let hasApiKey: Bool
    let hasApiSecret: Bool
    let apiKeyPreview: String
    let hasAnthropicKey: Bool
    let anthropicKeyPreview: String
    var aiModel: String
    var confidenceThreshold: Double
    var positionCheckIntervalMinutes: Int
    var trailingStopDistanceR: Double
    let hasLunarCrushKey: Bool
    let lunarCrushKeyPreview: String
}

struct UpdateTradingSettingsRequest: Encodable {
    let paperTradingOnly: Bool
    let autoTradingEnabled: Bool
    let maxDailyLossPercent: Double
    let riskPerTradePercent: Double
    let maxExposurePercent: Double
    let defaultLeverage: Int
    let autoSizingMode: Int?
    let targetLeverage: Int?
    let apiKey: String?
    let apiSecret: String?
    let anthropicApiKey: String?
    let aiModel: String?
    let confidenceThreshold: Double?
    let positionCheckIntervalMinutes: Int?
    let trailingStopDistanceR: Double?
    let lunarCrushApiKey: String?
    let targetMarginUsdt: Double?

    init(settings: TradingSettings) {
        paperTradingOnly = settings.paperTradingOnly
        autoTradingEnabled = settings.autoTradingEnabled
        maxDailyLossPercent = settings.maxDailyLossPercent
        riskPerTradePercent = settings.riskPerTradePercent
        maxExposurePercent = settings.maxExposurePercent
        defaultLeverage = settings.defaultLeverage
        autoSizingMode = settings.autoSizingMode
        targetLeverage = settings.targetLeverage
        apiKey = nil
        apiSecret = nil
        anthropicApiKey = nil
        aiModel = settings.aiModel
        confidenceThreshold = settings.confidenceThreshold
        positionCheckIntervalMinutes = settings.positionCheckIntervalMinutes
        trailingStopDistanceR = settings.trailingStopDistanceR
        lunarCrushApiKey = nil
        targetMarginUsdt = settings.targetMarginUsdt
    }
}

enum TradeSide: Int, CaseIterable, Identifiable, Encodable {
    case long = 1
    case short = 2
    var id: Int { rawValue }
    var title: String { self == .long ? "Long" : "Short" }
}

enum OrderKind: Int, CaseIterable, Identifiable, Encodable {
    case market = 1
    case limit = 2
    var id: Int { rawValue }
    var title: String { self == .market ? "Market" : "Limit" }
}

struct ManualOrderRequest: Encodable {
    let side: TradeSide
    let kind: OrderKind
    let quantity: Double
    let price: Double?
    let stopPrice: Double?
    let takeProfit: Double?
    let stopLoss: Double?
    let leverage: Int
    let reduceOnly: Bool
    let reason: String
}

struct ClosePositionRequest: Encodable {
    let side: TradeSide
    let quantity: Double?
    let reason: String
}

struct KillSwitchRequest: Encodable {
    let symbol: String
    let countdownTimeMs: Int
    let heartbeatIntervalMs: Int
}

struct TradeOrderResult: Codable {
    let symbol: String
    let orderId: FlexibleString
    let status: FlexibleString
    let quantity: Double
    let price: Double?
    let isPaper: Bool
    let message: String
    let time: String
}

struct ConnectionTestResult: Codable {
    let connected: Bool
    let message: String
    let detail: String?
}

extension ISO8601DateFormatter {
    static let crypto: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private extension Date {
    static func fromISO8601(_ value: String) -> Date {
        ISO8601DateFormatter.crypto.date(from: value)
            ?? ISO8601DateFormatter().date(from: value)
            ?? .distantPast
    }
}
