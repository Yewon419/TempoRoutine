// 템포루틴 — @Model ↔ DTO 변환·병합 (MASTER §5.5.1)
// 재임포트 dedup: PeriodDay=day / DailyCheckIn=day / 나머지=UUID (보존이라 완료·서브태스크 재연결).
// HK 재기록 없음(로컬 복원만 — §5.5.1). 전체 삭제 undo = 삭제 직전 봉투 스냅샷 재병합.

import Foundation
import SwiftData
import TempoCore

enum AppSettings {
    private static let trackedSignalsKey = "trackedSignals"

    /// 온보딩(⑧) 전 기본값: 체크인 카드 노출 구성과 일치(수면·한 줄)
    static var trackedSignals: TrackedSignals {
        get {
            guard let data = UserDefaults.standard.data(forKey: trackedSignalsKey),
                  let decoded = try? JSONDecoder().decode(TrackedSignals.self, from: data) else {
                return TrackedSignals(sleep: true, pain: false, appetite: false, note: true)
            }
            return decoded
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: trackedSignalsKey)
        }
    }
}

struct StoreArrays {
    let periodDays: [PeriodDay]
    let schedules: [ScheduleItem]
    let inputs: [InputItem]
    let outputs: [OutputItem]
    let completions: [ItemCompletion]
    let checkIns: [DailyCheckIn]
}

enum ExportImport {

    // ── 내보내기: @Model → 봉투 ──
    static func buildEnvelope(from store: StoreArrays) -> ExportEnvelopeV1 {
        ExportEnvelopeV1(
            exportedAt: .now,
            periodDays: store.periodDays.map {
                PeriodDayDTO(day: ExportCodec.dayString($0.day), origin: $0.origin.rawValue,
                             healthKitUUID: $0.healthKitUUID)
            },
            scheduleItems: store.schedules.map {
                ScheduleItemDTO(id: $0.id, title: $0.title,
                                date: $0.isAllDay ? ExportCodec.dayString($0.date) : ExportCodec.instantString($0.date),
                                isAllDay: $0.isAllDay, repeatRule: $0.repeatRule, createdAt: $0.createdAt,
                                endDate: $0.endDate.map { ExportCodec.instantString($0) },
                                reminderMinutes: $0.reminderMinutes >= 0 ? $0.reminderMinutes : nil)
            },
            inputItems: store.inputs.map {
                InputItemDTO(id: $0.id, title: $0.title, category: $0.category,
                             schedule: $0.schedule, createdAt: $0.createdAt)
            },
            outputItems: store.outputs.map { item in
                OutputItemDTO(id: item.id, title: item.title, schedule: item.schedule,
                              progressKind: item.progressKind,
                              subtasks: (item.subtasks ?? []).sorted { $0.order < $1.order }.map {
                                  OutputSubtaskDTO(id: $0.id, title: $0.title, isDone: $0.isDone, order: $0.order)
                              },
                              targetSessions: item.targetSessions, loggedSessions: item.loggedSessions,
                              percent: item.percent, createdAt: item.createdAt)
            },
            completions: store.completions.map {
                ItemCompletionDTO(id: $0.id, itemID: $0.itemID,
                                  occurredOn: ExportCodec.dayString($0.occurredOn), completedAt: $0.completedAt)
            },
            checkIns: store.checkIns.map {
                DailyCheckInDTO(id: $0.id, day: ExportCodec.dayString($0.day), energy: $0.energy,
                                mood: $0.mood, sleep: $0.sleep, pain: $0.pain, appetite: $0.appetite,
                                note: $0.note, createdAt: $0.createdAt)
            },
            trackedSignals: AppSettings.trackedSignals
        )
    }

