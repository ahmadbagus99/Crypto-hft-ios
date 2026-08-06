import Charts
import SwiftUI
import UIKit

// MARK: - Price levels

/// A horizontal price line drawn over the candles. Every level mirrors a value the
/// backend engine actually manages (position entry, reduce-only TP/SL orders,
/// trailing stop ratchet, liquidation) or a level the AI decision proposes.
struct ChartPriceLevel: Identifiable, Equatable {
    enum Dash {
        case solid, dashed, dotted
    }

    let id: String
    let tag: String
    let title: String
    let price: Double
    let color: Color
    var dash: Dash = .dashed
    var isPlanned = false

    var strokeStyle: StrokeStyle {
        switch dash {
        case .solid: StrokeStyle(lineWidth: 1.3)
        case .dashed: StrokeStyle(lineWidth: 1.3, dash: [6, 4])
        case .dotted: StrokeStyle(lineWidth: 1, dash: [2, 3])
        }
    }
}

/// Pan/zoom state, expressed in candle units so it survives new candles arriving.
struct ChartViewport: Equatable {
    /// How many candles fit on screen.
    var visibleCount: Double = 60
    /// How many candles are hidden past the right edge. `0` follows the latest candle.
    var offset: Double = 0

    static let minimumVisible: Double = 15
    static let maximumVisible: Double = 260
}

// MARK: - Card wrapper

struct TradingChartCard: View {
    let symbol: String
    let candles: [MarketKline]
    let levels: [ChartPriceLevel]
    let interval: String
    let intervals: [String]
    let onIntervalChange: (String) -> Void

    @State private var viewport = ChartViewport()
    @State private var showsFullScreen = false

    var body: some View {
        VStack(spacing: 10) {
            Picker("Interval", selection: Binding(
                get: { interval },
                set: onIntervalChange
            )) {
                ForEach(intervals, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)

            TradingChart(
                candles: candles,
                levels: levels,
                interval: interval,
                viewport: $viewport,
                chartHeight: 260
            )

            ChartControlBar(
                viewport: $viewport,
                candleCount: candles.count,
                isFullScreen: false,
                onToggleFullScreen: {
                    // Opt into landscape before presenting: the cover inherits the supported
                    // orientations that are in effect when it is created.
                    OrientationLock.allowLandscape()
                    showsFullScreen = true
                }
            )
        }
        .fullScreenCover(isPresented: $showsFullScreen) {
            FullScreenChartView(
                symbol: symbol,
                candles: candles,
                levels: levels,
                interval: interval,
                intervals: intervals,
                onIntervalChange: onIntervalChange,
                viewport: $viewport
            )
        }
    }
}

// MARK: - Full screen

private struct FullScreenChartView: View {
    let symbol: String
    let candles: [MarketKline]
    let levels: [ChartPriceLevel]
    let interval: String
    let intervals: [String]
    let onIntervalChange: (String) -> Void
    @Binding var viewport: ChartViewport

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(symbol).font(.headline)
                    Text(candles.last?.close.priceText ?? "—")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer(minLength: 8)

                Picker("Interval", selection: Binding(
                    get: { interval },
                    set: onIntervalChange
                )) {
                    ForEach(intervals, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(9)
                        .background(AppTheme.surfaceRaised, in: Circle())
                }
                .buttonStyle(.plain)
            }

            TradingChart(
                candles: candles,
                levels: levels,
                interval: interval,
                viewport: $viewport,
                chartHeight: nil
            )

            ChartControlBar(
                viewport: $viewport,
                candleCount: candles.count,
                isFullScreen: true,
                onToggleFullScreen: { dismiss() }
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
        .statusBarHidden()
        .task {
            // Give the cover time to become the presented controller before asking to rotate.
            try? await Task.sleep(nanoseconds: 80_000_000)
            OrientationLock.allowLandscape()
        }
        .onDisappear { OrientationLock.lockPortrait() }
    }
}

// MARK: - Control bar

private struct ChartControlBar: View {
    @Binding var viewport: ChartViewport
    let candleCount: Int
    let isFullScreen: Bool
    let onToggleFullScreen: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label("Drag to pan · pinch to zoom · hold for crosshair", systemImage: "hand.draw")
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 4)

            controlButton("minus.magnifyingglass") { zoom(by: 1.4) }
            controlButton("plus.magnifyingglass") { zoom(by: 1 / 1.4) }
            controlButton("arrow.uturn.right") { reset() }
                .opacity(viewport.offset > 0.5 ? 1 : 0.35)
            controlButton(isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", action: onToggleFullScreen)
        }
    }

    private func controlButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(AppTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func zoom(by factor: Double) {
        let maximum = min(ChartViewport.maximumVisible, Double(max(candleCount, 20)))
        withAnimation(.easeOut(duration: 0.18)) {
            viewport.visibleCount = min(max(viewport.visibleCount * factor, ChartViewport.minimumVisible), maximum)
            viewport.offset = min(viewport.offset, max(0, Double(candleCount) - viewport.visibleCount))
        }
    }

    private func reset() {
        withAnimation(.easeOut(duration: 0.2)) { viewport.offset = 0 }
    }
}

