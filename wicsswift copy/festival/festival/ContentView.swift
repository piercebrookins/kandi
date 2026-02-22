import SwiftUI

struct ContentView: View {
    @State private var viewModel = DashboardViewModel()
    @State private var selectedTab: Int = 0
    @State private var inAppSafetyMessage: String = ""
    @State private var showInAppSafetyBanner: Bool = false
    @State private var hideSafetyBannerTask: Task<Void, Never>?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView(viewModel: viewModel)
            }
            .tabItem {
                Label("Dashboard", systemImage: "gauge.with.dots.needle.33percent")
            }
            .tag(0)

            NavigationStack {
                HearingDetailView(engine: viewModel.hearingEngine)
            }
            .tabItem {
                Label("Hearing", systemImage: "ear.fill")
            }
            .tag(1)

            NavigationStack {
                FriendsListView(engine: viewModel.friendsEngine)
            }
            .tabItem {
                Label("Friends", systemImage: "person.2.fill")
            }
            .tag(2)

            NavigationStack {
                BridgeDetailView(viewModel: viewModel)
            }
            .tabItem {
                Label("Bridge", systemImage: "network")
            }
            .tag(3)

            NavigationStack {
                SettingsView(viewModel: viewModel)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(4)
        }
        .task {
            viewModel.startAll()
        }
        .sensoryFeedback(.warning, trigger: viewModel.hearingEngine.riskBand == .danger || viewModel.hearingEngine.riskBand == .critical)
        .alert("High Noise Alert", isPresented: $viewModel.showHighRiskAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Sound levels are dangerously high (\(Int(viewModel.hearingEngine.currentDB)) dB). Consider moving to a quieter area or using ear protection.")
        }
        .onChange(of: viewModel.hearingEngine.riskBand) { _, newValue in
            if newValue == .danger || newValue == .critical {
                viewModel.showHighRiskAlert = true
            }
        }
        .onChange(of: viewModel.glassesBridge.lastReceivedSafetyAlert) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            SafetyLog.debug("[SAFETY][UI] in-app banner show message=\(trimmed)")
            inAppSafetyMessage = trimmed
            showInAppSafetyBanner = true

            hideSafetyBannerTask?.cancel()
            hideSafetyBannerTask = Task {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showInAppSafetyBanner = false
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if showInAppSafetyBanner {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Safety Ping")
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.9))
                        Text(inAppSafetyMessage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                    }

                    Spacer()

                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showInAppSafetyBanner = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.red.gradient)
                .clipShape(.rect(cornerRadius: 14))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}
