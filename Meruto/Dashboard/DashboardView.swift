import MerutoCore
import MerutoProbes
import SwiftUI
import UIKit

struct DashboardView: View {
    let monitor: DeviceMonitor
    let quotaStore: AgentQuotaStore
    var onOpenWiFi: () -> Void
    var onOpenAI: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                DashboardHeader(monitor: monitor)
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 12) {
                            CPUCard(monitor: monitor)
                            NetworkCard(monitor: monitor)
                            HStack(alignment: .top, spacing: 12) {
                                BatteryCard(monitor: monitor)
                                ThermalCard(monitor: monitor)
                            }
                        }
                        VStack(spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                MemoryCard(monitor: monitor)
                                GPUCard(monitor: monitor)
                            }
                            HStack(alignment: .top, spacing: 12) {
                                StorageCard(monitor: monitor)
                                WiFiCard(monitor: monitor, onOpen: onOpenWiFi)
                            }
                            AIQuotaCard(store: quotaStore, onOpen: onOpenAI)
                        }
                    }
                } else {
                    CPUCard(monitor: monitor)
                    HStack(alignment: .top, spacing: 12) {
                        MemoryCard(monitor: monitor)
                        GPUCard(monitor: monitor)
                    }
                    NetworkCard(monitor: monitor)
                    HStack(alignment: .top, spacing: 12) {
                        BatteryCard(monitor: monitor)
                        ThermalCard(monitor: monitor)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        StorageCard(monitor: monitor)
                        WiFiCard(monitor: monitor, onOpen: onOpenWiFi)
                    }
                    AIQuotaCard(store: quotaStore, onOpen: onOpenAI)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
}
