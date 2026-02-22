import Foundation
import Observation

@Observable
@MainActor
final class GlassesBridge {
    var isConnected: Bool = false
    var isSearching: Bool = false
    var lastPayloadSent: Date?
    var connectionStatus: String = "Not configured"
    var availableSessions: [SessionInfo] = []
    var lastSongMatch: String = ""
    var lastSongPostedAt: Date?
    var lastSafetyAlertAt: Date?
    var lastReceivedSafetyAlert: String = ""
    var isBackgroundKeepaliveEnabled: Bool {
        didSet {
            AppSettings.set(isBackgroundKeepaliveEnabled, forKey: Self.backgroundKeepaliveKey)
            updateBackgroundKeepaliveState()
        }
    }
    var isBackgroundKeepaliveActive: Bool {
        backgroundMonitor.isActive
    }

    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let backgroundMonitor = SafetyBackgroundMonitor()
    private let safetyAlertCooldownSeconds: TimeInterval = 30
    private let safetyPollIntervalNanoseconds: UInt64 = 2_000_000_000
    private var safetyPollTask: Task<Void, Never>?
    private var seenSafetyAlertKeys: Set<String> = []

    private(set) var ngrokBaseURL: String {
        didSet { AppSettings.set(ngrokBaseURL, forKey: Self.baseURLKey) }
    }

    private(set) var selectedSessionId: String {
        didSet { AppSettings.set(selectedSessionId, forKey: Self.sessionIdKey) }
    }

    private static let baseURLKey = AppSettings.ngrokBaseURLKey
    private static let sessionIdKey = AppSettings.selectedSessionIdKey
    private static let backgroundKeepaliveKey = AppSettings.backgroundSafetyKeepaliveEnabledKey

    init(session: URLSession = .shared) {
        self.session = session
        self.ngrokBaseURL = AppSettings.string(forKey: Self.baseURLKey) ?? ""
        self.selectedSessionId = AppSettings.string(forKey: Self.sessionIdKey) ?? ""
        self.isBackgroundKeepaliveEnabled = AppSettings.bool(forKey: Self.backgroundKeepaliveKey)
    }

    func updateBaseURL(_ value: String) {
        ngrokBaseURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if ngrokBaseURL.isEmpty {
            connectionStatus = "Base URL required"
            isConnected = false
        }
    }

    func selectSession(_ sessionId: String) {
        selectedSessionId = sessionId
        connectionStatus = sessionId.isEmpty ? "Session required" : "Session selected"
    }

    func startSearching() {
        isSearching = true
        connectionStatus = "Ready"
        Task {
            await fetchSessions()
        }
        startSafetyAlertPolling()
        updateBackgroundKeepaliveState()
    }

    func stopSearching() {
        isSearching = false
        isConnected = false
        safetyPollTask?.cancel()
        safetyPollTask = nil
        updateBackgroundKeepaliveState()
        connectionStatus = "Stopped"
    }

    func fetchSessions() async {
        guard let baseURL = normalizedBaseURL() else {
            connectionStatus = "Invalid base URL"
            isConnected = false
            return
        }

        connectionStatus = "Fetching sessions..."

        do {
            let response = try await performWithRetry {
                try await self.fetchSessions(baseURL: baseURL)
            }
            availableSessions = response.sessions

            if selectedSessionId.isEmpty, let first = response.sessions.first {
                selectedSessionId = first.sessionId
            }

            isConnected = !response.sessions.isEmpty
            connectionStatus = response.sessions.isEmpty ? "No active sessions" : "Sessions loaded"
        } catch {
            connectionStatus = "Session fetch failed"
            isConnected = false
        }
    }