// MARK: - Chart

struct TradingChart: View {
    let candles: [MarketKline]
    let levels: [ChartPriceLevel]
    let interval: String
    @Binding var viewport: ChartViewport
    /// `nil` lets the chart expand to fill the available height (full screen).
    var chartHeight: CGFloat? = 260

    /// `ignored` is used when the finger moves vertically: the drag then belongs to the
    /// surrounding scroll view instead of the chart.
    private enum DragMode { case idle, pan, crosshair, ignored }

    @State private var plotRect: CGRect = .zero
    @State private var crosshairIndex: Int?
    @State private var dragMode: DragMode = .idle
    @State private var panAnchor: Double = 0
    @State private var zoomAnchor: Double?
    @State private var crosshairTask: Task<Void, Never>?

    private let axisLabelWidth: CGFloat = 52

    var body: some View {
        VStack(spacing: 6) {
            ohlcHeader
            priceChart
            volumeChart
            if !levels.isEmpty { legend }
        }
        .onChange(of: candles.count) { _, _ in crosshairIndex = nil }
    }

    // MARK: Derived geometry

    private var count: Int { candles.count }

    private var candleSpacing: TimeInterval {
        var deltas: [TimeInterval] = []
        for index in 1..<max(count, 1) {
            let delta = candles[index].date.timeIntervalSince(candles[index - 1].date)
            if delta > 0 { deltas.append(delta) }
        }
        guard !deltas.isEmpty else { return Self.seconds(for: interval) }
        deltas.sort()
        return deltas[deltas.count / 2]
    }

    /// Anchored on the newest candle so the right edge stays exact even if history has gaps.
    private var anchorDate: Date {
        guard let last = candles.last else { return .now }
        return last.date.addingTimeInterval(-Double(max(count - 1, 0)) * candleSpacing)
    }

    private var maximumVisible: Double { min(ChartViewport.maximumVisible, Double(max(count, 20))) }
    private var visibleCount: Double { min(max(viewport.visibleCount, ChartViewport.minimumVisible), maximumVisible) }
    private var maximumOffset: Double { max(0, Double(count) - visibleCount) }
    private var offset: Double { min(max(viewport.offset, 0), maximumOffset) }

    private var rightIndex: Double { Double(max(count - 1, 0)) - offset }
    private var leftIndex: Double { rightIndex - (visibleCount - 1) }
    private var domainSpan: Double { visibleCount + 0.2 }

    private func date(atIndex index: Double) -> Date {
        anchorDate.addingTimeInterval(index * candleSpacing)
    }

    private var xDomain: ClosedRange<Date> {
        date(atIndex: leftIndex - 0.6)...date(atIndex: rightIndex + 0.6)
    }

    private var visibleCandles: [MarketKline] {
        guard count > 0 else { return [] }
        let low = min(max(0, Int(leftIndex.rounded(.down)) - 1), count - 1)
        let high = min(count - 1, max(Int(rightIndex.rounded(.up)) + 1, 0))
        guard low <= high else { return [] }
        return Array(candles[low...high])
    }

    private var bodyWidth: CGFloat {
        guard plotRect.width > 0 else { return 4 }
        return max(1.5, min(18, (plotRect.width / CGFloat(visibleCount)) * 0.62))
    }

    private var priceDomain: ClosedRange<Double> {
        let visible = visibleCandles
        guard var low = visible.map(\.low).min(), var high = visible.map(\.high).max() else { return 0...1 }
        let span = max(high - low, max(high * 0.0008, 0.5))
        // Only pull a level into the scale when it is close enough to keep the candles readable.
        for level in levels where level.price > low - span * 0.75 && level.price < high + span * 0.75 {
            low = min(low, level.price)
            high = max(high, level.price)
        }
        let padding = max((high - low) * 0.08, max(high * 0.0004, 0.5))
        return (low - padding)...(high + padding)
    }

    private var drawableLevels: [ChartPriceLevel] {
        let domain = priceDomain
        return levels.filter { domain.contains($0.price) }
    }

    private var crosshairCandle: MarketKline? {
        guard let crosshairIndex, candles.indices.contains(crosshairIndex) else { return nil }
        return candles[crosshairIndex]
    }

    private var focusedCandle: MarketKline? {
        crosshairCandle ?? visibleCandles.last ?? candles.last
    }

    // MARK: Header

