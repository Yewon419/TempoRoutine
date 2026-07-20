// 템포루틴 — 생리 기록 중앙 쓰기 경로 (Phase 0 ⑦)
// 모든 PeriodDay 추가/삭제는 여기로 — 로컬 항상 기록 + 연동 시 HK 미러(§5.7).
// 에피소드 첫날 플래그(HKMetadataKeyMenstrualCycleStart)는 경계 변화 시 해당 샘플만 재기록.

import Foundation
import SwiftData
import TempoCore

@MainActor
enum PeriodStore {

    /// 추가: 미래 금지·dedup=day는 호출측 UI 가드와 이중으로 여기서도 보장.
    static func add(days: [Date], context: ModelContext, existing: [PeriodDay]) async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let existingDays = Set(existing.map(\.day))
        let newDays = days.map { cal.startOfDay(for: $0) }
            .filter { $0 <= today && !existingDays.contains($0) }
        guard !newDays.isEmpty else { return }

        var newRecords: [PeriodDay] = []
        for day in Set(newDays).sorted() {
            let record = PeriodDay(day: day)
            context.insert(record)
            newRecords.append(record)
        }
        HealthMirror.clearTombstones(days: newDays)   // 재추가 = 재부활 허용

        let before = Set(PeriodMath.episodeStarts(days: Array(existingDays)))
        let all = existing + newRecords
        let after = Set(PeriodMath.episodeStarts(days: all.map(\.day)))

        // 새 레코드 write (첫날 여부 = after 기준)
        for record in newRecords {
            if let uuid = await HealthMirror.shared.writeSample(day: record.day,
                                                               isCycleStart: after.contains(record.day)) {
                record.origin = .appAuthored
                record.healthKitUUID = uuid
            }
        }
        // 경계 변화 재기록: 기존 appAuthored 샘플 중 첫날 여부가 바뀐 것만
        await reconcile(records: existing, before: before, after: after)
    }

    /// 삭제: appAuthored는 HK 샘플도 삭제, imported는 로컬만(+재부활 방지 툼스톤).
    static func remove(records: [PeriodDay], context: ModelContext, all: [PeriodDay]) async {
        guard !records.isEmpty else { return }
        let removedIDs = Set(records.map(\.id))
        let before = Set(PeriodMath.episodeStarts(days: all.map(\.day)))
        let survivors = all.filter { !removedIDs.contains($0.id) }
        let after = Set(PeriodMath.episodeStarts(days: survivors.map(\.day)))

        var uuidsToDelete: [UUID] = []
        for record in records {
            switch record.origin {
            case .appAuthored:
                if let uuid = record.healthKitUUID { uuidsToDelete.append(uuid) }
            case .healthKitImported:
                HealthMirror.addTombstone(day: record.day)   // Health 원본은 못 지움 — 로컬 편집만(§5.7)
            case .local:
                break
            }
            context.delete(record)
        }
        await HealthMirror.shared.deleteSamples(uuids: uuidsToDelete)
        await reconcile(records: survivors, before: before, after: after)
    }

    /// 첫날 여부가 바뀐 appAuthored 샘플 재기록(삭제 후 재작성) — 대상은 경계 변화분만.
    private static func reconcile(records: [PeriodDay], before: Set<Date>, after: Set<Date>) async {
        for record in records where record.origin == .appAuthored {
            let was = before.contains(record.day)
            let now = after.contains(record.day)
            guard was != now, let oldUUID = record.healthKitUUID else { continue }
            await HealthMirror.shared.deleteSamples(uuids: [oldUUID])
            record.healthKitUUID = await HealthMirror.shared.writeSample(day: record.day, isCycleStart: now)
        }
    }
}
