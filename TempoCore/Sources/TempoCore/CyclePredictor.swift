// 템포루틴 — 예측 엔진 (MASTER §5.6 / §5.6.1 / §5.6.2)
// Playground Step1(아이폰 검증 25/25) 이식본 — 알고리즘 무변경, 접근 제어만 public.

import Foundation

public enum CyclePredictor {

    /// 평균 주기 길이. 기록<2개면 28, [21,35] 클램프.
    public static func averageLength(startDates: [Date]) -> Int {
        let sorted = startDates.sorted()
        guard sorted.count >= 2 else { return 28 }
        let gaps = zip(sorted, sorted.dropFirst())
            .map { Calendar.current.dateComponents([.day], from: $0, to: $1).day ?? 28 }
        return max(21, min(35, gaps.reduce(0, +) / gaps.count))
    }

    /// §5.3 LOCKED 경계(황체기 고정·양방향 앵커). 합은 항상 n. M=5/B=14/O=3.
    public static func phaseSpans(cycleLength n: Int) -> [PhaseSpan] {
        let m = 5, b = 14, o = 3
        var menLen = m
        var folLen = (n - b) - m       // N−B−M (탄력)
        var ovuLen = o
        var lutLen = b - o             // B−O
        // 짧은 주기 클램프: 난포기 <1이면 후반부(황체→배란→월경 순) 1일씩 양보. 디폴트+[21,35]에선 미발동.
        while folLen < 1 {
            if lutLen > 1 { lutLen -= 1; folLen += 1 }
            else if ovuLen > 1 { ovuLen -= 1; folLen += 1 }
            else if menLen > 1 { menLen -= 1; folLen += 1 }
            else { break }
        }
        let menStart = 1
        let folStart = menStart + menLen
        let ovuStart = folStart + folLen
        let lutStart = ovuStart + ovuLen
        return [
            PhaseSpan(phase: .menstrual,  startDay: menStart, length: menLen),
            PhaseSpan(phase: .follicular, startDay: folStart, length: folLen),
            PhaseSpan(phase: .ovulation,  startDay: ovuStart, length: ovuLen),
            PhaseSpan(phase: .luteal,     startDay: lutStart, length: lutLen),
        ]
    }

    /// 주기 기준 반복을 특정 주기(cycleStart=1일차)에서 절대 날짜로 resolve. ← 제품의 심장.
    public static func resolveDate(recurrence r: CycleRecurrence, cycleStart: Date, prediction p: CyclePrediction) -> Date? {
        let n = p.averageLength
        // 1. 앵커 span(시작일 1-indexed, 길이)
        let span: (start: Int, length: Int)
        switch r.anchor {
        case .cycleStart:
            span = (1, n)
        case .phase(let ph):
            guard let s = phaseSpans(cycleLength: n).first(where: { $0.phase == ph }) else { return nil }
            span = (s.startDay, s.length)
        }
        // 2. dayOffset + overflow
        let offset = max(0, r.dayOffset)
        var targetDay: Int
        if offset >= span.length {                       // overflow
            switch r.overflowRule {
            case .skip:  return nil                       // 이번 주기 미발생
            case .clamp: targetDay = span.start + span.length - 1   // span 마지막 날
            case .carry: targetDay = span.start + offset            // 다음 단계로 이월(같은 주기 내)
            }
        } else {
            targetDay = span.start + offset
        }
        // 3. 주기 경계로 가둠 (carry가 주기 밖이면 day n; .cycleStart에선 carry≡clamp)
        targetDay = min(max(targetDay, 1), n)
        // 4. 절대 날짜 = cycleStart + (targetDay-1)일
        return Calendar.current.date(byAdding: .day, value: targetDay - 1, to: cycleStart)
    }

    /// 날짜의 단계 + projected 플래그. 기록 0개면 nil(S0).
    public static func phase(on date: Date, periodStarts: [Date], averageLength n: Int) -> (phase: CyclePhase, projected: Bool)? {
        guard let r = cycleDay(of: date, periodStarts: periodStarts, averageLength: n) else { return nil }
        return (phaseForDay(r.day, cycleLength: n), r.projected)
    }

    /// 기록 규칙성으로 신뢰도. <2 low / spread>7일 low / 4+개 & spread≤3일 high / 그 외 medium.
    public static func confidence(periodStarts: [Date]) -> CyclePrediction.Confidence {
        let sorted = periodStarts.sorted()
        guard sorted.count >= 2 else { return .low }
        let gaps = zip(sorted, sorted.dropFirst())
            .map { Calendar.current.dateComponents([.day], from: $0, to: $1).day ?? 28 }
        let spread = (gaps.max() ?? 0) - (gaps.min() ?? 0)
        if sorted.count >= 4 && spread <= 3 { return .high }
        if spread <= 7 { return .medium }
        return .low
    }

    /// 예측 다음 생리일(마지막 기록 + 예측길이) 경과인데 새 기록 없음 = overdue.
    public static func isOverdue(on date: Date, periodStarts: [Date], averageLength n: Int) -> Bool {
        guard let last = periodStarts.max() else { return false }
        let diff = Calendar.current.dateComponents([.day], from: last, to: date).day ?? 0
        return diff >= n
    }

    /// 날짜 → day-in-cycle(1-indexed) + projected. 과거=포함 실주기 앵커, 미래/overdue=예측 투영.
    /// §5.6.2 정정: 모듈로 단일투영의 과거 오류 제거.
    public static func cycleDay(of date: Date, periodStarts: [Date], averageLength n: Int) -> DayResolution? {
        let sorted = periodStarts.sorted()
        guard let first = sorted.first else { return nil }            // 기록 0개(S0)
        guard let base = sorted.last(where: { $0 <= date }) else {    // 첫 기록 이전 → 역투영
            let diff = Calendar.current.dateComponents([.day], from: first, to: date).day ?? 0
            return DayResolution(day: ((diff % n) + n) % n + 1, projected: true)
        }
        let diff = Calendar.current.dateComponents([.day], from: base, to: date).day ?? 0
        if base == sorted.last && diff >= n {                          // 마지막 앵커+예측 초과 = 예측/overdue
            return DayResolution(day: diff % n + 1, projected: true)
        }
        return DayResolution(day: diff + 1, projected: false)          // 실제 주기 내
    }

    /// day-in-cycle → 단계.
    public static func phaseForDay(_ day: Int, cycleLength n: Int) -> CyclePhase {
        let d = min(max(day, 1), n)
        for s in phaseSpans(cycleLength: n) where d >= s.startDay && d < s.startDay + s.length {
            return s.phase
        }
        return .luteal
    }
}
