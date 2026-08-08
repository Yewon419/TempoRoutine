// 템포루틴 — 리듬 신호 값 타입 (MASTER §5.12 / §3.11)
//
// 개정 M(2026-08-08): 푸리에+칼만 축 엔진 폐기로 HarmonicResult·AxisState는 제거됐다.
// 남은 것들의 소비처 — DailySignal·SignalConversion = 사분면 커버 리마인더(§5.12 ⑤,
// 과거 irritability·pain 기록 보유자의 커버 판정에 여전히 유효) / RhythmType = 유형
// 표시(§3.11)와 새 윈도우 통계 엔진(WindowStats.swift)의 산출 타입.
//
// ⚠ SignalConversion의 규칙: **계열 값은 전부 "높을수록 힘듦"으로 통일한다.**
//   mood         1 흐림 …… 5 맑음      (높을수록 좋음 → 뒤집는다)
//   irritability 1 잔잔함 … 5 날카로움  (높을수록 나쁨 → 그대로)
//   pain         1 불편해요 … 5 괜찮아요 (높을수록 좋음 → 뒤집는다)
// 뒤집기를 빠뜨리면 해석이 통째로 반대가 되는데 "계산은 되므로" 테스트 없이는 안 드러난다.

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