    func post(hearing: HearingData, friends: [FriendProximity]) async {
        guard let baseURL = normalizedBaseURL() else {
            connectionStatus = "Invalid base URL"
            return
        }

        guard !selectedSessionId.isEmpty else {
            connectionStatus = "Select a session"
            return
        }

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let hearingPayload = HearingOverlayRequest(
            sessionId: selectedSessionId,
            type: "hearing_overlay",
            timestamp: timestamp,
            db: hearing.dbLevel,
            riskLevel: hearing.riskBand.apiValue,
            safeTimeLeftMin: Int(max(0, hearing.safeTimeLeftMinutes)),
            trend: hearing.trend.rawValue,
            suggestion: hearing.suggestion
        )

        let friendItems = friends.map {
            FriendItem(
                name: $0.displayName,
                distanceBand: $0.proximityBand.rawValue,
                hint: $0.directionHint.rawValue,
                confidence: $0.confidence
            )
        }

        let friendsPayload = FriendsOverlayRequest(
            sessionId: selectedSessionId,
            type: "friends_overlay",
            timestamp: timestamp,
            friends: friendItems
        )

        do {
            try await performWithRetry {
                try await self.postHearing(baseURL: baseURL, payload: hearingPayload)
            }
            try await performWithRetry {
                try await self.postFriends(baseURL: baseURL, payload: friendsPayload)
            }

            isConnected = true
            lastPayloadSent = .now
            connectionStatus = "Synced"
        } catch {
            isConnected = false
            connectionStatus = "Sync failed"
        }
    }

    private func normalizedBaseURL() -> URL? {
        let trimmed = ngrokBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private func fetchSessions(baseURL: URL) async throws -> SessionListResponse {
        let cacheBust = "\(Int(Date().timeIntervalSince1970 * 1000))"
        var comps = URLComponents(url: baseURL.appendingPathComponent("api/session/list"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "t", value: cacheBust)]
        guard let url = comps?.url else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.setValue("no-cache", forHTTPHeaderField: "Pragma")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if http.statusCode == 304 {
            return SessionListResponse(count: availableSessions.count, sessions: availableSessions)
        }

        try validate(response)
        return try decoder.decode(SessionListResponse.self, from: data)
    }

    private func postHearing(baseURL: URL, payload: HearingOverlayRequest) async throws {
        try await postJSON(path: "api/overlay/hearing", baseURL: baseURL, payload: payload)
    }

    private func postFriends(baseURL: URL, payload: FriendsOverlayRequest) async throws {
        try await postJSON(path: "api/overlay/friends", baseURL: baseURL, payload: payload)
    }

    func postSongIdentify(audioBase64: String, mimeType: String = "audio/wav") async {
        guard let baseURL = normalizedBaseURL() else {
            connectionStatus = "Invalid base URL"
            return
        }

        guard !selectedSessionId.isEmpty else {
            connectionStatus = "Select a session"
            return
        }

        do {
            let response: SongIdentifyResponse = try await performWithRetry {
                try await self.postSongIdentifyPlain(baseURL: baseURL, sessionId: self.selectedSessionId, audioBase64: audioBase64, mimeType: mimeType)
            }
            lastSongPostedAt = .now

            let title = response.song?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? response.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""
            let artist = response.song?.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? response.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""

            if !title.isEmpty || !artist.isEmpty {
                lastSongMatch = [title, artist].filter { !$0.isEmpty }.joined(separator: " — ")
            } else if let match = response.match, !match.isEmpty {
                lastSongMatch = match
            } else {
                lastSongMatch = "No confident match"
            }

            if response.shouldTriggerSafetyHelp {
                emitImmediateLocalSafetyAlert(keyword: response.detectedKeyword)
                await postFriendSafetyAlertIfNeeded(keyword: response.detectedKeyword)
            }
        } catch {
            connectionStatus = "Song identify failed"
        }
    }

    /// Even when using local ShazamKit for song matching, send audio to backend
    /// keyword detection so safety trigger words (e.g., banana) still work.
    func checkSafetyKeywords(audioBase64: String, mimeType: String = "audio/wav") async {
        guard let baseURL = normalizedBaseURL() else { return }
        guard !selectedSessionId.isEmpty else { return }

        do {
            let response: SongIdentifyResponse = try await performWithRetry {
                try await self.postSongIdentifyPlain(baseURL: baseURL, sessionId: self.selectedSessionId, audioBase64: audioBase64, mimeType: mimeType)
            }

            SafetyLog.debug("[SAFETY][KEYWORD] analyzed audio shouldTrigger=\(response.shouldTriggerSafetyHelp) keyword=\(response.detectedKeyword ?? "nil")")

            if response.shouldTriggerSafetyHelp {
                await postFriendSafetyAlertIfNeeded(keyword: response.detectedKeyword)
            }
        } catch {
            SafetyLog.error("[SAFETY][KEYWORD] analysis failed error=\(error.localizedDescription)")
        }
    }

    private func postJSON<T: Encodable>(path: String, baseURL: URL, payload: T) async throws {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(payload)

        let (_, response) = try await session.data(for: req)
        try validate(response)
    }

    private func postJSONWithResponse<T: Encodable, R: Decodable>(path: String, baseURL: URL, payload: T) async throws -> R {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: req)
        try validate(response)
        return try decoder.decode(R.self, from: data)
    }

