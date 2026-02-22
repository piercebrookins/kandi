import Foundation

struct WidgetSessionListResponse: Codable {
    let count: Int
    let sessions: [WidgetSessionInfo]
}

struct WidgetSessionInfo: Codable, Identifiable {
    var id: String { sessionId }
    let sessionId: String
    let hasHearing: Bool
    let friendCount: Int
    let updatedAt: Int?
}

struct WidgetSafetyAlertEnvelope: Codable {
    let alerts: [WidgetSafetyAlert]
    let count: Int?
}

struct WidgetSafetyAlert: Codable {
    let type: String?
    let message: String?
    let triggerWord: String?
    let timestamp: Int?
}

struct WidgetSnapshot {
    let fetchedAt: Date
    let isConfigured: Bool
    let sessionCount: Int
    let selectedSession: WidgetSessionInfo?
    let latestSafetyMessage: String?
    let hasSafetyAlert: Bool

    static var empty: WidgetSnapshot {
        WidgetSnapshot(
            fetchedAt: .now,
            isConfigured: false,
            sessionCount: 0,
            selectedSession: nil,
            latestSafetyMessage: nil,
            hasSafetyAlert: false
        )
    }
}
