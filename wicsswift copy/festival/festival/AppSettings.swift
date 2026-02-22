import Foundation

nonisolated enum AppMode: String, Codable, Sendable {
    case normal
    case event
    case invisible
}

nonisolated enum AppSettings {
    static let appGroupID = "group.com.wicshackathon.rightsnow"

    static let ngrokBaseURLKey = "ngrokBaseURL"
    static let selectedSessionIdKey = "selectedSessionId"
    static let backgroundSafetyKeepaliveEnabledKey = "backgroundSafetyKeepaliveEnabled"

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func string(forKey key: String) -> String? {
        sharedDefaults.string(forKey: key) ?? UserDefaults.standard.string(forKey: key)
    }

    static func set(_ value: String, forKey key: String) {
        // Write both for backward compatibility across builds/targets.
        sharedDefaults.set(value, forKey: key)
        UserDefaults.standard.set(value, forKey: key)
    }

    static func bool(forKey key: String) -> Bool {
        if sharedDefaults.object(forKey: key) != nil {
            return sharedDefaults.bool(forKey: key)
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func set(_ value: Bool, forKey key: String) {
        sharedDefaults.set(value, forKey: key)
        UserDefaults.standard.set(value, forKey: key)
    }
}
