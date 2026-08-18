import Combine
import Foundation
import UserNotifications
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var cachedStatus: CachedStatus?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusNotificationsEnabled: Bool
    @Published private(set) var notificationPermissionDenied = false

    private static let notificationsEnabledKey = "status-change-notifications-enabled"
    private let userNotificationCenter = UNUserNotificationCenter.current()
    private var refreshTask: Task<Void, Never>?
    private var refreshObserver: NSObjectProtocol?

    init() {
        statusNotificationsEnabled = UserDefaults.standard.bool(
            forKey: Self.notificationsEnabledKey
        )
        cachedStatus = StatusStore.load()
        errorMessage = cachedStatus?.lastError
        refreshObserver = NotificationCenter.default.addObserver(
            forName: .inputStatusRefreshRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshNow() }
        }
        reconcileNotificationAuthorization()
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

    func setStatusNotificationsEnabled(_ isEnabled: Bool) {
        guard isEnabled else {
            updateNotificationPreference(false)
            notificationPermissionDenied = false
            return
        }

        userNotificationCenter.requestAuthorization(options: [.alert, .sound]) {
            [weak self] granted, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateNotificationPreference(granted)
                self.notificationPermissionDenied = !granted
                if let error {
                    NSLog(
                        "Unable to authorize Input Status notifications: %@",
                        error.localizedDescription
                    )
                }
            }
        }
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
            let previousSnapshot = cachedStatus?.snapshot
            let refreshedStatus = try await StatusRefresher.refresh()
            cachedStatus = refreshedStatus
            errorMessage = nil
            WidgetCenter.shared.reloadTimelines(ofKind: InputStatusConstants.widgetKind)

            if let previousSnapshot,
               let currentSnapshot = refreshedStatus.snapshot,
               let change = StatusChange(from: previousSnapshot, to: currentSnapshot) {
                sendStatusChangeNotification(change)
            }
        } catch {
            cachedStatus = StatusStore.load()
            errorMessage = error.localizedDescription
        }
    }

    private func reconcileNotificationAuthorization() {
        guard statusNotificationsEnabled else { return }

        userNotificationCenter.getNotificationSettings { [weak self] settings in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if settings.authorizationStatus == .denied {
                    self.updateNotificationPreference(false)
                    self.notificationPermissionDenied = true
                } else if settings.authorizationStatus == .notDetermined {
                    self.setStatusNotificationsEnabled(true)
                }
            }
        }
    }

    private func updateNotificationPreference(_ isEnabled: Bool) {
        statusNotificationsEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.notificationsEnabledKey)
    }

    private func sendStatusChangeNotification(_ change: StatusChange) {
        guard statusNotificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        if !change.newlyOffline.isEmpty && change.recovered.isEmpty {
            content.title = change.newlyOffline.count == 1 ? "服务出现异常" : "多个服务出现异常"
        } else if change.newlyOffline.isEmpty {
            content.title = change.recovered.count == 1 ? "服务已恢复" : "多个服务已恢复"
        } else {
            content.title = "服务状态发生变化"
        }

        var details: [String] = []
        if !change.newlyOffline.isEmpty {
            details.append("异常：\(summarizedModels(change.newlyOffline))")
        }
        if !change.recovered.isEmpty {
            details.append("恢复：\(summarizedModels(change.recovered))")
        }
        content.body = details.joined(separator: "；")
        content.sound = .default
        content.threadIdentifier = "input-status-service-changes"

        let request = UNNotificationRequest(
            identifier: "input-status-service-change",
            content: content,
            trigger: nil
        )
        userNotificationCenter.add(request) { error in
            if let error {
                NSLog(
                    "Unable to deliver Input Status notification: %@",
                    error.localizedDescription
                )
            }
        }
    }

    private func summarizedModels(_ models: [String]) -> String {
        let visibleModels = models.prefix(3).joined(separator: "、")
        guard models.count > 3 else { return visibleModels }
        return "\(visibleModels) 等 \(models.count) 项"
    }
}

extension Notification.Name {
    static let inputStatusRefreshRequested = Notification.Name("InputStatusRefreshRequested")
}
