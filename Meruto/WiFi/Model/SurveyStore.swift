import Foundation
import MerutoCore
import WidgetKit

/// 電波マップの保存と一覧。App Group に置き、ウィジェットが最新のマップを描けるようにする。
@MainActor @Observable
final class SurveyStore {
    private(set) var surveys: [Survey] = []
    var currentID: UUID?

    init() {
        surveys = SharedContainer.readJSON([Survey].self, from: SharedContainer.File.surveys) ?? []
        currentID = surveys.first?.id
    }

    var current: Survey? {
        guard let currentID else { return nil }
        return surveys.first { $0.id == currentID }
    }

    @discardableResult
    func create(mode: SurveyMode, roomWidth: Double = 8, roomDepth: Double = 6) -> Survey {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        let survey = Survey(
            name: "\(mode == .walk ? "ウォーク" : "タップ") \(formatter.string(from: Date()))", mode: mode,
            roomWidth: roomWidth, roomDepth: roomDepth)
        surveys.insert(survey, at: 0)
        currentID = survey.id
        save()
        return survey
    }

    func append(_ point: SurveyPoint, to id: UUID) {
        guard let index = surveys.firstIndex(where: { $0.id == id }) else { return }
        surveys[index].points.append(point)
        surveys[index].updatedAt = Date()
        // 歩行中は頻繁に呼ばれるので、保存は 10 点ごとにまとめる。
        if surveys[index].points.count % 10 == 0 { save() }
    }

    func removeLastPoint(from id: UUID) {
        guard let index = surveys.firstIndex(where: { $0.id == id }), !surveys[index].points.isEmpty else { return }
        surveys[index].points.removeLast()
        save()
    }

    func update(_ survey: Survey) {
        guard let index = surveys.firstIndex(where: { $0.id == survey.id }) else { return }
        surveys[index] = survey
        save()
    }

    func delete(_ id: UUID) {
        surveys.removeAll { $0.id == id }
        if currentID == id { currentID = surveys.first?.id }
        save()
    }

    func save() {
        SharedContainer.writeJSON(surveys, to: SharedContainer.File.surveys)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.wifi)
    }
}
