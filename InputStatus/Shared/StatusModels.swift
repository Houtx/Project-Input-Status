import Foundation

enum InputStatusConstants {
    static let endpoint = URL(string: "https://status.input.im/api/status")!
    static let statusPage = URL(string: "https://status.input.im/")!
    static let refreshURL = URL(string: "inputstatus://refresh")!
    static let widgetKind = "InputStatusWidget"
    static let historyLength = 60
    static let refreshInterval: TimeInterval = 120
}

struct ProbeResult: Codable, Equatable, Sendable {
    let timestamp: Date
    let isOK: Bool
    let latencyMS: Int?
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case timestamp = "ts"
        case isOK = "ok"
        case latencyMS = "latency_ms"
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let timestamp = try container.decode(Double.self, forKey: .timestamp)
        self.timestamp = Date(timeIntervalSince1970: timestamp)
        isOK = try container.decode(Bool.self, forKey: .isOK)
        latencyMS = try container.decodeIfPresent(Int.self, forKey: .latencyMS)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    init(timestamp: Date, isOK: Bool, latencyMS: Int? = nil, error: String? = nil) {
        self.timestamp = timestamp
        self.isOK = isOK
        self.latencyMS = latencyMS
        self.error = error
    }
}

struct StatusService: Codable, Equatable, Sendable, Identifiable {
    let model: String
    let uptimePercent: Double
    let last: ProbeResult?
    let history: [ProbeResult]

    var id: String { model }
    var isOnline: Bool { last?.isOK == true }

    private enum CodingKeys: String, CodingKey {
        case model
        case uptimePercent = "uptime_pct"
        case last
        case history
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(String.self, forKey: .model)
        uptimePercent = try container.decode(Double.self, forKey: .uptimePercent)
        last = try container.decodeIfPresent(ProbeResult.self, forKey: .last)
        history = try container.decodeIfPresent([ProbeResult].self, forKey: .history) ?? []
    }

    init(model: String, uptimePercent: Double, last: ProbeResult?, history: [ProbeResult]) {
        self.model = model
        self.uptimePercent = uptimePercent
        self.last = last
        self.history = history
    }
}

struct StatusSnapshot: Codable, Equatable, Sendable {
    let allOK: Bool
    let generatedAt: Date
    let services: [StatusService]

    var onlineCount: Int { services.filter(\.isOnline).count }
    var failingCount: Int { services.count - onlineCount }
    var averageUptime: Double {
        guard !services.isEmpty else { return 100 }
        return services.map(\.uptimePercent).reduce(0, +) / Double(services.count)
    }

    private enum CodingKeys: String, CodingKey {
        case allOK = "all_ok"
        case generatedAt = "generated_at"
        case services
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        allOK = try container.decode(Bool.self, forKey: .allOK)
        let timestamp = try container.decode(Double.self, forKey: .generatedAt)
        generatedAt = Date(timeIntervalSince1970: timestamp)
        services = try container.decodeIfPresent([StatusService].self, forKey: .services) ?? []
    }

    init(allOK: Bool, generatedAt: Date, services: [StatusService]) {
        self.allOK = allOK
        self.generatedAt = generatedAt
        self.services = services
    }
}

struct CachedStatus: Codable, Equatable, Sendable {
    var snapshot: StatusSnapshot?
    var fetchedAt: Date?
    var lastAttemptAt: Date
    var lastError: String?

    init(
        snapshot: StatusSnapshot? = nil,
        fetchedAt: Date? = nil,
        lastAttemptAt: Date = Date(),
        lastError: String? = nil
    ) {
        self.snapshot = snapshot
        self.fetchedAt = fetchedAt
        self.lastAttemptAt = lastAttemptAt
        self.lastError = lastError
    }

    var age: TimeInterval? {
        guard let fetchedAt else { return nil }
        return max(0, Date().timeIntervalSince(fetchedAt))
    }

    var isStale: Bool {
        guard let age else { return true }
        return age > InputStatusConstants.refreshInterval * 2
    }
}
