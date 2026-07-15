import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft: TradingSettings?
    @State private var editBaseline: TradingSettings?
    @State private var isEditingSettings = false
    @State private var remoteSettingsChanged = false
    @State private var pendingAction: ConfirmAction?
    @State private var isWorking = false

    private enum ConfirmAction: String, Identifiable {
        case enableKillSwitch, disableKillSwitch, saveSettings
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                backendCard
                emergencyCard
                if let binding = draftBinding { tradingCard(binding) }
                else { unavailableSettings }
                connectionsCard
                aboutCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .onAppear { syncFromStore() }
        .onChange(of: store.tradingSettings) { _, updated in
            guard let updated else { return }
            if isEditingSettings {
                remoteSettingsChanged = editBaseline != nil && updated != editBaseline
            } else {
                draft = updated
                editBaseline = updated
                remoteSettingsChanged = false
            }
        }
        .alert(item: $pendingAction) { action in
            switch action {
            case .enableKillSwitch:
                Alert(title: Text("Enable the kill switch?"), message: Text("The backend will activate heartbeat protection for \(store.symbol)."), primaryButton: .destructive(Text("Enable")) { setKillSwitch(true) }, secondaryButton: .cancel())
            case .disableKillSwitch:
                Alert(title: Text("Disable the kill switch?"), message: Text("Heartbeat protection will be stopped."), primaryButton: .destructive(Text("Disable")) { setKillSwitch(false) }, secondaryButton: .cancel())
            case .saveSettings:
                Alert(
                    title: Text("Save trading settings?"),
                    message: Text(remoteSettingsChanged ? "Settings changed on another client while you were editing. Saving will use the values from this iPhone." : "Risk and trading mode changes will be applied immediately by the backend."),
                    primaryButton: .default(Text("Save")) { saveSettings() },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private var draftBinding: Binding<TradingSettings>? {
        guard let initial = draft else { return nil }
        return Binding(get: { draft ?? initial }, set: { draft = $0 })
    }

    private var backendCard: some View {
        AppCard {
            HStack {
                Label("Backend API", systemImage: "server.rack")
                    .font(.headline)
                Spacer()
                StatusPill(
                    label: store.isConnected ? "Connected" : "Disconnected",
                    active: store.isConnected
                )
            }
        }
    }

    private var emergencyCard: some View {
        let enabled = store.killSwitch?.enabled == true
        return AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "bolt.shield.fill").foregroundStyle(enabled ? AppTheme.positive : AppTheme.warning)
                    Text("Futures Kill Switch").font(.headline)
                    Spacer()
                    StatusPill(label: enabled ? "Armed" : "Off", active: enabled)
                }
                Text(enabled ? "Heartbeat protection is active." : "Heartbeat protection is currently inactive.")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                Button(enabled ? "Disable Kill Switch" : "Enable Kill Switch") {
                    pendingAction = enabled ? .disableKillSwitch : .enableKillSwitch
                }
                .buttonStyle(.borderedProminent)
                .tint(enabled ? AppTheme.negative : AppTheme.warning)
                .disabled(!store.isConnected || isWorking)
            }
        }
    }

    private func tradingCard(_ settings: Binding<TradingSettings>) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Trading & Risk").font(.headline)
                    Spacer()
                    Text(settings.wrappedValue.paperTradingOnly ? "PAPER" : "LIVE")
                        .font(.caption.bold())
                        .foregroundStyle(settings.wrappedValue.paperTradingOnly ? AppTheme.warning : AppTheme.negative)
                }

                if remoteSettingsChanged {
                    Label("New changes were received from another web or app client.", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.warning)
                }

                Group {
                    Text("Trading Mode")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                    Toggle("Paper trading only", isOn: settings.paperTradingOnly)
                    Toggle("Auto trading enabled", isOn: settings.autoTradingEnabled)

                    Divider().overlay(AppTheme.border)
                    Text("Risk Configuration")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)

                    riskSlider("Risk per trade", value: settings.riskPerTradePercent, range: 0.1...20)
                    riskSlider("Max daily loss", value: settings.maxDailyLossPercent, range: 1...100)
                    riskSlider("Max exposure", value: settings.maxExposurePercent, range: 1...500)

                    decimalStepper(
                        "Target margin per position",
                        value: settings.targetMarginUsdt,
                        range: 1...1_000,
                        step: 0.5,
                        suffix: " USDT",
                        hint: settings.wrappedValue.autoSizingMode == 1
                            ? "Notional target = margin × target leverage."
                            : "Margin reference for the minimum order calculated by the risk engine."
                    )

                    settingPicker(
                        "Auto position sizing",
                        selection: settings.autoSizingMode,
                        options: [
                            (0, "Risk Engine"),
                            (1, "Margin × Leverage")
                        ],
                        hint: settings.wrappedValue.autoSizingMode == 1
                            ? "Uses the notional target while remaining limited by the exposure risk gate."
                            : "Position size is calculated from risk per trade."
                    )

                    settingPicker(
                        "Target leverage",
                        selection: settings.targetLeverage,
                        options: [5, 10, 15, 20].map { ($0, "\($0)x") },
                        hint: "Used in Margin × Leverage mode. The system cap is 20x."
                    )

                    directSlider(
                        "Min confidence open order",
                        value: settings.confidenceThreshold,
                        range: 1...100,
                        step: 1,
                        suffix: "%",
                        hint: "A new order opens only when AI confidence reaches this value."
                    )

                    integerStepper(
                        "Position check interval",
                        value: settings.positionCheckIntervalMinutes,
                        range: 5...120,
                        suffix: " min",
                        hint: "Validates the direction of open positions. Recommended: 10–15 minutes."
                    )

                    trailingStopPicker(settings.trailingStopDistanceR)
                }
                .disabled(!isEditingSettings)

                if isEditingSettings {
                    HStack {
                        Button("Cancel", role: .cancel) { cancelEditing() }
                            .buttonStyle(.bordered)
                        Button("Save Settings") { pendingAction = .saveSettings }
                            .buttonStyle(.borderedProminent)
                            .disabled(isWorking)
                    }
                } else {
                    Button("Edit Trading Settings") { beginEditing() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func riskSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        let percentage = Binding<Double>(
            get: { value.wrappedValue * 100 },
            set: { value.wrappedValue = $0 / 100 }
        )
        return VStack(spacing: 7) {
            HStack {
                Text(label).foregroundStyle(AppTheme.secondaryText)
                Spacer()
                Text(percentage.wrappedValue.percentText).font(.subheadline.bold())
            }
            Slider(value: percentage, in: range, step: 0.1)
        }
    }

    private func directSlider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        suffix: String,
        hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label).foregroundStyle(AppTheme.secondaryText)
                Spacer()
                Text("\(value.wrappedValue.formatted(.number.precision(.fractionLength(0))))\(suffix)")
                    .font(.subheadline.bold())
            }
            Slider(value: value, in: range, step: step)
            Text(hint).font(.caption2).foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func decimalStepper(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        suffix: String,
        hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Stepper(value: value, in: range, step: step) {
                HStack {
                    Text(label).foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                    Text("\(value.wrappedValue.formatted(.number.precision(.fractionLength(1))))\(suffix)")
                        .font(.subheadline.bold())
                }
            }
            Text(hint).font(.caption2).foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func integerStepper(
        _ label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        suffix: String,
        hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Stepper(value: value, in: range) {
                HStack {
                    Text(label).foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                    Text("\(value.wrappedValue)\(suffix)").font(.subheadline.bold())
                }
            }
            Text(hint).font(.caption2).foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func settingPicker(
        _ label: String,
        selection: Binding<Int>,
        options: [(Int, String)],
        hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Picker(label, selection: selection) {
                ForEach(options.indices, id: \.self) { index in
                    Text(options[index].1).tag(options[index].0)
                }
            }
            .pickerStyle(.menu)
            Text(hint).font(.caption2).foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func trailingStopPicker(_ selection: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Picker("Trailing stop distance", selection: selection) {
                Text("Aggressive — 0.50R").tag(0.50)
                Text("Balanced — 0.75R").tag(0.75)
                Text("Conservative — 1.00R").tag(1.00)
                Text("Loose — 1.25R").tag(1.25)
            }
            .pickerStyle(.menu)
            Text("Trailing stop-loss distance after profit exceeds +1R.")
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var unavailableSettings: some View {
        AppCard {
            ContentUnavailableView("Trading settings unavailable", systemImage: "slider.horizontal.3", description: Text("Connect to the backend to change risk settings."))
                .frame(minHeight: 150)
        }
    }

    private var connectionsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Service connections").font(.headline)
                connectionRow("Binance", connected: store.tradingSettings?.hasApiKey == true && store.tradingSettings?.hasApiSecret == true, target: "binance")
                Divider().overlay(AppTheme.border)
                connectionRow("Anthropic", connected: store.tradingSettings?.hasAnthropicKey == true, target: "anthropic")
            }
        }
    }

    private func connectionRow(_ title: String, connected: Bool, target: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold())
                Text(connected ? "Credentials configured" : "Credentials missing")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            Button("Test") { Task { _ = await store.testConnection(target) } }
                .buttonStyle(.bordered)
                .disabled(!connected || !store.isConnected)
        }
    }

    private var aboutCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Seqra Quant").font(.headline)
                Text("Native SwiftUI client · BTCUSDT · REST polling every 8 seconds")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private func syncFromStore() {
        if !isEditingSettings, let settings = store.tradingSettings {
            draft = settings
            editBaseline = settings
            remoteSettingsChanged = false
        }
    }

    private func beginEditing() {
        guard let latest = store.tradingSettings else { return }
        draft = latest
        editBaseline = latest
        remoteSettingsChanged = false
        isEditingSettings = true
    }

    private func cancelEditing() {
        isEditingSettings = false
        remoteSettingsChanged = false
        syncFromStore()
    }

    private func setKillSwitch(_ enabled: Bool) {
        isWorking = true
        Task { _ = await store.setKillSwitch(enabled: enabled); isWorking = false }
    }

    private func saveSettings() {
        guard let draft else { return }
        isWorking = true
        Task {
            let saved = await store.saveSettings(draft)
            if saved {
                isEditingSettings = false
                remoteSettingsChanged = false
                syncFromStore()
            }
            isWorking = false
        }
    }
}

