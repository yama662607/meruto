import MerutoCore
import MerutoProbes
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Timeline

struct DeviceEntry: TimelineEntry {
    let date: Date
    let cpu: Double?
    let memory: Double?
    let memoryUsed: UInt64?
    let storage: Double?
    let storageFree: UInt64?
    let battery: Double?
    let chargeState: ChargeState
    let thermal: ThermalLevel
    let lowPower: Bool
    let wifiScore: Double?
    let wifiMeasuredAt: Date?

    static let sample = DeviceEntry(
        date: .now, cpu: 0.23, memory: 0.61, memoryUsed: 5_000_000_000, storage: 0.72, storageFree: 70_000_000_000,
        battery: 0.8, chargeState: .unplugged, thermal: .nominal, lowPower: false, wifiScore: 82, wifiMeasuredAt: .now)
}

/// ウィジェット拡張の中で読める値は自分で読む (CPU・メモリ・ストレージ・熱状態・電池)。
/// Wi-Fi の品質はアプリが最後に測った値を App Group から読む。
struct DeviceProvider: TimelineProvider {
    func placeholder(in context: Context) -> DeviceEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (DeviceEntry) -> Void) {
        if context.isPreview {
            completion(.sample)
            return
        }
        let completion = CompletionBox(call: completion)
        Task { completion.call(await Self.read()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DeviceEntry>) -> Void) {
        let completion = CompletionBox(call: completion)
        Task {
            let entry = await Self.read()
            completion.call(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }

    static func read() async -> DeviceEntry {
        let cpuProbe = CPUProbe()
        _ = cpuProbe.sample()
        try? await Task.sleep(nanoseconds: 500_000_000)
        let cpu = cpuProbe.sample()?.total.total
        let memory = MemoryProbe().sample()
        let storage = StorageUsage.read()
        let snapshot = SharedContainer.readJSON(DeviceSnapshot.self, from: SharedContainer.File.deviceSnapshot)

        let (battery, state) = await MainActor.run { () -> (Double?, ChargeState) in
            let device = UIDevice.current
            device.isBatteryMonitoringEnabled = true
            let level = device.batteryLevel >= 0 ? Double(device.batteryLevel) : nil
            let state: ChargeState =
                switch device.batteryState {
                case .unplugged: .unplugged
                case .charging: .charging
                case .full: .full
                default: .unknown
                }
            return (level, state)
        }

        return DeviceEntry(
            date: .now,
            cpu: cpu ?? snapshot?.cpu,
            memory: memory?.usedFraction ?? snapshot?.memoryFraction,
            memoryUsed: memory?.used ?? snapshot?.memoryUsed,
            storage: storage?.usedFraction ?? snapshot?.storageFraction,
            storageFree: storage?.available,
            battery: battery ?? snapshot?.batteryLevel,
            chargeState: battery != nil ? state : (snapshot?.chargeState ?? .unknown),
            thermal: ThermalLevel(rawValue: ProcessInfo.processInfo.thermalState.rawValue) ?? .nominal,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            wifiScore: snapshot?.wifiScore,
            wifiMeasuredAt: snapshot?.wifiMeasuredAt)
    }
}

// MARK: - Widget

struct DeviceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.device, provider: DeviceProvider()) { entry in
            DeviceWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
                .widgetURL(URL(string: "meruto://dashboard"))
        }
        .configurationDisplayName("デバイスモニター")
        .description("CPU・メモリ・ストレージ・バッテリー・熱状態を表示します。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct DeviceWidgetView: View {
    let entry: DeviceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall: small
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: medium
        }
    }

    private var metrics: [(String, Double?, [Color])] {
        [
            ("CPU", entry.cpu, [Theme.blue, Theme.cyan]),
            ("MEM", entry.memory, [Theme.blue, Theme.violet]),
            ("SSD", entry.storage, [Theme.violet, Theme.blue]),
            ("BAT", entry.battery, [Theme.green, batteryColor]),
        ]
    }

    private var batteryColor: Color {
        Theme.severity(batterySeverity(level: entry.battery, state: entry.chargeState), base: Theme.lime)
    }

    private var small: some View {
        VStack(spacing: 6) {
            WidgetHeader(title: "MERUTO", icon: "gauge.with.dots.needle.67percent", tint: Theme.cyan) {
                thermalDot
            }
            Grid(horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    ring(metrics[0])
                    ring(metrics[1])
                }
                GridRow {
                    ring(metrics[2])
                    ring(metrics[3])
                }
            }
        }
    }

    private var medium: some View {
        VStack(spacing: 8) {
            WidgetHeader(title: "MERUTO", icon: "gauge.with.dots.needle.67percent", tint: Theme.cyan) {
                Text(entry.date, style: .time)
                    .font(Theme.mono(8.5, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
            HStack(spacing: 10) {
                ForEach(metrics, id: \.0) { ring($0) }
            }
            HStack(spacing: 8) {
                chip(
                    icon: "thermometer.medium", text: entry.thermal.englishLabel,
                    color: Theme.severity(entry.thermal.severity, base: Theme.cyan))
                if let score = entry.wifiScore {
                    chip(icon: "wifi", text: "\(Int(score.rounded())) \(QualityGrade(score: score).code)", color: Theme.quality(score))
                }
                if let free = entry.storageFree {
                    chip(icon: "internaldrive", text: "空き \(Format.bytes(free))", color: Theme.blue)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func ring(_ metric: (String, Double?, [Color])) -> some View {
        RingGauge(value: metric.1 ?? 0, colors: metric.2, lineWidth: 5, glow: false) {
            VStack(spacing: -1) {
                Text(metric.1.map { "\(Int(($0 * 100).rounded()))" } ?? "--")
                    .font(Theme.rounded(13, weight: .heavy))
                    .foregroundStyle(.white)
                Text(metric.0)
                    .font(Theme.mono(7, weight: .bold))
                    .foregroundStyle(Theme.label)
            }
        }
        .frame(width: 50, height: 50)
    }

    private var thermalDot: some View {
        Circle()
            .fill(Theme.severity(entry.thermal.severity, base: Theme.green))
            .frame(width: 6, height: 6)
    }

    private func chip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8, weight: .bold))
            Text(text).font(Theme.mono(8.5, weight: .bold)).lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }

    // MARK: ロック画面

    private var circular: some View {
        Gauge(value: entry.battery ?? 0) {
            Image(systemName: entry.chargeState == .charging ? "bolt.fill" : "battery.75percent")
        } currentValueLabel: {
            Text(entry.battery.map { "\(Int(($0 * 100).rounded()))" } ?? "--")
                .font(.system(size: 14, weight: .bold).monospacedDigit())
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("CPU \(percent(entry.cpu)) · MEM \(percent(entry.memory))")
            Text("BAT \(percent(entry.battery)) · SSD \(percent(entry.storage))")
            Text("熱 \(entry.thermal.label)")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12, weight: .semibold).monospacedDigit())
    }

    private var inline: some View {
        Text("CPU \(percent(entry.cpu)) · MEM \(percent(entry.memory))")
    }

    private func percent(_ value: Double?) -> String {
        value.map { Format.percent($0) } ?? "--"
    }
}
