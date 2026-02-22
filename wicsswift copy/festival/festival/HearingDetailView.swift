import SwiftUI

struct HearingDetailView: View {
    let engine: HearingEngine

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                liveGauge
                exposureSection
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Hearing Monitor")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var liveGauge: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 12)
                    .frame(width: 200, height: 200)

                Circle()
                    .trim(from: 0, to: min(1, engine.currentDB / 120))
                    .stroke(gaugeGradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.2), value: engine.currentDB)

                VStack(spacing: 4) {
                    Text(String(format: "%.0f", engine.currentDB))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("decibels")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 24) {
                StatPill(title: "Risk", value: engine.riskBand.rawValue, color: riskColor)
                StatPill(title: "Peak", value: "\(Int(engine.peakDB)) dB", color: .orange)
            }

            Text(engine.suggestion)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    private var exposureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("NIOSH Exposure", systemImage: "clock.badge.exclamationmark")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Time Remaining")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(safeTimeText)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(safeTimeColor)
                }
                Spacer()
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    private var riskColor: Color {
        switch engine.riskBand {
        case .safe: return .green
        case .caution: return .yellow
        case .warning: return .orange
        case .danger: return .red
        case .critical: return .purple
        }
    }

    private var gaugeGradient: AngularGradient {
        AngularGradient(
            colors: [.green, .yellow, .orange, .red, .purple],
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(360 * min(1, engine.currentDB / 120))
        )
    }

    private var safeTimeColor: Color {
        let m = engine.safeTimeLeftMinutes
        if m > 120 { return .green }
        if m > 30 { return .orange }
        return .red
    }

    private var safeTimeText: String {
        let m = engine.safeTimeLeftMinutes
        if m >= 60 {
            return "\(Int(m) / 60)h \(Int(m) % 60)m"
        }
        return "\(Int(m))m"
    }
}

struct StatPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .clipShape(.rect(cornerRadius: 10))
    }
}
