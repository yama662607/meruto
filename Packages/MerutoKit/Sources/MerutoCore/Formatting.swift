import Foundation

public enum Format {
    /// 1024 進のバイト数。"12.3 GB" のように有効数字 3 桁前後で出す。
    public static func bytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = max(0, value)
        var index = 0
        while v >= 1024, index < units.count - 1 {
            v /= 1024
            index += 1
        }
        return "\(significant(v, index: index)) \(units[index])"
    }

    public static func bytes(_ value: UInt64) -> String { bytes(Double(value)) }

    /// 通信速度。"1.2 MB/s"
    public static func rate(_ bytesPerSecond: Double) -> String {
        bytes(bytesPerSecond) + "/s"
    }

    /// 通信速度 (ビット)。"12.3 Mbps"
    public static func bitRate(bitsPerSecond: Double) -> String {
        let units = ["bps", "Kbps", "Mbps", "Gbps"]
        var v = max(0, bitsPerSecond)
        var index = 0
        while v >= 1000, index < units.count - 1 {
            v /= 1000
            index += 1
        }
        return "\(significant(v, index: index)) \(units[index])"
    }

    /// 0...1 を "42%" にする。
    public static func percent(_ fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    /// ミリ秒。"3.2 ms" / "120 ms"
    public static func milliseconds(_ seconds: Double) -> String {
        let ms = seconds * 1000
        if ms < 10 { return String(format: "%.1f ms", ms) }
        return "\(Int(ms.rounded())) ms"
    }

    /// 稼働時間。"3d 4h" / "5h 12m" / "8m"
    public static func uptime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let hours = minutes / 60
        let days = hours / 24
        if days > 0 { return "\(days)d \(hours % 24)h" }
        if hours > 0 { return "\(hours)h \(minutes % 60)m" }
        return "\(minutes)m"
    }

    private static func significant(_ v: Double, index: Int) -> String {
        if index == 0 { return "\(Int(v.rounded()))" }
        if v < 10 { return String(format: "%.1f", v) }
        return "\(Int(v.rounded()))"
    }
}
