import Foundation

enum WidgetAPIError: Error {
    case invalidResponse
}

struct WidgetAPIClient {
    private let session: URLSession = .shared
    private let decoder = JSONDecoder()

    func fetchSnapshot() async throws -> WidgetSnapshot {
        let base = WidgetConfig.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: base), !base.isEmpty else {
            return .empty
        }

        let sessions = try await fetchSessions(baseURL: baseURL)
        let selectedId = WidgetConfig.selectedSessionId
        let selected = sessions.first(where: { $0.sessionId == selectedId }) ?? sessions.first

        let latestSafety = try? await fetchLatestSafetyMessage(baseURL: baseURL, sessionId: selected?.sessionId)
        let hasSafetyAlert = (latestSafety?.isEmpty == false)

        return WidgetSnapshot(
            fetchedAt: .now,
            isConfigured: true,
            sessionCount: sessions.count,
            selectedSession: selected,
            latestSafetyMessage: latestSafety ?? nil,
            hasSafetyAlert: hasSafetyAlert
        )
    }

    private func fetchSessions(baseURL: URL) async throws -> [WidgetSessionInfo] {
        let url = baseURL.appendingPathComponent("api/session/list")
        let (data, response) = try await session.data(from: url)
        try validate(response)
        let decoded = try decoder.decode(WidgetSessionListResponse.self, from: data)
        return decoded.sessions
    }

    private func fetchLatestSafetyMessage(baseURL: URL, sessionId: String?) async throws -> String? {
        guard let sessionId, !sessionId.isEmpty else { return nil }

        var components = URLComponents(url: baseURL.appendingPathComponent("api/friends/safety-alerts"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "sessionId", value: sessionId),
            URLQueryItem(name: "t", value: "\(Int(Date().timeIntervalSince1970 * 1000))")
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        let (data, response) = try await session.data(for: request)
        try validate(response)

        if let envelope = try? decoder.decode(WidgetSafetyAlertEnvelope.self, from: data),
           let message = envelope.alerts.last?.message,
           !message.isEmpty {
            return message
        }

        if let list = try? decoder.decode([WidgetSafetyAlert].self, from: data),
           let message = list.last?.message,
           !message.isEmpty {
            return message
        }

        if let single = try? decoder.decode(WidgetSafetyAlert.self, from: data),
           let message = single.message,
           !message.isEmpty {
            return message
        }

        return nil
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw WidgetAPIError.invalidResponse
        }
    }
}