    // ── 재임포트: merge·dedup → 추가 건수 ──
    @discardableResult
    static func merge(_ envelope: ExportEnvelopeV1, into context: ModelContext, existing store: StoreArrays) -> Int {
        var added = 0
        let existingDays = Set(store.periodDays.map(\.day))
        for dto in envelope.periodDays {
            guard let day = ExportCodec.day(from: dto.day), !existingDays.contains(day) else { continue }
            context.insert(PeriodDay(day: day, origin: PeriodDayOrigin(rawValue: dto.origin) ?? .local,
                                     healthKitUUID: dto.healthKitUUID))
            added += 1
        }

        let scheduleIDs = Set(store.schedules.map(\.id))
        for dto in envelope.scheduleItems where !scheduleIDs.contains(dto.id) {
            let date = dto.isAllDay ? ExportCodec.day(from: dto.date) : ExportCodec.instant(from: dto.date)
            guard let date else { continue }
            let item = ScheduleItem(title: dto.title, date: date, isAllDay: dto.isAllDay, repeatRule: dto.repeatRule,
                                    endDate: dto.endDate.flatMap { ExportCodec.instant(from: $0) },
                                    reminderMinutes: dto.reminderMinutes ?? -1)
            item.id = dto.id
            item.createdAt = dto.createdAt
            context.insert(item)
            added += 1
            // 백업 복원 일정의 알림 재스케줄(HK 재기록 금지 원칙과 달리 노티는 로컬 파생 상태라 재생성이 맞음)
            ScheduleReminder.schedule(id: item.id, title: item.title, date: item.date,
                                      isAllDay: item.isAllDay, repeatRule: item.repeatRule,
                                      reminderMinutes: item.reminderMinutes)
        }

        let inputIDs = Set(store.inputs.map(\.id))
        for dto in envelope.inputItems where !inputIDs.contains(dto.id) {
            let item = InputItem(title: dto.title, category: dto.category, schedule: dto.schedule)
            item.id = dto.id
            item.createdAt = dto.createdAt
            context.insert(item)
            added += 1
        }

        let outputIDs = Set(store.outputs.map(\.id))
        for dto in envelope.outputItems where !outputIDs.contains(dto.id) {
            let item = OutputItem(title: dto.title, schedule: dto.schedule, progressKind: dto.progressKind)
            item.id = dto.id
            item.createdAt = dto.createdAt
            item.targetSessions = dto.targetSessions
            item.loggedSessions = dto.loggedSessions
            item.percent = dto.percent
            item.subtasks = dto.subtasks.map { sub in
                let subtask = OutputSubtask(title: sub.title, order: sub.order)
                subtask.id = sub.id
                subtask.isDone = sub.isDone
                return subtask
            }
            context.insert(item)
            added += 1
        }

        let completionIDs = Set(store.completions.map(\.id))
        for dto in envelope.completions where !completionIDs.contains(dto.id) {
            guard let occurredOn = ExportCodec.day(from: dto.occurredOn) else { continue }
            let completion = ItemCompletion(itemID: dto.itemID, occurredOn: occurredOn)
            completion.id = dto.id
            completion.completedAt = dto.completedAt
            context.insert(completion)
            added += 1
        }

        let checkInDays = Set(store.checkIns.map(\.day))
        for dto in envelope.checkIns {
            guard let day = ExportCodec.day(from: dto.day), !checkInDays.contains(day) else { continue }
            guard dto.energy >= 1, dto.mood >= 1 else { continue }   // §5.5 계약(필수 1...5) 위반 행 방어
            let record = DailyCheckIn(day: day, energy: dto.energy, mood: dto.mood)
            record.id = dto.id
            record.sleep = dto.sleep
            record.pain = dto.pain
            record.appetite = dto.appetite
            record.note = dto.note
            record.createdAt = dto.createdAt
            context.insert(record)
            added += 1
        }
        return added
    }

    // ── 전체 삭제 (§8.2.6 — undo는 호출측이 스냅샷으로. 알림은 undo 미복원 — 재저장 시 재스케줄) ──
    static func wipeAll(_ store: StoreArrays, context: ModelContext) {
        store.schedules.forEach { ScheduleReminder.cancel(id: $0.id) }
        store.periodDays.forEach { context.delete($0) }
        store.schedules.forEach { context.delete($0) }
        store.inputs.forEach { context.delete($0) }
        store.outputs.forEach { context.delete($0) }     // subtasks는 cascade
        store.completions.forEach { context.delete($0) }
        store.checkIns.forEach { context.delete($0) }
    }
}
