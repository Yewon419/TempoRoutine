// 템포루틴 — 리듬 엔진: 윈도우 통계 (MASTER §5.12 개정 M 2026-08-08 전면 대체)
//
// 구 푸리에+칼만(HarmonicFit·AxisEstimator)을 대체한다. 대체 사유(§5.12):
// 08-05 체크인 병합으로 irritability·pain 수집이 중단돼 구 엔진의 두 계열 입력이 죽었고,
// 1차 조화는 대칭 형태만 표현해 "언제부터 떨어지나"(P)를 원리적으로 못 뽑으며,
// 산출(A·ψ)이 §3.5 서술로 직역되지 않아 서술 엔진과 이중 구현이었다.
//
// 좌표계 = §5.3 양방향 앵커 공용: d(시작 후 일수) + r(다음 시작까지 남은 일수).
// 완료 주기만 받으므로 r도 실측이다. 모든 산출은 "윈도우 + 강건 통계(중앙값·비율·합의)"라
// "지난 N주기, 이 구간 기록이 평소보다 낮았어요"로 직역된다.
//
// 실패 모드 = 침묵: 빈 윈도우·표본 미달이면 nil (§7 "로그가 없으면 말하지 않는다").
// 특이 행렬·분산 붕괴류 죽는 모드가 구조적으로 없다.

import Foundation

/// 완료된 한 주기의 하루 기록 — 양방향 앵커 좌표.
public struct WindowDaySample: Equatable, Sendable {
    public let daysFromStart: Int   // d — 1-indexed, 주기 시작(생리 1일차)부터
    public let daysUntilNext: Int   // r — 1-indexed, 다음 주기 시작 전날이 1
    public let energy: Int?         // 1...5 (범위 밖·0 = 미기록으로 무시)
    public let mood: Int?           // 1...5

    public init(daysFromStart: Int, daysUntilNext: Int, energy: Int?, mood: Int?) {
        self.daysFromStart = daysFromStart
        self.daysUntilNext = daysUntilNext
        self.energy = energy
        self.mood = mood
    }
}

/// 완료 주기 하나 — 길이는 실측(연속 시작일 간격).
public struct WindowCycle: Equatable, Sendable {
    public let length: Int
    public let samples: [WindowDaySample]

    public init(length: Int, samples: [WindowDaySample]) {
        self.length = length
        self.samples = samples
    }
}

public enum WindowSignal: String, CaseIterable, Sendable {
    case energy
    case mood
}

/// 서술·내보내기용 요약 — (계절 × 신호)의 최근 주기 중앙값.
public struct WindowSummary: Equatable, Sendable {
    public let phase: CyclePhase
    public let signal: WindowSignal
    public let median: Double        // 주기별 윈도우 중앙값들의 중앙값
    public let cyclesWithData: Int

    public init(phase: CyclePhase, signal: WindowSignal, median: Double, cyclesWithData: Int) {
        self.phase = phase
        self.signal = signal
        self.median = median
        self.cyclesWithData = cyclesWithData
    }
}

public enum WindowStatsEngine {

    // ── 상수 (§5.12 루프 2 — 설문·문헌·파일럿으로 조정하고 앱 업데이트로 배포. 미결: K·m·A₀)

    /// 최근 K주기만 본다 — 예측 엔진 v1.1의 이동 윈도(최근 5 gap)와 정렬.
    public static let recentCycles = 5
    /// 판정 게이트 — 유효 주기가 이만큼은 있어야 말한다(§5.3 학습 계약 ≥3주기).
    public static let minCycles = 3
    /// 주기 하나가 판정에 들어가기 위한 최소 기록 일수(구 엔진 상수 승계).
    public static let minSamplesPerCycle = 4
    /// "낮다/높다" 판정 여유 — 5점 척도 반 칸.
    public static let margin = 0.5
    /// `P` 후보 범위(§5.3 클램프 [2,7]).
    public static let preWindowRange = 2...7
    /// suffix 판정에 필요한 최소 기록 일수.
    public static let minSuffixSamples = 2
    /// suffix 안 "저컨디션 날" 비율 임계. 중앙값은 오염 50%까지 무반응이라 경계 탐지에 못 쓴다 —
    /// 비율 규칙은 해석 가능하고("저컨디션 날 비율"), 과대 추정이 +1일 수준에 묶인다. 파일럿 조정 대상.
    public static let lowDayFraction = 0.75
    /// A축 판정 기준 range — 구 A₀ 0.5는 사인 진폭(peak-to-peak 1.0)이었다. range는 그 자체가
    /// peak-to-peak라 등가 기준 = 1.0(5점 척도 한 칸). 재보정은 파일럿 확인(§5.12 미결).
    public static let baselineRange = 1.0

    // ── 기초 통계

