import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.035, green: 0.047, blue: 0.075)
    static let surface = Color(red: 0.070, green: 0.086, blue: 0.125)
    static let surfaceRaised = Color(red: 0.094, green: 0.114, blue: 0.157)
    static let border = Color.white.opacity(0.08)
    static let positive = Color(red: 0.18, green: 0.84, blue: 0.60)
    static let negative = Color(red: 1.00, green: 0.34, blue: 0.42)
    static let warning = Color(red: 1.00, green: 0.72, blue: 0.25)
    static let accent = Color(red: 0.38, green: 0.55, blue: 1.00)
    static let secondaryText = Color.white.opacity(0.58)
}

struct AppCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.border))
    }
}

struct MetricView: View {
    let title: String
    let value: String
    var tint: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusPill: View {
    let label: String
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(active ? AppTheme.positive : AppTheme.negative).frame(width: 7, height: 7)
            Text(label).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((active ? AppTheme.positive : AppTheme.negative).opacity(0.12))
        .clipShape(Capsule())
    }
}

extension Double {
    var currencyText: String {
        AppNumberFormatter.decimal.string(from: NSNumber(value: self)) ?? String(format: "%.2f", self)
    }

    var priceText: String {
        AppNumberFormatter.decimal.string(from: NSNumber(value: self)) ?? String(format: "%.2f", self)
    }

    var signedCurrencyText: String {
        let sign = self > 0 ? "+" : ""
        return sign + currencyText
    }

    /// For values the backend already expresses in percent (55 → "55%", 47.368 → "47.37%").
    var percentText: String {
        let text = AppNumberFormatter.percent.string(from: NSNumber(value: self)) ?? String(format: "%.2f", self)
        return text + "%"
    }

    /// For values the backend stores as a 0–1 ratio (0.15 → "15%", -0.0989 → "-9.9%").
    var ratioPercentText: String { (self * 100).percentText }

    /// Ratio rendered as a percentage with extra precision, for very small rates such as funding.
    func ratioPercentText(fractionDigits: Int) -> String {
        let text = (self * 100).formatted(
            .number
                .precision(.fractionLength(0...fractionDigits))
                .locale(Locale(identifier: "en_US"))
        )
        return text + "%"
    }

    var apiCostText: String {
        AppNumberFormatter.apiCost.string(from: NSNumber(value: self)) ?? String(format: "%.6f", self)
    }
}

extension Int {
    var groupedText: String {
        AppNumberFormatter.integer.string(from: NSNumber(value: self)) ?? String(self)
    }
}

private enum AppNumberFormatter {
    static let decimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    /// Whole percentages stay whole ("15%"); fractional ones keep up to two digits ("47.37%").
    static let percent: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static let apiCost: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = 4
        formatter.maximumFractionDigits = 6
        return formatter
    }()

    static let integer: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
