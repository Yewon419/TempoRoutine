// 템포루틴 — KoreanHolidays 테스트 (T90~)
// 대체공휴일 규칙(2023 개정)과 음력 테이블(2024~2028 웹 검증)을 못 박는다.

import XCTest
@testable import TempoCore

final class KoreanHolidaysTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func names(_ y: Int, _ m: Int, _ d: Int) -> [String] {
        KoreanHolidays.holidays(on: date(y, m, d), calendar: cal).map(\.name)
    }

    // T90: 고정일 공휴일
    func testT90_fixedHolidays() {
        XCTAssertEqual(names(2026, 1, 1), ["신정"])
        XCTAssertEqual(names(2026, 5, 5), ["어린이날"])
        XCTAssertEqual(names(2026, 10, 9), ["한글날"])
        XCTAssertEqual(names(2026, 12, 25), ["성탄절"])
    }

    // T91: 음력 명절 테이블 — 2026 설·추석·석탄일
    func testT91_lunar2026() {
        XCTAssertEqual(names(2026, 2, 16), ["설 연휴"])
        XCTAssertEqual(names(2026, 2, 17), ["설날"])
        XCTAssertEqual(names(2026, 2, 18), ["설 연휴"])
        XCTAssertEqual(names(2026, 5, 24), ["석가탄신일"])
        XCTAssertEqual(names(2026, 5, 25), ["대체공휴일"])
        XCTAssertEqual(names(2026, 9, 25), ["추석"])
    }

    // T92: 규칙 기반 대체공휴일 — 2026 삼일절(일)·광복절(토)·개천절(토)
    func testT92_ruleSubstitutes2026() {
        XCTAssertEqual(names(2026, 3, 2), ["대체공휴일(삼일절)"])
        XCTAssertEqual(names(2026, 8, 17), ["대체공휴일(광복절)"])
        XCTAssertEqual(names(2026, 10, 5), ["대체공휴일(개천절)"])
    }

    // T93: 대체 미적용 — 현충일 2026-06-06(토)은 대체 없음
    func testT93_noSubstituteForHyunchung() {
        XCTAssertEqual(names(2026, 6, 6), ["현충일"])
        XCTAssertEqual(names(2026, 6, 8), [])
    }

    // T94: 겹침 — 2025 어린이날 = 석가탄신일(같은 날 두 이름), 다음 날 대체
    func testT94_overlap2025() {
        XCTAssertEqual(Set(names(2025, 5, 5)), Set(["어린이날", "석가탄신일"]))
        XCTAssertEqual(names(2025, 5, 6), ["대체공휴일"])
    }

    // T95: 기념일 — 공휴일 아님(isPublic=false)
    func testT95_commemorations() {
        let jeheon = KoreanHolidays.holidays(on: date(2026, 7, 17), calendar: cal)
        XCTAssertEqual(jeheon.map(\.name), ["제헌절"])
        XCTAssertEqual(jeheon.first?.isPublic, false)
        XCTAssertEqual(names(2026, 5, 8), ["어버이날"])
        XCTAssertEqual(names(2026, 10, 1), ["국군의 날"])
    }

    // T96: 2027 설 연휴 + 대체(설날 일요일)
    func testT96_lunar2027() {
        XCTAssertEqual(names(2027, 2, 7), ["설날"])
        XCTAssertEqual(names(2027, 2, 9), ["대체공휴일"])
    }

    // T97: 2028 추석·개천절 겹침 — 10/3은 개천절(고정)로 표기, 대체는 10/5
    func testT97_chuseok2028() {
        XCTAssertEqual(names(2028, 10, 3), ["개천절"])
        XCTAssertEqual(names(2028, 10, 2), ["추석 연휴"])
        XCTAssertEqual(names(2028, 10, 5), ["대체공휴일"])
    }

    // T98: 테이블 밖 연도 — 음력 명절은 미표기(빈 배열), 고정일은 정상
    func testT98_outsideTable() {
        XCTAssertEqual(names(2030, 2, 3), [])            // 설날이지만 테이블 밖
        XCTAssertEqual(names(2030, 3, 1), ["삼일절"])     // 고정일은 연도 무관
    }

    // T99: 평일·무표기 날
    func testT99_plainDay() {
        XCTAssertEqual(names(2026, 7, 28), [])
        XCTAssertEqual(names(2026, 11, 11), [])
    }
}