    /// 중앙값. 빈 배열 = nil(침묵).
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// 1...5 밖(0 = 미기록)은 nil.
    static func value(of sample: WindowDaySample, signal: WindowSignal) -> Double? {
        let raw: Int?
        switch signal {
        case .energy: raw = sample.energy
        case .mood: raw = sample.mood
        }
        guard let raw, (1...AxisScale.max).contains(raw) else { return nil }
        return Double(raw)
    }

    static func windowMedian(_ cycle: WindowCycle, signal: WindowSignal,
                             where predicate: (WindowDaySample) -> Bool) -> Double? {
        median(cycle.samples.filter(predicate).compactMap { value(of: $0, signal: signal) })
    }

    /// 주기 전체 중앙값 = 그 주기의 본인 베이스라인.
    public static func baseline(_ cycle: WindowCycle, signal: WindowSignal) -> Double? {
        windowMedian(cycle, signal: signal) { _ in true }
    }

    /// suffix 윈도우(r ≤ p) 중앙값.
    public static func suffixMedian(_ cycle: WindowCycle, signal: WindowSignal, p: Int) -> Double? {
        windowMedian(cycle, signal: signal) { $0.daysUntilNext <= p }
    }

    /// 계절 윈도우 중앙값 — 경계는 §5.3 실측 길이 기준(phaseSpans와 같은 단일 출처).
    public static func phaseMedian(_ cycle: WindowCycle, signal: WindowSignal,
                                   phase: CyclePhase, menstrualLength: Int = 5) -> Double? {
        windowMedian(cycle, signal: signal) {
            CyclePredictor.phaseForDay($0.daysFromStart, cycleLength: cycle.length,
                                       menstrualLength: menstrualLength) == phase
        }
    }

    // ── 판정 공통

    /// 판정에 쓸 주기 — 최근 K개 중 기록 일수가 충분한 것만.
    static func usable(_ cycles: [WindowCycle]) -> [WindowCycle] {
        cycles.suffix(recentCycles).filter { cycle in
            cycle.samples.filter {
                value(of: $0, signal: .energy) != nil || value(of: $0, signal: .mood) != nil
            }.count >= minSamplesPerCycle
        }
    }

    /// 합의 임계 — n주기 중 max(minCycles, n−1)주기가 같은 방향이어야 한다.
    static func agreementThreshold(_ n: Int) -> Int { max(minCycles, n - 1) }

    // ── `P` 저컨디션 윈도우 (§5.3 층 2 — 신호 = energy)

    /// 주기 하나의 suffix 길이 후보 — 기록된 suffix 일들의 저컨디션 비율(≤ 베이스라인 − margin)이
    /// lowDayFraction 이상인 가장 큰 p. 없으면 nil.
    static func perCyclePreWindow(_ cycle: WindowCycle) -> Int? {
        guard let base = baseline(cycle, signal: .energy) else { return nil }
        var best: Int?
        for p in preWindowRange {
            let days = cycle.samples.filter { $0.daysUntilNext <= p }
                .compactMap { value(of: $0, signal: .energy) }
            guard days.count >= minSuffixSamples else { continue }
            let lows = days.filter { $0 <= base - margin }.count
            if Double(lows) / Double(days.count) >= lowDayFraction { best = p }
        }
        return best
    }

    /// 학습된 `P` — 주기별 후보의 중앙값(합의 임계 충족 시). 없으면 nil → 앱은 §5.3 디폴트 5.
    /// 소비처는 adoptedPreWindow(홀드아웃 채택 게이트 통과분)를 쓴다 — 이 함수는 원시 학습값.
    public static func preMenstrualWindow(cycles allCycles: [WindowCycle]) -> Int? {
        let cycles = usable(allCycles)
        guard cycles.count >= minCycles else { return nil }
        let candidates = cycles.compactMap(perCyclePreWindow)
        guard candidates.count >= agreementThreshold(cycles.count),
              let mid = median(candidates.map(Double.init)) else { return nil }
        let clamped = min(preWindowRange.upperBound,
                          max(preWindowRange.lowerBound, Int(mid.rounded())))
        return clamped
    }

    /// §5.3 층 2 `P` 디폴트 — 학습값이 게이트를 못 넘으면 이 값.
    public static let defaultPreWindow = 5

