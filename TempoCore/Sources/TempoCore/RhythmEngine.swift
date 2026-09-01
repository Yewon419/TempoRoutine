// 템포루틴 — "나의 리듬" 집계 엔진 (MASTER §5.6.3 계약의 P1 실장)
//
// (단계 × 신호) 버킷 평균 + 주기별 argmax(일관성 서술의 입력). 카피는 앱 몫이고
// 여기는 계산만 한다(WindowStatsEngine/AxisProfile과 같은 분업).
//
// 계약(§5.6.3): energy·mood 둘 다 1...5인 행만 입력 · projected=true·nil 단계는 집계 제외
// (추정 위에 추정을 쌓지 않는다) · 옵션 신호는 non-nil만 · MIN_SAMPLES는 튜닝 가능 상수.

import Foundation

/// 리듬 탭이 다루는 신호(§8.2.5 — 에너지·기분·수면·식욕). pain은 M축 전용이라 여기 없다.
/// appetite = 2026-08-09 추가(베타 피드백 "에너지 기분 수면 식욕 다 넣어놓되 세로로 쭉").
public enum SignalKind: String, CaseIterable, Equatable, Sendable {
    case energy
    case mood
    case sleep
    case appetite
}

/// 집계 입력 행 — 앱의 DailyCheckIn에서 변환해 넘긴다(TempoCore는 SwiftData를 모른다).
public struct SignalSample: Equatable, Sendable {
    public let day: Date
    public let energy: Int
    public let mood: Int
    public let sleep: Int?
    public let appetite: Int?
    /// 집계 가중(2026-09-01 아픈 날) — 통증 0.5, 무증상 1. 질병(0)은 앱이 아예 안 넘긴다.
    public let weight: Double

    /// appetite·weight 기본값 — 기존 콜사이트·테스트 하위 호환.
    public init(day: Date, energy: Int, mood: Int, sleep: Int?, appetite: Int? = nil,
                weight: Double = 1) {
        self.day = day
        self.energy = energy
        self.mood = mood
        self.sleep = sleep
        self.appetite = appetite
        self.weight = weight
    }

    func value(of signal: SignalKind) -> Int? {
        switch signal {
        case .energy: energy
        case .mood: mood
        case .sleep: sleep
        case .appetite: appetite
        }
    }
}

/// 주기 일차 버킷 평균 한 점 — 일차 축 곡선(§8.2.5, 2026-08-30)의 입력.
public struct DayCurvePoint: Equatable, Sendable {
    public let day: Int          // 1-indexed 주기 일차
    public let mean: Double
    public let sampleCount: Int

    public init(day: Int, mean: Double, sampleCount: Int) {
        self.day = day
        self.mean = mean
        self.sampleCount = sampleCount
    }
}

/// §5.6.3 계약 그대로.
public struct PhaseSignalSummary: Equatable, Sendable {
    public let phase: CyclePhase
    public let signal: SignalKind
    public let mean: Double
    public let sampleCount: Int

    public init(phase: CyclePhase, signal: SignalKind, mean: Double, sampleCount: Int) {
        self.phase = phase
        self.signal = signal
        self.mean = mean
        self.sampleCount = sampleCount
    }
}

public enum RhythmEngine {

    /// 신호별 이 개수 이상 쌓인 단계가 2개 이상일 때만 비교 서술(§5.6.3).
    public static let minSamples = 3

    /// (단계 × 신호) 버킷 평균. energy·mood 둘 다 1...5인 행만 입력 — 필터를 호출측에 맡기면
    /// 노트 단독 행(0·0)이 새어 들어와 평균을 끌어내린다(§5.5 개정 2026-07-22).
    public static func summaries(samples: [SignalSample], periodStarts: [Date],
                                 averageLength: Int, menstrualLength: Int = 5) -> [PhaseSignalSummary] {
        guard averageLength > 0 else { return [] }
        // 가중 누적(2026-09-01 아픈 날) — sum = Σ(w·x), weight = Σw. 유효 표본 수 = ⌊Σw⌋.
        var buckets: [CyclePhase: [SignalKind: (sum: Double, weight: Double)]] = [:]

        for sample in samples {
            guard (1...5).contains(sample.energy), (1...5).contains(sample.mood),
                  sample.weight > 0 else { continue }
            guard let r = CyclePredictor.cycleDay(of: sample.day, periodStarts: periodStarts,
                                                  averageLength: averageLength),
                  !r.projected else { continue }
            let phase = CyclePredictor.phaseForDay(r.day, cycleLength: averageLength,
                                                   menstrualLength: menstrualLength)
            for signal in SignalKind.allCases {
                guard let value = sample.value(of: signal), (1...5).contains(value) else { continue }
                let cur = buckets[phase]?[signal] ?? (0, 0)
                buckets[phase, default: [:]][signal] =
                    (cur.sum + Double(value) * sample.weight, cur.weight + sample.weight)
            }
        }

        return buckets.flatMap { phase, signals in
            signals.map { signal, acc in
                PhaseSignalSummary(phase: phase, signal: signal,
                                   mean: acc.sum / acc.weight,
                                   sampleCount: Int(acc.weight.rounded(.down)))
            }
        }
    }

