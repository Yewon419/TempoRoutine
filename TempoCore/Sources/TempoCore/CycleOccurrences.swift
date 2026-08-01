// 템포루틴 — occurrence 열거 (MASTER §5.6.4 LOCKED)
// resolveDate(§5.6)는 "한 주기 안"만 답한다 — 어느 주기들에 물을지가 이 계약.
// 입력 날짜는 start-of-day 정규화 가정(엔진 전체 관례).

import Foundation

public struct CycleWindow: Equatable, Sendable {
    public let start: Date
    public let length: Int       // 과거=실측 간격, 현재/미래=평균 N
    public let projected: Bool   // 미래 예측 주기

    public init(start: Date, length: Int, projected: Bool) {
        self.start = start
        self.length = length
        self.projected = projected
    }
}

public enum CycleOccurrences {

    /// §5.6.4 주기 열거: ① 과거 = 연속 시작일 쌍(길이 실측) ② 현재 = 마지막 시작일 + N ③ 미래 = lastStart + k·N (k ≤ 투영 지평).
    public static func cycleWindows(periodStarts: [Date], averageLength n: Int, horizonCycles: Int) -> [CycleWindow] {
        let sorted = periodStarts.sorted()
        guard let last = sorted.last else { return [] }
        var windows: [CycleWindow] = []
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            let measured = Calendar.current.dateComponents([.day], from: a, to: b).day ?? n
            windows.append(CycleWindow(start: a, length: measured, projected: false))
        }
        windows.append(CycleWindow(start: last, length: n, projected: false))
        if horizonCycles >= 1 {
            for k in 1...horizonCycles {
                guard let start = Calendar.current.date(byAdding: .day, value: k * n, to: last) else { break }
                windows.append(CycleWindow(start: start, length: n, projected: true))
            }
        }
        return windows
    }

    public struct Occurrence: Equatable, Sendable {
        public let date: Date
        public let cycleStart: Date
        public let projected: Bool

        public init(date: Date, cycleStart: Date, projected: Bool) {
            self.date = date
            self.cycleStart = cycleStart
            self.projected = projected
        }
    }

    /// 주기 기준 반복의 occurrence 열거.
    /// repeatsEveryCycle=true → 창마다 resolve(skip이면 그 주기 미발생).
    /// one-shot(§5.5.3) → createdAt이 속한 주기에 바인딩, resolve 날짜가 createdAt 이전이면 다음 주기로 1회 이월.
    ///   one-shot의 .skip은 clamp로 해석(§5.5.3 — skip+overflow는 영원히 미발생이라 무의미).
    public static func occurrences(of r: CycleRecurrence, createdAt: Date, periodStarts: [Date],
                                   averageLength n: Int, horizonCycles: Int) -> [Occurrence] {
        let windows = cycleWindows(periodStarts: periodStarts, averageLength: n, horizonCycles: horizonCycles)
        guard !windows.isEmpty else { return [] }

        func resolve(in w: CycleWindow, rule: OffsetOverflowRule) -> Date? {
            var rec = r
            rec.overflowRule = rule
            let p = CyclePrediction(lastPeriodStart: w.start, averageLength: w.length, confidence: .low)
            return CyclePredictor.resolveDate(recurrence: rec, cycleStart: w.start, prediction: p)
        }

        // 계절 전체(2026-08-01): 한 주기에서 그 계절의 모든 날이 발생일이다 — dayOffset·overflowRule은 무의미.
        // 계절 길이는 주기 길이에 따라 달라지므로(§5.3 양방향 앵커) 창마다 다시 계산한다.
        if r.spansWholePhase, case .phase(let phase) = r.anchor {
            let cal = Calendar.current
            func phaseDays(in w: CycleWindow) -> [Occurrence] {
                guard let span = CyclePredictor.phaseSpans(cycleLength: w.length).first(where: { $0.phase == phase }),
                      span.length > 0 else { return [] }
                return (0..<span.length).compactMap { i in
                    // startDay는 1-indexed — 창 시작일이 1일차다
                    cal.date(byAdding: .day, value: span.startDay - 1 + i, to: w.start)
                        .map { Occurrence(date: $0, cycleStart: w.start, projected: w.projected) }
                }
            }
            if r.repeatsEveryCycle { return windows.flatMap(phaseDays) }
            // one-shot = createdAt이 속한 창의 그 계절만. 이미 지난 계절이면 다음 창으로 넘긴다.
            var index = windows.count - 1
            for (i, w) in windows.enumerated() {
                guard let end = cal.date(byAdding: .day, value: w.length, to: w.start) else { continue }
                if createdAt < end { index = i; break }
            }
            let days = phaseDays(in: windows[index])
            if let last = days.last?.date, last < createdAt, index + 1 < windows.count {
                return phaseDays(in: windows[index + 1])
            }
            return days
        }

        if r.repeatsEveryCycle {
            return windows.compactMap { w in
                resolve(in: w, rule: r.overflowRule).map { Occurrence(date: $0, cycleStart: w.start, projected: w.projected) }
            }
        }

        // one-shot: 바인딩 주기 = createdAt이 속한 창 (첫 창 이전 → 첫 창, 전부 지난 뒤 → 마지막 창)
        let effectiveRule: OffsetOverflowRule = r.overflowRule == .skip ? .clamp : r.overflowRule
        var bindingIndex = windows.count - 1
        for (i, w) in windows.enumerated() {
            guard let end = Calendar.current.date(byAdding: .day, value: w.length, to: w.start) else { continue }
            if createdAt < end { bindingIndex = i; break }
        }
        guard let resolved = resolve(in: windows[bindingIndex], rule: effectiveRule) else { return [] }
        if resolved < createdAt, bindingIndex + 1 < windows.count,
           let rolled = resolve(in: windows[bindingIndex + 1], rule: effectiveRule) {
            let w = windows[bindingIndex + 1]
            return [Occurrence(date: rolled, cycleStart: w.start, projected: w.projected)]
        }
        let w = windows[bindingIndex]
        return [Occurrence(date: resolved, cycleStart: w.start, projected: w.projected)]
    }
}
