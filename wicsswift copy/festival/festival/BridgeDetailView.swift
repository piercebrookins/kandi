import SwiftUI

struct BridgeDetailView: View {
    let viewModel: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                connectionCard
                sessionsCard
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Mentra Bridge")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var connectionCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "network")
                .font(.system(size: 42))
                .foregroundStyle(viewModel.glassesBridge.isConnected ? .green : .secondary)

            Text(viewModel.glassesBridge.connectionStatus)
                .font(.title3.weight(.semibold))

            if let lastSent = viewModel.glassesBridge.lastPayloadSent {
                Text("Last sent: \(lastSent.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.refreshSessions()
            } label: {
                Label("Refresh Sessions", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    private var sessionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Active Sessions", systemImage: "list.bullet.rectangle")
                .font(.headline)

            if viewModel.glassesBridge.availableSessions.isEmpty {
                Text("No sessions loaded yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.glassesBridge.availableSessions) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.sessionId)
                            .font(.caption.monospaced())
                        Text("Friends: \(session.friendCount) • Hearing: \(session.hasHearing ? "yes" : "no")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(.rect(cornerRadius: 8))
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}
