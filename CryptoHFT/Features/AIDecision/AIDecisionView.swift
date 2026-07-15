import SwiftUI

struct AIDecisionView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if let decision = store.aiDecision {
                    decisionHeader(decision)
                    claudeUsageCard
                    confidenceCard(decision)
                    executionCard(decision)
                    factorCard(decision)
                    claudeCard(decision)
                    reasoningCard(decision)
                    sourceNote(decision)
                } else {
                    ContentUnavailableView(
                        "No AI decision yet",
                        systemImage: "brain.head.profile",
                        description: Text("The latest analysis will appear after the backend makes a decision for BTCUSDT.")
                    )
                    .frame(minHeight: 240)
                    claudeUsageCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("AI Decision")
        .refreshable { await store.refresh() }
    }

    private func decisionHeader(_ decision: AIDecision) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(decision.symbol)
                            .font(.caption.weight(.bold))
                            .tracking(1)
                            .foregroundStyle(AppTheme.secondaryText)
                        Text(decision.actionLabel)
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                            .foregroundStyle(directionColor(decision.direction))
                    }
                    Spacer()
                    StatusPill(
                        label: decision.shouldTrade ? "TRADE" : "NO TRADE",
                        active: decision.shouldTrade
                    )
                }

                HStack {
                    MetricView(title: "Confidence", value: decision.confidence.percentText, tint: directionColor(decision.direction))
                    MetricView(title: "Success prob.", value: decision.probabilityOfSuccess.percentText)
                    MetricView(title: "Regime", value: decision.regimeLabel, tint: AppTheme.accent)
                }

                if !decision.shouldTrade, !decision.noTradeReason.isEmpty {
                    Label(decision.noTradeReason, systemImage: "pause.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.warning)
                }
            }
        }
    }

    private func confidenceCard(_ decision: AIDecision) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Directional Confidence").font(.headline)
                confidenceBar("Buy", value: decision.confidenceBuy, color: AppTheme.positive)
                confidenceBar("Sell", value: decision.confidenceSell, color: AppTheme.negative)
                confidenceBar("Hold", value: decision.confidenceHold, color: AppTheme.warning)
            }
        }
    }

    private func confidenceBar(_ title: String, value: Double, color: Color) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(value.percentText).font(.subheadline.monospacedDigit()).foregroundStyle(color)
            }
            ProgressView(value: max(0, min(100, value)), total: 100)
                .tint(color)
        }
    }

    private func executionCard(_ decision: AIDecision) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Trade Plan").font(.headline)
                HStack {
                    MetricView(title: "Entry", value: decision.entryPrice.priceText)
                    MetricView(title: "Stop loss", value: decision.stopLoss.priceText, tint: AppTheme.negative)
                    MetricView(title: "Take profit", value: decision.takeProfit.priceText, tint: AppTheme.positive)
                }
                Divider().overlay(AppTheme.border)
                HStack {
                    MetricView(title: "Risk / reward", value: String(format: "%.2f", decision.riskReward))
                    MetricView(title: "Size", value: String(format: "%.6f BTC", decision.positionSizeQuantity))
                    MetricView(title: "Leverage", value: "\(decision.leverage)x", tint: AppTheme.warning)
                }
                Text("Trailing stop \(decision.trailingStopPercent.percentText)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private func factorCard(_ decision: AIDecision) -> some View {
        let factors = decision.scores.sorted { lhs, rhs in
            (decision.weights[lhs.key] ?? 0) > (decision.weights[rhs.key] ?? 0)
        }

        return AppCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Decision Factors").font(.headline)
                ForEach(factors, id: \.key) { factor in
                    VStack(spacing: 6) {
                        HStack {
                            Text(factor.key.capitalized).font(.subheadline)
                            if let weight = decision.weights[factor.key], weight > 0 {
                                Text("· \((weight * 100).formatted(.number.precision(.fractionLength(0))))% weight")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                            Spacer()
                            Text(factor.value.formatted(.number.precision(.fractionLength(1))))
                                .font(.subheadline.monospacedDigit())
                        }
                        ProgressView(value: max(0, min(100, factor.value)), total: 100)
                            .tint(scoreColor(factor.value))
                    }
                }
            }
        }
    }

    private func claudeCard(_ decision: AIDecision) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("Claude Validation", systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                    Text(decision.llm.used ? (decision.llm.confirmed ? "CONFIRMED" : "ADJUSTED") : "NOT USED")
                        .font(.caption2.bold())
                        .foregroundStyle(decision.llm.confirmed ? AppTheme.positive : AppTheme.warning)
                }

                if decision.llm.used {
                    HStack {
                        MetricView(title: "Adjusted confidence", value: decision.llm.adjustedConfidence.percentText)
                        if let multiplier = decision.llm.sizeMultiplier {
                            MetricView(title: "Size multiplier", value: String(format: "%.2fx", multiplier))
                        }
                    }
                    if !decision.llm.narrative.isEmpty {
                        Text(decision.llm.narrative)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.86))
                    }
                    if !decision.llm.risks.isEmpty {
                        Divider().overlay(AppTheme.border)
                        Text("Risks").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.warning)
                        ForEach(Array(decision.llm.risks.enumerated()), id: \.offset) { _, risk in
                            bullet(risk, color: AppTheme.warning)
                        }
                    }
                } else {
                    Text("This decision has not undergone LLM validation.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    private var claudeUsageCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Claude API Usage", systemImage: "chart.bar.fill")
                        .font(.headline)
                    Spacer()
                    if let usage = store.aiUsage {
                        Text(usage.callsToday > 0 ? "ACTIVE TODAY" : "TRACKING")
                            .font(.caption2.bold())
                            .foregroundStyle(usage.callsToday > 0 ? AppTheme.positive : AppTheme.secondaryText)
                    }
                }

                if let usage = store.aiUsage {
                    HStack {
                        MetricView(title: "Cost today (USD)", value: usage.costTodayUsd.apiCostText)
                        MetricView(title: "Cost total (USD)", value: usage.costTotalUsd.apiCostText)
                    }
                    HStack {
                        MetricView(title: "Calls today", value: usage.callsToday.groupedText)
                        MetricView(title: "Calls total", value: usage.callsTotal.groupedText)
                    }
                    Divider().overlay(AppTheme.border)
                    HStack {
                        MetricView(title: "Input tokens", value: usage.inputTokensTotal.groupedText)
                        MetricView(title: "Output tokens", value: usage.outputTokensTotal.groupedText)
                    }

                    if let model = usage.lastModel, !model.isEmpty {
                        Label(model, systemImage: "cpu")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    if let lastCall = usage.lastCallDate {
                        Label(
                            "Last call \(lastCall.formatted(date: .abbreviated, time: .shortened))",
                            systemImage: "clock"
                        )
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    }

                    Text("Estimated usage, not the remaining balance. Anthropic does not provide a credit balance API.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    ContentUnavailableView(
                        "Claude usage unavailable",
                        systemImage: "chart.bar",
                        description: Text("Usage data will appear after the backend responds.")
                    )
                    .frame(minHeight: 130)
                }
            }
        }
    }

    private func reasoningCard(_ decision: AIDecision) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Analysis Detail").font(.headline)

                if let cautions = decision.cautions, !cautions.isEmpty {
                    Text("Cautions").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.warning)
                    ForEach(Array(cautions.enumerated()), id: \.offset) { _, caution in
                        bullet(caution, color: AppTheme.warning)
                    }
                    Divider().overlay(AppTheme.border)
                }

                DisclosureGroup("Engine reasoning (\(decision.reasons.count))") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(decision.reasons.enumerated()), id: \.offset) { _, reason in
                            bullet(reason, color: AppTheme.accent)
                        }
                    }
                    .padding(.top, 12)
                }
                .tint(.white)

                if let note = decision.volumeProfileNote, !note.isEmpty {
                    Divider().overlay(AppTheme.border)
                    Label(note, systemImage: "chart.bar.xaxis")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    private func sourceNote(_ decision: AIDecision) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "clock.arrow.circlepath")
            Text("Cached backend decision · \(decision.date.formatted(date: .abbreviated, time: .shortened))")
        }
        .font(.caption)
        .foregroundStyle(AppTheme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func bullet(_ text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle().fill(color).frame(width: 5, height: 5).padding(.top, 6)
            Text(text).font(.caption).foregroundStyle(.white.opacity(0.78))
        }
    }

    private func directionColor(_ direction: AIDecisionDirection) -> Color {
        switch direction {
        case .buy: AppTheme.positive
        case .sell: AppTheme.negative
        case .hold: AppTheme.warning
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 60 { return AppTheme.positive }
        if score <= 40 { return AppTheme.negative }
        return AppTheme.warning
    }
}
