import MerutoCore
import SwiftUI

struct DashboardHeader: View {
    let monitor: DeviceMonitor

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MERUTO")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(
                            LinearGradient(colors: [.white, Theme.cyan], startPoint: .leading, endPoint: .trailing)
                        )
                        .shadow(color: Theme.cyan.opacity(0.5), radius: 8)
                    Text("\(UIDevice.current.model) · \(monitor.system.modelIdentifier) · iOS \(UIDevice.current.systemVersion)")
                        .font(Theme.mono(10.5, weight: .medium))
                        .foregroundStyle(Theme.label)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(context.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
                        .font(Theme.mono(18, weight: .bold))
                        .foregroundStyle(.white)
                    if let boot = monitor.system.bootDate {
                        Text("UPTIME \(Format.uptime(context.date.timeIntervalSince(boot)))")
                            .font(Theme.mono(9.5, weight: .semibold))
                            .foregroundStyle(Theme.faint)
                    }
                }
            }
            .padding(.top, 8)
        }
    }
}
