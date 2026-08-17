import AppKit
import Combine
import ServiceManagement
@preconcurrency import Sparkle
import SwiftUI

@MainActor
final class InputStatusAppDelegate: NSObject, NSApplicationDelegate, @MainActor SPUStandardUserDriverDelegate {
    let model = AppModel()
    lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )
    private var desktopWidgetController: DesktopWidgetWindowController?

    var isDesktopWidgetVisible: Bool {
        desktopWidgetController?.isVisible == true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = updaterController
        registerLoginItemIfNeeded()
        desktopWidgetController = DesktopWidgetWindowController(model: model)
        desktopWidgetController?.show()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "inputstatus" && $0.host == "refresh" }) else {
            return
        }
        NotificationCenter.default.post(name: .inputStatusRefreshRequested, object: nil)
    }

    func toggleDesktopWidget() {
        desktopWidgetController?.toggle()
    }

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func standardUserDriverWillFinishUpdateSession() {
        NSApp.setActivationPolicy(.accessory)
    }

    private func registerLoginItemIfNeeded() {
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else { return }
        guard SMAppService.mainApp.status == .notRegistered else { return }

        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("Unable to register Input Status as a login item: %@", error.localizedDescription)
        }
    }
}

@main
struct InputStatusApp: App {
    @NSApplicationDelegateAdaptor(InputStatusAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView(model: appDelegate.model, appDelegate: appDelegate)
        } label: {
            Label("输入法服务状态", systemImage: appDelegate.model.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct StatusMenuView: View {
    @ObservedObject var model: AppModel
    let appDelegate: InputStatusAppDelegate

    private var snapshot: StatusSnapshot? {
        model.cachedStatus?.snapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            if let snapshot {
                summary(snapshot)
                serviceList(snapshot.services)
            } else {
                ContentUnavailableView(
                    "等待状态数据",
                    systemImage: "waveform.path.ecg",
                    description: Text(model.errorMessage ?? "正在连接 status.input.im")
                )
                .frame(height: 150)
            }

            Divider()
            Button {
                appDelegate.toggleDesktopWidget()
            } label: {
                Label("显示/隐藏桌面挂件", systemImage: "rectangle.on.rectangle")
            }

            Divider()
            Button {
                appDelegate.updaterController.checkForUpdates(nil)
            } label: {
                Label("检查更新…", systemImage: "arrow.triangle.2.circlepath")
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("AI.INPUT.IM")
                    .font(.headline)
                Text("服务状态")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.refreshNow()
            } label: {
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("立即刷新")
            .disabled(model.isRefreshing)
        }
    }

    private func summary(_ snapshot: StatusSnapshot) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(snapshot.allOK ? Color.green : Color.red)
                .frame(width: 9, height: 9)

            Text(snapshot.allOK ? "全部服务正常" : "\(snapshot.failingCount) 个服务异常")
                .font(.subheadline.weight(.semibold))

            Spacer()

            if model.cachedStatus?.isStale == true {
                Text("数据已过期")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func serviceList(_ services: [StatusService]) -> some View {
        VStack(spacing: 0) {
            ForEach(services) { service in
                HStack(spacing: 8) {
                    Circle()
                        .fill(service.isOnline ? Color.green : Color.red)
                        .frame(width: 7, height: 7)

                    Text(service.model)
                        .font(.system(.body, design: .monospaced))

                    Spacer()

                    Text(service.uptimePercent, format: .number.precision(.fractionLength(1)))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let fetchedAt = model.cachedStatus?.fetchedAt {
                Text("更新于 \(fetchedAt, style: .time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(model.errorMessage ?? "尚未更新")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("打开状态页") {
                NSWorkspace.shared.open(InputStatusConstants.statusPage)
            }
            .buttonStyle(.link)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("退出")
        }
    }
}

@MainActor
private final class DesktopWidgetWindowController: NSObject {
    private let model: AppModel
    private let settings = DesktopWidgetSettings()
    private var window: NSPanel?
    private var hostingController: NSHostingController<DesktopWidgetView>?

    init(model: AppModel) {
        self.model = model
        super.init()
        settings.onLockChanged = { [weak self] isLocked in
            self?.applyLockState(isLocked)
        }
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show() {
        if window == nil {
            makeWindow()
        }
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    private func makeWindow() {
        let size = NSSize(width: 330, height: 278)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let hostingController = NSHostingController(
            rootView: DesktopWidgetView(model: model, settings: settings)
        )
        self.hostingController = hostingController
        panel.contentView = hostingController.view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = !settings.isLocked
        let desktopWidgetLevel = Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
        panel.level = NSWindow.Level(rawValue: desktopWidgetLevel)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let frameName = "InputStatusDesktopWidget"
        let restoredFrame = panel.setFrameUsingName(frameName)
        panel.setFrameAutosaveName(frameName)

        if !restoredFrame, let screen = NSScreen.main ?? NSScreen.screens.first {
            let visibleFrame = screen.visibleFrame
            let origin = NSPoint(
                x: visibleFrame.maxX - size.width - 28,
                y: visibleFrame.minY + 28
            )
            panel.setFrameOrigin(origin)
        }

        window = panel
    }

    private func applyLockState(_ isLocked: Bool) {
        window?.isMovableByWindowBackground = !isLocked
    }
}

@MainActor
private final class DesktopWidgetSettings: ObservableObject {
    private static let lockKey = "desktop-widget-position-locked"

    @Published private(set) var isLocked: Bool
    var onLockChanged: ((Bool) -> Void)?

    init() {
        let storedValue = UserDefaults.standard.object(forKey: Self.lockKey) as? Bool
        isLocked = storedValue ?? true
    }

    func toggleLock() {
        isLocked.toggle()
        UserDefaults.standard.set(isLocked, forKey: Self.lockKey)
        onLockChanged?(isLocked)
    }
}

private struct DesktopWidgetView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: DesktopWidgetSettings

    private var snapshot: StatusSnapshot? {
        model.cachedStatus?.snapshot
    }

    private var statusColor: Color {
        guard model.cachedStatus?.isStale == false, let snapshot else { return .orange }
        return snapshot.allOK ? .green : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let snapshot {
                summary(snapshot)
                serviceList(snapshot.services)
            } else {
                ContentUnavailableView(
                    "等待状态数据",
                    systemImage: "waveform.path.ecg",
                    description: Text(model.errorMessage ?? "正在连接 status.input.im")
                )
                .frame(maxHeight: .infinity)
            }

            footer
        }
        .padding(16)
        .frame(width: 330, height: 278)
        .modifier(DesktopGlassModifier())
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text("AI.INPUT.IM")
                        .font(.system(.headline, design: .monospaced, weight: .semibold))
                }
                Text("服务状态")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                settings.toggleLock()
            } label: {
                Image(systemName: settings.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.borderless)
            .background(
                settings.isLocked ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.08),
                in: Circle()
            )
            .help(settings.isLocked ? "解锁挂件位置" : "锁定挂件位置")
            .accessibilityLabel(settings.isLocked ? "解锁挂件位置" : "锁定挂件位置")

            Button {
                model.refreshNow()
            } label: {
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
            }
            .buttonStyle(.borderless)
            .background(Color.primary.opacity(0.08), in: Circle())
            .help("立即刷新")
            .accessibilityLabel("立即刷新")
            .disabled(model.isRefreshing)
        }
    }

    private func summary(_ snapshot: StatusSnapshot) -> some View {
        HStack(spacing: 8) {
            Text(snapshot.allOK ? "全部正常" : "\(snapshot.failingCount) 项异常")
                .font(.title3.weight(.semibold))
                .foregroundStyle(snapshot.allOK ? Color.primary : Color.red)

            Spacer()

            Text("\(snapshot.onlineCount)/\(snapshot.services.count) 在线")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func serviceList(_ services: [StatusService]) -> some View {
        VStack(spacing: 0) {
            ForEach(services.prefix(6)) { service in
                HStack(spacing: 8) {
                    Circle()
                        .fill(service.isOnline ? Color.green : Color.red)
                        .frame(width: 7, height: 7)

                    Text(service.model)
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Text(service.uptimePercent, format: .number.precision(.fractionLength(1)))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 23)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let fetchedAt = model.cachedStatus?.fetchedAt {
                Text("更新于 \(fetchedAt, style: .time)")
            } else {
                Text(model.errorMessage ?? "尚未更新")
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button("打开状态页") {
                NSWorkspace.shared.open(InputStatusConstants.statusPage)
            }
            .buttonStyle(.link)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

private struct DesktopGlassModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        }
    }
}
