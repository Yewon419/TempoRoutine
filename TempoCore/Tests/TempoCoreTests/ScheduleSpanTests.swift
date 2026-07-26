// 템포루틴 — ScheduleSpan 테스트 (여러 날 일정, T80~)
// 주 경계에서 잘린 쪽은 각지게(isStart/isEnd = false), 실제 시작·끝만 둥글게 — 이 규칙을 못 박는다.

import XCTest
@testable import TempoCore

final class ScheduleSpanTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0, minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
    }

    /// 그리드 칸 포함 배열 만들기 — trueRange의 인덱스만 true
    private func cells(_ count: Int, _ trueIndices: [Int]) -> [Bool] {
        (0..<count).map { trueIndices.contains($0) }
    }

    // T80: 기간 계산 — 종료 없음·같은 날·여러 날·거꾸로
    func testT80_dayCount() {
        XCTAssertEqual(ScheduleSpan.dayCount(start: date(2026, 8, 3), end: nil, calendar: cal), 1)
        XCTAssertEqual(ScheduleSpan.dayCount(start: date(2026, 8, 3, hour: 9),
                                             end: date(2026, 8, 3, hour: 18), calendar: cal), 1)
        XCTAssertEqual(ScheduleSpan.dayCount(start: date(2026, 8, 3),
                                             end: date(2026, 8, 5), calendar: cal), 3)
        // 밤 11시 → 다음 날 새벽 1시 = 이틀에 걸침
        XCTAssertEqual(ScheduleSpan.dayCount(start: date(2026, 8, 3, hour: 23),
                                             end: date(2026, 8, 4, hour: 1), calendar: cal), 2)
        // 종료가 시작보다 이르면 1로 클램프
        XCTAssertEqual(ScheduleSpan.dayCount(start: date(2026, 8, 5),
                                             end: date(2026, 8, 3), calendar: cal), 1)
        // 월 경계
        XCTAssertEqual(ScheduleSpan.dayCount(start: date(2026, 7, 30),
                                             end: date(2026, 8, 2), calendar: cal), 4)
    }

    // T81: 한 주 안에서 이어지는 3일 → 조각 1개, 양 끝 둥글게
    func testT81_singleWeekRun() {
        let segments = ScheduleSpan.bandSegments(cells: cells(14, [8, 9, 10]))
        XCTAssertEqual(segments, [BandSegment(row: 1, column: 1, length: 3, isStart: true, isEnd: true)])
    }

    // T82: 주 경계를 넘으면 조각 2개 — 잘린 쪽은 각지게
    func testT82_weekBoundarySplit() {
        // 금(5)~월(8)
        let segments = ScheduleSpan.bandSegments(cells: cells(21, [5, 6, 7, 8]))
        XCTAssertEqual(segments, [
            BandSegment(row: 0, column: 5, length: 2, isStart: true, isEnd: false),
            BandSegment(row: 1, column: 0, length: 2, isStart: false, isEnd: true),
        ])
    }

    // T83: 3주에 걸치면 가운데 조각은 양쪽 다 각지게
    func testT83_threeWeeks() {
        let segments = ScheduleSpan.bandSegments(cells: cells(21, Array(6...15)))
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0], BandSegment(row: 0, column: 6, length: 1, isStart: true, isEnd: false))
        XCTAssertEqual(segments[1], BandSegment(row: 1, column: 0, length: 7, isStart: false, isEnd: false))
        XCTAssertEqual(segments[2], BandSegment(row: 2, column: 0, length: 2, isStart: false, isEnd: true))
    }

    // T84: 달 밖에서 이어지면 그 끝은 둥글지 않다
    func testT84_monthBoundaryContinuation() {
        let head = ScheduleSpan.bandSegments(cells: cells(7, [0, 1]), continuesBefore: true)
        XCTAssertEqual(head, [BandSegment(row: 0, column: 0, length: 2, isStart: false, isEnd: true)])

        let tail = ScheduleSpan.bandSegments(cells: cells(7, [5, 6]), continuesAfter: true)
        XCTAssertEqual(tail, [BandSegment(row: 0, column: 5, length: 2, isStart: true, isEnd: false)])
    }

    // T85: 반복으로 끊긴 두 구간 → 각각 양 끝 둥글게
    func testT85_repeatedRunsAreSeparate() {
        let segments = ScheduleSpan.bandSegments(cells: cells(21, [1, 2, 8, 9]))
        XCTAssertEqual(segments, [
            BandSegment(row: 0, column: 1, length: 2, isStart: true, isEnd: true),
            BandSegment(row: 1, column: 1, length: 2, isStart: true, isEnd: true),
        ])
    }

    // T86: 하루짜리·빈 배열·전 구간
    func testT86_edges() {
        XCTAssertEqual(ScheduleSpan.bandSegments(cells: cells(7, [3])),
                       [BandSegment(row: 0, column: 3, length: 1, isStart: true, isEnd: true)])
        XCTAssertEqual(ScheduleSpan.bandSegments(cells: cells(7, [])), [])
        XCTAssertEqual(ScheduleSpan.bandSegments(cells: []), [])
        let full = ScheduleSpan.bandSegments(cells: cells(14, Array(0...13)))
        XCTAssertEqual(full.count, 2)
        XCTAssertEqual(full[0], BandSegment(row: 0, column: 0, length: 7, isStart: true, isEnd: false))
        XCTAssertEqual(full[1], BandSegment(row: 1, column: 0, length: 7, isStart: false, isEnd: true))
    }
}