    /// 홀드아웃 적중률 — 그 주기에서 "suffix p일 윈도우" 예측과 "실제 저컨디션 날(energy ≤ 2)"의 F1.
    /// 기록된 날만 대상. 저컨디션 날이 0이고 윈도우 기록도 0이면 완전 일치(1), 판정 불능이면 nil.
    static func holdoutScore(_ cycle: WindowCycle, p: Int) -> Double? {
        let recorded = cycle.samples.compactMap { s in
            value(of: s, signal: .energy).map { (inWindow: s.daysUntilNext <= p, low: $0 <= 2) }
        }
        guard !recorded.isEmpty else { return nil }
        let tp = Double(recorded.filter { $0.inWindow && $0.low }.count)
        let fp = Double(recorded.filter { $0.inWindow && !$0.low }.count)
        let fn = Double(recorded.filter { !$0.inWindow && $0.low }.count)
        if tp + fp + fn == 0 { return 1 }   // 저컨디션도 윈도우 기록도 없음 = 예측이 틀린 게 없다
        return 2 * tp / (2 * tp + fp + fn)
    }

    /// §5.3 채택 게이트 — 마지막 완료 주기를 홀드아웃으로 두고, 나머지로 학습한 P가
    /// 디폴트 5보다 홀드아웃 F1이 **나을 때만** 채택. 아니면 nil(소비처는 defaultPreWindow).
    /// "감이 아니라 측정으로"(2026-08-08 회의) — 알고리즘 고도화의 성공 정의를 코드로 강제.
    public static func adoptedPreWindow(cycles: [WindowCycle]) -> Int? {
        guard cycles.count >= minCycles + 1, let holdout = cycles.last else { return nil }
        let training = Array(cycles.dropLast())
        guard let learned = preMenstrualWindow(cycles: training),
              learned != defaultPreWindow else { return nil }
        guard let learnedScore = holdoutScore(holdout, p: learned),
              let defaultScore = holdoutScore(holdout, p: defaultPreWindow),
              learnedScore > defaultScore else { return nil }
        return learned
    }

    // ── H1 배란 주변 기분 상승 (§2.3 가설 레지스트리 — 신호 = mood)

    /// true = 상승 합의(여름 서사 발화 허용) / false = 상승 없음 합의 / nil = 불확정·표본 미달(침묵).
    public static func h1SummerMoodLift(cycles allCycles: [WindowCycle], menstrualLength: Int = 5) -> Bool? {
        var up = 0, judged = 0
        for cycle in usable(allCycles) {
            guard let base = baseline(cycle, signal: .mood),
                  let summer = phaseMedian(cycle, signal: .mood, phase: .ovulation,
                                           menstrualLength: menstrualLength) else { continue }
            judged += 1
            if summer >= base + margin { up += 1 }
        }
        guard judged >= minCycles else { return nil }
        let threshold = agreementThreshold(judged)
        if up >= threshold { return true }
        if judged - up >= threshold { return false }
        return nil
    }

    // ── A축 유형 (신호 = mood — 구 엔진 정서 계열 연속성)

    /// 주기 하나의 진폭 = 계절 윈도우 중앙값들의 range. 표본 있는 계절이 2개 미만이면 nil.
    static func perCycleRange(_ cycle: WindowCycle, signal: WindowSignal = .mood,
                              menstrualLength: Int = 5) -> Double? {
        let medians = CyclePhase.allCases.compactMap {
            phaseMedian(cycle, signal: signal, phase: $0, menstrualLength: menstrualLength)
        }
        guard medians.count >= 2, let hi = medians.max(), let lo = medians.min() else { return nil }
        return hi - lo
    }

    /// 유형 배정 — nil = 데이터 부족(카드 미노출), 루바토 = 표본은 충분한데 주기 간 불일치.
    /// 구 엔진 교훈 승계: 기준(baselineRange)과 비교해야 안단테가 존재한다(2026-08-04 실측).
    /// ⚠ 사전 설문의 루바토와 산출 경로가 다르다(§3.11). 같은 필드에 담지 말 것.
    public static func classify(cycles allCycles: [WindowCycle], menstrualLength: Int = 5) -> RhythmType? {
        let ranges = usable(allCycles).compactMap { perCycleRange($0, menstrualLength: menstrualLength) }
        guard ranges.count >= minCycles else { return nil }
        let threshold = agreementThreshold(ranges.count)
        let high = ranges.filter { $0 >= baselineRange }.count
        if high >= threshold { return .vivace }
        if ranges.count - high >= threshold { return .andante }
        return .rubato
    }

    // ── 서술·내보내기 프로파일

    /// (계절 × 신호) 요약 — 표본 없는 칸은 조용히 빠진다.
    public static func profile(cycles allCycles: [WindowCycle], menstrualLength: Int = 5) -> [WindowSummary] {
        let cycles = usable(allCycles)
        var result: [WindowSummary] = []
        for signal in WindowSignal.allCases {
            for phase in CyclePhase.allCases {
                let medians = cycles.compactMap {
                    phaseMedian($0, signal: signal, phase: phase, menstrualLength: menstrualLength)
                }
                guard let mid = median(medians) else { continue }
                result.append(WindowSummary(phase: phase, signal: signal,
                                            median: mid, cyclesWithData: medians.count))
            }
        }
        return result
    }
}
