// 템포루틴 — PeriodMath 테스트 (MASTER §5.5.4, T20~)
// 기존 CyclePredictorTests(T1~T16, 검증본 25/25)는 불변 — 여기는 파생 함수 전용.

import XCTest
@testable import TempoCore

final class PeriodMathTests: XCTestCase {

    private let cal = Calendar.current

    private func day(_ offset: Int) -> Date {
        cal.startOfDay(for: cal.date(byAdding: .day, value: offset, to: Date())!)
    }

    // T20: 빈 배열 → 에피소드 없음
    func testT20_emptyDays() {
        XCTAssertEqual(PeriodMath.episodes(days: []).count, 0)
        XCTAssertEqual(PeriodMath.episodeStarts(days: []), [])
    }

    // T21: 연속 5일 → 에피소드 1개, 시작일 = 최소 day
    func testT21_singleContiguousEpisode() {
        let days = (0..<5).map { day($0) }
        let starts = PeriodMath.episodeStarts(days: days)
        XCTAssertEqual(starts, [day(0)])
    }

    // T22: 두 에피소드 (0~4일차, 28~31일차) → 시작일 2개
    func testT22_twoEpisodes() {
        let days = (0..<5).map { day($0) } + (28..<32).map { day($0) }
        let starts = PeriodMath.episodeStarts(days: days)
        XCTAssertEqual(starts, [day(0), day(28)])
    }

    // T23: 시작일 + 13일 기록 = 갭 14 미만 → 같은 에피소드
    func testT23_gapBelowMinIsSameEpisode() {
        let days = [day(0), day(13)]
        let episodes = PeriodMath.episodes(days: days)
        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(PeriodMath.episodeStarts(days: days), [day(0)])
    }

    // T24: 시작일 + 14일 = 경계 → 새 에피소드
    func testT24_gapAtMinIsNewEpisode() {
        let days = [day(0), day(14)]
        XCTAssertEqual(PeriodMath.episodeStarts(days: days), [day(0), day(14)])
    }

    // T25: 비정렬·중복 입력 허용 → 정렬·dedup 후 동일 결과
    func testT25_unsortedDuplicatedInput() {
        let days = [day(28), day(1), day(0), day(1), day(29), day(2)]
        let starts = PeriodMath.episodeStarts(days: days)
        XCTAssertEqual(starts, [day(0), day(28)])
        let episodes = PeriodMath.episodes(days: days)
        XCTAssertEqual(episodes[0], [day(0), day(1), day(2)])
        XCTAssertEqual(episodes[1], [day(28), day(29)])
    }

    // T26: 불연속 day 허용 — 에피소드 내부 결측(HK 타앱 import 대비)
    func testT26_nonContiguousDaysWithinEpisode() {
        let days = [day(0), day(2), day(4), day(30)]
        let episodes = PeriodMath.episodes(days: days)
        XCTAssertEqual(episodes.count, 2)
        XCTAssertEqual(episodes[0], [day(0), day(2), day(4)])
        XCTAssertEqual(PeriodMath.episodeStarts(days: days), [day(0), day(30)])
    }

    // T27: 파생 → 엔진 입력 연결 — episodeStarts가 averageLength에 그대로 들어간다
    func testT27_feedsEngine() {
        let days = (0..<5).map { day($0) } + (28..<33).map { day($0) } + (56..<60).map { day($0) }
        let starts = PeriodMath.episodeStarts(days: days)
        XCTAssertEqual(starts.count, 3)
        XCTAssertEqual(CyclePredictor.averageLength(startDates: starts), 28)
    }
}