    private func postSongIdentifyPlain(baseURL: URL, sessionId: String, audioBase64: String, mimeType: String) async throws -> SongIdentifyResponse {
        let url = baseURL.appendingPathComponent("api/song/identify")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 20
        req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        req.setValue(sessionId, forHTTPHeaderField: "x-session-id")
        req.setValue(mimeType, forHTTPHeaderField: "x-mime-type")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.httpBody = Data(audioBase64.utf8)

        let (data, response) = try await session.data(for: req)
        try validate(response)
        return try decoder.decode(SongIdentifyResponse.self, from: data)
    }

    private func postFriendSafetyAlertIfNeeded(keyword: String?) async {
        guard let baseURL = normalizedBaseURL() else {
            connectionStatus = "Invalid base URL"
            return
        }

        let targetSessions = targetSafetySessions()
        guard !targetSessions.isEmpty else {
            connectionStatus = "No sessions for safety alert"
            return
        }

        if let lastSent = lastSafetyAlertAt,
           Date().timeIntervalSince(lastSent) < safetyAlertCooldownSeconds {
            connectionStatus = "Safety alert throttled"
            return
        }

        do {
            for sessionId in targetSessions {
                let payload = FriendSafetyAlertRequest(
                    sessionId: sessionId,
                    message: "I need help",
                    severity: "urgent",
                    source: "keyword-detection",
                    keyword: keyword
                )

                try await performWithRetry {

                    try await self.postFriendSafety(baseURL: baseURL, payload: payload)
                }
            }

            lastSafetyAlertAt = .now
            connectionStatus = "Safety alert sent to \(targetSessions.count) sessions"
            emitImmediateLocalSafetyAlert(keyword: keyword)
        } catch {
            connectionStatus = "Safety alert failed"
        }
    }

    private func targetSafetySessions() -> [String] {
        let listed = availableSessions.map(\.sessionId).filter { !$0.isEmpty }
        if !listed.isEmpty {
            return Array(Set(listed)).sorted()
        }

        if !selectedSessionId.isEmpty {
            return [selectedSessionId]
        }

        SafetyLog.debug("[SAFETY][POLL] no sessions available for safety polling")
        return []
    }

    private func postFriendSafety(baseURL: URL, payload: FriendSafetyAlertRequest) async throws {
        try await postJSON(path: "api/friends/safety-alert", baseURL: baseURL, payload: payload)
    }

    private func emitImmediateLocalSafetyAlert(keyword: String?) {
        let trigger = keyword?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = "🚨 Safety trigger detected on this device"
            + ((trigger?.isEmpty == false) ? " (\(trigger!))" : "")

        lastReceivedSafetyAlert = body
        SafetyNotificationManager.shared.postSafetyAlert(body: body)
        SafetyLog.debug("[SAFETY][LOCAL] immediate local alert emitted body=\(body)")
    }

    private func updateBackgroundKeepaliveState() {
        if isSearching && isBackgroundKeepaliveEnabled {
            backgroundMonitor.start()
        } else {
            backgroundMonitor.stop()
        }
    }

