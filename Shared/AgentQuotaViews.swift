import MerutoCore
import SwiftUI
import UIKit

// SuperNotch の AgentQuotaHomeCard の見た目をそのまま移植した部品。
// アプリ (TimelineView で毎秒更新) とウィジェット (エントリの日時で描画) の両方から使う。

/// 高解像度の AI プロバイダーアイコン。アセットカタログに SVG をベクターのまま入れてある。
struct AgentBrandIconView: View {
    let provider: String
    var size: CGFloat = 14

    var body: some View {
        Group {
            if UIImage(named: "AgentIcon-\(provider)") != nil {
                Image("AgentIcon-\(provider)")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else if provider == "devin" {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "cpu")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.purple)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}

enum AgentQuotaStyle {
    static func gaugeColor(remainingPct: Double) -> Color {
        if remainingPct <= 0 { return .red }
        if remainingPct < 15 { return .orange }
        // 鮮やかすぎる蛍光グリーンから、落ち着いた上品なミントフォレストグリーンへ
        return Theme.quotaGreen
    }

    static func gaugeGradient(remainingPct: Double) -> LinearGradient {
        let color = gaugeColor(remainingPct: remainingPct)
        return LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing)
    }

    static func resetColor(for window: AgentQuotaWindow?, now: Date) -> Color {
        guard let window else { return .white }
        let seconds = AgentQuotaDisplay.resetSeconds(for: window, now: now)
        return seconds.map { $0 < 3600 ? Color.orange : Color.white } ?? .white
    }
}

/// 1 プロバイダー分のミニゲージ (5h リング + リセット時刻 + 週次ミニバー + 週次リセット)。
/// `scale` はウィジェットの小さい枠に収めるための縮尺 (1 が SuperNotch と同じ寸法)。
struct AgentQuotaMiniGauge: View {
    let item: AgentQuotaProviderItem
    let now: Date
    var scale: CGFloat = 1
    var showsWeekly: Bool = true

    var body: some View {
        let showsStaleState = AgentQuotaDisplay.shouldShowStaleState(
            isStale: item.isStale, timestamp: item.dataTimestamp, now: now)

        VStack(spacing: 4 * scale) {
            // 1. リング (5hローリング枠: 線幅3.2px、中央ロゴ24px)
            ZStack {
                let win5h = item.primaryWindow
                let pct5h = win5h?.remainingPct ?? 100.0
                let color5h = item.hasData ? AgentQuotaStyle.gaugeColor(remainingPct: pct5h) : Color.white

                // 背景トラック
                Circle()
                    .stroke(color5h.opacity(0.18), lineWidth: 3.2 * scale)
                    .frame(width: 44 * scale, height: 44 * scale)
                    .opacity(showsStaleState ? 0.58 : 1)

                // 5hプログレス円弧
                if let win = win5h {
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0.001, min(1.0, win.remainingPct / 100.0))))
                        .stroke(
                            AgentQuotaStyle.gaugeGradient(remainingPct: win.remainingPct),
                            style: StrokeStyle(lineWidth: 3.2 * scale, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 44 * scale, height: 44 * scale)
                        .opacity(showsStaleState ? 0.58 : 1)
                } else if item.credits != nil {
                    Circle()
                        .trim(from: 0, to: 0.8)
                        .stroke(
                            LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 3.2 * scale, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 44 * scale, height: 44 * scale)
                        .opacity(showsStaleState ? 0.58 : 1)
                }

                // 中央: ロゴアイコン（大きく24px）
                AgentBrandIconView(provider: item.provider, size: 24 * scale)
            }
            .frame(width: 46 * scale, height: 46 * scale)

            // 2. 円のした: 5hリセットまでの時間
            if let timeText = AgentQuotaDisplay.resetLabel(for: item.primaryWindow, now: now) {
                Text(timeText)
                    .font(.system(size: 11 * scale, weight: .bold).monospacedDigit())
                    .foregroundStyle(AgentQuotaStyle.resetColor(for: item.primaryWindow, now: now))
            } else if item.status == "rate_limited" {
                Text("制限中")
                    .font(.system(size: 10.5 * scale, weight: .bold))
                    .foregroundStyle(Color.red)
            } else if let creds = item.credits {
                Text("$\(String(format: "%.1f", creds))")
                    .font(.system(size: 11 * scale, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.cyan)
            } else {
                Text("-")
                    .font(.system(size: 11 * scale, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.3))
            }

            if showsWeekly {
                // 3. ミニバー (1w週間枠: 線幅2.5px)
                if let weekly = item.weeklyWindow {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 2.5 * scale)
                            Capsule()
                                .fill(AgentQuotaStyle.gaugeColor(remainingPct: weekly.remainingPct))
                                .frame(
                                    width: max(2, geo.size.width * CGFloat(weekly.remainingPct / 100.0)),
                                    height: 2.5 * scale
                                )
                                .opacity(showsStaleState ? 0.58 : 1)
                        }
                    }
                    .frame(width: 36 * scale, height: 2.5 * scale)
                    .padding(.top, 1)
                } else if item.credits != nil {
                    Capsule()
                        .fill(Color.cyan.opacity(0.6))
                        .frame(width: 36 * scale, height: 2.5 * scale)
                        .opacity(showsStaleState ? 0.58 : 1)
                        .padding(.top, 1)
                } else {
                    Spacer().frame(height: 2.5 * scale)
                }

                // 4. バーのした: 1wリセットまでの時間
                if let weekText = AgentQuotaDisplay.resetLabel(for: item.weeklyWindow, now: now) {
                    Text(weekText)
                        .font(.system(size: 8.5 * scale, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.40))
                } else if item.credits != nil {
                    Text("残高")
                        .font(.system(size: 8.5 * scale, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.35))
                } else {
                    Text("-")
                        .font(.system(size: 8.5 * scale, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.25))
                }
            }

            if showsStaleState {
                Text(AgentQuotaDisplay.ageLabel(for: item.dataTimestamp, now: now) ?? "Stale")
                    .font(.system(size: 7 * scale, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.orange.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
    }
}

/// 固定 6 プロバイダーのゲージ列。
struct AgentQuotaGaugeRow: View {
    let providers: [AgentQuotaProviderItem]
    let now: Date
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 3) {
            ForEach(providers.prefix(AgentQuotaProviderItem.homeProviderIDs.count)) { item in
                AgentQuotaMiniGauge(item: item, now: now, scale: scale)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 展開時の週次制限バー一覧。
struct AgentQuotaWeeklyBars: View {
    let providers: [AgentQuotaProviderItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("週間制限 (Weekly Window)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)

            ForEach(providers.filter { $0.weeklyWindow != nil }) { item in
                if let weekly = item.weeklyWindow {
                    HStack(spacing: 8) {
                        Text(item.scopeLabel.isEmpty ? item.provider.uppercased() : item.scopeLabel)
                            .font(.system(size: 10, weight: .medium))
                            .frame(width: 80, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(height: 5)
                                Capsule()
                                    .fill(AgentQuotaStyle.gaugeGradient(remainingPct: weekly.remainingPct))
                                    .frame(width: max(2, geo.size.width * CGFloat(weekly.remainingPct / 100.0)), height: 5)
                            }
                        }
                        .frame(height: 5)
                        Text("残り \(Int(weekly.remainingPct))%")
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundStyle(AgentQuotaStyle.gaugeColor(remainingPct: weekly.remainingPct))
                            .frame(width: 50, alignment: .trailing)
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }
}
