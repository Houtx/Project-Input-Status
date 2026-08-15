import Foundation

enum StatusAPIError: LocalizedError, Sendable {
    case badResponse(Int)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .badResponse(let code):
            return "服务器返回 HTTP \(code)"
        case .malformedResponse:
            return "状态数据格式无法识别"
        }
    }
}

struct StatusAPI: Sendable {
    func fetch() async throws -> StatusSnapshot {
        var request = URLRequest(
            url: InputStatusConstants.endpoint,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StatusAPIError.malformedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw StatusAPIError.badResponse(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(StatusSnapshot.self, from: data)
        } catch {
            throw StatusAPIError.malformedResponse
        }
    }
}

enum StatusStore {
    private static let key = "latest-status"

    static func load() -> CachedStatus? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CachedStatus.self, from: data)
    }

    static func save(_ cachedStatus: CachedStatus) throws {
        let data = try JSONEncoder().encode(cachedStatus)
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum StatusRefresher {
    static func refresh() async throws -> CachedStatus {
        do {
            let snapshot = try await StatusAPI().fetch()
            let result = CachedStatus(
                snapshot: snapshot,
                fetchedAt: Date(),
                lastAttemptAt: Date(),
                lastError: nil
            )
            try StatusStore.save(result)
            return result
        } catch {
            var failed = StatusStore.load() ?? CachedStatus()
            failed.lastAttemptAt = Date()
            failed.lastError = error.localizedDescription
            try? StatusStore.save(failed)
            throw error
        }
    }
}
