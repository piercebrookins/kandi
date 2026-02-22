import Foundation
import os

enum SafetyLog {
    private static let logger = Logger(subsystem: "com.wicshackathon.rightsnow", category: "safety")

    static func debug(_ message: String) {
        // Use notice for Console visibility (debug level often hidden by default)
        logger.notice("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
