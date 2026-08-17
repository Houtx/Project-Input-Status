import Foundation

enum InputStatusConstants {
    static let endpoint = URL(string: "https://status.input.im/api/status")!
    static let statusPage = URL(string: "https://status.input.im/")!
    static let refreshURL = URL(string: "inputstatus://refresh")!
    static let widgetKind = "InputStatusWidget"
    static let historyLength = 60
    static let maximumServiceCount = 32
    static let maximumResponseBytes = 1_048_576
    static let maximumFutureClockSkew: TimeInterval = 300
    static let minimumGeneratedTimestamp: TimeInterval = 1_577_836_800
    static let refreshInterval: TimeInterval = 120
}

enum StatusSnapshotValidationError: Error, Equatable {
    case invalidGeneratedAt
    case invalidServiceCount
    case invalidService(String)
    case duplicateService(String)
    case inconsistentSummary
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp.timeIntervalSince1970, forKey: .timestamp)
        try container.encode(isOK, forKey: .isOK)
        try container.encodeIfPresent(latencyMS, forKey: .latencyMS)
        try container.encodeIfPresent(error, forKey: .error)
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(allOK, forKey: .allOK)
        try container.encode(generatedAt.timeIntervalSince1970, forKey: .generatedAt)
        try container.encode(services, forKey: .services)
    }

    func validated(referenceDate: Date = Date()) throws -> StatusSnapshot {
        let generatedTimestamp = generatedAt.timeIntervalSince1970
        guard generatedTimestamp.isFinite,
              generatedTimestamp >= InputStatusConstants.minimumGeneratedTimestamp,
              generatedAt <= referenceDate.addingTimeInterval(
                  InputStatusConstants.maximumFutureClockSkew
              ) else {
            throw StatusSnapshotValidationError.invalidGeneratedAt
        }
        guard !services.isEmpty,
              services.count <= InputStatusConstants.maximumServiceCount else {
            throw StatusSnapshotValidationError.invalidServiceCount
        }

        var seenModels = Set<String>()
        let normalizedServices = try services.map { service in
            let model = service.model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty,
                  service.uptimePercent.isFinite,
                  (0...100).contains(service.uptimePercent) else {
                throw StatusSnapshotValidationError.invalidService(service.model)
            }

            let modelKey = model.lowercased()
            guard seenModels.insert(modelKey).inserted else {
                throw StatusSnapshotValidationError.duplicateService(model)
            }

            let probes = service.history + [service.last].compactMap { $0 }
            guard probes.allSatisfy({ probe in
                probe.timestamp.timeIntervalSince1970.isFinite
                    && probe.timestamp.timeIntervalSince1970 > 0
                    && (probe.latencyMS.map { $0 >= 0 } ?? true)
            }) else {
                throw StatusSnapshotValidationError.invalidService(model)
            }

            let history = Array(
                service.history
                    .sorted { $0.timestamp < $1.timestamp }
                    .suffix(InputStatusConstants.historyLength)
            )
            return StatusService(
                model: model,
                uptimePercent: service.uptimePercent,
                last: service.last,
                history: history
            )
        }

        guard allOK == normalizedServices.allSatisfy(\.isOnline) else {
            throw StatusSnapshotValidationError.inconsistentSummary
        }

        return StatusSnapshot(
            allOK: allOK,
            generatedAt: generatedAt,
            services: normalizedServices
        )
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

    func age(at date: Date) -> TimeInterval? {
        guard let fetchedAt else { return nil }
        return max(0, date.timeIntervalSince(fetchedAt))
    }

    var age: TimeInterval? {
        age(at: Date())
    }

    func isStale(at date: Date) -> Bool {
        guard let age = age(at: date) else { return true }
        return age > InputStatusConstants.refreshInterval * 2
    }

    var isStale: Bool {
        isStale(at: Date())
    }
}