private extension Binding where Value == TradingSettings {
    var paperTradingOnly: Binding<Bool> { .init(get: { wrappedValue.paperTradingOnly }, set: { wrappedValue.paperTradingOnly = $0 }) }
    var autoTradingEnabled: Binding<Bool> { .init(get: { wrappedValue.autoTradingEnabled }, set: { wrappedValue.autoTradingEnabled = $0 }) }
    var riskPerTradePercent: Binding<Double> { .init(get: { wrappedValue.riskPerTradePercent }, set: { wrappedValue.riskPerTradePercent = $0 }) }
    var maxDailyLossPercent: Binding<Double> { .init(get: { wrappedValue.maxDailyLossPercent }, set: { wrappedValue.maxDailyLossPercent = $0 }) }
    var maxExposurePercent: Binding<Double> { .init(get: { wrappedValue.maxExposurePercent }, set: { wrappedValue.maxExposurePercent = $0 }) }
    var defaultLeverage: Binding<Int> { .init(get: { wrappedValue.defaultLeverage }, set: { wrappedValue.defaultLeverage = $0 }) }
    var targetMarginUsdt: Binding<Double> { .init(get: { wrappedValue.targetMarginUsdt }, set: { wrappedValue.targetMarginUsdt = $0 }) }
    var autoSizingMode: Binding<Int> { .init(get: { wrappedValue.autoSizingMode }, set: { wrappedValue.autoSizingMode = $0 }) }
    var targetLeverage: Binding<Int> { .init(get: { wrappedValue.targetLeverage }, set: { wrappedValue.targetLeverage = $0 }) }
    var confidenceThreshold: Binding<Double> { .init(get: { wrappedValue.confidenceThreshold }, set: { wrappedValue.confidenceThreshold = $0 }) }
    var positionCheckIntervalMinutes: Binding<Int> { .init(get: { wrappedValue.positionCheckIntervalMinutes }, set: { wrappedValue.positionCheckIntervalMinutes = $0 }) }
    var trailingStopDistanceR: Binding<Double> { .init(get: { wrappedValue.trailingStopDistanceR }, set: { wrappedValue.trailingStopDistanceR = $0 }) }
}
