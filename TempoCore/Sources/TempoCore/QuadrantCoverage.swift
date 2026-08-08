// 템포루틴 — 주기 사분면 커버리지 (MASTER §5.12 ⑤ / 핸드오프 v1.5 §3-5)
//
// **이건 알림 기능이 아니라 엔진 입력 결손 대책이다.** (개정 M 2026-08-08 목적 재정의:
// 구 "정규방정식 특이 행렬 대책" → **윈도우 결손 대책** — 기록이 주기 한쪽에만 몰리면
// 반대쪽 윈도우가 비어 프로파일·P·H1이 침묵한다. 구조·발화 규칙 무변경.)
// 비어 있는 사분면을 짚어 그쪽 기록을 한 개라도 받으면 주기가 살아난다.
//
// ⚠ 사분면 경계는 **계절 경계와 일부러 다르다.** 계절(§5.3)은 길이가 불균등한 생리적 구간이고,
// 여기는 위상 θ를 4등분한 적합 표본의 균형 단위다. 둘을 같은 함수로 묶지 말 것.

import Foundation

public enum QuadrantCoverage {

    /// 위상 4등분. 계절 4개와 개수만 같고 경계가 다르다.
    public static let count = 4

    /// cycleDay(1-indexed) → 사분면 인덱스 0...3.
    /// 마지막 날이 4로 넘어가지 않게 상한을 물린다(day == length일 때 정확히 count가 된다).
    public static func quadrant(day: Int, cycleLength: Int) -> Int? {
        guard cycleLength > 0, day >= 1, day <= cycleLength else { return nil }
        let index = (day - 1) * count / cycleLength
        return min(count - 1, index)
    }

    /// 사분면별 기록 수. 두 계열 중 한쪽만 있어도 1건으로 센다 — 적합은 계열별로 따로 돌기 때문에
    /// "정서만 있는 날"도 A축 표본으로는 유효하다.
    public static func coverage(_ signals: [DailySignal]) -> [Int] {
        var counts = [Int](repeating: 0, count: count)
        for signal in signals {
            guard signal.emotional != nil || signal.bodily != nil else { continue }
            guard let index = quadrant(day: signal.cycleDay, cycleLength: signal.cycleLength) else { continue }
            counts[index] += 1
        }
        return counts
    }

    /// 기록이 하나도 없는 사분면.
    public static func emptyQuadrants(_ signals: [DailySignal]) -> [Int] {
        coverage(signals).enumerated().compactMap { $0.element == 0 ? $0.offset : nil }
    }

    /// 사분면이 차지하는 cycleDay 구간(양끝 포함). 알림 발화일을 잡는 쪽에서 쓴다.
    public static func dayRange(quadrant index: Int, cycleLength: Int) -> ClosedRange<Int>? {
        guard cycleLength > 0, index >= 0, index < count else { return nil }
        // quadrant(day:)의 역함수 — 경계를 따로 계산하면 두 정의가 어긋난다.
        let days = (1...cycleLength).filter { quadrant(day: $0, cycleLength: cycleLength) == index }
        guard let first = days.first, let last = days.last else { return nil }
        return first...last
    }

    /// 사분면 안에서 알림을 걸 cycleDay.
    /// 구간 시작 당일에 조르면 재촉이 되고(§7), 끝나고 알리면 만회할 날이 없다.
    /// **구간의 중간 지점** = 아직 그 사분면에 하루 이상 남아 있는 마지막 여지.
    public static func reminderDay(quadrant index: Int, cycleLength: Int) -> Int? {
        guard let range = dayRange(quadrant: index, cycleLength: cycleLength) else { return nil }
        return range.lowerBound + (range.count - 1) / 2
    }
}
