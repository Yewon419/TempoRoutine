// 템포루틴 — 개발자 모드 자체 표본 (2026-08-30 대표님 "개발자모드에 자체 데이터를 넣어놔줘")
//
// dev 스토어가 비어 있으면 첫 진입에 합성 표본을 자동 주입한다 — 샘플 JSON을 기기로 옮겨
// 「백업 가져오기」 하던 사람 단계를 없앤 것. 30차 계약의 「진입 = 빈 화면」은 이 지시로 개정.
//
// - 데이터 = 4주기(29일) 생리 기록 + 계절 따라 오르내리는 체크인(겨울 2 → 봄 4 → 여름 5 →
//   가을 3 + 지터)뿐. 플래너(일정·루틴·목표)는 안 넣는다(2026-08-30 대표님 "아침 스트레칭
//   이런거 다 빼") — 화면에 얹을 내용은 dev에서 직접 만든다. 기준일 = 오늘.
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
    // v2(2026-08-30 플래너 제거) — 키를 갈아 구 표본을 이미 받은 기기도 기록 삭제 후 새 표본을 받는다
    private static let seededKey = "devSampleSeeded2"
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

        // 플래너(일정·루틴·목표)는 넣지 않는다(2026-08-30 대표님 "아침 스트레칭 이런거 다 빼")
        // — 표본은 생리 기록·체크인만. 화면에 얹을 플래너 내용은 dev에서 직접 만든다.
        return ExportEnvelopeV1(
            exportedAt: .now, periodDays: periodDays, scheduleItems: [],
            inputItems: [], outputItems: [], completions: [],
            checkIns: checkIns, trackedSignals: AppSettings.trackedSignals)
    }
}
