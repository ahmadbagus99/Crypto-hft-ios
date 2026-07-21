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
                        MetricView(title: "Max daily loss", value: settings.maxDailyLossPercent.percentText, tint: AppTheme.warning)
                        MetricView(title: "Risk / trade", value: settings.riskPerTradePercent.percentText)
                        MetricView(title: "Max exposure", value: settings.maxExposurePercent.percentText)
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
                            Text((funding * 100).percentText)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(funding >= 0 ? AppTheme.positive : AppTheme.negative)
                        }
                    }
                }

                Picker("Interval", selection: Binding(
                    get: { store.chartInterval },
                    set: { value in Task { await store.changeInterval(value) } }
                )) {
                    ForEach(intervals, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)

                if store.klines.isEmpty {
                    ContentUnavailableView("No market data yet", systemImage: "chart.bar.xaxis")
                        .frame(height: 260)
                } else {
                    CandlestickChart(
                        candles: store.klines,
                        markPrice: store.markPrice?.markPrice,
                        interval: store.chartInterval
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
        let maxLoss = equity * settings.maxDailyLossPercent / 100
        guard maxLoss > 0 else { return 0 }
        let dailyLoss = max(0, -(store.overview?.dailyPnl ?? 0))
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

private struct CandlestickChart: View {
    let candles: [MarketKline]
    let markPrice: Double?
    let interval: String
    @State private var selectedID: String?

    private var visibleCandles: [MarketKline] { Array(candles.suffix(60)) }
    private var selectedCandle: MarketKline? {
        visibleCandles.first { $0.id == selectedID }
    }
    private var focusedCandle: MarketKline? { selectedCandle ?? visibleCandles.last }

    private var priceDomain: ClosedRange<Double> {
        var values = visibleCandles.flatMap { [$0.low, $0.high] }
        if let markPrice { values.append(markPrice) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let padding = max((high - low) * 0.08, max(abs(high) * 0.0005, 1))
        return (low - padding)...(high + padding)
    }

    var body: some View {
        VStack(spacing: 10) {
            if let candle = focusedCandle {
                HStack(spacing: 8) {
                    MetricView(title: "Open", value: candle.open.priceText)
                    MetricView(title: "High", value: candle.high.priceText, tint: AppTheme.positive)
                    MetricView(title: "Low", value: candle.low.priceText, tint: AppTheme.negative)
                    MetricView(title: "Close", value: candle.close.priceText, tint: candle.isUp ? AppTheme.positive : AppTheme.negative)
                }
            }

            Chart {
                ForEach(visibleCandles) { candle in
                    RuleMark(
                        x: .value("Time", candle.date),
                        yStart: .value("Low", candle.low),
                        yEnd: .value("High", candle.high)
                    )
                    .foregroundStyle(candleColor(candle))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                    RectangleMark(
                        x: .value("Time", candle.date),
                        yStart: .value("Open", min(candle.open, candle.close)),
                        yEnd: .value("Close", max(candle.open, candle.close)),
                        width: .fixed(4)
                    )
                    .foregroundStyle(candleColor(candle))
                }

                if let markPrice {
                    RuleMark(y: .value("Mark price", markPrice))
                        .foregroundStyle(AppTheme.warning.opacity(0.75))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                if let selectedCandle {
                    RuleMark(x: .value("Selected", selectedCandle.date))
                        .foregroundStyle(Color.white.opacity(0.34))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartYScale(domain: priceDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(AppTheme.border)
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(axisLabel(date))
                        }
                    }
                    .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine().foregroundStyle(AppTheme.border)
                    AxisValueLabel {
                        if let price = value.as(Double.self) {
                            Text(price.formatted(.number.notation(.compactName).precision(.fractionLength(1))))
                        }
                    }
                    .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .chartPlotStyle { plot in
                plot
                    .background(AppTheme.background.opacity(0.34))
                    .border(AppTheme.border)
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in selectCandle(at: value.location, proxy: proxy, geometry: geometry) }
                                .onEnded { _ in selectedID = nil }
                        )
                }
            }
            .frame(height: 250)

            HStack {
                Label("Drag the chart to inspect OHLC", systemImage: "hand.draw")
                Spacer()
                if let candle = focusedCandle {
                    Text(candle.date.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .font(.caption2)
            .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func candleColor(_ candle: MarketKline) -> Color {
        candle.isUp ? AppTheme.positive : AppTheme.negative
    }

    private func axisLabel(_ date: Date) -> String {
        if interval == "1d" {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.hour().minute())
    }

    private func selectCandle(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        guard frame.contains(location) else { return }
        let plotX = location.x - frame.origin.x
        guard let date: Date = proxy.value(atX: plotX) else { return }
        selectedID = visibleCandles.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }?.id
    }
}