    private var ohlcHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let candle = focusedCandle {
                ohlcItem("O", candle.open, .white)
                ohlcItem("H", candle.high, AppTheme.positive)
                ohlcItem("L", candle.low, AppTheme.negative)
                ohlcItem("C", candle.close, candle.isUp ? AppTheme.positive : AppTheme.negative)

                let change = candle.open > 0 ? (candle.close - candle.open) / candle.open * 100 : 0
                Text(String(format: "%+.2f%%", change))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(change >= 0 ? AppTheme.positive : AppTheme.negative)

                Spacer(minLength: 0)

                Text(timeLabel(candle.date))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                Text("No candles").font(.caption).foregroundStyle(AppTheme.secondaryText)
                Spacer(minLength: 0)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func ohlcItem(_ title: String, _ value: Double, _ tint: Color) -> some View {
        HStack(spacing: 3) {
            Text(title).foregroundStyle(AppTheme.secondaryText)
            Text(Self.compactPrice(value)).foregroundStyle(tint)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
    }

    /// Drops the cents on large prices so four OHLC values fit on a phone width.
    private static func compactPrice(_ value: Double) -> String {
        let digits = abs(value) >= 1_000 ? 0 : 2
        return value.formatted(.number.precision(.fractionLength(digits)).locale(Locale(identifier: "en_US")))
    }

    // MARK: Price chart

    private var priceChart: some View {
        Chart {
            ForEach(visibleCandles) { candle in
                RuleMark(
                    x: .value("Time", candle.date),
                    yStart: .value("Low", candle.low),
                    yEnd: .value("High", candle.high)
                )
                .foregroundStyle(color(for: candle))
                .lineStyle(StrokeStyle(lineWidth: max(1, bodyWidth * 0.16)))

                RectangleMark(
                    x: .value("Time", candle.date),
                    yStart: .value("Open", min(candle.open, candle.close)),
                    yEnd: .value("Close", max(candle.open, candle.close)),
                    width: .fixed(bodyWidth)
                )
                .foregroundStyle(color(for: candle))
            }

            ForEach(drawableLevels) { level in
                RuleMark(y: .value(level.title, level.price))
                    .foregroundStyle(level.color.opacity(level.isPlanned ? 0.5 : 0.9))
                    .lineStyle(level.strokeStyle)
                    .annotation(
                        position: .top,
                        alignment: .trailing,
                        spacing: 1,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        levelTag(level)
                    }
            }

            if let candle = crosshairCandle {
                RuleMark(x: .value("Crosshair", candle.date))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                RuleMark(y: .value("Crosshair price", candle.close))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(
                        position: .top,
                        alignment: .leading,
                        spacing: 1,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        Text(candle.close.priceText)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.16), in: Capsule())
                    }
            }
        }
        .chartXScale(domain: xDomain)
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
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 6)) { value in
                AxisGridLine().foregroundStyle(AppTheme.border)
                AxisValueLabel {
                    if let price = value.as(Double.self) {
                        Text(Self.compactPrice(price))
                            .frame(width: axisLabelWidth, alignment: .leading)
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
                let rect = proxy.plotFrame.map { geometry[$0] } ?? .zero
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onChange(of: rect, initial: true) { _, newValue in plotRect = newValue }
                    // Simultaneous so a vertical drag still scrolls the dashboard underneath.
                    .simultaneousGesture(panAndCrosshairGesture)
                    .simultaneousGesture(zoomGesture)
                    .onTapGesture(count: 2) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            viewport = ChartViewport()
                            crosshairIndex = nil
                        }
                    }
            }
        }
        .frame(height: chartHeight)
        .frame(maxHeight: chartHeight == nil ? .infinity : nil)
    }

    // MARK: Volume chart

    private var volumeChart: some View {
        Chart {
            ForEach(visibleCandles) { candle in
                BarMark(
                    x: .value("Time", candle.date),
                    y: .value("Volume", candle.volume),
                    width: .fixed(bodyWidth)
                )
                .foregroundStyle(color(for: candle).opacity(0.45))
            }
        }
        .chartXScale(domain: xDomain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) { value in
                AxisGridLine().foregroundStyle(AppTheme.border)
                AxisValueLabel {
                    if let volume = value.as(Double.self) {
                        Text(volume.formatted(.number.notation(.compactName).precision(.fractionLength(0))))
                            .frame(width: axisLabelWidth, alignment: .leading)
                    }
                }
                .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .chartPlotStyle { plot in
            plot.background(AppTheme.background.opacity(0.34))
        }
        .frame(height: chartHeight == nil ? 64 : 46)
    }

    // MARK: Legend

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(levels) { level in
                    HStack(spacing: 4) {
                        Capsule()
                            .fill(level.color)
                            .frame(width: 10, height: 2)
                        Text("\(level.tag) \(level.price.priceText)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(level.color.opacity(level.isPlanned ? 0.7 : 1))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(level.color.opacity(0.12), in: Capsule())
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func levelTag(_ level: ChartPriceLevel) -> some View {
        Text("\(level.tag) \(level.price.priceText)")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(level.color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(AppTheme.surface.opacity(0.92), in: Capsule())
            .overlay(Capsule().stroke(level.color.opacity(0.55), lineWidth: 0.8))
    }

    // MARK: Gestures

    private var panAndCrosshairGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                switch dragMode {
                case .idle:
                    let horizontal = abs(value.translation.width)
                    let vertical = abs(value.translation.height)
                    if horizontal > 8 && horizontal >= vertical {
                        crosshairTask?.cancel()
                        crosshairTask = nil
                        crosshairIndex = nil
                        dragMode = .pan
                        panAnchor = offset
                    } else if vertical > 8 {
                        crosshairTask?.cancel()
                        crosshairTask = nil
                        dragMode = .ignored
                    } else if crosshairTask == nil {
                        scheduleCrosshair(at: value.location.x)
                    }
                case .pan, .ignored:
                    break
                case .crosshair:
                    crosshairIndex = index(atX: value.location.x)
                }

                if dragMode == .pan {
                    let candlesPerPoint = domainSpan / Double(max(plotRect.width, 1))
                    setOffset(panAnchor + Double(value.translation.width) * candlesPerPoint)
                }
            }
            .onEnded { _ in
                crosshairTask?.cancel()
                crosshairTask = nil
                dragMode = .idle
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                crosshairTask?.cancel()
                crosshairTask = nil
                let anchor = zoomAnchor ?? visibleCount
                zoomAnchor = anchor
                let target = anchor / max(value.magnification, 0.1)
                viewport.visibleCount = min(max(target, ChartViewport.minimumVisible), maximumVisible)
                setOffset(viewport.offset)
            }
            .onEnded { _ in zoomAnchor = nil }
    }

    private func scheduleCrosshair(at x: CGFloat) {
        crosshairTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled, dragMode == .idle else { return }
            dragMode = .crosshair
            crosshairIndex = index(atX: x)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func setOffset(_ value: Double) {
        viewport.offset = min(max(value, 0), maximumOffset)
    }

    private func index(atX x: CGFloat) -> Int {
        guard count > 0 else { return 0 }
        guard plotRect.width > 0 else { return count - 1 }
        let ratio = Double((x - plotRect.minX) / plotRect.width)
        let raw = leftIndex - 0.6 + ratio * domainSpan
        return min(max(Int(raw.rounded()), 0), count - 1)
    }

    // MARK: Formatting

    private func color(for candle: MarketKline) -> Color {
        candle.isUp ? AppTheme.positive : AppTheme.negative
    }

    private func axisLabel(_ date: Date) -> String {
        switch interval {
        case "1d": date.formatted(.dateTime.month(.abbreviated).day())
        case "4h", "1h": date.formatted(.dateTime.day().hour())
        default: date.formatted(.dateTime.hour().minute())
        }
    }

    private func timeLabel(_ date: Date) -> String {
        interval == "1d"
            ? date.formatted(date: .abbreviated, time: .omitted)
            : date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func seconds(for interval: String) -> TimeInterval {
        switch interval {
        case "1m": 60
        case "5m": 300
        case "15m": 900
        case "1h": 3_600
        case "4h": 14_400
        case "1d": 86_400
        default: 900
        }
    }
}

// MARK: - Orientation

/// The app ships portrait-only; the full screen chart temporarily opts into landscape
/// so the candles get the same room they would in a desktop terminal.
@MainActor
enum OrientationLock {
    private(set) static var mask: UIInterfaceOrientationMask = .portrait

    static func allowLandscape() {
        mask = [.portrait, .landscapeLeft, .landscapeRight]
        apply(preferred: .landscapeRight)
    }

    static func lockPortrait() {
        mask = .portrait
        apply(preferred: .portrait)
    }

    private static func apply(preferred: UIInterfaceOrientationMask) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }

        // UIKit asks the topmost presented controller, so the full screen cover has to be
        // the one told that its supported orientations changed.
        for window in scene.windows {
            var controller = window.rootViewController
            while let presented = controller?.presentedViewController { controller = presented }
            controller?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }

        // The invalidation above is applied on the next run loop pass, so requesting the
        // rotation immediately would still be measured against the previous mask.
        Task { @MainActor in
            let wantsLandscape = preferred != .portrait
            // Retry a few times: the first request can still be measured against the old mask.
            for _ in 0..<8 {
                if scene.interfaceOrientation.isLandscape == wantsLandscape { return }
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: preferred))
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
        }
    }
}
