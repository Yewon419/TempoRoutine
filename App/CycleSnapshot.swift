// 템포루틴 — 뷰 공용 주기 스냅샷 (§5.6 엔진 + §5.6.4 열거의 앱측 접합부)
// PeriodDay 배열 → 파생값 한 번에. 단계는 저장하지 않고 매번 도출(§5.5 — stale 방지).

import Foundation
import TempoCore

/// 개인화 파라미터 단일 제공자(개정 M — §5.3 층 2). 스냅샷·캘린더·알림이 전부 여기를 거친다 —
/// 표면마다 직접 CyclePredictor를 부르면 prior 반영 여부가 갈라진다(2026-08-08 실결함 2곳 정정).
enum CycleParams {

    /// N — 실측 gap 우선, 없으면 온보딩 ②-4 보고값(T1b), 그것도 없으면 28.
    static func averageLength(starts: [Date]) -> Int {
        CyclePredictor.averageLength(startDates: starts, priorLength: AppSettings.cycleLengthPrior)
    }

    /// M(월경 길이) — 실측 에피소드 길이 중앙값(2개 이상일 때) → 온보딩 ②-2 보고값 → 5.
    /// 1일짜리 에피소드는 "시작일만 기록" 아티팩트(HK 타앱 import 대비)로 보고 실측에서 제외.
    static func menstrualLength(days: [Date]) -> Int {
        let measured = PeriodMath.episodeLengths(days: days).filter { (2...10).contains($0) }
        if measured.count >= 2 {
            let sorted = measured.sorted()
            let mid = sorted.count / 2
            let median = sorted.count % 2 == 1
                ? Double(sorted[mid])
                : Double(sorted[mid - 1] + sorted[mid]) / 2
            return min(10, max(2, Int(median.rounded())))
        }
        return AppSettings.periodLengthPrior.map { min(10, max(1, $0)) } ?? 5
    }
}

struct CycleSnapshot {
    let starts: [Date]
    let averageLength: Int
    let menstrualLength: Int   // §5.3 층 2 M(개정 M) — CycleParams 산출
    let horizonCycles: Int   // §5.6.2 투영 지평: low=1 / medium=2 / high=3

    init(periodDays: [PeriodDay]) {
        self.init(days: periodDays.map(\.day))
    }

    /// PeriodDay 모델 없이 day만으로 스냅샷 계산 — 아직 커밋 전인 드래프트 미리보기용(§4 계절 전환 판정 등)
    init(days: [Date]) {
        self.starts = PeriodMath.episodeStarts(days: days)
        self.averageLength = CycleParams.averageLength(starts: starts)
        self.menstrualLength = CycleParams.menstrualLength(days: days)
        self.horizonCycles = switch CyclePredictor.confidence(periodStarts: starts) {
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }

    var isColdStart: Bool { starts.isEmpty }
    var isSingleRecord: Bool { starts.count == 1 }   // S1 hedge

    /// 그 날짜의 단계만 (계절광 등 — S0이면 nil)
    func phase(on date: Date) -> CyclePhase? {
        guard let r = CyclePredictor.cycleDay(of: date, periodStarts: starts, averageLength: averageLength) else {
            return nil
        }
        return CyclePredictor.phaseForDay(r.day, cycleLength: averageLength,
                                          menstrualLength: menstrualLength)
    }

    /// 그 날짜의 계절·단계 (S0이면 nil)
    func phaseInfo(on date: Date) -> (meta: SeasonMeta, dayInCycle: Int, projected: Bool)? {
        guard let r = CyclePredictor.cycleDay(of: date, periodStarts: starts, averageLength: averageLength) else {
            return nil
        }
        let meta = seasonMeta(for: CyclePredictor.phaseForDay(r.day, cycleLength: averageLength,
                                                              menstrualLength: menstrualLength))
        return (meta, r.day, r.projected)
    }

    /// 주기 기준 반복의 occurrence 열거 (§5.6.4 — 과거 실측·현재·미래 지평까지)
    func occurrences(of recurrence: CycleRecurrence, createdAt: Date) -> [CycleOccurrences.Occurrence] {
        CycleOccurrences.occurrences(of: recurrence, createdAt: createdAt, periodStarts: starts,
                                     averageLength: averageLength, horizonCycles: horizonCycles,
                                     menstrualLength: menstrualLength)
    }

    /// 특정 날짜에 발생하는가
    func occurrence(of recurrence: CycleRecurrence, createdAt: Date, on day: Date) -> CycleOccurrences.Occurrence? {
        occurrences(of: recurrence, createdAt: createdAt)
            .first { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }
}
