// 템포루틴 — 여러 날 일정의 기간·띠 세그먼트 (§8.2.3 다중일 일정, 2026-07-25 사용자 지시)
// 순수 Foundation — 월 그리드의 "이 칸에 걸치는가" 배열만 받아 주 단위 띠 조각으로 자른다.
// 발생 판정 자체(반복 규칙)는 앱 타깃 ScheduleItem이 소유한다 — 여기는 조판 계산만.

import Foundation

/// 월 그리드 한 행(주) 안에서 이어지는 띠 한 조각.
/// isStart·isEnd = 일정의 실제 시작·끝(양 끝만 둥글게). 주 경계로 잘린 쪽은 false = 각지게 이어 보인다.
public struct BandSegment: Equatable, Sendable {
    public let row: Int
    public let column: Int
    public let length: Int
    public let isStart: Bool
    public let isEnd: Bool

    public init(row: Int, column: Int, length: Int, isStart: Bool, isEnd: Bool) {
        self.row = row
        self.column = column
        self.length = length
        self.isStart = isStart
        self.isEnd = isEnd
    }
}

public enum ScheduleSpan {

    /// 시작~종료가 걸치는 날 수(자정 기준). 종료가 없거나 시작보다 이르면 1.
    public static func dayCount(start: Date, end: Date?, calendar: Calendar) -> Int {
        guard let end else { return 1 }
        let s = calendar.startOfDay(for: start)
        let e = calendar.startOfDay(for: end)
        guard let diff = calendar.dateComponents([.day], from: s, to: e).day else { return 1 }
        return max(1, diff + 1)
    }

    /// 그리드 칸별 포함 여부 → 주 단위 띠 조각.
    /// continuesBefore·continuesAfter = 그리드 밖(이전·다음 달)에서 이어지는지 — 월 경계에서 끝을 둥글게 하지 않기 위함.
    public static func bandSegments(cells: [Bool], columns: Int = 7,
                                    continuesBefore: Bool = false,
                                    continuesAfter: Bool = false) -> [BandSegment] {
        guard columns > 0 else { return [] }
        var out: [BandSegment] = []
        var i = 0
        while i < cells.count {
            guard cells[i] else {
                i += 1
                continue
            }
            let row = i / columns
            var j = i
            while j + 1 < cells.count, cells[j + 1], (j + 1) / columns == row { j += 1 }
            let isStart = i == 0 ? !continuesBefore : !cells[i - 1]
            let isEnd = j == cells.count - 1 ? !continuesAfter : !cells[j + 1]
            out.append(BandSegment(row: row, column: i % columns, length: j - i + 1,
                                   isStart: isStart, isEnd: isEnd))
            i = j + 1
        }
        return out
    }
}
