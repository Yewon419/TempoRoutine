// 템포루틴 — ScheduleTextParser 테스트 (빠른 일정 시각 파싱, T60~)
// iOS TempoCoreTests/ScheduleTextParserTests.swift 1:1 이식. 여기 케이스가 곧 명세다.

package app.temporoutine.core

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ScheduleTextParserTests {

    private fun parse(s: String): ParsedScheduleText = ScheduleTextParser.parse(s)

    private fun assertTime(text: String, hour: Int, minute: Int, title: String) {
        val r = parse(text)
        assertEquals(ParsedTime(hour, minute), r.start, text)
        assertEquals(title, r.title, text)
    }

    // T60: 수식어 없는 "N시" — 1~6시는 오후, 7~12시는 오전
    @Test fun testT60_bareHourMeridiemHeuristic() {
        assertTime("회의 3시", 15, 0, "회의")
        assertTime("3시 회의", 15, 0, "회의")
        assertTime("조깅 8시", 8, 0, "조깅")
        assertTime("점심 약속 12시", 12, 0, "점심 약속")
        assertTime("퇴근 6시", 18, 0, "퇴근")
        assertTime("마감 17시", 17, 0, "마감")
    }

    // T60b: 실사용 어구
    @Test fun testT60b_realPhrases() {
        assertTime("약속 9시", 9, 0, "약속")
        assertTime("약속9시", 9, 0, "약속")
        assertTime("친구 약속 9시", 9, 0, "친구 약속")
        assertTime("병원 예약 10시", 10, 0, "병원 예약")
        assertTime("스터디 2시", 14, 0, "스터디")
    }

    // T60c: 알려진 한계 — 수식어가 숫자에서 떨어져 있으면 못 쓴다
    @Test fun testT60c_detachedModifierNotApplied() {
        assertTime("저녁 약속 9시", 9, 0, "저녁 약속")
    }

    // T61: 수식어
    @Test fun testT61_modifiers() {
        assertTime("오전 9시 병원", 9, 0, "병원")
        assertTime("아침 7시 산책", 7, 0, "산책")
        assertTime("오후 2시 미팅", 14, 0, "미팅")
        assertTime("저녁 7시 약속", 19, 0, "약속")
        assertTime("점심 1시 식사", 13, 0, "식사")
        assertTime("새벽 2시 알람", 2, 0, "알람")
        assertTime("밤 9시 스트레칭", 21, 0, "스트레칭")
    }

    // T62: 12시 경계
    @Test fun testT62_twelveBoundary() {
        assertTime("오전 12시 마감", 0, 0, "마감")
        assertTime("밤 12시 마감", 0, 0, "마감")
        assertTime("오후 12시 점심", 12, 0, "점심")
        assertTime("정오 산책", 12, 0, "산책")
        assertTime("자정 마감", 0, 0, "마감")
    }

    // T63: 분
    @Test fun testT63_minutes() {
        assertTime("3시 30분 미팅", 15, 30, "미팅")
        assertTime("3시30분 미팅", 15, 30, "미팅")
        assertTime("3시반 미팅", 15, 30, "미팅")
        assertTime("9:30 스터디", 9, 30, "스터디")
        assertTime("15:00 회의", 15, 0, "회의")
        assertTime("3:00 기상", 3, 0, "기상")
    }

    // T64: 조사·얼버무림 어미
    @Test fun testT64_particlesStripped() {
        assertTime("3시에 회의", 15, 0, "회의")
        assertTime("10시쯤 전화", 10, 0, "전화")
        assertTime("회의 3시경", 15, 0, "회의")
        assertTime("3시에는 낮잠", 15, 0, "낮잠")
    }

    // T65: 범위
    @Test fun testT65_ranges() {
        val a = parse("3시~5시 스터디")
        assertEquals(ParsedTime(15, 0), a.start)
        assertEquals(ParsedTime(17, 0), a.end)
        assertEquals("스터디", a.title)

        val b = parse("오후 3시부터 5시까지 스터디")
        assertEquals(ParsedTime(15, 0), b.start)
        assertEquals(ParsedTime(17, 0), b.end)
        assertEquals("스터디", b.title)

        val c = parse("11시-2시 외출")
        assertEquals(ParsedTime(11, 0), c.start)
        assertEquals(ParsedTime(14, 0), c.end)
        assertEquals("외출", c.title)

        val d = parse("9시~11시 강의")
        assertEquals(ParsedTime(9, 0), d.start)
        assertEquals(ParsedTime(11, 0), d.end)
        assertEquals("강의", d.title)

        val e = parse("3시부터 청소")
        assertEquals(ParsedTime(15, 0), e.start)
        assertNull(e.end)
        assertEquals("청소", e.title)
    }

    // T66: 시각이 아닌 것
    @Test fun testT66_notATime() {
        for (text in listOf("3시간 공부", "24시간 운영", "회의", "2026 계획", "3 회의", "25시 회의", "1234 정산")) {
            val r = parse(text)
            assertNull(r.start, text)
            assertEquals(text, r.title, text)
        }
    }

    // T67: 숫자 한가운데서 다시 스캔하지 않는다
    @Test fun testT67_noMidNumberRescan() {
        assertNull(parse("25시").start)
        assertNull(parse("100시").start)
    }

    // T68: 제목이 시각뿐이면 빈 제목
    @Test fun testT68_timeOnly() {
        val r = parse("3시")
        assertEquals(ParsedTime(15, 0), r.start)
        assertEquals("", r.title)
        assertEquals("3시", r.matchedText)
    }

    // T69: 빈 입력·공백
    @Test fun testT69_empty() {
        assertEquals("", parse("").title)
        assertNull(parse("   ").start)
        assertEquals("", parse("   ").title)
    }

    // T70: 인식 근거 조각
    @Test fun testT70_matchedText() {
        assertEquals("오후 3시", parse("오후 3시 회의").matchedText)
        assertEquals("3시~5시", parse("3시~5시 스터디").matchedText)
        assertNull(parse("회의").matchedText)
    }

    // T72: 오전·오후 모호 판정
    @Test fun testT72_ambiguousMeridiem() {
        for (text in listOf("약속 9시", "회의 3시", "12시 점심", "3시반 미팅", "3시 30분 미팅")) {
            assertTrue(parse(text).ambiguousMeridiem, text)
        }
        for (text in listOf("오전 9시 병원", "저녁 7시 약속", "밤 12시 마감", "15:00 회의", "9:30 스터디",
            "정오 산책", "자정 마감", "회의")) {
            assertFalse(parse(text).ambiguousMeridiem, text)
        }
    }

    // T71: 첫 시각만 쓴다
    @Test fun testT71_firstOnly() {
        val r = parse("3시 회의 준비 5시 발표")
        assertEquals(ParsedTime(15, 0), r.start)
        assertNull(r.end)
        assertEquals("회의 준비 5시 발표", r.title)
    }
}
