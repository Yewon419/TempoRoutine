// 템포루틴 — 예측 렌더 지평 테스트 (T100~, §5.6.2 off-by-one 정정 2026-07-28)
// "예정일이 캘린더에 안 뜬다" 제보의 원인 — low(h=1)에서 예상 월경 구간이 하루로 잘리던 결함.

import XCTest
@testable import TempoCore

final class ProjectionHorizonTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return c
    }

    private func day(_ base: Date, _ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: base)!
    }

    // T100: h=1·n=28 — 지평이 첫 예상 월경 구간(L+28~L+32) 전체를 덮는다
    func testT100_horizonCoversFirstPredictedWindow() {
        let last = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        let horizon = CyclePredictor.projectionHorizon(lastStart: last, averageLength: 28,
                                                       horizonCycles: 1, calendar: cal)!
        // 월경 5일(§5.3 M=5): L+28 ~ L+32 전부 지평 안
        for offset in 28...32 {
            XCTAssertLessThanOrEqual(day(last, offset), horizon, "L+\(offset)")
        }
        XCTAssertGreaterThan(day(last, 33), horizon)   // 구간 끝 다음 날부터 밖
    }

    // T101: 예상 구간의 판정 조합 — projected + menstrual (캘린더 회색 형광펜 조건)
    func testT101_predictedWindowIsProjectedMenstrual() {
        let last = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        for offset in 28...32 {
            let d = day(last, offset)
            let r = CyclePredictor.cycleDay(of: d, periodStarts: [last], averageLength: 28)
            XCTAssertEqual(r?.projected, true, "L+\(offset)")
            XCTAssertEqual(r.map { CyclePredictor.phaseForDay($0.day, cycleLength: 28) },
                           .menstrual, "L+\(offset)")
        }
        // 구간 직전(황체기 끝)은 월경이 아니다
        let before = CyclePredictor.cycleDay(of: day(last, 27), periodStarts: [last], averageLength: 28)
        XCTAssertNotEqual(before.map { CyclePredictor.phaseForDay($0.day, cycleLength: 28) }, .menstrual)
    }

    // T102: h=3(high) — 세 번째 예상 구간 끝(L+3n+4)까지, 그 다음 날부터 밖
    func testT102_threeCycles() {
        let last = cal.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let horizon = CyclePredictor.projectionHorizon(lastStart: last, averageLength: 30,
                                                       horizonCycles: 3, calendar: cal)!
        XCTAssertLessThanOrEqual(day(last, 3 * 30 + 4), horizon)
        XCTAssertGreaterThan(day(last, 3 * 30 + 5), horizon)
    }
}
