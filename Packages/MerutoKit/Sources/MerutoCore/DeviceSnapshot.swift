import Foundation

/// アプリが最後に測った値。App Group に置いてウィジェットが読む
/// (ウィジェットは自分で読める値は自分で読み、読めない値だけこれで補う)。
public struct DeviceSnapshot: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var cpu: Double?
    public var memoryUsed: UInt64?
    public var memoryTotal: UInt64?
    public var storageUsed: UInt64?
    public var storageTotal: UInt64?
    public var batteryLevel: Double?
    public var chargeState: ChargeState
    public var thermal: ThermalLevel
    public var lowPowerMode: Bool
    public var download: Double?
    public var upload: Double?
    public var wifiScore: Double?
    public var wifiRTT: TimeInterval?
    public var wifiSSID: String?
    public var wifiMeasuredAt: Date?

    public init(
        timestamp: Date = Date(), cpu: Double? = nil, memoryUsed: UInt64? = nil, memoryTotal: UInt64? = nil,
        storageUsed: UInt64? = nil, storageTotal: UInt64? = nil, batteryLevel: Double? = nil,
        chargeState: ChargeState = .unknown, thermal: ThermalLevel = .nominal, lowPowerMode: Bool = false,
        download: Double? = nil, upload: Double? = nil, wifiScore: Double? = nil, wifiRTT: TimeInterval? = nil,
        wifiSSID: String? = nil, wifiMeasuredAt: Date? = nil
    ) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
        self.storageUsed = storageUsed
        self.storageTotal = storageTotal
        self.batteryLevel = batteryLevel
        self.chargeState = chargeState
        self.thermal = thermal
        self.lowPowerMode = lowPowerMode
        self.download = download
        self.upload = upload
        self.wifiScore = wifiScore
        self.wifiRTT = wifiRTT
        self.wifiSSID = wifiSSID
        self.wifiMeasuredAt = wifiMeasuredAt
    }

    public var memoryFraction: Double? {
        guard let used = memoryUsed, let total = memoryTotal, total > 0 else { return nil }
        return Double(used) / Double(total)
    }

    public var storageFraction: Double? {
        guard let used = storageUsed, let total = storageTotal, total > 0 else { return nil }
        return Double(used) / Double(total)
    }
}
