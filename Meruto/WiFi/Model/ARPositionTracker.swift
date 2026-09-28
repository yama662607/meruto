import ARKit
import Foundation
import RealityKit
import SwiftUI
import simd

/// ARKit のワールドトラッキングで端末の床面上の位置 (m) と向きを追う。
/// 座標は開始地点が原点、x が右、y が開始時に向いていた方向 (奥)。
@MainActor @Observable
final class ARPositionTracker {
    struct Pose: Equatable {
        var x: Double
        var y: Double
        /// 上 (奥) を 0 とした時計回りのラジアン。
        var heading: Double
    }

    enum Tracking: Equatable {
        case notStarted
        case initializing
        case normal
        case limited(String)
        case unavailable
    }

    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    private(set) var pose: Pose?
    private(set) var tracking: Tracking = .notStarted
    /// 最初に記録を始めたときに作る (起動時にカメラ周りを用意しない)。
    private(set) var arView: ARView?

    @ObservationIgnored private let latest = LatestFrame()
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    func start() {
        guard Self.isSupported else {
            tracking = .unavailable
            return
        }
        let arView = self.arView ?? makeARView()
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = []
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        tracking = .initializing
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func makeARView() -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disablePersonOcclusion, .disableGroundingShadows]
        view.session.delegate = latest
        arView = view
        return view
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        arView?.session.pause()
        tracking = .notStarted
        pose = nil
    }

    private func poll() {
        guard let snapshot = latest.read() else { return }
        switch snapshot.state {
        case .normal: tracking = .normal
        case .notAvailable: tracking = .unavailable
        case .limited(let reason):
            tracking =
                switch reason {
                case .initializing, .relocalizing: .initializing
                case .excessiveMotion: .limited("ゆっくり動かしてください")
                case .insufficientFeatures: .limited("周囲が暗いか模様が少なすぎます")
                @unknown default: .limited("追跡が不安定です")
                }
        }
        let t = snapshot.transform
        // ARKit: x 右 / y 上 / z 手前。床面の地図では奥 (-z) を上にする。
        let forward = -simd_make_float3(t.columns.2)
        pose = Pose(
            x: Double(t.columns.3.x),
            y: Double(-t.columns.3.z),
            heading: Double(atan2(forward.x, -forward.z)))
    }
}

/// デリゲートは ARKit のスレッドから毎フレーム呼ばれるので、最新値だけをロック付きで持つ。
private final class LatestFrame: NSObject, ARSessionDelegate, @unchecked Sendable {
    struct Snapshot {
        var transform: simd_float4x4
        var state: ARCamera.TrackingState
    }

    private let lock = NSLock()
    private var snapshot: Snapshot?

    func read() -> Snapshot? {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let value = Snapshot(transform: frame.camera.transform, state: frame.camera.trackingState)
        lock.lock()
        snapshot = value
        lock.unlock()
    }
}

/// AR のカメラ映像 (歩行モードで追跡できているかを目で確かめる用)。
struct ARCameraPreview: UIViewRepresentable {
    let arView: ARView

    func makeUIView(context: Context) -> ARView { arView }
    func updateUIView(_ uiView: ARView, context: Context) {}
}
