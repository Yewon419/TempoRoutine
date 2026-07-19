// 템포루틴 — 뷰 공용 주기 스냅샷 (§5.6 엔진 + §5.6.4 열거의 앱측 접합부)
// PeriodDay 배열 → 파생값 한 번에. 단계는 저장하지 않고 매번 도출(§5.5 — stale 방지).

import Foundation
import TempoCore

struct CycleSnapshot {
    let starts: [Date]
    let averageLength: Int
    let horizonCycles: Int   // §5.6.2 투영 지평: low=1 / medium=2 / high=3

    init(periodDays: [PeriodDay]) {
        let days = periodDays.map(\.day)
        self.starts = PeriodMath.episodeStarts(days: days)
        self.averageLength = CyclePredictor.averageLength(startDates: starts)
        self.horizonCycles = switch CyclePredictor.confidence(periodStarts: starts) {
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }

    var isColdStart: Bool { starts.isEmpty }
    var isSingleRecord: Bool { starts.count == 1 }   // S1 hedge

    /// 그 날짜의 계절·단계 (S0이면 nil)
    func phaseInfo(on date: Date) -> (meta: SeasonMeta, dayInCycle: Int, projected: Bool)? {
        guard let r = CyclePredictor.cycleDay(of: date, periodStarts: starts, averageLength: averageLength) else {
            return nil
        }
        let meta = seasonMeta(for: CyclePredictor.phaseForDay(r.day, cycleLength: averageLength))
        return (meta, r.day, r.projected)
    }

    /// 주기 기준 반복의 occurrence 열거 (§5.6.4 — 과거 실측·현재·미래 지평까지)
    func occurrences(of recurrence: CycleRecurrence, createdAt: Date) -> [CycleOccurrences.Occurrence] {
        CycleOccurrences.occurrences(of: recurrence, createdAt: createdAt, periodStarts: starts,
                                     averageLength: averageLength, horizonCycles: horizonCycles)
    }

    /// 특정 날짜에 발생하는가
    func occurrence(of recurrence: CycleRecurrence, createdAt: Date, on day: Date) -> CycleOccurrences.Occurrence? {
        occurrences(of: recurrence, createdAt: createdAt)
            .first { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }
}
