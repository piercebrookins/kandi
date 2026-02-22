import Foundation

nonisolated struct SessionListResponse: Codable, Sendable {
    let count: Int
    let sessions: [SessionInfo]
}

nonisolated struct SessionInfo: Codable, Sendable, Identifiable, Hashable {
    var id: String { sessionId }
    let sessionId: String
    let hasHearing: Bool
    let friendCount: Int
    let updatedAt: Int?
}

nonisolated struct HearingOverlayRequest: Codable, Sendable {
    let sessionId: String
    let type: String
    let timestamp: Int
    let db: Double
    let riskLevel: String
    let safeTimeLeftMin: Int
    let trend: String
    let suggestion: String
}

nonisolated struct FriendItem: Codable, Sendable {
    let name: String
    let distanceBand: String
    let hint: String
    let confidence: Double
}

nonisolated struct FriendsOverlayRequest: Codable, Sendable {
    let sessionId: String
    let type: String
    let timestamp: Int
    let friends: [FriendItem]
}

nonisolated struct SongIdentifyRequest: Codable, Sendable {
    let sessionId: String
    let audioBase64: String
    let mimeType: String
}

nonisolated struct SongIdentifyResponse: Codable, Sendable {
    let success: Bool?
    let ok: Bool?
    let match: String?
    let artist: String?
    let title: String?
    let song: SongMatch?

    // Optional safety/keyword metadata from API
    let keywordDetected: Bool?
    let detectedKeyword: String?
    let shouldBroadcastHelp: Bool?
    let emergency: Bool?
    let intent: String?
    let action: String?

    var shouldTriggerSafetyHelp: Bool {
        if shouldBroadcastHelp == true || keywordDetected == true || emergency == true {
            return true
        }

        let normalizedIntent = intent?.lowercased() ?? ""
        let normalizedAction = action?.lowercased() ?? ""
        return normalizedIntent.contains("help") || normalizedIntent.contains("sos") ||
            normalizedAction.contains("help") || normalizedAction.contains("sos")
    }

    nonisolated struct SongMatch: Codable, Sendable {
        let title: String?
        let artist: String?
        let provider: String?
        let confidence: Double?
    }
}

/// For sending pre-identified song results from ShazamKit
nonisolated struct SongResultRequest: Codable, Sendable {
    let sessionId: String
    let type: String = "song_result"
    let timestamp: Int
    let title: String
    let artist: String
    let provider: String  // "shazamkit"

    init(sessionId: String, title: String, artist: String, provider: String = "shazamkit") {
        self.sessionId = sessionId
        self.timestamp = Int(Date().timeIntervalSince1970)
        self.title = title
        self.artist = artist
        self.provider = provider
    }
}

nonisolated struct FriendSafetyAlertRequest: Codable, Sendable {
    let sessionId: String
    let type: String = "friend_safety_alert"
    let timestamp: Int
    let message: String
    let severity: String
    let source: String
    let keyword: String?

    init(sessionId: String, message: String = "I need help", severity: String = "urgent", source: String = "keyword-detection", keyword: String? = nil) {
        self.sessionId = sessionId
        self.timestamp = Int(Date().timeIntervalSince1970 * 1000)
        self.message = message
        self.severity = severity
        self.source = source
        self.keyword = keyword
    }
}

nonisolated struct SafetyAlertEnvelope: Codable, Sendable {
    let alerts: [SafetyAlertEvent]
    let count: Int?
}

/// New lightweight endpoint response: /api/friends/has-safety-alert
nonisolated struct SafetyAlertCheckResponse: Codable, Sendable {
    let hasAlert: Bool
    let alert: SafetyAlertEvent?
    let timestamp: Int?
}

nonisolated struct SafetyAlertEvent: Codable, Sendable, Hashable {
    let type: String?
    let sessionId: String?
    let userId: String?
    let triggerWord: String?
    let timestamp: Int?
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case sessionId
        case userId
        case triggerWord
        case timestamp
        case message
    }

    init(type: String?, sessionId: String?, userId: String?, triggerWord: String?, timestamp: Int?, message: String?) {
        self.type = type
        self.sessionId = sessionId
        self.userId = userId
        self.triggerWord = triggerWord
        self.timestamp = timestamp
        self.message = message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        triggerWord = try container.decodeIfPresent(String.self, forKey: .triggerWord)
        message = try container.decodeIfPresent(String.self, forKey: .message)

        if let intValue = try container.decodeIfPresent(Int.self, forKey: .timestamp) {
            timestamp = intValue
        } else if let stringValue = try container.decodeIfPresent(String.self, forKey: .timestamp),
                  let parsed = Int(stringValue) {
            timestamp = parsed
        } else {
            timestamp = nil
        }
    }

    var dedupeKey: String {
        "\(sessionId ?? "")|\(userId ?? "")|\(triggerWord ?? "")|\(timestamp ?? 0)"
    }
}
