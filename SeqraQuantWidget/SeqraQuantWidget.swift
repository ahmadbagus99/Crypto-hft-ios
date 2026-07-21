import SwiftUI
import WidgetKit

private let widgetSymbol = "BTCUSDT"
private let widgetBackendURL = "https://trading.seqra.space"

struct SeqraQuantWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: SeqraQuantWidgetSnapshot
}

struct SeqraQuantWidgetSnapshot {
    let isConnected: Bool
    let markPrice: Double?
    let indexPrice: Double?
    let dailyPnl: Double?
    let walletBalance: Double?
    let position: FuturesPosition?
    let takeProfit: Double?
    let stopLoss: Double?
    let errorMessage: String?

    static let placeholder = SeqraQuantWidgetSnapshot(
        isConnected: true,
        markPrice: 64_499.38,
        indexPrice: 64_488.21,
        dailyPnl: 124.82,
        walletBalance: 1_250.00,
        position: nil,
        takeProfit: 65_400.00,
        stopLoss: 63_900.00,
        errorMessage: nil
    )

    static let offline = SeqraQuantWidgetSnapshot(
        isConnected: false,
        markPrice: nil,
        indexPrice: nil,
        dailyPnl: nil,
        walletBalance: nil,
        position: nil,
        takeProfit: nil,
        stopLoss: nil,
        errorMessage: "Backend unavailable"
    )
}

struct SeqraQuantWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SeqraQuantWidgetEntry {
        SeqraQuantWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SeqraQuantWidgetEntry) -> Void) {
        completion(SeqraQuantWidgetEntry(date: Date(), snapshot: .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SeqraQuantWidgetEntry>) -> Void) {
        Task {
            let snapshot = await loadSnapshot()
            let entry = SeqraQuantWidgetEntry(date: Date(), snapshot: snapshot)
            let refreshDate = Calendar.current.date(byAdding: .minute, value: 5, to: entry.date) ?? entry.date.addingTimeInterval(300)
            completion(Timeline(entries: [entry], policy: .after(refreshDate)))
        }
    }

    private func loadSnapshot() async -> SeqraQuantWidgetSnapshot {
        guard let api = APIClient(baseURLString: widgetBackendURL) else { return .offline }

        async let markTask: MarketMarkPrice? = try? api.markPrice(symbol: widgetSymbol)
        async let overviewTask: Overview? = try? api.overview()
        async let positionsTask: [FuturesPosition]? = try? api.positions(symbol: widgetSymbol)
        async let ordersTask: JournalOrdersResponse? = try? api.journalOrders(symbol: widgetSymbol, limit: 30)

        let mark = await markTask
        let overview = await overviewTask
        let positions = await positionsTask ?? []
        let orders = await ordersTask
        let position = positions.first(where: \.isOpen)
        let protection = position.map { protectionLevels(for: $0, orders: orders?.orders ?? []) }

        let hasAnyData = mark != nil || overview != nil || position != nil
        return SeqraQuantWidgetSnapshot(
            isConnected: hasAnyData,
            markPrice: mark?.markPrice,
            indexPrice: mark?.indexPrice,
            dailyPnl: overview?.dailyPnl,
            walletBalance: overview?.walletBalance,
            position: position,
            takeProfit: protection?.takeProfit,
            stopLoss: protection?.stopLoss,
            errorMessage: hasAnyData ? nil : "Backend unavailable"
        )
    }

    private func protectionLevels(for position: FuturesPosition, orders: [JournalOrder]) -> (takeProfit: Double?, stopLoss: Double?) {
        let closingSide = position.positionAmount > 0 ? "Short" : "Long"
        let activeOrders = orders.filter {
            $0.symbol == position.symbol &&
            $0.reduceOnly &&
            $0.status == "New" &&
            $0.side == closingSide
        }

        let takeProfit = activeOrders.first { $0.kind == "TakeProfit" }?.stopPrice
        let stopLoss = activeOrders.first { $0.kind == "StopMarket" }?.stopPrice
        return (takeProfit, stopLoss)
    }
}

