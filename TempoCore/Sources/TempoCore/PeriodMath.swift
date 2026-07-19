// 템포루틴 — 생리 기간 파생 로직 (MASTER §5.5.4, I-2 LOCKED)
// PeriodDay(일별 기록) 집합 → 에피소드 도출. 저장하지 않는 순수 파생 — 예측 엔진(§5.6) 코드 불변.

import Foundation

public enum PeriodMath {

    /// §5.6.5 최소 에피소드 간격 — 이 미만 근접은 같은 에피소드로 묶는다.
    public static let minPeriodGapDays = 14

    /// 일별 기록 → 에피소드(연속 덩어리) 배열. 각 에피소드는 day 오름차순.
    /// 규칙(§5.5.4): day 오름차순 순회, 직전 에피소드 "시작일 + minGap" 미만이면 같은 에피소드.
    /// 불연속 day 허용(HK 타앱 import 대비), 입력 중복·비정렬 허용.
    public static func episodes(days: [Date], minGap: Int = minPeriodGapDays) -> [[Date]] {
        let sorted = Array(Set(days)).sorted()
        guard !sorted.isEmpty else { return [] }
        var result: [[Date]] = []
        var current: [Date] = []
        var currentStart: Date = sorted[0]
        for day in sorted {
            if current.isEmpty {
                current = [day]
                currentStart = day
                continue
            }
            let gap = Calendar.current.dateComponents([.day], from: currentStart, to: day).day ?? 0
            if gap < minGap {
                current.append(day)
            } else {
                result.append(current)
                current = [day]
                currentStart = day
            }
        }
        result.append(current)
        return result
    }

    /// 주기 시작일 배열 = 각 에피소드의 최소 day → §5.6 엔진 입력 `periodStarts`.
    public static func episodeStarts(days: [Date], minGap: Int = minPeriodGapDays) -> [Date] {
        episodes(days: days, minGap: minGap).compactMap(\.first)
    }
}
