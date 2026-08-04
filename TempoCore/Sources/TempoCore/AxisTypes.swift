// 템포루틴 — 축 엔진 값 타입 (MASTER §5.12 / §3.11)
//
// ⚠ 이 파일의 첫 번째 규칙: **계열 값은 전부 "높을수록 힘듦"으로 통일한다.**
// 체크인 UI는 방향이 섞여 있다 —
//   mood         1 흐림 …… 5 맑음      (높을수록 좋음 → 뒤집는다)
//   irritability 1 잔잔함 … 5 날카로움  (높을수록 나쁨 → 그대로)
//   pain         1 불편해요 … 5 괜찮아요 (높을수록 좋음 → 뒤집는다)
// 뒤집기를 빠뜨리면 M축 부호가 통째로 반대가 되고, 증상은 "계산은 되는데 해석이 반대"라
// 테스트 없이는 안 드러난다. 환산은 반드시 이 파일의 함수를 거친다.

import Foundation

public enum AxisScale {
    /// 체크인 저장 척도 상한(1...5). UI는 3버튼이고 롱프레스로 2·4가 들어온다(§3.4).
    public static let max = 5
}

/// 하루치 관측 — 두 계열 중 한쪽만 있어도 유효하다.
public struct DailySignal: Equatable, Sendable {
    public let cycleDay: Int        // 1-indexed
    public let cycleLength: Int
    public let emotional: Double?   // y_정서 (높을수록 힘듦)
    public let bodily: Double?      // y_신체 (높을수록 힘듦)
    public let isBackfilled: Bool

    public init(cycleDay: Int, cycleLength: Int, emotional: Double?, bodily: Double?,
                isBackfilled: Bool = false) {
        self.cycleDay = cycleDay
        self.cycleLength = cycleLength
        self.emotional = emotional
        self.bodily = bodily
        self.isBackfilled = isBackfilled
    }

    /// 주기 위상 θ = 2π(day−1)/length
    public var theta: Double {
        guard cycleLength > 0 else { return 0 }
        return 2 * Double.pi * Double(cycleDay - 1) / Double(cycleLength)
    }
}

public enum SignalConversion {
    /// 0 또는 nil = 미기록. 저장 규약상 0이 미기록이다(§5.5).
    private static func recorded(_ value: Int?) -> Double? {
        guard let value, value >= 1, value <= AxisScale.max else { return nil }
        return Double(value)
    }

    private static func flipped(_ value: Double) -> Double {
        Double(AxisScale.max + 1) - value
    }

    /// y_정서 = ((MAX+1 − mood) + irritability) / 2. 한쪽만 있으면 그 한쪽을 쓴다.
    public static func emotional(mood: Int?, irritability: Int?) -> Double? {
        let flippedMood = recorded(mood).map(flipped)
        let rawIrritability = recorded(irritability)
        switch (flippedMood, rawIrritability) {
        case let (m?, i?): return (m + i) / 2
        case let (m?, nil): return m
        case let (nil, i?): return i
        case (nil, nil): return nil
        }
    }

    /// y_신체 = MAX+1 − pain (UI가 "불편해요(1) ~ 괜찮아요(5)"라 불편감은 역방향)
    public static func bodily(pain: Int?) -> Double? {
        recorded(pain).map(flipped)
    }
}

/// 한 주기의 적합 결과
public struct HarmonicResult: Equatable, Sendable {
    public let mean: Double        // 절편 c
    public let amplitude: Double   // 편향 보정 후 진폭 (≥ 0)
    public let phase: Double       // ψ, radian (-π...π]
    public let sampleCount: Int

    public init(mean: Double, amplitude: Double, phase: Double, sampleCount: Int) {
        self.mean = mean
        self.amplitude = amplitude
        self.phase = phase
        self.sampleCount = sampleCount
    }
}

public enum RhythmType: String, Equatable, Sendable {
    case vivace     // 변동이 큰 편
    case andante    // 잔잔한 편
    case rubato     // 아직 정해지는 중

    public var displayName: String {
        switch self {
        case .vivace: "비바체"
        case .andante: "안단테"
        case .rubato: "루바토"
        }
    }
}

/// 축 추정 상태 — 주기가 끝날 때마다 갱신된다(칼만 1D).
public struct AxisState: Equatable, Sendable {
    public let amplitude: Double        // 평활된 A축 추정치 μ
    public let variance: Double         // σ² (하한이 걸려 있어 0이 되지 않는다)
    public let modality: Double         // M축 = 정서 − 신체 (주기 평균)
    public let observedCycles: Int

    public init(amplitude: Double, variance: Double, modality: Double, observedCycles: Int) {
        self.amplitude = amplitude
        self.variance = variance
        self.modality = modality
        self.observedCycles = observedCycles
    }
}