    private func startSafetyAlertPolling() {
        SafetyLog.debug("[SAFETY][POLL] starting loop | searching=\(isSearching)")
        safetyPollTask?.cancel()
        safetyPollTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await self.pollSafetyAlertsOnce()
                try? await Task.sleep(nanoseconds: self.safetyPollIntervalNanoseconds)
            }
        }
    }

    private func pollSafetyAlertsOnce() async {
        guard isSearching,
              let baseURL = normalizedBaseURL() else {
            SafetyLog.debug("[SAFETY][POLL] skipped | searching=\(isSearching) baseURLValid=\(normalizedBaseURL() != nil)")
            return
        }

        let sessionIds = targetSafetySessions()
        guard !sessionIds.isEmpty else {
            SafetyLog.debug("[SAFETY][POLL] skipped | no target sessions")
            return
        }

        SafetyLog.debug("[SAFETY][POLL] tick | sessions=\(sessionIds.count)")

        for sessionId in sessionIds {
            do {
                let alerts = try await performWithRetry {
                    try await self.fetchSafetyAlertsStateAware(baseURL: baseURL, sessionId: sessionId)
                }
                SafetyLog.debug("[SAFETY][POLL] fetched | session=\(sessionId) alerts=\(alerts.count)")
                handleIncomingSafetyAlerts(alerts)
            } catch {
                SafetyLog.error("[SAFETY][POLL] error | session=\(sessionId) error=\(error.localizedDescription)")
            }
        }
    }

    private func fetchSafetyAlertsStateAware(baseURL: URL, sessionId: String) async throws -> [SafetyAlertEvent] {
        var stateAlerts: [SafetyAlertEvent] = []

        // New endpoint: boolean + optional alert
        do {
            var stateComponents = URLComponents(url: baseURL.appendingPathComponent("api/friends/has-safety-alert"), resolvingAgainstBaseURL: false)
            stateComponents?.queryItems = [
                URLQueryItem(name: "sessionId", value: sessionId),
                URLQueryItem(name: "t", value: "\(Int(Date().timeIntervalSince1970 * 1000))")
            ]

            guard let stateURL = stateComponents?.url else { throw URLError(.badURL) }
            var stateRequest = URLRequest(url: stateURL)
            stateRequest.httpMethod = "GET"
            stateRequest.cachePolicy = .reloadIgnoringLocalCacheData
            stateRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            stateRequest.setValue("no-cache", forHTTPHeaderField: "Pragma")

            let (stateData, stateResponse) = try await session.data(for: stateRequest)
            if let http = stateResponse as? HTTPURLResponse {
                SafetyLog.debug("[SAFETY][FETCH] has-safety-alert status=\(http.statusCode) bytes=\(stateData.count) session=\(sessionId)")
            }
            try validate(stateResponse)

            if let check = try? decoder.decode(SafetyAlertCheckResponse.self, from: stateData) {
                SafetyLog.debug("[SAFETY][DECODE] hasAlert=\(check.hasAlert) timestamp=\(check.timestamp ?? -1)")
                if check.hasAlert, let alert = check.alert {
                    stateAlerts = [alert]
                }
            } else if let raw = String(data: stateData, encoding: .utf8) {
                SafetyLog.debug("[SAFETY][RAW] has-safety-alert unparsed body=\(raw)")
            }
        } catch {
            SafetyLog.error("[SAFETY][FETCH] has-safety-alert failed error=\(error.localizedDescription)")
        }

        // Legacy endpoint still queried during rollout. Some backend builds may only
        // surface alerts there even when hasAlert is false.
        var legacyAlerts: [SafetyAlertEvent] = []
        do {
            legacyAlerts = try await fetchSafetyAlerts(baseURL: baseURL, sessionId: sessionId)
        } catch {
            SafetyLog.error("[SAFETY][FETCH] legacy safety-alerts failed error=\(error.localizedDescription)")
        }

        SafetyLog.debug("[SAFETY][MERGE] stateAlerts=\(stateAlerts.count) legacyAlerts=\(legacyAlerts.count)")

        // Merge + dedupe by stable key
        var mergedByKey: [String: SafetyAlertEvent] = [:]
        for alert in stateAlerts + legacyAlerts {
            mergedByKey[alert.dedupeKey] = alert
        }

        return Array(mergedByKey.values)
    }

    private func fetchSafetyAlerts(baseURL: URL, sessionId: String) async throws -> [SafetyAlertEvent] {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/friends/safety-alerts"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "sessionId", value: sessionId),
            URLQueryItem(name: "t", value: "\(Int(Date().timeIntervalSince1970 * 1000))")
        ]

        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            SafetyLog.debug("[SAFETY][FETCH] status=\(http.statusCode) bytes=\(data.count) session=\(sessionId)")
        }
        try validate(response)

        if let envelope = try? decoder.decode(SafetyAlertEnvelope.self, from: data) {
            SafetyLog.debug("[SAFETY][DECODE] envelope alerts=\(envelope.alerts.count) count=\(envelope.count ?? -1)")
            if envelope.alerts.isEmpty, let raw = String(data: data, encoding: .utf8) {
                SafetyLog.debug("[SAFETY][RAW] empty envelope body=\(raw)")
            }
            return envelope.alerts
        }

        if let list = try? decoder.decode([SafetyAlertEvent].self, from: data) {
            SafetyLog.debug("[SAFETY][DECODE] array alerts=\(list.count)")
            return list
        }

        if let single = try? decoder.decode(SafetyAlertEvent.self, from: data) {
            SafetyLog.debug("[SAFETY][DECODE] single alert")
            return [single]
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let alertDicts = json["alerts"] as? [[String: Any]] {
                let parsed = alertDicts.compactMap(parseSafetyAlertEvent)
                SafetyLog.debug("[SAFETY][DECODE] json.alerts parsed=\(parsed.count)")
                return parsed
            }

            if let alert = json["alert"] as? [String: Any],
               let parsed = parseSafetyAlertEvent(from: alert) {
                return [parsed]
            }

            if let nested = json["data"] as? [String: Any] {
                if let alertDicts = nested["alerts"] as? [[String: Any]] {
                    let parsed = alertDicts.compactMap(parseSafetyAlertEvent)
                    SafetyLog.debug("[SAFETY][DECODE] json.data.alerts parsed=\(parsed.count)")
                    return parsed
                }

                if let alert = nested["alert"] as? [String: Any],
                   let parsed = parseSafetyAlertEvent(from: alert) {
                    return [parsed]
                }
            }
        }

        return []
    }

    private func parseSafetyAlertEvent(from json: [String: Any]) -> SafetyAlertEvent? {
        let type = json["type"] as? String
        let sessionId = json["sessionId"] as? String
        let userId = json["userId"] as? String
        let triggerWord = json["triggerWord"] as? String
        let message = json["message"] as? String

        let timestamp: Int? = {
            if let value = json["timestamp"] as? Int { return value }
            if let value = json["timestamp"] as? Double { return Int(value) }
            if let value = json["timestamp"] as? String { return Int(value) }
            return nil
        }()

        return SafetyAlertEvent(
            type: type,
            sessionId: sessionId,
            userId: userId,
            triggerWord: triggerWord,
            timestamp: timestamp,
            message: message
        )
    }

    private func handleIncomingSafetyAlerts(_ alerts: [SafetyAlertEvent]) {
        guard !alerts.isEmpty else {
            SafetyLog.debug("[SAFETY][HANDLE] no alerts to handle")
            return
        }

        for alert in alerts {
            let key = alert.dedupeKey
            guard !seenSafetyAlertKeys.contains(key) else {
                SafetyLog.debug("[SAFETY][HANDLE] deduped key=\(key)")
                continue
            }

            seenSafetyAlertKeys.insert(key)
            if seenSafetyAlertKeys.count > 300 {
                seenSafetyAlertKeys.removeAll()
                seenSafetyAlertKeys.insert(key)
            }

            let message = alert.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = "🚨 \(alert.userId ?? "A friend") needs help"
                + ((alert.triggerWord?.isEmpty == false) ? " (triggered by: \(alert.triggerWord!))" : "")
            let body = (message?.isEmpty == false) ? message! : fallback

            SafetyLog.debug("[SAFETY][HANDLE] posting notification key=\(key) body=\(body)")
            lastReceivedSafetyAlert = body
            SafetyNotificationManager.shared.postSafetyAlert(body: body)
        }
    }

    /// Send song identification result from ShazamKit to server for display
    func postSongResult(title: String, artist: String) async {
        guard let baseURL = normalizedBaseURL() else {
            connectionStatus = "Invalid base URL"
            return
        }

        guard !selectedSessionId.isEmpty else {
            connectionStatus = "Select a session"
            return
        }

        let payload = SongResultRequest(sessionId: selectedSessionId, title: title, artist: artist, provider: "shazamkit")

        do {
            try await performWithRetry {
                try await self.postJSON(path: "api/song/result", baseURL: baseURL, payload: payload)
            }
            lastSongPostedAt = .now
            connectionStatus = "Song sent to glasses"
        } catch {
            connectionStatus = "Failed to send song"
        }
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func performWithRetry<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        let backoffNanos: [UInt64] = [500_000_000, 1_000_000_000, 2_000_000_000]
        var lastError: Error?

        for (index, delay) in backoffNanos.enumerated() {
            do {
                return try await operation()
            } catch {
                lastError = error
                if index < backoffNanos.count - 1 {
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }

        throw lastError ?? URLError(.cannotLoadFromNetwork)
    }
}
