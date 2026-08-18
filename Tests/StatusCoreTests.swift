import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case expectation(String)

    var description: String {
        switch self {
        case .expectation(let message):
            return message
        }
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw TestFailure.expectation(message)
    }
}

private func expectValidationFailure(
    _ message: String,
    operation: () throws -> Void
) throws {
    do {
        try operation()
    } catch is StatusSnapshotValidationError {
        return
    }
    throw TestFailure.expectation(message)
}

@main
private struct StatusCoreTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let history = (0..<65).map { index in
            ProbeResult(
                timestamp: now.addingTimeInterval(Double(index - 65) * 60),
                isOK: true,
                latencyMS: 1_000 + index
            )
        }
        let service = StatusService(
            model: "  gpt-test  ",
            uptimePercent: 99.9,
            last: history.last,
            history: Array(history.reversed())
        )
        let snapshot = StatusSnapshot(
            allOK: true,
            generatedAt: now,
            services: [service]
        )

        let normalized = try snapshot.validated(referenceDate: now)
        try expect(normalized.services[0].model == "gpt-test", "Service names must be trimmed")
        try expect(
            normalized.services[0].history.count == InputStatusConstants.historyLength,
            "History must be capped"
        )
        try expect(
            normalized.services[0].history.first?.latencyMS == 1_005,
            "History must be sorted before retaining recent probes"
        )

        let cached = CachedStatus(
            snapshot: normalized,
            fetchedAt: now,
            lastAttemptAt: now
        )
        let encoded = try JSONEncoder().encode(cached)
        let decoded = try JSONDecoder().decode(CachedStatus.self, from: encoded)
        try expect(decoded == cached, "Cached timestamps must survive a JSON round trip")

        let duplicate = StatusSnapshot(
            allOK: true,
            generatedAt: now,
            services: [
                service,
                StatusService(
                    model: "Gpt-Test",
                    uptimePercent: 100,
                    last: history.last,
                    history: []
                )
            ]
        )
        try expectValidationFailure("Duplicate models must be rejected") {
            _ = try duplicate.validated(referenceDate: now)
        }

        let empty = StatusSnapshot(allOK: true, generatedAt: now, services: [])
        try expectValidationFailure("Empty service lists must be rejected") {
            _ = try empty.validated(referenceDate: now)
        }

        let inconsistent = StatusSnapshot(
            allOK: false,
            generatedAt: now,
            services: [service]
        )
        try expectValidationFailure("Summary state must agree with service state") {
            _ = try inconsistent.validated(referenceDate: now)
        }

        let offlineProbe = ProbeResult(timestamp: now, isOK: false)
        let previouslyOffline = StatusService(
            model: "Legacy-Service",
            uptimePercent: 98,
            last: offlineProbe,
            history: [offlineProbe]
        )
        let previousStatus = StatusSnapshot(
            allOK: false,
            generatedAt: now,
            services: [service, previouslyOffline]
        )
        let currentStatus = StatusSnapshot(
            allOK: false,
            generatedAt: now.addingTimeInterval(60),
            services: [
                StatusService(
                    model: "gpt-test",
                    uptimePercent: 99,
                    last: offlineProbe,
                    history: [offlineProbe]
                ),
                StatusService(
                    model: "legacy-service",
                    uptimePercent: 99,
                    last: history.last,
                    history: history
                ),
                StatusService(
                    model: "new-service",
                    uptimePercent: 0,
                    last: offlineProbe,
                    history: [offlineProbe]
                )
            ]
        )
        let statusChange = try {
            guard let change = StatusChange(from: previousStatus, to: currentStatus) else {
                throw TestFailure.expectation("Status transitions must be detected")
            }
            return change
        }()
        try expect(
            statusChange.newlyOffline == ["gpt-test", "new-service"],
            "Offline and newly introduced failing services must be reported"
        )
        try expect(
            statusChange.recovered == ["legacy-service"],
            "Recovered services must be matched case-insensitively"
        )
        try expect(
            StatusChange(from: currentStatus, to: currentStatus) == nil,
            "Unchanged snapshots must not create notifications"
        )

        let legacyEpoch = StatusSnapshot(
            allOK: true,
            generatedAt: Date(timeIntervalSince1970: 800_000_000),
            services: [service]
        )
        try expectValidationFailure("Corrupted legacy cache dates must be rejected") {
            _ = try legacyEpoch.validated(referenceDate: now)
        }

        let freshCache = CachedStatus(snapshot: normalized, fetchedAt: now)
        try expect(
            !freshCache.isStale(at: now.addingTimeInterval(240)),
            "Cache should remain fresh at the stale threshold"
        )
        try expect(
            freshCache.isStale(at: now.addingTimeInterval(241)),
            "Cache should become stale after the threshold"
        )

        print("Status core tests passed")
    }
}
