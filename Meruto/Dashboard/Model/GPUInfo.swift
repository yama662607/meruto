import Metal

/// Metal から読める GPU の情報。iOS は GPU 使用率を公開していないので、仕様と
/// このアプリが確保している GPU メモリを出す。
struct GPUInfo {
    var name: String
    var family: String
    var recommendedWorkingSet: UInt64
    var supportsRaytracing: Bool

    static func read() -> GPUInfo {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return GPUInfo(name: "—", family: "—", recommendedWorkingSet: 0, supportsRaytracing: false)
        }
        let families: [(MTLGPUFamily, String)] = [
            (.apple10, "Apple 10"), (.apple9, "Apple 9"), (.apple8, "Apple 8"), (.apple7, "Apple 7"), (.apple6, "Apple 6"),
            (.apple5, "Apple 5"), (.apple4, "Apple 4"),
        ]
        let family = families.first { device.supportsFamily($0.0) }?.1 ?? "Apple"
        return GPUInfo(
            name: device.name,
            family: family,
            recommendedWorkingSet: device.recommendedMaxWorkingSetSize,
            supportsRaytracing: device.supportsRaytracing)
    }
}
