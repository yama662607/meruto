import MerutoCore
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct WiFiEntry: TimelineEntry {
    let date: Date
    let score: Double?
    let rtt: TimeInterval?
    let ssid: String?
    let measuredAt: Date?
    let survey: Survey?

    static let sample: WiFiEntry = {
        let points = [(0.0, 0.0, 92.0), (1.5, 0.5, 85.0), (3.0, 1.2, 64.0), (4.2, 2.5, 41.0), (2.0, 3.0, 70.0), (0.5, 2.2, 88.0)]
            .map { SurveyPoint(x: $0.0, y: $0.1, score: $0.2, rtt: nil, jitter: nil, loss: 0) }
        return WiFiEntry(
            date: .now, score: 82, rtt: 0.004, ssid: "Home-5G", measuredAt: .now,
            survey: Survey(name: "リビング", mode: .walk, points: points))
    }()
}

/// Wi-Fi の品質はアプリの中でしか測れない (ローカルネットワークの許可はアプリに付く) ので、
/// アプリが最後に測った値と、最新の電波マップを表示する。
struct WiFiProvider: TimelineProvider {
    func placeholder(in context: Context) -> WiFiEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (WiFiEntry) -> Void) {
        completion(context.isPreview ? .sample : Self.read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WiFiEntry>) -> Void) {
        completion(Timeline(entries: [Self.read()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    static func read() -> WiFiEntry {
        let snapshot = SharedContainer.readJSON(DeviceSnapshot.self, from: SharedContainer.File.deviceSnapshot)
        let surveys = SharedContainer.readJSON([Survey].self, from: SharedContainer.File.surveys) ?? []
        let latest = surveys.filter { !$0.points.isEmpty }.max { $0.updatedAt < $1.updatedAt }
        return WiFiEntry(
            date: .now, score: snapshot?.wifiScore, rtt: snapshot?.wifiRTT, ssid: snapshot?.wifiSSID,
            measuredAt: snapshot?.wifiMeasuredAt, survey: latest)
    }
}

// MARK: - Widget

struct WiFiWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.wifi, provider: WiFiProvider()) { entry in
            WiFiWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
                .widgetURL(URL(string: "meruto://wifi"))
        }
        .configurationDisplayName("Wi-Fi 電波")
        .description("最後に測ったWi-Fiのリンク品質と、最新の電波マップを表示します。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular])
    }
}

struct WiFiWidgetView: View {
    let entry: WiFiEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemLarge: large
        case .accessoryCircular: circular
        default: medium
        }
    }

    private var color: Color { entry.score.map(Theme.quality) ?? Theme.faint }

    private var scoreBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetHeader(title: entry.ssid ?? "Wi-Fi", icon: "wifi", tint: color)
            ZStack(alignment: .bottom) {
                ArcMeter(value: entry.score, segmentCount: 32)
                VStack(spacing: 0) {
                    Text(entry.score.map { "\(Int($0.rounded()))" } ?? "--")
                        .font(Theme.rounded(30, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: color.opacity(0.7), radius: 6)
                    Text(entry.score.map { QualityGrade(score: $0).code } ?? "未測定")
                        .font(Theme.mono(8.5, weight: .heavy))
                        .foregroundStyle(color)
                }
            }
            if let measuredAt = entry.measuredAt {
                Text(measuredAt, style: .relative)
                    .font(Theme.mono(8, weight: .medium))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
            }
        }
    }

    private var small: some View { scoreBlock }

    private var medium: some View {
        HStack(spacing: 12) {
            scoreBlock
                .frame(maxWidth: .infinity)
            mapBlock
                .frame(maxWidth: .infinity)
        }
    }

    private var large: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                scoreBlock.frame(maxWidth: .infinity)
                if let survey = entry.survey {
                    let summary = survey.summary
                    VStack(alignment: .leading, spacing: 6) {
                        stat("平均", summary.average)
                        stat("最弱", summary.weakest?.score)
                        stat("最強", summary.strongest?.score)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 130)
            mapBlock
        }
    }

    @ViewBuilder
    private var mapBlock: some View {
        if let survey = entry.survey {
            VStack(alignment: .leading, spacing: 3) {
                HeatmapThumbnail(survey: survey)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.panelStroke, lineWidth: 1))
                Text("\(survey.name) · \(survey.points.count)点")
                    .font(Theme.mono(8, weight: .medium))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
            }
        } else {
            VStack(spacing: 4) {
                Image(systemName: "map")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.yellow)
                Text("アプリで電波マップを作成")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.label)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
        }
    }

    private func stat(_ label: String, _ value: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(Theme.mono(9, weight: .semibold))
                .foregroundStyle(Theme.faint)
                .frame(width: 28, alignment: .leading)
            Text(value.map { "\(Int($0.rounded()))" } ?? "—")
                .font(Theme.rounded(20, weight: .heavy))
                .foregroundStyle(value.map(Theme.quality) ?? .white)
        }
    }

    private var circular: some View {
        Gauge(value: entry.score ?? 0, in: 0...100) {
            Image(systemName: "wifi")
        } currentValueLabel: {
            Text(entry.score.map { "\(Int($0.rounded()))" } ?? "--")
                .font(.system(size: 14, weight: .bold).monospacedDigit())
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }
}
