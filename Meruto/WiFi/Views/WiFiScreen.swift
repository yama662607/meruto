import MerutoCore
import SwiftUI

/// Wi-Fi 電波測定器。上半分がリアルタイムのメーター、下半分が部屋の電波マップ。
struct WiFiScreen: View {
    let meter: WiFiMeter
    let store: SurveyStore
    let recorder: SurveyRecorder
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(SharedContainer.Key.hapticGeiger) private var geigerEnabled = false
    @State private var geiger = HapticGeiger()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ScreenTitle(title: "Wi-Fi METER", subtitle: subtitle)
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 12) {
                            MeterPanel(meter: meter, geigerEnabled: $geigerEnabled)
                            ScopePanel(meter: meter)
                        }
                        SurveyPanel(meter: meter, store: store, recorder: recorder, mapHeight: 520)
                    }
                } else {
                    MeterPanel(meter: meter, geigerEnabled: $geigerEnabled)
                    ScopePanel(meter: meter)
                    SurveyPanel(meter: meter, store: store, recorder: recorder, mapHeight: 380)
                }
                MethodNote()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            meter.acquire()
            updateGeiger()
        }
        .onDisappear {
            meter.release()
            geiger.stop()
        }
        .onChange(of: geigerEnabled) { updateGeiger() }
    }

    private var subtitle: String {
        [meter.ssid ?? "Wi-Fi", meter.gateway.map { "GW \($0)" }].compactMap { $0 }.joined(separator: " · ")
    }

    private func updateGeiger() {
        if geigerEnabled {
            geiger.start { [meter] in meter.smoothedScore }
        } else {
            geiger.stop()
        }
    }
}
