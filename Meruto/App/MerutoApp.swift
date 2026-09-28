import SwiftUI

@main
struct MerutoApp: App {
    @State private var monitor: DeviceMonitor
    @State private var meter: WiFiMeter
    @State private var surveys: SurveyStore
    @State private var quota = AgentQuotaStore()
    @State private var recorder: SurveyRecorder

    init() {
        let monitor = DeviceMonitor()
        let meter = WiFiMeter()
        let surveys = SurveyStore()
        meter.onSample = { [monitor] score, rtt, ssid in
            monitor.latestWiFi = (score, rtt, ssid, Date())
        }
        _monitor = State(initialValue: monitor)
        _meter = State(initialValue: meter)
        _surveys = State(initialValue: surveys)
        _recorder = State(initialValue: SurveyRecorder(meter: meter, store: surveys, tracker: ARPositionTracker()))
    }

    var body: some Scene {
        WindowGroup {
            RootView(monitor: monitor, meter: meter, surveys: surveys, quota: quota, recorder: recorder)
                .preferredColorScheme(.dark)
        }
    }
}
