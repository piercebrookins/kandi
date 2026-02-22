import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: DashboardViewModel
    @State private var baseURLInput: String = ""
    @State private var displayNameInput: String = ""
    @State private var backgroundKeepaliveEnabled: Bool = false

    var body: some View {
        Form {
            Section("Mode") {
                Toggle(isOn: $viewModel.isEventMode) {
                    Label("Event Mode", systemImage: "music.note.list")
                }
                .onChange(of: viewModel.isEventMode) { _, newValue in
                    viewModel.setEventMode(newValue)
                }

                Toggle(isOn: $viewModel.isInvisibleMode) {
                    Label("Invisible Mode", systemImage: "eye.slash.fill")
                }
                .onChange(of: viewModel.isInvisibleMode) { _, newValue in
                    viewModel.setInvisibleMode(newValue)
                }
            }

            Section("Song Recognition") {
                Toggle(isOn: $viewModel.useShazamKit) {
                    Label("Use ShazamKit (Local)", systemImage: "shazam.logo")
                }

                Toggle(isOn: $viewModel.handsfreeMode) {
                    Label("Handsfree Auto-Detect", systemImage: "ear.badge.waveform")
                }

                Text(viewModel.handsfreeMode
                     ? "Handsfree: Automatically identifies songs when music is detected (>65 dB). No button needed!"
                     : (viewModel.useShazamKit
                        ? "ShazamKit: Tap button to identify songs locally on your device."
                        : "Server: Tap button to send audio to server for identification."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Identity") {
                TextField("Display name", text: $displayNameInput)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onSubmit {
                        viewModel.updateUserName(displayNameInput)
                    }

                Button("Save Display Name") {
                    viewModel.updateUserName(displayNameInput)
                }
                .buttonStyle(.bordered)

                Text("Use different names on each phone so friend beacons are easy to identify.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle(isOn: $backgroundKeepaliveEnabled) {
                    Label("Background Safety Keepalive", systemImage: "location.fill")
                }
                .onChange(of: backgroundKeepaliveEnabled) { _, newValue in
                    viewModel.glassesBridge.isBackgroundKeepaliveEnabled = newValue
                }

                Text("Uses Always Location in background to help safety polling stay active longer. iOS may still pause the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    Task {
                        await SafetyNotificationManager.shared.requestAuthorizationIfNeeded()
                        SafetyNotificationManager.shared.postSafetyAlert(
                            title: "🚨 Test Safety Alert",
                            body: "This is a time-sensitive test notification from Settings."
                        )
                    }
                } label: {
                    Label("Send Test Safety Notification", systemImage: "bell.badge.fill")
                }
                .buttonStyle(.borderedProminent)

                Text("Use this to verify alerts, banner delivery, and Time Sensitive notification settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Mentra API") {
                TextField("https://your-ngrok-url.ngrok-free.app", text: $baseURLInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                HStack {
                    Button("Save URL") {
                        viewModel.glassesBridge.updateBaseURL(baseURLInput)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Fetch Sessions") {
                        viewModel.refreshSessions()
                    }
                    .buttonStyle(.bordered)
                }

                if !viewModel.glassesBridge.availableSessions.isEmpty {
                    Picker("Session", selection: selectedSessionBinding) {
                        Text("Select session").tag("")
                        ForEach(viewModel.glassesBridge.availableSessions) { session in
                            Text(session.sessionId).tag(session.sessionId)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }

            Section("Friend Simulator") {
                HStack {
                    Button {
                        viewModel.friendsEngine.spawnFakeFriend()
                    } label: {
                        Label("Spawn Fake Friend", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        viewModel.friendsEngine.clearFakeFriends()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }

                if viewModel.friendsEngine.fakeFriends.isEmpty {
                    Text("No fake friends yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.friendsEngine.fakeFriends) { friend in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(friend.displayName)
                                Text("\(friend.proximityBand.rawValue) • RSSI \(friend.rssi)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                viewModel.friendsEngine.deleteFakeFriend(id: friend.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section("Hearing") {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(viewModel.hearingEngine.isMonitoring ? "Active" : "Inactive")
                        .foregroundStyle(viewModel.hearingEngine.isMonitoring ? .green : .secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Calibration Offset")
                        Spacer()
                        Text(String(format: "%.0f dB", viewModel.hearingEngine.calibrationOffset))
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: calibrationBinding, in: 70...120, step: 1)

                    Text("Tip: Compare with a trusted meter app and adjust until readings match in the same environment.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    viewModel.hearingEngine.resetCalibration()
                } label: {
                    Label("Reset Calibration", systemImage: "dial.min")
                }

                Button {
                    viewModel.hearingEngine.resetExposure()
                } label: {
                    Label("Reset Exposure Counter", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            baseURLInput = viewModel.glassesBridge.ngrokBaseURL
            displayNameInput = viewModel.userName
            backgroundKeepaliveEnabled = viewModel.glassesBridge.isBackgroundKeepaliveEnabled
        }
    }

    private var calibrationBinding: Binding<Double> {
        Binding {
            viewModel.hearingEngine.calibrationOffset
        } set: { newValue in
            viewModel.hearingEngine.calibrationOffset = newValue
        }
    }

    private var selectedSessionBinding: Binding<String> {
        Binding {
            viewModel.glassesBridge.selectedSessionId
        } set: { newValue in
            viewModel.glassesBridge.selectSession(newValue)
        }
    }
}