struct SeqraQuantPositionWidget: Widget {
    let kind = "SeqraQuantPositionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SeqraQuantWidgetProvider()) { entry in
            SeqraQuantWidgetView(entry: entry)
        }
        .configurationDisplayName("Seqra Quant")
        .description("Monitor BTC price, open position, PnL, margin, leverage, TP and SL.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct SeqraQuantWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SeqraQuantWidgetEntry

    private var snapshot: SeqraQuantWidgetSnapshot { entry.snapshot }
    private var position: FuturesPosition? { snapshot.position }

    var body: some View {
        ZStack {
            AppTheme.background

            switch family {
            case .systemSmall:
                smallLayout
            case .systemLarge:
                largeLayout
            default:
                mediumLayout
            }
        }
        .containerBackground(AppTheme.background, for: .widget)
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            Text(snapshot.markPrice?.priceText ?? "—")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)

            if let position {
                positionPill(position)
                Text(position.unrealizedProfit.signedCurrencyText)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(position.unrealizedProfit >= 0 ? AppTheme.positive : AppTheme.negative)
            } else {
                Text(snapshot.errorMessage ?? "No open position")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(14)
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 7) {
            compactHeader
            mediumTopLine

            Divider().overlay(AppTheme.border)

            if let position {
                mediumPosition(position)
            } else {
                mediumNoPosition
            }

            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 13) {
            mediumLayoutContent

            Divider().overlay(AppTheme.border)

            if let position {
                HStack {
                    widgetMetric("Take profit", snapshot.takeProfit?.priceText ?? "—", tint: AppTheme.positive)
                    widgetMetric("Stop loss", snapshot.stopLoss?.priceText ?? "—", tint: AppTheme.negative)
                    widgetMetric("Liquidation", position.liquidationPrice > 0 ? position.liquidationPrice.priceText : "—", tint: AppTheme.warning)
                }
                HStack {
                    widgetMetric("Margin", position.marginUsed.currencyText)
                    widgetMetric("Leverage", "\(Int(position.leverage))x", tint: AppTheme.warning)
                    widgetMetric("Notional", position.notional.currencyText)
                }
            } else {
                noPositionView
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var mediumLayoutContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack {
                widgetMetric("BTC mark", snapshot.markPrice?.priceText ?? "—")
                widgetMetric("Index", snapshot.indexPrice?.priceText ?? "—")
                widgetMetric("Daily PnL", snapshot.dailyPnl?.signedCurrencyText ?? "—", tint: (snapshot.dailyPnl ?? 0) >= 0 ? AppTheme.positive : AppTheme.negative)
            }
            if let position {
                compactPosition(position)
            }
        }
    }

    private func compactPosition(_ position: FuturesPosition) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                positionPill(position)
                Spacer()
                Text(position.unrealizedProfit.signedCurrencyText)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(position.unrealizedProfit >= 0 ? AppTheme.positive : AppTheme.negative)
            }

            HStack {
                widgetMetric("Entry", position.entryPrice.priceText)
                widgetMetric("Mark", position.markPrice.priceText)
                widgetMetric("ROI", position.pnlPercent.percentText, tint: position.pnlPercent >= 0 ? AppTheme.positive : AppTheme.negative)
            }

            HStack {
                widgetMetric("Margin", position.marginUsed.currencyText)
                widgetMetric("Lev", "\(Int(position.leverage))x", tint: AppTheme.warning)
                widgetMetric("TP / SL", "\(snapshot.takeProfit?.priceText ?? "—") / \(snapshot.stopLoss?.priceText ?? "—")")
            }
        }
    }

    private var mediumTopLine: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("BTC MARK")
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(snapshot.markPrice?.priceText ?? "—")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text("DAILY PNL")
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(snapshot.dailyPnl?.signedCurrencyText ?? "—")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle((snapshot.dailyPnl ?? 0) >= 0 ? AppTheme.positive : AppTheme.negative)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
    }

    private func mediumPosition(_ position: FuturesPosition) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                positionPill(position)
                HStack(spacing: 8) {
                    tinyMetric("ENTRY", position.entryPrice.priceText)
                    tinyMetric("MARK", position.markPrice.priceText)
                    tinyMetric("ROI", position.pnlPercent.percentText, tint: position.pnlPercent >= 0 ? AppTheme.positive : AppTheme.negative)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 5) {
                Text(position.unrealizedProfit.signedCurrencyText)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(position.unrealizedProfit >= 0 ? AppTheme.positive : AppTheme.negative)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text("M \(position.marginUsed.currencyText)  \(Int(position.leverage))x")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("TP \(snapshot.takeProfit?.priceText ?? "—") / SL \(snapshot.stopLoss?.priceText ?? "—")")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            .frame(maxWidth: 150, alignment: .trailing)
        }
    }

    private var mediumNoPosition: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.errorMessage ?? "No open position")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Last updated \(entry.date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            Text(snapshot.walletBalance?.currencyText ?? "—")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
        }
    }

    private var noPositionView: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(snapshot.errorMessage ?? "No open position")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text("Last updated \(entry.date.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(snapshot.isConnected ? AppTheme.positive : AppTheme.negative)
                .frame(width: 7, height: 7)
            Text("SEQRA QUANT")
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer(minLength: 0)
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var compactHeader: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(snapshot.isConnected ? AppTheme.positive : AppTheme.negative)
                .frame(width: 6, height: 6)
            Text("SEQRA QUANT")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer(minLength: 0)
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func positionPill(_ position: FuturesPosition) -> some View {
        Text("\(position.direction) \(position.symbol.replacingOccurrences(of: "USDT", with: ""))")
            .font(.caption.weight(.bold))
            .foregroundStyle(position.positionAmount >= 0 ? AppTheme.positive : AppTheme.negative)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((position.positionAmount >= 0 ? AppTheme.positive : AppTheme.negative).opacity(0.13))
            .clipShape(Capsule())
    }

    private func widgetMetric(_ title: String, _ value: String, tint: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tinyMetric(_ title: String, _ value: String, tint: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: 58, alignment: .leading)
    }
}

@main
struct SeqraQuantWidgetBundle: WidgetBundle {
    var body: some Widget {
        SeqraQuantPositionWidget()
    }
}
