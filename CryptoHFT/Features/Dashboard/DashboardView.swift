import Charts
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedForClose: FuturesPosition?
    @State private var isClosing = false
    private let intervals = ["1m", "5m", "15m", "1h", "4h", "1d"]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                connectionHeader
                accountRiskGuardCard
                priceCard
                accountCard
                openPositionsSection
                trailingStopSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("BTC / USDT")
        .refreshable { await store.refresh() }
        .alert(item: $selectedForClose) { position in
            Alert(
                title: Text("Close \(position.direction) position?"),
                message: Text("The entire \(position.symbol) position will be closed through the backend."),
                primaryButton: .destructive(Text("Close Position")) { close(position) },
                secondaryButton: .cancel()
            )
        }
    }

    private var connectionHeader: some View {
        StatusPill(label: store.isConnected ? "Live" : "Offline", active: store.isConnected)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accountRiskGuardCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Account Risk Guard")
                            .font(.headline)
                        Text(riskGuardSubtitle)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    Spacer()

                    StatusPill(
                        label: riskGuardStatusLabel,
                        active: riskGuardStatusIsActive
                    )
                }

                if let settings = store.tradingSettings {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Daily loss usage")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                            Spacer()
                            Text(dailyLossUsageText(settings))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(dailyLossUsageTint(settings))
                        }

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(AppTheme.surfaceRaised)
                                Capsule()
                                    .fill(dailyLossUsageTint(settings))
                                    .frame(width: proxy.size.width * dailyLossUsageRatio(settings))
                            }
                        }
                        .frame(height: 8)
                    }

                    HStack {
                        MetricView(title: "Max daily loss", value: settings.maxDailyLossPercent.ratioPercentText, tint: AppTheme.warning)
                        MetricView(title: "Risk / trade", value: settings.riskPerTradePercent.ratioPercentText)
                        MetricView(title: "Max exposure", value: settings.maxExposurePercent.ratioPercentText)
                    }

                    HStack {
                        MetricView(title: "Target margin", value: settings.targetMarginUsdt.currencyText)
                        MetricView(title: "Target leverage", value: "\(settings.targetLeverage)x", tint: AppTheme.warning)
                        MetricView(title: "Min confidence", value: settings.confidenceThreshold.percentText)
                    }
                } else {
                    ContentUnavailableView(
                        "Risk guard unavailable",
                        systemImage: "shield.slash",
                        description: Text("Connect to the backend to load risk settings.")
                    )
                    .frame(minHeight: 110)
                }
            }
        }
    }

    private var priceCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MARK PRICE")
                            .font(.caption2.weight(.bold)).tracking(1)
                            .foregroundStyle(AppTheme.secondaryText)
                        Text(store.markPrice?.markPrice.priceText ?? "—")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    if let funding = store.markPrice?.fundingRate {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Funding").font(.caption).foregroundStyle(AppTheme.secondaryText)
                            Text(funding.ratioPercentText(fractionDigits: 4))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(funding >= 0 ? AppTheme.positive : AppTheme.negative)
                        }
                    }
                }

                if store.klines.isEmpty {
                    ContentUnavailableView("No market data yet", systemImage: "chart.bar.xaxis")
                        .frame(height: 260)
                } else {
                    TradingChartCard(
                        symbol: store.symbol,
                        candles: store.klines,
                        levels: chartLevels,
                        interval: store.chartInterval,
                        intervals: intervals,
                        onIntervalChange: { value in Task { await store.changeInterval(value) } }
                    )
                }

                HStack {
                    MetricView(title: "Index", value: store.markPrice?.indexPrice.priceText ?? "—")
                    MetricView(title: "Candles", value: "\(store.klines.count)")
                    MetricView(title: "Mode", value: store.overview?.mode.contains("Paper") == true ? "Paper" : "Live", tint: store.overview?.mode.contains("Paper") == true ? AppTheme.warning : AppTheme.positive)
                }
            }
        }
    }

    private var accountCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Account").font(.headline)
                    Spacer()
                    Text(store.overview?.mode ?? "Waiting for backend")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                HStack {
                    MetricView(title: "Equity", value: store.overview?.walletBalance.currencyText ?? "—")
                    MetricView(title: "Available", value: store.overview?.availableBalance.currencyText ?? "—")
                    MetricView(title: "Open positions", value: "\(store.openPositions.count)")
                }
            }
        }
    }

    private var openPositionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Open positions").font(.headline)

            if store.openPositions.isEmpty {
                AppCard {
                    ContentUnavailableView(
                        "No open positions",
                        systemImage: "tray",
                        description: Text("Binance Futures positions will appear here.")
                    )
                    .frame(minHeight: 150)
                }
            } else {
                ForEach(store.openPositions) { position in
                    openPositionCard(position)
                }
            }
        }
    }

    private func openPositionCard(_ position: FuturesPosition) -> some View {
        AppCard {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(position.symbol).font(.headline)
                        Text("\(position.direction) · \(Int(position.leverage))x · \(position.marginType.uppercased())")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(position.positionAmount >= 0 ? AppTheme.positive : AppTheme.negative)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(position.unrealizedProfit.signedCurrencyText)
                            .font(.title3.bold())
                            .foregroundStyle(position.unrealizedProfit >= 0 ? AppTheme.positive : AppTheme.negative)
                        Text(position.pnlPercent.percentText)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                Divider().overlay(AppTheme.border)
                let protection = protectionLevels(for: position)
                HStack {
                    MetricView(title: "Size", value: String(format: "%.5f BTC", abs(position.positionAmount)))
                    MetricView(title: "Entry", value: position.entryPrice.priceText)
                    MetricView(title: "Mark", value: position.markPrice.priceText)
                }
                HStack {
                    MetricView(
                        title: "Take profit",
                        value: protection.takeProfit?.priceText ?? "—",
                        tint: AppTheme.positive
                    )
                    MetricView(
                        title: "Stop loss",
                        value: protection.stopLoss?.priceText ?? "—",
                        tint: AppTheme.negative
                    )
                    MetricView(
                        title: "Liquidation",
                        value: position.liquidationPrice > 0 ? position.liquidationPrice.priceText : "—",
                        tint: AppTheme.warning
                    )
                }
                HStack {
                    MetricView(title: "Margin", value: position.marginUsed.currencyText)
                    MetricView(title: "Leverage", value: "\(Int(position.leverage))x", tint: AppTheme.warning)
                    MetricView(title: "Notional", value: position.notional.currencyText)
                }
                HStack {
                    Spacer(minLength: 0)
                    Button(role: .destructive) { selectedForClose = position } label: {
                        Text(isClosing ? "Closing..." : "Close")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppTheme.negative.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(isClosing)
                }
            }
        }
    }

    private var trailingStopSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trailing stop").font(.headline)

            AppCard {
                if let snapshot = store.trailingStop,
                   snapshot.positionSide != nil,
                   let entryPrice = snapshot.entryPrice {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(snapshot.sideLabel)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(snapshot.positionSide == 1 ? AppTheme.positive : AppTheme.negative)
                                Text("Entry \(entryPrice.priceText)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                            Spacer()
                            StatusPill(
                                label: snapshot.events.isEmpty ? "WAITING +1R" : "RATCHET ACTIVE",
                                active: !snapshot.events.isEmpty
                            )
                        }

                        Divider().overlay(AppTheme.border)

                        HStack {
                            MetricView(
                                title: "Initial SL",
                                value: snapshot.initialStopLoss?.priceText ?? "—",
                                tint: AppTheme.secondaryText
                            )
                            MetricView(
                                title: "Current SL",
                                value: snapshot.currentStopLoss?.priceText ?? "—",
                                tint: hasRatcheted(snapshot) ? AppTheme.positive : AppTheme.warning
                            )
                        }

                        if let event = snapshot.events.first {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Latest ratchet")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.secondaryText)
                                HStack {
                                    MetricView(
                                        title: "SL move",
                                        value: "\(event.previousStopLoss?.priceText ?? "—") → \(event.newStopLoss.priceText)",
                                        tint: AppTheme.positive
                                    )
                                    MetricView(
                                        title: "Profit at ratchet",
                                        value: String(format: "+%.2fR", event.profitR),
                                        tint: AppTheme.positive
                                    )
                                }
                                Text("Mark \(event.markPrice.priceText) · \(event.date.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        } else {
                            Text("No ratchet yet. The stop loss will move automatically once profit reaches +1R.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Trailing stop inactive",
                        systemImage: "arrow.up.right",
                        description: Text("Trailing stop details appear when a position is open.")
                    )
                    .frame(minHeight: 135)
                }
            }
        }
    }

    /// Price lines drawn on the chart. Everything here mirrors the engine state that the
    /// backend reports: the live position, its reduce-only TP/SL orders, the trailing stop
    /// ratchet and the liquidation price. When no position is open, the AI decision levels
    /// are shown as planned (faded) lines instead.
    private var chartLevels: [ChartPriceLevel] {
        var result: [ChartPriceLevel] = []

        if let mark = store.markPrice?.markPrice {
            result.append(ChartPriceLevel(
                id: "mark",
                tag: "MARK",
                title: "Mark price",
                price: mark,
                color: AppTheme.warning,
                dash: .dotted
            ))
        }

        if let position = store.openPositions.first {
            let protection = protectionLevels(for: position)

            result.append(ChartPriceLevel(
                id: "entry",
                tag: "ENTRY",
                title: "Entry price",
                price: position.entryPrice,
                color: AppTheme.accent,
                dash: .solid
            ))

            if let takeProfit = protection.takeProfit, takeProfit > 0 {
                result.append(ChartPriceLevel(
                    id: "tp",
                    tag: "TP",
                    title: "Take profit",
                    price: takeProfit,
                    color: AppTheme.positive
                ))
            }

            if let stopLoss = protection.stopLoss, stopLoss > 0 {
                result.append(ChartPriceLevel(
                    id: "sl",
                    tag: "SL",
                    title: "Stop loss",
                    price: stopLoss,
                    color: AppTheme.negative
                ))
            }

            if position.liquidationPrice > 0 {
                result.append(ChartPriceLevel(
                    id: "liq",
                    tag: "LIQ",
                    title: "Liquidation",
                    price: position.liquidationPrice,
                    color: AppTheme.negative.opacity(0.7),
                    dash: .dotted
                ))
            }

            if let trailing = store.trailingStop?.currentStopLoss,
               trailing > 0,
               abs(trailing - (protection.stopLoss ?? 0)) > 0.5 {
                result.append(ChartPriceLevel(
                    id: "tsl",
                    tag: "TSL",
                    title: "Trailing stop",
                    price: trailing,
                    color: AppTheme.warning
                ))
            }
        } else if let decision = store.aiDecision, decision.shouldTrade, decision.entryPrice > 0 {
            result.append(ChartPriceLevel(
                id: "ai-entry",
                tag: "AI ENTRY",
                title: "Planned entry",
                price: decision.entryPrice,
                color: AppTheme.accent,
                dash: .dashed,
                isPlanned: true
            ))

            if decision.takeProfit > 0 {
                result.append(ChartPriceLevel(
                    id: "ai-tp",
                    tag: "AI TP",
                    title: "Planned take profit",
                    price: decision.takeProfit,
                    color: AppTheme.positive,
                    isPlanned: true
                ))
            }

            if decision.stopLoss > 0 {
                result.append(ChartPriceLevel(
                    id: "ai-sl",
                    tag: "AI SL",
                    title: "Planned stop loss",
                    price: decision.stopLoss,
                    color: AppTheme.negative,
                    isPlanned: true
                ))
            }
        }

        return result
    }

    private func protectionLevels(for position: FuturesPosition) -> (takeProfit: Double?, stopLoss: Double?) {
        let closingSide = position.positionAmount > 0 ? "Short" : "Long"
        let activeOrders = store.journalOrders?.orders.filter {
            $0.symbol == position.symbol &&
            $0.reduceOnly &&
            $0.status == "New" &&
            $0.side == closingSide
        } ?? []
        let takeProfit = activeOrders.first { $0.kind == "TakeProfit" }?.stopPrice
        let stopLoss = activeOrders.first { $0.kind == "StopMarket" }?.stopPrice
        return (takeProfit, stopLoss)
    }

    private var riskGuardStatusLabel: String {
        if store.killSwitch?.enabled == true { return "STOPPED" }
        guard let settings = store.tradingSettings else { return store.isConnected ? "LOADING" : "OFFLINE" }
        if settings.paperTradingOnly { return "PAPER" }
        return settings.autoTradingEnabled ? "ARMED" : "PAUSED"
    }

    private var riskGuardStatusIsActive: Bool {
        guard store.killSwitch?.enabled != true else { return false }
        guard let settings = store.tradingSettings else { return store.isConnected }
        return settings.autoTradingEnabled
    }

    private var riskGuardSubtitle: String {
        if store.killSwitch?.enabled == true {
            return store.killSwitch?.message ?? "Kill switch is currently enabled."
        }

        guard let settings = store.tradingSettings else {
            return store.isConnected ? "Loading risk limits from backend." : "Backend connection is offline."
        }

        if settings.paperTradingOnly {
            return "Paper trading guard is active. Live orders are blocked."
        }

        return settings.autoTradingEnabled
            ? "Auto trading is allowed within configured risk limits."
            : "Auto trading is paused. Monitoring remains active."
    }

    private func dailyLossUsageRatio(_ settings: TradingSettings) -> Double {
        guard let equity = store.overview?.walletBalance, equity > 0 else { return 0 }
        // maxDailyLossPercent is stored as a 0–1 ratio by the backend.
        let maxLoss = equity * settings.maxDailyLossPercent
        guard maxLoss > 0 else { return 0 }
        // abs(min(...)) instead of max(0, -x) so a zero PnL cannot produce -0.
        let dailyLoss = abs(min(store.overview?.dailyPnl ?? 0, 0))
        return min(dailyLoss / maxLoss, 1)
    }

    private func dailyLossUsageText(_ settings: TradingSettings) -> String {
        let ratio = dailyLossUsageRatio(settings)
        return (ratio * 100).percentText
    }

    private func dailyLossUsageTint(_ settings: TradingSettings) -> Color {
        let ratio = dailyLossUsageRatio(settings)
        if ratio >= 0.8 { return AppTheme.negative }
        if ratio >= 0.5 { return AppTheme.warning }
        return AppTheme.positive
    }

    private func hasRatcheted(_ snapshot: TrailingStopSnapshot) -> Bool {
        guard let initial = snapshot.initialStopLoss, let current = snapshot.currentStopLoss else { return false }
        return abs(initial - current) > 0.000_001
    }

    private func close(_ position: FuturesPosition) {
        isClosing = true
        Task {
            _ = await store.close(position)
            isClosing = false
        }
    }
}
