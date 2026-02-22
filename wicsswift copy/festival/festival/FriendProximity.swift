import Foundation

nonisolated enum ProximityBand: String, Codable, Sendable {
    case immediate = "IMMEDIATE"
    case near = "NEAR"
    case area = "AREA"
    case weak = "WEAK"
}

nonisolated enum DirectionHint: String, Codable, Sendable {
    case left
    case right
    case ahead
    case behind
    case unknown
}

nonisolated struct FriendProximity: Codable, Sendable, Identifiable {
    let id: String
    let displayName: String
    let proximityBand: ProximityBand
    let rssi: Int
    let estimatedMeters: Double
    let directionHint: DirectionHint
    let confidence: Double
    let lastSeen: Date
}
