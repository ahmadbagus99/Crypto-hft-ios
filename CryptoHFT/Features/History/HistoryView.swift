import Charts
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedPeriod: HistoryPeriod = .month
    @State private var currentPage = 0

    private let pageSize = 10

    private var closedPositions: [PositionHistoryItem] {
        store.history?.positions.sorted { $0.closedDate > $1.closedDate } ?? []
    }

    private var pageCount: Int {
        max(1, Int(ceil(Double(closedPositions.count) / Double(pageSize))))
    }

    private var visiblePositions: [PositionHistoryItem] {
        let safePage = min(currentPage, pageCount - 1)
        let start = safePage * pageSize
        guard start < closedPositions.count else { return [] }
        return Array(closedPositions[start..<min(start + pageSize, closedPositions.count)])
    }

    private var cumulativePoints: [CumulativePnLPoint] {
        let ascending = closedPositions.sorted { $0.closedDate < $1.closedDate }
        guard let first = ascending.first else { return [] }

        var total = 0.0
        var points = [CumulativePnLPoint(
            id: "baseline",
            date: first.closedDate.addingTimeInterval(-1),
            value: 0
        )]
        for item in ascending {
            total += item.realizedPnl
            points.append(CumulativePnLPoint(id: item.id.uuidString, date: item.closedDate, value: total))
        }
        return points
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                realizationCard
                closedPositionsSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("History")
        .refreshable { await store.refresh() }
        .onChange(of: closedPositions.count) { _, _ in
            currentPage = min(currentPage, pageCount - 1)
        }
    }

    private var realizationCard: some View {
        let summary = store.history?.summary
        let total = summary?.totalRealizedPnl ?? 0

        return AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Realized Profit / Loss", systemImage: total >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(total >= 0 ? AppTheme.positive : AppTheme.negative)
                        Text(summary == nil ? "—" : total.signedCurrencyText)
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                            .foregroundStyle(total >= 0 ? .white : AppTheme.negative)
                        Text(selectedPeriod.subtitle)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer(minLength: 10)
                    periodSelector
                }

                if cumulativePoints.count > 1 {
                    Chart {
                        ForEach(cumulativePoints) { point in
                            AreaMark(
                                x: .value("Closed", point.date),
                                y: .value("Cumulative PnL", point.value)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AppTheme.accent.opacity(0.30), AppTheme.accent.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.linear)

                            LineMark(
                                x: .value("Closed", point.date),
                                y: .value("Cumulative PnL", point.value)
                            )
                            .foregroundStyle(AppTheme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.linear)
                        }

                        RuleMark(y: .value("Break even", 0))
                            .foregroundStyle(Color.white.opacity(0.12))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartPlotStyle { plot in
                        plot.background(AppTheme.background.opacity(0.18))
                    }
                    .frame(height: 180)
                } else {
                    ContentUnavailableView(
                        "No realized PnL yet",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Closed positions in this period will form the PnL curve.")
                    )
                    .frame(height: 180)
                }

                Divider().overlay(AppTheme.border)
                HStack {
                    MetricView(
                        title: "Win rate",
                        value: summary.map { ($0.winRate * 100).percentText } ?? "—"
                    )
                    MetricView(title: "Trades", value: summary.map { "\($0.totalTrades)" } ?? "—")
                    MetricView(
                        title: "Best",
                        value: summary?.bestTrade.signedCurrencyText ?? "—",
                        tint: AppTheme.positive
                    )
                    MetricView(
                        title: "Worst",
                        value: summary?.worstTrade.signedCurrencyText ?? "—",
                        tint: AppTheme.negative
                    )
                }
            }
        }
    }

    private var periodSelector: some View {
        HStack(spacing: 4) {
            ForEach(HistoryPeriod.allCases) { period in
                Button {
                    guard period != selectedPeriod else { return }
                    selectedPeriod = period
                    currentPage = 0
                    Task { await store.changeHistoryPeriod(period.rawValue) }
                } label: {
                    Text(period.shortLabel)
                        .font(.caption2.bold())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .foregroundStyle(selectedPeriod == period ? .white : AppTheme.secondaryText)
                        .background(selectedPeriod == period ? AppTheme.accent.opacity(0.24) : .clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(AppTheme.surfaceRaised.opacity(0.65))
        .clipShape(Capsule())
    }

    private var closedPositionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Closed positions").font(.headline)
                Spacer()
                Text("\(closedPositions.count) trades")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            if closedPositions.isEmpty {
                AppCard {
                    ContentUnavailableView(
                        "No closed positions yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("There is no history for this period yet.")
                    )
                    .frame(minHeight: 150)
                }
            } else {
                ForEach(visiblePositions) { position in
                    closedPositionCard(position)
                }
                pagination
            }
        }
    }

    private func closedPositionCard(_ position: PositionHistoryItem) -> some View {
        AppCard {
            VStack(spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(position.symbol).font(.headline)
                        Text("\(position.side.uppercased()) · \(position.leverage)x · \(position.closeReason?.description ?? "Closed")")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(position.realizedPnl.signedCurrencyText)
                            .font(.title3.bold())
                            .foregroundStyle(position.realizedPnl >= 0 ? AppTheme.positive : AppTheme.negative)
                        Text("ROI \(position.roi.percentText)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                Divider().overlay(AppTheme.border)
                HStack {
                    MetricView(title: "Entry", value: position.entryPrice.priceText)
                    MetricView(title: "Margin", value: position.margin.currencyText)
                    MetricView(title: "Size", value: String(format: "%.6f BTC", position.quantity))
                }
                HStack {
                    Text(position.openedDate.formatted(date: .abbreviated, time: .shortened))
                    Image(systemName: "arrow.right")
                    Text(position.closedDate.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var pagination: some View {
        HStack(spacing: 18) {
            Button {
                currentPage = max(0, currentPage - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 34)
                    .background(AppTheme.surfaceRaised)
                    .clipShape(Circle())
            }
            .disabled(currentPage == 0)
            .opacity(currentPage == 0 ? 0.35 : 1)

            Text("Page \(currentPage + 1) of \(pageCount) · 10 per page")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.secondaryText)

            Button {
                currentPage = min(pageCount - 1, currentPage + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 34, height: 34)
                    .background(AppTheme.surfaceRaised)
                    .clipShape(Circle())
            }
            .disabled(currentPage >= pageCount - 1)
            .opacity(currentPage >= pageCount - 1 ? 0.35 : 1)
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .padding(.top, 4)
    }
}

private enum HistoryPeriod: String, CaseIterable, Identifiable {
    case week
    case month
    case all

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .week: "1W"
        case .month: "1M"
        case .all: "ALL"
        }
    }

    var subtitle: String {
        switch self {
        case .week: "This week"
        case .month: "This month"
        case .all: "All time"
        }
    }
}

private struct CumulativePnLPoint: Identifiable {
    let id: String
    let date: Date
    let value: Double
}
