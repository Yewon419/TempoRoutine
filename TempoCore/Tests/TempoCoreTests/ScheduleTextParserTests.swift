// 템포루틴 — ScheduleTextParser 테스트 (빠른 일정 시각 파싱, T60~)
// 여기 케이스가 곧 명세다 — 12시간제 해석 규칙(수식어 없으면 1~6시=오후)도 테스트로 고정한다.

import XCTest
@testable import TempoCore

final class ScheduleTextParserTests: XCTestCase {

    private func parse(_ s: String) -> ParsedScheduleText { ScheduleTextParser.parse(s) }

    private func assertTime(_ text: String, _ hour: Int, _ minute: Int, title: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        let r = parse(text)
        XCTAssertEqual(r.start, ParsedTime(hour: hour, minute: minute), text, file: file, line: line)
        XCTAssertEqual(r.title, title, text, file: file, line: line)
    }

    // T60: 수식어 없는 "N시" — 1~6시는 오후, 7~12시는 오전(일상 관례)
    func testT60_bareHourMeridiemHeuristic() {
        assertTime("회의 3시", 15, 0, title: "회의")
        assertTime("3시 회의", 15, 0, title: "회의")
        assertTime("조깅 8시", 8, 0, title: "조깅")
        assertTime("점심 약속 12시", 12, 0, title: "점심 약속")
        assertTime("퇴근 6시", 18, 0, title: "퇴근")
        assertTime("마감 17시", 17, 0, title: "마감")
    }

    // T60b: 실사용 어구 — 명사 + 시각(2026-07-26 사용자 제보 확인용)
    func testT60b_realPhrases() {
        assertTime("약속 9시", 9, 0, title: "약속")
        assertTime("약속9시", 9, 0, title: "약속")
        assertTime("친구 약속 9시", 9, 0, title: "친구 약속")
        assertTime("병원 예약 10시", 10, 0, title: "병원 예약")
        assertTime("스터디 2시", 14, 0, title: "스터디")
    }

    // T60c: 알려진 한계 — 수식어가 숫자에서 떨어져 있으면 못 쓴다("저녁 … 9시" → 09:00).
    // 문맥 수식어 적용은 미도입(2026-07-26) — 이 테스트는 현재 동작을 고정해 회귀를 잡는 용도.
    func testT60c_detachedModifierNotApplied() {
        assertTime("저녁 약속 9시", 9, 0, title: "저녁 약속")
    }

    // T61: 수식어 — 오전·아침 / 오후·점심·저녁 / 밤 / 새벽
    func testT61_modifiers() {
        assertTime("오전 9시 병원", 9, 0, title: "병원")
        assertTime("아침 7시 산책", 7, 0, title: "산책")
        assertTime("오후 2시 미팅", 14, 0, title: "미팅")
        assertTime("저녁 7시 약속", 19, 0, title: "약속")
        assertTime("점심 1시 식사", 13, 0, title: "식사")
        assertTime("새벽 2시 알람", 2, 0, title: "알람")
        assertTime("밤 9시 스트레칭", 21, 0, title: "스트레칭")
    }

    // T62: 12시 경계 — 오전 12시·밤 12시 = 자정 / 오후 12시 = 정오
    func testT62_twelveBoundary() {
        assertTime("오전 12시 마감", 0, 0, title: "마감")
        assertTime("밤 12시 마감", 0, 0, title: "마감")
        assertTime("오후 12시 점심", 12, 0, title: "점심")
        assertTime("정오 산책", 12, 0, title: "산책")
        assertTime("자정 마감", 0, 0, title: "마감")
    }

    // T63: 분 — "30분" / "반" / 콜론 표기
    func testT63_minutes() {
        assertTime("3시 30분 미팅", 15, 30, title: "미팅")
        assertTime("3시30분 미팅", 15, 30, title: "미팅")
        assertTime("3시반 미팅", 15, 30, title: "미팅")
        assertTime("9:30 스터디", 9, 30, title: "스터디")
        assertTime("15:00 회의", 15, 0, title: "회의")
        // 콜론 표기는 24시간제로 그대로 읽는다(1~6시 오후 보정 안 함)
        assertTime("3:00 기상", 3, 0, title: "기상")
    }

    // T64: 조사·얼버무림 어미는 제목에 남기지 않는다
    func testT64_particlesStripped() {
        assertTime("3시에 회의", 15, 0, title: "회의")
        assertTime("10시쯤 전화", 10, 0, title: "전화")
        assertTime("회의 3시경", 15, 0, title: "회의")
        assertTime("3시에는 낮잠", 15, 0, title: "낮잠")
    }

