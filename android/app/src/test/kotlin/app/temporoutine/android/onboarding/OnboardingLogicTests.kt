// 온보딩 순수 규칙 — 캘린더 채움 캡·에피소드 분기·달 이동 상한·자 입력 값을 고정.

package app.temporoutine.android.onboarding

import org.junit.jupiter.api.Test
import java.time.LocalDate
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class OnboardingLogicTests {

    private val today = LocalDate.of(2026, 9, 5)

    @Test fun fillDaysCapsAtToday() {
        assertEquals((20..24).map { LocalDate.of(2026, 8, it) }, BaselineLogic.fillDays(LocalDate.of(2026, 8, 20), 5, today))
        // 시작 9/3 + 5일 = 9/3..9/7 → 오늘(9/5) 이후 잘림
        assertEquals((3..5).map { LocalDate.of(2026, 9, it) }, BaselineLogic.fillDays(LocalDate.of(2026, 9, 3), 5, today))
        assertEquals(listOf(today), BaselineLogic.fillDays(today, 1, today))
    }

    @Test fun cycleQuestionOnlyForSingleEpisode() {
        assertFalse(BaselineLogic.asksCycleLength(0))
        assertTrue(BaselineLogic.asksCycleLength(1))
        assertFalse(BaselineLogic.asksCycleLength(2), "실측 gap 있음 → 안 묻는다")
    }

    @Test fun calendarForwardBound() {
        assertTrue(BaselineLogic.canGoForward(LocalDate.of(2026, 8, 1), today), "8월 → 9월 가능")
        assertFalse(BaselineLogic.canGoForward(LocalDate.of(2026, 9, 1), today), "9월 → 10월은 미래")
        assertTrue(BaselineLogic.canGoForward(LocalDate.of(2026, 8, 1), LocalDate.of(2026, 9, 1)), "다음 달 1일 = 오늘이면 가능")
    }

    /** 자(ruler) 위치 → 값 — 좌단 22dp 여백 기준 반올림 + 범위 캡(iOS RulerSlider). */
    @Test fun rulerValueRoundsAndClamps() {
        val usable = 300f
        assertEquals(1, BaselineLogic.rulerValue(0f, 22f, usable, 1..10), "왼쪽 여백 안 = 최솟값")
        assertEquals(10, BaselineLogic.rulerValue(22f + usable + 40f, 22f, usable, 1..10), "오른쪽 넘침 = 최댓값")
        assertEquals(5, BaselineLogic.rulerValue(22f + usable * 4 / 9, 22f, usable, 1..10))
        assertEquals(28, BaselineLogic.rulerValue(22f + usable * 7 / 14 + 1f, 22f, usable, 21..35))
    }
}
