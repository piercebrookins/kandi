import Foundation

nonisolated enum RiskBand: String, Codable, Sendable {
    case safe = "SAFE"
    case caution = "CAUTION"
    case warning = "WARNING"
    case danger = "DANGER"
    case critical = "CRITICAL"

    var apiValue: String {
        switch self {
        case .safe: return "safe"
        case .caution, .warning: return "caution"
        case .danger, .critical: return "risk"
        }
    }
}

nonisolated enum Trend: String, Codable, Sendable {
    case rising
    case falling
    case steady
}

nonisolated struct HearingData: Codable, Sendable {
    let dbLevel: Double
    let riskBand: RiskBand
    let safeTimeLeftMinutes: Double
    let peakDB: Double
    let trend: Trend
    let suggestion: String
    let timestamp: Date
}
