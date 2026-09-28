import AppIntents
import MerutoCore
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct AIQuotaEntry: TimelineEntry {
    let date: Date
    let providers: [AgentQuotaProviderItem]
    let fetchedAt: Date?
    let isFromCache: Bool
    let isPlaceholder: Bool

    var displayed: [AgentQuotaProviderItem] { AgentQuotaProviderItem.displayOrder(providers) }

    /// 5h 枠 (無ければ週次枠) の残りが最も少ないプロバイダー。
    var mostConstrained: AgentQuotaProviderItem? {
        providers
            .filter { $0.primaryWindow != nil }
            .min { ($0.primaryWindow?.remainingPct ?? 100) < ($1.primaryWindow?.remainingPct ?? 100) }
    }
}

struct AIQuotaProvider: TimelineProvider {
    func placeholder(in context: Context) -> AIQuotaEntry {
        AIQuotaEntry(date: .now, providers: QuotaClient.sample, fetchedAt: .now, isFromCache: false, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (AIQuotaEntry) -> Void) {
        if let cached = QuotaClient.cached() {
            completion(
                AIQuotaEntry(
                    date: .now, providers: cached.providers, fetchedAt: cached.fetchedAt, isFromCache: true,
                    isPlaceholder: false))
        } else {
            completion(placeholder(in: context))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AIQuotaEntry>) -> Void) {
        let completion = CompletionBox(call: completion)
        Task {
            let result = await QuotaClient.fetchOrCached()
            let now = Date()
            // 値はそのままで、リセットまでの残り時間だけ進めるエントリを 5 分刻みで 30 分ぶん並べる。
            let entries = (0...6).map { step in
                AIQuotaEntry(
                    date: now.addingTimeInterval(Double(step) * 300),
                    providers: result?.providers ?? [],
                    fetchedAt: result?.fetchedAt,
                    isFromCache: result?.isFromCache ?? true,
                    isPlaceholder: false)
            }
            completion.call(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
        }
    }
}

/// ウィジェットの再取得ボタン。実行後に WidgetKit がタイムラインを取り直す。
struct ReloadQuotaIntent: AppIntent {
    static let title: LocalizedStringResource = "AI使用量を更新"

    func perform() async throws -> some IntentResult {
        _ = try? await QuotaClient.fetch()
        return .result()
    }
}

// MARK: - Widget

struct AIQuotaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.aiQuota, provider: AIQuotaProvider()) { entry in
            AIQuotaWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
                .widgetURL(URL(string: "meruto://ai"))
        }
        .configurationDisplayName("AI 使用量")
        .description("Codex・Claude・Gemini などの5時間枠と週次枠の残りを表示します。")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct AIQuotaWidgetView: View {
    let entry: AIQuotaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemLarge: large
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: medium
        }
    }

    // SuperNotch と同じ 6 連ゲージ。
    private var medium: some View {
        VStack(spacing: 6) {
            header
            Spacer(minLength: 0)
            AgentQuotaGaugeRow(providers: entry.displayed, now: entry.date)
            Spacer(minLength: 0)
        }
    }

    private var small: some View {
        VStack(spacing: 4) {
            header
            Spacer(minLength: 0)
            let items = Array(entry.displayed.prefix(6))
            Grid(horizontalSpacing: 4, verticalSpacing: 6) {
                GridRow {
                    ForEach(items.prefix(3)) { AgentQuotaMiniGauge(item: $0, now: entry.date, scale: 0.74, showsWeekly: false) }
                }
                GridRow {
                    ForEach(items.dropFirst(3)) { AgentQuotaMiniGauge(item: $0, now: entry.date, scale: 0.74, showsWeekly: false) }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            AgentQuotaGaugeRow(providers: entry.displayed, now: entry.date)
            let others = Array(entry.displayed.dropFirst(AgentQuotaProviderItem.homeProviderIDs.count))
            if !others.isEmpty {
                HStack(spacing: 0) {
                    ForEach(others.prefix(6)) { item in
                        AgentQuotaMiniGauge(item: item, now: entry.date, scale: 0.85)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            Divider().overlay(Color.white.opacity(0.08))
            AgentQuotaWeeklyBars(providers: entry.displayed)
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        WidgetHeader(title: "AI USAGE", icon: "sparkles", tint: Theme.quotaGreen) {
            if let fetchedAt = entry.fetchedAt, fetchedAt > .distantPast {
                Text(fetchedAt, style: .time)
                    .font(Theme.mono(8.5, weight: .semibold))
                    .foregroundStyle(entry.isFromCache ? Theme.orange : Theme.faint)
            } else if !entry.isPlaceholder {
                Text("未接続")
                    .font(Theme.mono(8.5, weight: .semibold))
                    .foregroundStyle(Theme.orange)
            }
            Button(intent: ReloadQuotaIntent()) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.label)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: ロック画面

    @ViewBuilder
    private var circular: some View {
        if let item = entry.mostConstrained, let window = item.primaryWindow {
            Gauge(value: window.remainingPct, in: 0...100) {
                AgentBrandIconView(provider: item.provider, size: 12)
            } currentValueLabel: {
                Text("\(Int(window.remainingPct))")
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        } else {
            Image(systemName: "sparkles")
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(entry.displayed.filter { $0.primaryWindow != nil }.prefix(3)) { item in
                HStack(spacing: 4) {
                    Text(shortName(item.provider))
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 44, alignment: .leading)
                    Text("\(Int(item.primaryWindow?.remainingPct ?? 0))%")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .widgetAccentable()
                    if let reset = AgentQuotaDisplay.resetLabel(for: item.primaryWindow, now: entry.date) {
                        Text("↻\(reset)")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var inline: some View {
        if let item = entry.mostConstrained, let window = item.primaryWindow {
            Text(
                "\(shortName(item.provider)) \(Int(window.remainingPct))%"
                    + (AgentQuotaDisplay.resetLabel(for: window, now: entry.date).map { " · \($0)" } ?? ""))
        } else {
            Text("AI 使用量 —")
        }
    }

    private func shortName(_ provider: String) -> String {
        switch provider {
        case "codex": "Codex"
        case "claude_code": "Claude"
        case "antigravity": "Gemini"
        case "zai": "GLM"
        case "deepseek": "DSeek"
        case "devin": "Devin"
        default: provider.capitalized
        }
    }
}
