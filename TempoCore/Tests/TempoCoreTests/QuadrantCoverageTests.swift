// 사분면 커버리지 테스트 (MASTER §5.12 ⑤)
// 막아야 할 것: ① 마지막 날이 5번째 사분면으로 새는 것 ② quadrant()와 dayRange()의 정의가 갈리는 것
// ③ 위상이 한쪽에 몰린 주기(적합이 죽는 입력)를 "비어 있음"으로 못 잡는 것

import XCTest
@testable import TempoCore

final class QuadrantCoverageTests: XCTestCase {

    private func signal(day: Int, length: Int, emotional: Double? = 3, bodily: Double? = nil) -> DailySignal {
        DailySignal(cycleDay: day, cycleLength: length, emotional: emotional, bodily: bodily)
    }

    func testQuadrantBoundaries() {
        XCTAssertEqual(QuadrantCoverage.quadrant(day: 1, cycleLength: 28), 0)
        XCTAssertEqual(QuadrantCoverage.quadrant(day: 7, cycleLength: 28), 0)
        XCTAssertEqual(QuadrantCoverage.quadrant(day: 8, cycleLength: 28), 1)
        XCTAssertEqual(QuadrantCoverage.quadrant(day: 21, cycleLength: 28), 2)
        XCTAssertEqual(QuadrantCoverage.quadrant(day: 22, cycleLength: 28), 3)
    }

    /// 마지막 날은 반드시 3이어야 한다 — 상한을 안 물리면 (L-1)*4/L 이 4가 되어 배열이 터진다.
    func testLastDayStaysInRange() {
        for length in 21...35 {
            XCTAssertEqual(QuadrantCoverage.quadrant(day: length, cycleLength: length), 3,
                           "length \(length)")
        }
    }

    func testOutOfRangeIsNil() {
        XCTAssertNil(QuadrantCoverage.quadrant(day: 0, cycleLength: 28))
        XCTAssertNil(QuadrantCoverage.quadrant(day: 29, cycleLength: 28))
        XCTAssertNil(QuadrantCoverage.quadrant(day: 1, cycleLength: 0))
    }

    /// 짧은 주기에서도 사분면이 하나도 비지 않아야 한다(모든 날을 넣었을 때).
    func testEveryQuadrantReachableForShortCycles() {
        for length in 4...35 {
            let signals = (1...length).map { signal(day: $0, length: length) }
            XCTAssertEqual(QuadrantCoverage.emptyQuadrants(signals), [], "length \(length)")
        }
    }

    func testCoverageCountsPerQuadrant() {
        let length = 28
        let signals = [1, 3, 9, 25].map { signal(day: $0, length: length) }
        XCTAssertEqual(QuadrantCoverage.coverage(signals), [2, 1, 0, 1])
        XCTAssertEqual(QuadrantCoverage.emptyQuadrants(signals), [2])
    }

    /// 두 계열이 다 없는 날은 기록으로 세지 않는다 — 적합에 안 들어가는 행이라 커버가 아니다.
    func testEmptySignalIsNotCounted() {
        let signals = [signal(day: 5, length: 28, emotional: nil, bodily: nil)]
        XCTAssertEqual(QuadrantCoverage.coverage(signals), [0, 0, 0, 0])
    }

    /// 신체만 기록된 날도 커버로 센다(계열별로 적합이 따로 돈다).
    func testBodilyOnlyCounts() {
        let signals = [signal(day: 5, length: 28, emotional: nil, bodily: 4)]
        XCTAssertEqual(QuadrantCoverage.coverage(signals), [1, 0, 0, 0])
    }

    /// dayRange는 quadrant()의 역함수여야 한다 — 두 정의가 갈리면 엉뚱한 날에 알림이 간다.
    func testDayRangeMatchesQuadrantFunction() {
        for length in 21...35 {
            for index in 0..<QuadrantCoverage.count {
                let range = QuadrantCoverage.dayRange(quadrant: index, cycleLength: length)
                XCTAssertNotNil(range, "length \(length) q \(index)")
                for day in range! {
                    XCTAssertEqual(QuadrantCoverage.quadrant(day: day, cycleLength: length), index,
                                   "length \(length) q \(index) day \(day)")
                }
            }
        }
    }

    /// 발화일은 그 사분면 안이고, 구간 끝이 아니어야 한다(만회할 하루가 남아야 한다).
    func testReminderDayIsInsideAndNotLast() {
        for length in 21...35 {
            for index in 0..<QuadrantCoverage.count {
                let day = QuadrantCoverage.reminderDay(quadrant: index, cycleLength: length)
                let range = QuadrantCoverage.dayRange(quadrant: index, cycleLength: length)
                XCTAssertNotNil(day)
                XCTAssertTrue(range!.contains(day!), "length \(length) q \(index)")
                if range!.count > 1 {
                    XCTAssertLessThan(day!, range!.upperBound, "length \(length) q \(index)")
                }
            }
        }
    }

    /// 한쪽 쏠림 = 반대쪽 윈도우가 비어 엔진이 침묵하는 입력. 그걸 빈 사분면으로 짚어내는 게 목적이다.
    /// (표본 수만 보면 주기당 최소 기록 관문은 통과한다 — 개수로는 못 거른다.)
    func testDetectsPhaseClustering() {
        let length = 28
        let clustered = (1...7).map { signal(day: $0, length: length) }
        XCTAssertGreaterThanOrEqual(clustered.count, WindowStatsEngine.minSamplesPerCycle)
        XCTAssertEqual(QuadrantCoverage.emptyQuadrants(clustered), [1, 2, 3])
    }
}
