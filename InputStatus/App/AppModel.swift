import Combine
import Foundation
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var cachedStatus: CachedStatus?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    private var refreshTask: Task<Void, Never>?
    private var refreshObserver: NSObjectProtocol?

    init() {
        cachedStatus = StatusStore.load()
        errorMessage = cachedStatus?.lastError
        refreshObserver = NotificationCenter.default.addObserver(
            forName: .inputStatusRefreshRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
        startRefreshing()
    }

    deinit {
        refreshTask?.cancel()
        if let refreshObserver {
            NotificationCenter.default.removeObserver(refreshObserver)
        }
    }

    var menuBarSymbol: String {
        guard let cachedStatus, !cachedStatus.isStale, let snapshot = cachedStatus.snapshot else {
            return "questionmark.circle"
        }
        return snapshot.allOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    func refreshNow() {
        Task { await refresh() }
    }

    private func startRefreshing() {
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await refresh()

            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: UInt64(InputStatusConstants.refreshInterval * 1_000_000_000)
                )
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            cachedStatus = try await StatusRefresher.refresh()
            errorMessage = nil
            WidgetCenter.shared.reloadTimelines(ofKind: InputStatusConstants.widgetKind)
        } catch {
            cachedStatus = StatusStore.load()
            errorMessage = error.localizedDescription
        }
    }
}

extension Notification.Name {
    static let inputStatusRefreshRequested = Notification.Name("InputStatusRefreshRequested")
}