    /// 주기 일차별 버킷 평균 — 일차 축 곡선의 입력. 필터·도출은 `summaries`와 동일 의미론
    /// (energy·mood 유효 행만 · projected 제외 · 해당 신호 1...5만). 일차가 averageLength를
    /// 넘는 표본(늦어진 주기 꼬리)은 버린다 — x축이 1...averageLength라 자리가 없다.
    public static func dayCurve(signal: SignalKind, samples: [SignalSample],
                                periodStarts: [Date], averageLength: Int) -> [DayCurvePoint] {
        guard averageLength > 0 else { return [] }
        var buckets: [Int: (sum: Double, weight: Double)] = [:]
        for sample in samples {
            guard (1...5).contains(sample.energy), (1...5).contains(sample.mood),
                  sample.weight > 0,
                  let value = sample.value(of: signal), (1...5).contains(value),
                  let r = CyclePredictor.cycleDay(of: sample.day, periodStarts: periodStarts,
                                                  averageLength: averageLength),
                  !r.projected, (1...averageLength).contains(r.day) else { continue }
            let cur = buckets[r.day] ?? (0, 0)
            buckets[r.day] = (cur.sum + Double(value) * sample.weight, cur.weight + sample.weight)
        }
        return buckets.sorted { $0.key < $1.key }.map {
            DayCurvePoint(day: $0.key,
                          mean: $0.value.sum / $0.value.weight,
                          sampleCount: Int($0.value.weight.rounded(.down)))
        }
    }

    /// 한 신호의 비교 서술 가능 여부 — minSamples를 채운 단계가 2개 이상(§5.6.3).
    public static func narratable(_ summaries: [PhaseSignalSummary], signal: SignalKind) -> Bool {
        summaries.filter { $0.signal == signal && $0.sampleCount >= minSamples }.count >= 2
    }

    /// 그 신호의 유효 표본이 든 완료 주기 수 — 서술의 "지난 N주기"에 쓴다.
    /// ⚠ 전체 주기 수(starts−1)를 쓰면 안 된다: HK로 수년치 생리 기록만 이어받은 사용자는
    /// 체크인 없는 주기가 수십 개라 "지난 23주기, 기록 9회" 같은 어긋난 서술이 된다(2026-08-05 실기기).
    public static func cyclesWithData(signal: SignalKind, samples: [SignalSample],
                                      periodStarts: [Date],
                                      calendar: Calendar = .current) -> Int {
        let starts = periodStarts.sorted()
        guard starts.count >= 2 else { return 0 }
        var count = 0
        for (index, start) in starts.enumerated() where index < starts.count - 1 {
            let end = starts[index + 1]
            let hasData = samples.contains { sample in
                (1...5).contains(sample.energy) && (1...5).contains(sample.mood)
                    && sample.weight > 0
                    && sample.value(of: signal).map { (1...5).contains($0) } == true
                    && sample.day >= start && sample.day < end
            }
            if hasData { count += 1 }
        }
        return count
    }

    /// 완료 주기(연속 시작일 쌍, 실측 길이)별로 그 신호가 가장 높았던 단계.
    /// "3주기 연속, 봄이 가장 높게 기록됐어요"(§8.2.5 ⑤ 일관성 서술)의 입력 — 오래된 주기부터.
    /// 주기 안에서 표본 있는 단계가 2개 미만이면 그 주기는 건너뛴다(비교가 성립하지 않는다).
    public static func perCycleTopPhases(signal: SignalKind, samples: [SignalSample],
                                         periodStarts: [Date],
                                         menstrualLength: Int = 5,
                                         calendar: Calendar = .current) -> [CyclePhase] {
        let starts = periodStarts.sorted()
        guard starts.count >= 2 else { return [] }

        var result: [CyclePhase] = []
        for (index, start) in starts.enumerated() where index < starts.count - 1 {
            let end = starts[index + 1]
            guard let length = calendar.dateComponents([.day], from: start, to: end).day,
                  length > 0 else { continue }

            var acc: [CyclePhase: (sum: Double, weight: Double)] = [:]
            for sample in samples {
                guard (1...5).contains(sample.energy), (1...5).contains(sample.mood),
                      sample.weight > 0,
                      let value = sample.value(of: signal), (1...5).contains(value),
                      sample.day >= start, sample.day < end,
                      let offset = calendar.dateComponents([.day], from: start, to: sample.day).day
                else { continue }
                // 과거 주기의 단계는 실측 길이로 도출(§5.6.4 ① — 과거는 실주기)
                let phase = CyclePredictor.phaseForDay(offset + 1, cycleLength: length,
                                                       menstrualLength: menstrualLength)
                let cur = acc[phase] ?? (0, 0)
                acc[phase] = (cur.sum + Double(value) * sample.weight, cur.weight + sample.weight)
            }
            guard acc.count >= 2 else { continue }
            let top = acc.max {
                ($0.value.sum / $0.value.weight) < ($1.value.sum / $1.value.weight)
            }
            if let top { result.append(top.key) }
        }
        return result
    }
}
