import QuartzCore
import UIKit

/// 画面の実際のリフレッシュ回数を数える (ProMotion なら最大 120Hz)。
@MainActor
final class FPSCounter: NSObject {
    private var link: CADisplayLink?
    private var frames = 0
    private var windowStart: CFTimeInterval = 0
    private let onUpdate: @MainActor (Double) -> Void

    init(onUpdate: @escaping @MainActor (Double) -> Void) {
        self.onUpdate = onUpdate
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        let maxFPS = Float(UIScreen.main.maximumFramesPerSecond)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: maxFPS, preferred: maxFPS)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        if windowStart == 0 { windowStart = link.timestamp }
        frames += 1
        let elapsed = link.timestamp - windowStart
        if elapsed >= 1 {
            onUpdate(Double(frames) / elapsed)
            frames = 0
            windowStart = link.timestamp
        }
    }

    func invalidate() {
        link?.invalidate()
        link = nil
    }
}
