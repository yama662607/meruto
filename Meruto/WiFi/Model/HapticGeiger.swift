import UIKit

/// ガイガーカウンターのように、電波が強いほど速く振動させる。画面を見ずに歩き回って探せる。
@MainActor
final class HapticGeiger {
    private var task: Task<Void, Never>?
    private let generator = UIImpactFeedbackGenerator(style: .rigid)

    func start(score: @escaping @MainActor () -> Double?) {
        guard task == nil else { return }
        generator.prepare()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let value = score() else {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
                // 100 点で 0.1 秒間隔、0 点で 1.2 秒間隔。
                let interval = 1.2 - 1.1 * min(1, max(0, value / 100))
                self?.generator.impactOccurred(intensity: 0.4 + 0.6 * value / 100)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1e9))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
