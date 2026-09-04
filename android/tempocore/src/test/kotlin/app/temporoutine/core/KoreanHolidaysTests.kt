// 템포루틴 — KoreanHolidays 테스트 (T90~)
// iOS TempoCoreTests/KoreanHolidaysTests.swift 1:1 이식.

package app.temporoutine.core

import org.junit.jupiter.api.Test
import java.time.LocalDate
import kotlin.test.assertEquals

class KoreanHolidaysTests {

    private fun names(y: Int, m: Int, d: Int): List<String> = KoreanHolidays.holidays(LocalDate.of(y, m, d)).map { it.name }

    // T90: 고정일 공휴일
    @Test fun testT90_fixedHolidays() {
        assertEquals(listOf("신정"), names(2026, 1, 1))
        assertEquals(listOf("어린이날"), names(2026, 5, 5))
        assertEquals(listOf("한글날"), names(2026, 10, 9))
        assertEquals(listOf("성탄절"), names(2026, 12, 25))
    }

    // T91: 음력 명절 테이블 — 2026
    @Test fun testT91_lunar2026() {
        assertEquals(listOf("설 연휴"), names(2026, 2, 16))
        assertEquals(listOf("설날"), names(2026, 2, 17))
        assertEquals(listOf("설 연휴"), names(2026, 2, 18))
        assertEquals(listOf("석가탄신일"), names(2026, 5, 24))
        assertEquals(listOf("대체공휴일"), names(2026, 5, 25))
        assertEquals(listOf("추석"), names(2026, 9, 25))
    }

    // T92: 규칙 기반 대체공휴일
    @Test fun testT92_ruleSubstitutes2026() {
        assertEquals(listOf("대체공휴일(삼일절)"), names(2026, 3, 2))
        assertEquals(listOf("대체공휴일(광복절)"), names(2026, 8, 17))
        assertEquals(listOf("대체공휴일(개천절)"), names(2026, 10, 5))
    }

    // T93: 대체 미적용 — 현충일
    @Test fun testT93_noSubstituteForHyunchung() {
        assertEquals(listOf("현충일"), names(2026, 6, 6))
        assertEquals(emptyList(), names(2026, 6, 8))
    }

    // T94: 겹침 — 2025 어린이날 = 석가탄신일
    @Test fun testT94_overlap2025() {
        assertEquals(setOf("어린이날", "석가탄신일"), names(2025, 5, 5).toSet())
        assertEquals(listOf("대체공휴일"), names(2025, 5, 6))
    }

    // T95: 기념일
    @Test fun testT95_commemorations() {
        val jeheon = KoreanHolidays.holidays(LocalDate.of(2026, 7, 17))
        assertEquals(listOf("제헌절"), jeheon.map { it.name })
        assertEquals(false, jeheon.firstOrNull()?.isPublic)
        assertEquals(listOf("어버이날"), names(2026, 5, 8))
        assertEquals(listOf("국군의 날"), names(2026, 10, 1))
    }

    // T96: 2027 설 연휴 + 대체
    @Test fun testT96_lunar2027() {
        assertEquals(listOf("설날"), names(2027, 2, 7))
        assertEquals(listOf("대체공휴일"), names(2027, 2, 9))
    }

    // T97: 2028 추석·개천절 겹침
    @Test fun testT97_chuseok2028() {
        assertEquals(listOf("개천절"), names(2028, 10, 3))
        assertEquals(listOf("추석 연휴"), names(2028, 10, 2))
        assertEquals(listOf("대체공휴일"), names(2028, 10, 5))
    }

    // T98: 테이블 밖 연도
    @Test fun testT98_outsideTable() {
        assertEquals(emptyList(), names(2030, 2, 3))
        assertEquals(listOf("삼일절"), names(2030, 3, 1))
    }

    // T99: 평일
    @Test fun testT99_plainDay() {
        assertEquals(emptyList(), names(2026, 7, 28))
        assertEquals(emptyList(), names(2026, 11, 11))
    }
}
