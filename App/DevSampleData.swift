// 템포루틴 — 개발자 모드 자체 표본 (2026-08-30 대표님 "개발자모드에 자체 데이터를 넣어놔줘")
//
// dev 스토어가 비어 있으면 첫 진입에 합성 표본을 자동 주입한다 — 샘플 JSON을 기기로 옮겨
// 「백업 가져오기」 하던 사람 단계를 없앤 것. 30차 계약의 「진입 = 빈 화면」은 이 지시로 개정.
//
// - 데이터 모양 = tools/make_review_sample.py와 동일 취지: 4주기(29일) 생리 기록 ·
//   계절 따라 오르내리는 체크인(겨울 2 → 봄 4 → 여름 5 → 가을 3 + 지터) · 플래너 4종.
//   기준일 = 오늘 — 실행 시점마다 최신이라 스크린샷의 「오늘」이 늘 채워져 있다.
// - 주입 경로 = ExportImport.merge(가져오기와 같은 코드) — 모델 생성 규칙(스키마·dedup·
//   서브태스크 재연결)을 두 벌로 만들지 않는다. merge 안의 ScheduleReminder는 dev 게이트가
//   진입점에서 막는다(실알림 무접촉).
// - 씨앗 원장(seedLedger)은 싣지 않는다 — UserDefaults 공유라 실씨앗을 오염시킨다.
//   dev는 전 테마 개방이라 씨앗이 필요 없다.
// - 1회성 플래그 — dev에서 「모든 기록 삭제」로 일부러 비운 화면을 다시 채우지 않는다.

import Foundation
import SwiftData
import TempoCore

enum DevSampleData {
    private static let seededKey = "devSampleSeeded"
    private static let cycleLength = 29
    private static let cycles = 4
    private static let periodDaysPerCycle = 5

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        guard DevMode.active, !UserDefaults.standard.bool(forKey: seededKey) else { return }
        // 이미 뭔가 있으면(수동 임포트·직접 기록) 섞지 않는다 — 플래그만 세운다
        let existing = (try? context.fetchCount(FetchDescriptor<DailyCheckIn>())) ?? 0
        guard existing == 0 else {
            UserDefaults.standard.set(true, forKey: seededKey)
            return
        }
        let empty = StoreArrays(periodDays: [], schedules: [], inputs: [],
                                outputs: [], completions: [], checkIns: [])
        ExportImport.merge(envelope(end: Calendar.current.startOfDay(for: .now)),
                           into: context, existing: empty)
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    // ── 봉투 조립 (전부 합성 — 실기록 무접촉) ──

    /// 시드 고정 LCG — 실행마다 같은 「빠진 날」 패턴(스크린샷 재현성). SystemRNG는 시드 불가.
    private struct LCG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    private static func envelope(end: Date) -> ExportEnvelopeV1 {
        let cal = Calendar.current
        var rng = LCG(state: 20_260_830)
        let totalDays = cycleLength * cycles
        let start = cal.date(byAdding: .day, value: -totalDays, to: end) ?? end

        func day(_ offset: Int) -> Date {
            cal.date(byAdding: .day, value: offset, to: start) ?? start
        }
        func at(_ date: Date, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }

        var periodDays: [PeriodDayDTO] = []
        for cycle in 0..<cycles {
            for offset in 0..<periodDaysPerCycle {
                periodDays.append(PeriodDayDTO(
                    day: ExportCodec.dayString(day(cycleLength * cycle + offset)),
                    origin: PeriodDayOrigin.local.rawValue, healthKitUUID: nil))
            }
        }

        // 체크인 — 계절 프로필 + 지터. 빠진 날(~15%)이 있어야 실기록처럼 보인다.
        var checkIns: [DailyCheckInDTO] = []
        for offset in 0...totalDays {
            if Int.random(in: 0..<100, using: &rng) < 15 { continue }
            let phaseDay = offset % cycleLength
            let (energy, mood, sleep): (Int, Int, Int) = switch phaseDay {
            case ..<5: (2, 2, 3)      // 겨울(월경)
            case ..<13: (4, 4, 4)     // 봄
            case ..<18: (5, 5, 4)     // 여름
            default: (3, 3, 3)        // 가을
            }
            let jitter = [-1, 0, 0, 1][Int.random(in: 0..<4, using: &rng)]
            let date = day(offset)
            let stamped = at(date, 21, 30)
            checkIns.append(DailyCheckInDTO(
                id: UUID(), day: ExportCodec.dayString(date),
                energy: max(1, min(5, energy + jitter)),
                mood: max(1, min(5, mood + jitter)),
                sleep: max(1, min(5, sleep + jitter)),
                pain: nil, appetite: max(1, min(5, energy)), note: nil,
                createdAt: stamped, completedAt: stamped))
        }

