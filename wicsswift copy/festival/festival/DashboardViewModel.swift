import Foundation
import Observation
import ShazamKit

@Observable
@MainActor
final class DashboardViewModel {
    var hearingEngine = HearingEngine()
    var friendsEngine = FriendsEngine()
    var glassesBridge = GlassesBridge()

    var appMode: AppMode = .normal
    var isEventMode: Bool = false
    var isInvisibleMode: Bool = false
    var showHighRiskAlert: Bool = false
    var userName: String = "Me"

    // ShazamKit for local song recognition
    var shazamKitManager = ShazamKitManager()
    var useShazamKit = true  // Toggle between local ShazamKit and server recognition
    var handsfreeMode = false  // Auto-detect songs when music is playing

    private var sendTask: Task<Void, Never>?
    private var songIdentifyTask: Task<Void, Never>?
    private var keywordScanTask: Task<Void, Never>?
    private var isStarted: Bool = false

    // Handsfree detection threshold (dB level that indicates music is playing)
    private let musicDetectionThreshold: Double = 65.0  // 65 dB = music/concert level

    func startAll() {
        guard !isStarted else { return }
        isStarted = true

        userName = friendsEngine.currentDisplayName()
        hearingEngine.setEventMode(isEventMode)
        friendsEngine.setEventMode(isEventMode)
        hearingEngine.startMonitoring()
        friendsEngine.start(name: userName)
        glassesBridge.startSearching()
        startPostingLoop()
        startSongIdentifyLoop()
        startKeywordScanLoop()
    }

    func stopAll() {
        isStarted = false
        hearingEngine.stopMonitoring()
        friendsEngine.stop()
        glassesBridge.stopSearching()
        sendTask?.cancel()
        sendTask = nil
        songIdentifyTask?.cancel()
        songIdentifyTask = nil
        keywordScanTask?.cancel()
        keywordScanTask = nil
    }

    func refreshSessions() {
        Task {
            await glassesBridge.fetchSessions()
        }
    }

    func updateUserName(_ newName: String) {
        friendsEngine.setDisplayName(newName)
        userName = friendsEngine.currentDisplayName()
    }

    func setEventMode(_ enabled: Bool) {
        isEventMode = enabled
        if enabled {
            isInvisibleMode = false
        }
        appMode = enabled ? .event : (isInvisibleMode ? .invisible : .normal)
        hearingEngine.setEventMode(enabled)
        friendsEngine.setEventMode(enabled)
    }

    func toggleEventMode() {
        setEventMode(!isEventMode)
    }

    func setInvisibleMode(_ enabled: Bool) {
        isInvisibleMode = enabled
        if enabled {
            isEventMode = false
            hearingEngine.setEventMode(false)
            friendsEngine.setEventMode(false)
        }

        appMode = enabled ? .invisible : (isEventMode ? .event : .normal)

        if enabled {
            friendsEngine.stop()
        } else {
            friendsEngine.start(name: userName)
        }
    }

    func toggleInvisibleMode() {
        setInvisibleMode(!isInvisibleMode)
    }

    /// Manually trigger song identification
    func identifySongNow() async {
        guard !isInvisibleMode, hearingEngine.isMonitoring else { return }

        // Show user we're waiting for music to start
        glassesBridge.connectionStatus = "Listening for music..."

        // Wait 3 seconds before capturing to allow music to start
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        if useShazamKit {
            // Use local ShazamKit (faster, offline, no API keys!)
            await identifyWithShazamKit()
        } else {
            // Fall back to server-side recognition
            await identifyWithServer()
        }
    }

    private func identifyWithShazamKit() async {
        glassesBridge.connectionStatus = "Matching with ShazamKit..."

        // Get PCM samples from hearing engine
        guard let samples = hearingEngine.getLatestPCMSamples(seconds: 5) else {
            glassesBridge.connectionStatus = "No audio captured"
            return
        }

        // Identify using ShazamKit
        if let match = await shazamKitManager.identifyFromPCM(samples, sampleRate: hearingEngine.sampleRate) {
            glassesBridge.lastSongMatch = "\(match.title) — \(match.artist)"
            glassesBridge.connectionStatus = "Matched with ShazamKit!"

            // Send song info to server for display
            await glassesBridge.postSongResult(title: match.title, artist: match.artist)
        } else {
            glassesBridge.lastSongMatch = "No match found"
            glassesBridge.connectionStatus = "ShazamKit: No match"
        }

        // Always run backend keyword detection so safety triggers work in ShazamKit mode.
        if let audioBase64 = hearingEngine.latestAudioBase64Wav(seconds: 4) {
            await glassesBridge.checkSafetyKeywords(audioBase64: audioBase64, mimeType: "audio/wav")
        }
    }

