// 템포루틴 — @Model ↔ DTO 변환·병합 (MASTER §5.5.1)
// 재임포트 dedup: PeriodDay=day / DailyCheckIn=day / 나머지=UUID (보존이라 완료·서브태스크 재연결).
// HK 재기록 없음(로컬 복원만 — §5.5.1). 전체 삭제 undo = 삭제 직전 봉투 스냅샷 재병합.

import Foundation
import SwiftData
import TempoCore

enum AppSettings {
    private static let trackedSignalsKey = "trackedSignals"

    /// 온보딩 전 기본값. 예민함·몸은 2026-08-05 사용자 결정으로 입력 행 제거(기분·에너지와
    /// 겹침) — 기본값도 꺼짐. 스키마 필드는 구 백업 디코딩 호환을 위해 유지된다.
    static var trackedSignals: TrackedSignals {
        get {
            guard let data = UserDefaults.standard.data(forKey: trackedSignalsKey),
                  let decoded = try? JSONDecoder().decode(TrackedSignals.self, from: data) else {
                return TrackedSignals(sleep: true, pain: false, appetite: true, note: true,
                                      irritability: false)
            }
            return decoded
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: trackedSignalsKey)
        }
    }

    /// 온보딩 ②-4 주기 길이 보고값(개정 M) — 실측 gap이 없을 때만 예측 prior로 쓰인다(§5.6 T1b).
    /// nil = 답 안 함(디폴트 28). 저장은 0 = 없음 규약(UserDefaults integer 기본값).
    private static let cyclePriorKey = "cycleLengthPrior"
    static var cycleLengthPrior: Int? {
        get {
            let raw = UserDefaults.standard.integer(forKey: cyclePriorKey)
            return raw == 0 ? nil : raw
        }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: cyclePriorKey) }
    }

    /// 온보딩 ②-2 지속일 보고값(개정 M) — §5.3 층 2 `M`의 초기값. 실측 에피소드 길이가
    /// 충분히 쌓이면 CycleParams가 자동으로 실측 중앙값으로 대체한다.
    private static let periodPriorKey = "periodLengthPrior"
    static var periodLengthPrior: Int? {
        get {
            let raw = UserDefaults.standard.integer(forKey: periodPriorKey)
            return raw == 0 ? nil : raw
        }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: periodPriorKey) }
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
        // 리듬 엔진 산출물 동봉(개정 M-6c) — 그루핑 기준을 엔진 소비처(AxisProfile)와 공유
        let axis = AxisProfile(checkIns: store.checkIns,
                               snapshot: CycleSnapshot(periodDays: store.periodDays))
        return ExportEnvelopeV1(
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
                             schedule: $0.schedule, createdAt: $0.createdAt,
                             backfilled: $0.backfilled ? true : nil,
                             timeMinutes: $0.timeMinutes)
            },
            outputItems: store.outputs.map { item in
                OutputItemDTO(id: item.id, title: item.title, schedule: item.schedule,
                              progressKind: item.progressKind,
                              subtasks: (item.subtasks ?? []).sorted { $0.order < $1.order }.map {
                                  OutputSubtaskDTO(id: $0.id, title: $0.title, isDone: $0.isDone, order: $0.order)
                              },
                              targetSessions: item.targetSessions, loggedSessions: item.loggedSessions,
                              percent: item.percent, createdAt: item.createdAt,
                              targetDate: item.targetDate,
                              targetSeconds: item.targetSeconds,
                              // 실행 중이어도 스냅샷은 접힌 경과로(실행 상태는 봉투 밖)
                              elapsedSeconds: item.elapsedSeconds() > 0 ? item.elapsedSeconds() : nil,
                              timeMinutes: item.timeMinutes)
            },
            completions: store.completions.map {
                ItemCompletionDTO(id: $0.id, itemID: $0.itemID,
                                  occurredOn: ExportCodec.dayString($0.occurredOn), completedAt: $0.completedAt)
            },
            checkIns: store.checkIns.map {
                DailyCheckInDTO(id: $0.id, day: ExportCodec.dayString($0.day), energy: $0.energy,
                                mood: $0.mood, sleep: $0.sleep, pain: $0.pain, appetite: $0.appetite,
                                note: $0.note, createdAt: $0.createdAt,
                                irritability: $0.irritability,
                                isBackfilled: $0.isBackfilled ? true : nil,
                                completedAt: $0.completedAt)
            },
            trackedSignals: AppSettings.trackedSignals,
            rhythmSummary: RhythmSummaryDTO.build(cycles: axis.cycles,
                                                  menstrualLength: axis.menstrualLength,
                                                  computedAt: .now),
            // 씨앗 소비 원장(2026-08-11) — 획득 근거(체크인 completedAt)만 싣던 탓에 복원·기기
            // 이전에서 산 테마가 사라지고 씨앗만 되돌아왔다(§3.8.1 「구매한 테마는 사라지지 않아요」)
            seedLedger: Seeds.ledger
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
            let item = InputItem(title: dto.title, category: dto.category, schedule: dto.schedule,
                                 backfilled: dto.backfilled ?? false)
            item.id = dto.id
            item.createdAt = dto.createdAt
            item.timeMinutes = dto.timeMinutes
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
            item.targetDate = dto.targetDate
            item.targetSeconds = dto.targetSeconds
            item.elapsedAccumSeconds = dto.elapsedSeconds ?? 0   // 복원 = 정지 상태(2026-08-09)
            item.timeMinutes = dto.timeMinutes
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
            // §5.5 개정(2026-07-22): 노트 단독 저장 허용 — 신호 없는 행도 노트가 있으면 유효.
            // 종전 guard(energy·mood 필수)는 노트 단독 체크인을 복원에서 버렸다(2026-07-27 리뷰 결함).
            let hasSignals = dto.energy >= 1 && dto.mood >= 1
            let hasNote = !(dto.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard hasSignals || hasNote else { continue }
            let record = DailyCheckIn(day: day, energy: dto.energy, mood: dto.mood,
                                      isBackfilled: dto.isBackfilled ?? false)
            record.id = dto.id
            record.sleep = dto.sleep
            record.pain = dto.pain
            record.appetite = dto.appetite
            record.irritability = dto.irritability
            record.note = dto.note
            record.createdAt = dto.createdAt
            record.completedAt = dto.completedAt   // 씨앗 근거 복원(2026-08-09)
            context.insert(record)
            added += 1
        }

        // 씨앗 소비 원장 — 덮어쓰기가 아니라 합집합 병합. 백업이 이 기기보다 오래됐어도 그 사이에
        // 산 테마를 되돌리지 않는다. 아이템 추가 건수(added)에는 세지 않는다 — 재화는 항목이 아니다.
        if let remote = envelope.seedLedger { Seeds.merge(remote) }
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
