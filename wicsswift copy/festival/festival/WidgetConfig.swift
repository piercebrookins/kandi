import Foundation

enum WidgetConfig {
    /// Keep this in sync with app + widget target entitlements.
    static let appGroupID = "group.com.wicshackathon.rightsnow"

    static let baseURLKey = "ngrokBaseURL"
    static let sessionIdKey = "selectedSessionId"

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var baseURLString: String {
        sharedDefaults.string(forKey: baseURLKey) ?? ""
    }

    static var selectedSessionId: String {
        sharedDefaults.string(forKey: sessionIdKey) ?? ""
    }
}