    // T65: 범위 — "~", "-", "부터 ~ 까지". 뒤 시각은 앞 시각 이후로 당겨 읽는다.
    func testT65_ranges() {
        let a = parse("3시~5시 스터디")
        XCTAssertEqual(a.start, ParsedTime(hour: 15, minute: 0))
        XCTAssertEqual(a.end, ParsedTime(hour: 17, minute: 0))
        XCTAssertEqual(a.title, "스터디")

        let b = parse("오후 3시부터 5시까지 스터디")
        XCTAssertEqual(b.start, ParsedTime(hour: 15, minute: 0))
        XCTAssertEqual(b.end, ParsedTime(hour: 17, minute: 0))
        XCTAssertEqual(b.title, "스터디")

        let c = parse("11시-2시 외출")
        XCTAssertEqual(c.start, ParsedTime(hour: 11, minute: 0))
        XCTAssertEqual(c.end, ParsedTime(hour: 14, minute: 0))
        XCTAssertEqual(c.title, "외출")

        let d = parse("9시~11시 강의")
        XCTAssertEqual(d.start, ParsedTime(hour: 9, minute: 0))
        XCTAssertEqual(d.end, ParsedTime(hour: 11, minute: 0))
        XCTAssertEqual(d.title, "강의")

        // 종료 시각이 없으면 시작만
        let e = parse("3시부터 청소")
        XCTAssertEqual(e.start, ParsedTime(hour: 15, minute: 0))
        XCTAssertNil(e.end)
        XCTAssertEqual(e.title, "청소")
    }

    // T66: 시각이 아닌 것 — 기간·큰 수·단위 없는 숫자·범위 밖
    func testT66_notATime() {
        for text in ["3시간 공부", "24시간 운영", "회의", "2026 계획", "3 회의", "25시 회의", "1234 정산"] {
            let r = parse(text)
            XCTAssertNil(r.start, text)
            XCTAssertEqual(r.title, text, text)
        }
    }

    // T67: 숫자 한가운데서 다시 스캔하지 않는다 — "25시"가 "5시"로 읽히면 안 된다
    func testT67_noMidNumberRescan() {
        XCTAssertNil(parse("25시").start)
        XCTAssertNil(parse("100시").start)
    }

    // T68: 제목이 시각뿐이면 빈 제목(저장은 UI가 막는다)
    func testT68_timeOnly() {
        let r = parse("3시")
        XCTAssertEqual(r.start, ParsedTime(hour: 15, minute: 0))
        XCTAssertEqual(r.title, "")
        XCTAssertEqual(r.matchedText, "3시")
    }

    // T69: 빈 입력·공백
    func testT69_empty() {
        XCTAssertEqual(parse("").title, "")
        XCTAssertNil(parse("   ").start)
        XCTAssertEqual(parse("   ").title, "")
    }

    // T70: 인식 근거 조각(UI 표시용)
    func testT70_matchedText() {
        XCTAssertEqual(parse("오후 3시 회의").matchedText, "오후 3시")
        XCTAssertEqual(parse("3시~5시 스터디").matchedText, "3시~5시")
        XCTAssertNil(parse("회의").matchedText)
    }

    // T72: 오전·오후 모호 판정 — UI가 두 칩을 띄우는 조건(2026-07-26)
    func testT72_ambiguousMeridiem() {
        for text in ["약속 9시", "회의 3시", "12시 점심", "3시반 미팅", "3시 30분 미팅"] {
            XCTAssertTrue(parse(text).ambiguousMeridiem, text)
        }
        // 수식어를 썼거나 24시간 표기면 모호하지 않다
        for text in ["오전 9시 병원", "저녁 7시 약속", "밤 12시 마감", "15:00 회의", "9:30 스터디",
                     "정오 산책", "자정 마감", "회의"] {
            XCTAssertFalse(parse(text).ambiguousMeridiem, text)
        }
    }

    // T71: 첫 시각만 쓴다(뒤에 또 있어도 무시)
    func testT71_firstOnly() {
        let r = parse("3시 회의 준비 5시 발표")
        XCTAssertEqual(r.start, ParsedTime(hour: 15, minute: 0))
        XCTAssertNil(r.end)
        XCTAssertEqual(r.title, "회의 준비 5시 발표")
    }
}
