import SwiftUI
import WidgetKit

struct StatusEntry: TimelineEntry {
    let date: Date
    let cachedStatus: CachedStatus?

    static let placeholder = StatusEntry(
        date: Date(),
        cachedStatus: CachedStatus(
            snapshot: StatusSnapshot(
                allOK: false,
                generatedAt: Date(),
                services: [
                    previewService("gpt-5.6-sol", online: true, uptime: 99.9),
                    previewService("gpt-5.6-terra", online: true, uptime: 99.8),
                    previewService("gpt-5.6-luna", online: true, uptime: 99.7),
                    previewService("gpt-5.5", online: false, uptime: 96.5),
                    previewService("gpt-5.4", online: true, uptime: 99.9),
                    previewService("gpt-5.4-mini", online: true, uptime: 100)
                ]
            ),
            fetchedAt: Date()
        )
    )

    private static func previewService(
        _ model: String,
        online: Bool,
        uptime: Double
    ) -> StatusService {
        let history = (0..<24).map { index in
            ProbeResult(
                timestamp: Date().addingTimeInterval(Double(index - 24) * 60),
                isOK: online || index < 19,
                latencyMS: online ? 1_500 : nil
            )
        }
        return StatusService(
            model: model,
            uptimePercent: uptime,
            last: history.last,
            history: history
        )
    }
}

struct StatusTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(
            StatusEntry(
                date: Date(),
                cachedStatus: StatusStore.load() ?? StatusEntry.placeholder.cachedStatus
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        Task {
            let cachedStatus: CachedStatus?
            do {
                cachedStatus = try await StatusRefresher.refresh()
            } catch {
                cachedStatus = StatusStore.load()
            }

            let now = Date()
            let entry = StatusEntry(date: now, cachedStatus: cachedStatus)
            let nextRefresh = now.addingTimeInterval(InputStatusConstants.refreshInterval)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }
}

struct InputStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    private var snapshot: StatusSnapshot? {
        entry.cachedStatus?.snapshot
    }

    private var statusColor: Color {
        guard entry.cachedStatus?.isStale == false, let snapshot else { return .orange }
        return snapshot.allOK ? .green : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            if let snapshot {
                switch family {
                case .systemSmall:
                    smallContent(snapshot)
                case .systemMedium:
                    mediumContent(snapshot)
                default:
                    largeContent(snapshot)
                }
            } else {
                emptyContent
            }

            footer
        }
        .padding(14)
        .containerBackground(for: .widget) {
            Color(nsColor: .windowBackgroundColor)
        }
        .widgetURL(InputStatusConstants.statusPage)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)

            Text("AI.INPUT.IM")
                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 6)

            Link(destination: InputStatusConstants.refreshURL) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("立即刷新")
            .accessibilityLabel("立即刷新")
        }
    }

    private func smallContent(_ snapshot: StatusSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(snapshot.allOK ? "全部正常" : "\(snapshot.failingCount) 项异常")
                .font(.title3.weight(.semibold))
                .foregroundStyle(snapshot.allOK ? Color.primary : Color.red)
                .lineLimit(1)

            Text("\(snapshot.onlineCount) / \(snapshot.services.count) 在线")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                ForEach(snapshot.services) { service in
                    Circle()
                        .fill(service.isOnline ? Color.green : Color.red)
                        .frame(width: 9, height: 9)
                        .accessibilityLabel("\(service.model) \(service.isOnline ? "正常" : "异常")")
                }
            }
        }
    }

    private func mediumContent(_ snapshot: StatusSnapshot) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 16, alignment: .leading),
            GridItem(.flexible(), spacing: 16, alignment: .leading)
        ]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(snapshot.services) { service in
                ServiceCompactRow(service: service)
            }
        }
    }

    private func largeContent(_ snapshot: StatusSnapshot) -> some View {
        VStack(spacing: 9) {
            ForEach(snapshot.services) { service in
                ServiceHistoryRow(service: service)
            }
        }
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            Spacer(minLength: 0)
            Text("暂无状态数据")
                .font(.headline)
            Text(entry.cachedStatus?.lastError ?? "无法连接状态服务器")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if entry.cachedStatus?.isStale == true {
                Label("数据已过期", systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
            } else if let fetchedAt = entry.cachedStatus?.fetchedAt {
                Text(fetchedAt, style: .time)
            } else {
                Text("尚未更新")
            }

            Spacer()

            if let snapshot {
                Text("平均 \(snapshot.averageUptime, format: .number.precision(.fractionLength(1)))%")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct ServiceCompactRow: View {
    let service: StatusService

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(service.isOnline ? Color.green : Color.red)
                .frame(width: 7, height: 7)

            Text(service.model)
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 4)

            Text(service.uptimePercent, format: .number.precision(.fractionLength(0)))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ServiceHistoryRow: View {
    let service: StatusService

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(service.isOnline ? Color.green : Color.red)
                .frame(width: 7, height: 7)

            Text(service.model)
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .frame(width: 105, alignment: .leading)
                .lineLimit(1)

            HStack(spacing: 2) {
                ForEach(Array(service.history.suffix(30).enumerated()), id: \.offset) { _, result in
                    Rectangle()
                        .fill(result.isOK ? Color.green : Color.red)
                        .frame(maxWidth: .infinity, minHeight: 12, maxHeight: 12)
                }
            }

            Text("\(service.uptimePercent, format: .number.precision(.fractionLength(1)))%")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }
}

struct InputStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: InputStatusConstants.widgetKind, provider: StatusTimelineProvider()) { entry in
            InputStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("AI.INPUT.IM 服务状态")
        .description("在桌面查看各模型服务的最新可用状态。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct InputStatusWidgetBundle: WidgetBundle {
    var body: some Widget {
        InputStatusWidget()
    }
}