        // 일정 — 반복형이라 심사·시연이 언제 열려도 「오늘」이 채워진다
        let schedules: [ScheduleItemDTO] = {
            func repeating(_ title: String, _ hour: Int, _ minute: Int,
                           _ rule: ScheduleRepeat, reminder: Int?) -> ScheduleItemDTO {
                ScheduleItemDTO(id: UUID(), title: title,
                                date: ExportCodec.instantString(at(start, hour, minute)),
                                isAllDay: false, repeatRule: rule, createdAt: at(start, 9),
                                endDate: ExportCodec.instantString(at(start, hour + 1, minute)),
                                reminderMinutes: reminder)
            }
            let tripStart = cal.date(byAdding: .day, value: 5, to: end) ?? end
            let tripEnd = cal.date(byAdding: .day, value: 7, to: end) ?? end
            return [
                repeating(Loc.str("아침 스트레칭"), 7, 30, .daily, reminder: 10),
                repeating(Loc.str("팀 회의"), 10, 0, .weekly, reminder: 15),
                repeating(Loc.str("요가 수업"), 19, 30, .weekly, reminder: 30),
                ScheduleItemDTO(id: UUID(), title: Loc.str("짧은 여행"),
                                date: ExportCodec.dayString(tripStart), isAllDay: true,
                                repeatRule: .none, createdAt: at(start, 9),
                                endDate: ExportCodec.instantString(at(tripEnd, 23, 59)),
                                reminderMinutes: nil,
                                endDay: ExportCodec.dayString(tripEnd)),
            ]
        }()

        let inputs: [InputItemDTO] = [
            (Loc.str("물 여덟 잔"), InputCategory.other, InputSchedule.daily, nil),
            (Loc.str("아침 산책"), .exercise, .daily, 8 * 60),
            (Loc.str("영양제"), .other, .daily, 9 * 60),
            (Loc.str("저녁 스트레칭"), .exercise, .daily, 21 * 60),
            (Loc.str("드라마 한 편"), .media, .weekly, 22 * 60),
        ].map { title, category, schedule, minutes in
            InputItemDTO(id: UUID(), title: title, category: category, schedule: schedule,
                         createdAt: at(start, 9), timeMinutes: minutes)
        }

        let outputs: [OutputItemDTO] = {
            func base(_ title: String, _ kind: OutputProgressKind,
                      schedule: OutputSchedule = .once) -> OutputItemDTO {
                OutputItemDTO(id: UUID(), title: title, schedule: schedule, progressKind: kind,
                              subtasks: [], targetSessions: 0, loggedSessions: 0,
                              percent: 0, createdAt: at(start, 9))
            }
            var book = base(Loc.str("책 한 권 읽기"), .percent)
            book.percent = 0.45
            var resume = base(Loc.str("이력서 고치기"), .subtasks)
            resume.subtasks = [
                OutputSubtaskDTO(id: UUID(), title: Loc.str("경력 정리"), isDone: true, order: 0),
                OutputSubtaskDTO(id: UUID(), title: Loc.str("포트폴리오 링크"), isDone: true, order: 1),
                OutputSubtaskDTO(id: UUID(), title: Loc.str("맞춤법 검토"), isDone: false, order: 2),
            ]
            resume.targetDate = at(cal.date(byAdding: .day, value: 10, to: end) ?? end, 9)
            var running = base(Loc.str("달리기 스무 번"), .sessions)
            running.targetSessions = 20
            running.loggedSessions = 8
            var focus = base(Loc.str("집중 25분"), .timer, schedule: .daily)
            focus.targetSeconds = 25 * 60
            focus.elapsedSeconds = 0
            return [book, resume, running, focus]
        }()

        // 지난 3주 루틴 체크 — 빠진 날(~25%)이 있어야 실기록처럼 보인다
        var completions: [ItemCompletionDTO] = []
        let dailyInputs = inputs.filter { $0.schedule == .daily }
        for back in 0..<21 {
            let date = cal.date(byAdding: .day, value: -back, to: end) ?? end
            for item in dailyInputs {
                if Int.random(in: 0..<100, using: &rng) < 25 { continue }
                completions.append(ItemCompletionDTO(id: UUID(), itemID: item.id,
                                                     occurredOn: ExportCodec.dayString(date),
                                                     completedAt: at(date, 22)))
            }
        }

        return ExportEnvelopeV1(
            exportedAt: .now, periodDays: periodDays, scheduleItems: schedules,
            inputItems: inputs, outputItems: outputs, completions: completions,
            checkIns: checkIns, trackedSignals: AppSettings.trackedSignals)
    }
}