    private func identifyWithServer() async {
        if let audioBase64 = hearingEngine.latestAudioBase64Wav(seconds: 4) {
            await glassesBridge.postSongIdentify(audioBase64: audioBase64, mimeType: "audio/wav")
        } else {
            glassesBridge.connectionStatus = "No audio captured"
        }
    }

    private func startPostingLoop() {
        sendTask?.cancel()
        sendTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let hearing = self.hearingEngine.hearingData
                let friends = self.friendsEngine.friends
                await self.glassesBridge.post(hearing: hearing, friends: friends)
                let intervalNanoseconds: UInt64 = self.isEventMode ? 700_000_000 : 1_000_000_000
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
            }
        }
    }

    private func startSongIdentifyLoop() {
        songIdentifyTask?.cancel()
        songIdentifyTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                if !self.isInvisibleMode, self.hearingEngine.isMonitoring {
                    if self.handsfreeMode {
                        // HANDS FREE: Auto-detect when music is playing (dB > threshold)
                        await self.autoDetectAndIdentify()
                    } else {
                        // MANUAL MODE: Just wait 10 seconds between periodic checks
                        try? await Task.sleep(nanoseconds: 10_000_000_000)

                        if self.useShazamKit {
                            await self.autoIdentifyWithShazamKit()
                        } else {
                            await self.autoIdentifyWithServer()
                        }
                    }
                }

                try? await Task.sleep(nanoseconds: 5_000_000_000)  // Check every 5 seconds
            }
        }
    }

    /// Handsfree: Wait for music (high dB), then identify
    private func autoDetectAndIdentify() async {
        let currentDB = hearingEngine.currentDB

        // Only identify when music is detected (high dB level)
        guard currentDB > musicDetectionThreshold else {
            glassesBridge.connectionStatus = handsfreeMode ? "Waiting for music..." : "Monitoring"
            return
        }

        // Music detected! Show status and identify
        glassesBridge.connectionStatus = "Music detected! Matching..."

        if useShazamKit {
            await autoIdentifyWithShazamKit()
        } else {
            await autoIdentifyWithServer()
        }
    }

    private func autoIdentifyWithShazamKit() async {
        guard let samples = hearingEngine.getLatestPCMSamples(seconds: 5) else { return }

        if let match = await shazamKitManager.identifyFromPCM(samples, sampleRate: hearingEngine.sampleRate) {
            glassesBridge.lastSongMatch = "\(match.title) — \(match.artist)"
            glassesBridge.connectionStatus = "♪ \(match.title)"
            await glassesBridge.postSongResult(title: match.title, artist: match.artist)
        } else {
            glassesBridge.connectionStatus = "Music detected - no match"
        }

        // Always run backend keyword detection so safety triggers work in ShazamKit mode.
        if let audioBase64 = hearingEngine.latestAudioBase64Wav(seconds: 4) {
            await glassesBridge.checkSafetyKeywords(audioBase64: audioBase64, mimeType: "audio/wav")
        }
    }

    private func autoIdentifyWithServer() async {
        if let audioBase64 = hearingEngine.latestAudioBase64Wav(seconds: 4) {
            await glassesBridge.postSongIdentify(audioBase64: audioBase64, mimeType: "audio/wav")
        }
    }

    /// Dedicated frequent keyword scan so safety words are caught quickly,
    /// independent of slower song-identification cadence.
    private func startKeywordScanLoop() {
        keywordScanTask?.cancel()
        keywordScanTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                if !self.isInvisibleMode,
                   self.hearingEngine.isMonitoring,
                   let audioBase64 = self.hearingEngine.latestAudioBase64Wav(seconds: 2) {
                    await self.glassesBridge.checkSafetyKeywords(audioBase64: audioBase64, mimeType: "audio/wav")
                }

                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }
}
