import Foundation
import MerutoCore

/// 電波マップの記録係。
/// - 歩行モード: AR の位置が 0.35m 以上動くたびに、その時点のスコアを記録する。
/// - タップモード: タップした地点で 3 秒間測り、その平均を記録する。
@MainActor @Observable
final class SurveyRecorder {
    static let manualDuration: TimeInterval = 3

    private(set) var isRecording = false
    /// タップモードで測定中の地点と進み具合 (0...1)。
    private(set) var pendingManual: (x: Double, y: Double, progress: Double)?

    let meter: WiFiMeter
    let store: SurveyStore
    let tracker: ARPositionTracker

    @ObservationIgnored private var walkTask: Task<Void, Never>?
    @ObservationIgnored private var manualTask: Task<Void, Never>?

    init(meter: WiFiMeter, store: SurveyStore, tracker: ARPositionTracker) {
        self.meter = meter
        self.store = store
        self.tracker = tracker
    }

    // MARK: 歩行モード

    func startWalk() {
        guard !isRecording else { return }
        if store.current?.mode != .walk || !(store.current?.points.isEmpty ?? true) {
            store.create(mode: .walk)
        }
        guard let surveyID = store.currentID else { return }
        isRecording = true
        tracker.start()
        walkTask = Task { [weak self] in
            var last: (x: Double, y: Double)?
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, let pose = self.tracker.pose, self.tracker.tracking == .normal,
                    let score = self.meter.smoothedScore, self.meter.state == .measuring
                else { continue }
                // 同じ場所に留まっている間は点を重ねない。
                if let previous = last, hypot(pose.x - previous.x, pose.y - previous.y) < 0.35 { continue }
                self.record(x: pose.x, y: pose.y, score: score, into: surveyID)
                last = (pose.x, pose.y)
            }
        }
    }

    func stopWalk() {
        walkTask?.cancel()
        walkTask = nil
        tracker.stop()
        isRecording = false
        store.save()
    }

    // MARK: タップモード

    func startManualNewSurvey(width: Double, depth: Double) {
        store.create(mode: .manual, roomWidth: width, roomDepth: depth)
    }

    func measureManual(atX x: Double, y: Double) {
        guard pendingManual == nil, let survey = store.current, survey.mode == .manual else { return }
        let surveyID = survey.id
        pendingManual = (x, y, 0)
        manualTask = Task { [weak self] in
            guard let self else { return }
            var scores: [Double] = []
            let start = Date()
            while Date().timeIntervalSince(start) < Self.manualDuration, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if let score = self.meter.stats.score { scores.append(score) }
                self.pendingManual = (x, y, min(1, Date().timeIntervalSince(start) / Self.manualDuration))
            }
            if !scores.isEmpty, !Task.isCancelled {
                let average = scores.reduce(0, +) / Double(scores.count)
                self.record(x: x, y: y, score: average, into: surveyID)
                self.store.save()
            }
            self.pendingManual = nil
        }
    }

    func cancelManual() {
        manualTask?.cancel()
        manualTask = nil
        pendingManual = nil
    }

    private func record(x: Double, y: Double, score: Double, into surveyID: UUID) {
        let stats = meter.stats
        store.append(
            SurveyPoint(
                x: x, y: y, score: score, rtt: stats.medianRTT, jitter: stats.jitter, loss: stats.loss,
                bssid: meter.bssid),
            to: surveyID)
    }
}
