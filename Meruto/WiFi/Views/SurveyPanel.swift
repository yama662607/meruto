import MerutoCore
import SwiftUI

struct SurveyPanel: View {
    let meter: WiFiMeter
    let store: SurveyStore
    let recorder: SurveyRecorder
    var mapHeight: CGFloat
    @State private var mode: SurveyMode = ARPositionTracker.isSupported ? .walk : .manual
    @State private var showingList = false
    @State private var showingRoomSetup = false
    @State private var roomWidth = 8.0
    @State private var roomDepth = 6.0

    var body: some View {
        Panel(title: "Coverage Map", icon: "map", tint: Theme.yellow) {
            Button {
                showingList = true
            } label: {
                Label("\(store.surveys.count)", systemImage: "square.stack")
                    .font(Theme.mono(10, weight: .bold))
                    .foregroundStyle(Theme.label)
            }
            .disabled(recorder.isRecording)
        } content: {
            Picker("モード", selection: $mode) {
                Label("歩いて測る (AR)", systemImage: "figure.walk").tag(SurveyMode.walk)
                Label("タップで測る", systemImage: "hand.tap").tag(SurveyMode.manual)
            }
            .pickerStyle(.segmented)
            .disabled(recorder.isRecording)

            if mode == .walk && !ARPositionTracker.isSupported {
                Label("この端末ではARが使えません。タップで測るモードを使ってください。", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.orange)
            }

            let survey = displayedSurvey
            ZStack(alignment: .topTrailing) {
                SurveyMapView(
                    survey: survey,
                    livePose: recorder.isRecording ? recorder.tracker.pose : nil,
                    pending: recorder.pendingManual,
                    onTap: mode == .manual && store.current?.mode == .manual
                        ? { x, y in recorder.measureManual(atX: x, y: y) } : nil)
                if recorder.isRecording, let arView = recorder.tracker.arView {
                    VStack(alignment: .trailing, spacing: 6) {
                        ARCameraPreview(arView: arView)
                            .frame(width: 96, height: 128)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cyan.opacity(0.5), lineWidth: 1))
                        trackingBadge
                    }
                    .padding(8)
                }
            }
            .frame(height: mapHeight)

            QualityLegend()
            controls
            SurveySummaryView(survey: survey)
        }
        .sheet(isPresented: $showingList) {
            SurveyListView(store: store) { selected in
                mode = selected.mode
                store.currentID = selected.id
            }
        }
        .sheet(isPresented: $showingRoomSetup) {
            RoomSetupSheet(width: $roomWidth, depth: $roomDepth) {
                recorder.startManualNewSurvey(width: roomWidth, depth: roomDepth)
            }
            .presentationDetents([.height(300)])
        }
        .onAppear {
            if let current = store.current { mode = current.mode }
        }
        .onDisappear {
            if recorder.isRecording { recorder.stopWalk() }
            recorder.cancelManual()
        }
    }

    /// 選んだモードの現在のマップ。無ければ空のマップを見せる。
    private var displayedSurvey: Survey {
        if let current = store.current, current.mode == mode { return current }
        return Survey(name: "", mode: mode, roomWidth: roomWidth, roomDepth: roomDepth)
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            switch mode {
            case .walk:
                Button {
                    recorder.isRecording ? recorder.stopWalk() : recorder.startWalk()
                } label: {
                    Label(recorder.isRecording ? "記録を停止" : "記録を開始", systemImage: recorder.isRecording ? "stop.fill" : "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(recorder.isRecording ? Theme.red : Theme.cyan)
                .disabled(!ARPositionTracker.isSupported || meter.state != .measuring && !recorder.isRecording)
            case .manual:
                Button {
                    showingRoomSetup = true
                } label: {
                    Label(store.current?.mode == .manual ? "新しい部屋" : "部屋を設定して開始", systemImage: "square.dashed")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.cyan)
            }
            if let current = store.current, current.mode == mode, !current.points.isEmpty, !recorder.isRecording {
                Button {
                    store.removeLastPoint(from: current.id)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .font(.system(size: 14, weight: .bold))
        .controlSize(.large)
    }

    @ViewBuilder
    private var trackingBadge: some View {
        let (text, color): (String, Color) =
            switch recorder.tracker.tracking {
            case .normal: ("TRACKING", Theme.green)
            case .initializing: ("周囲を映してください", Theme.yellow)
            case .limited(let reason): (reason, Theme.orange)
            case .unavailable: ("AR 利用不可", Theme.red)
            case .notStarted: ("—", Theme.faint)
            }
        Text(text)
            .font(Theme.mono(9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.7)))
    }
}
