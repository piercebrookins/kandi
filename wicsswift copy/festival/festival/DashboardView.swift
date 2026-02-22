import SwiftUI

struct DashboardView: View {
    let viewModel: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                decibelCard
                riskTimerCard
                friendsSummaryCard
                bridgeStatusCard
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Festival Assistant")
                    .font(.title.bold())
                Text(modeLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            modeIndicator
        }
        .padding(.top, 8)
    }

    private var modeLabel: String {
        switch viewModel.appMode {
        case .normal: return "All systems active"
        case .event: return "Event Mode — enhanced monitoring"
        case .invisible: return "Invisible Mode — BLE hidden"
        }
    }

    @ViewBuilder
    private var modeIndicator: some View {
        let config: (String, Color) = switch viewModel.appMode {
        case .normal: ("antenna.radiowaves.left.and.right", .green)
        case .event: ("music.note.list", .orange)
        case .invisible: ("eye.slash.fill", .purple)
        }
        Image(systemName: config.0)
            .font(.title2)
            .foregroundStyle(config.1)
            .symbolEffect(.pulse, isActive: viewModel.hearingEngine.isMonitoring)
    }

    private var decibelCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.0f", viewModel.hearingEngine.currentDB))
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(riskColor)
                    .contentTransition(.numericText())
                Text("dB")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            DecibelBar(level: viewModel.hearingEngine.currentDB, peak: viewModel.hearingEngine.peakDB)
                .frame(height: 12)

            HStack {
                Label(viewModel.hearingEngine.riskBand.rawValue, systemImage: riskIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(riskColor)
                Spacer()
                Text("Peak: \(String(format: "%.0f", viewModel.hearingEngine.peakDB)) dB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    private var riskTimerCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "timer")
                .font(.title2)
                .foregroundStyle(safeTimeColor)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text("Safe Exposure Time")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(safeTimeText)
                    .font(.title3.weight(.semibold))
            }

            Spacer()

            if viewModel.hearingEngine.safeTimeLeftMinutes < 30 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .symbolEffect(.bounce, value: viewModel.hearingEngine.safeTimeLeftMinutes < 10)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    private var friendsSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Nearby Friends", systemImage: "person.2.fill")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.friendsEngine.friends.count)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.blue)
            }

            if viewModel.friendsEngine.friends.isEmpty {
                Text("No friends detected nearby")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.friendsEngine.friends.prefix(3)) { friend in
                    FriendRow(friend: friend)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    private var bridgeStatusCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "network")
                .font(.title2)
                .foregroundStyle(viewModel.glassesBridge.isConnected ? .green : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Mentra API Bridge")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(viewModel.glassesBridge.connectionStatus)
                    .font(.headline)
            }

            Spacer()

            if let lastSent = viewModel.glassesBridge.lastPayloadSent {
                Text(lastSent, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    private var riskColor: Color {
        switch viewModel.hearingEngine.riskBand {
        case .safe: return .green
        case .caution: return .yellow
        case .warning: return .orange
        case .danger: return .red
        case .critical: return .purple
        }
    }

    private var riskIcon: String {
        switch viewModel.hearingEngine.riskBand {
        case .safe: return "checkmark.shield.fill"
        case .caution: return "exclamationmark.shield.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "exclamationmark.octagon.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }

    private var safeTimeColor: Color {
        let minutes = viewModel.hearingEngine.safeTimeLeftMinutes
        if minutes > 120 { return .green }
        if minutes > 30 { return .orange }
        return .red
    }

    private var safeTimeText: String {
        let minutes = viewModel.hearingEngine.safeTimeLeftMinutes
        if minutes >= 60 {
            let hours = Int(minutes) / 60
            let mins = Int(minutes) % 60
            return "\(hours)h \(mins)m remaining"
        }
        return "\(Int(minutes))m remaining"
    }
}
