// 템포루틴 — 예측 렌더 지평 테스트 (T100~, §5.6.2 off-by-one 정정)
// iOS TempoCoreTests/ProjectionHorizonTests.swift 1:1 이식.

package app.temporoutine.core

import org.junit.jupiter.api.Test
import java.time.LocalDate
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class ProjectionHorizonTests {

    private fun day(base: LocalDate, offset: Int): LocalDate = base.plusDays(offset.toLong())

    // T100: h=1·n=28 — 지평이 첫 예상 월경 구간(L+28~L+32) 전체를 덮는다
    @Test fun testT100_horizonCoversFirstPredictedWindow() {
        val last = LocalDate.of(2026, 7, 1)
        val horizon = CyclePredictor.projectionHorizon(last, 28, horizonCycles = 1)
        for (offset in 28..32) {
            assertTrue(day(last, offset) <= horizon, "L+$offset")
        }
        assertTrue(day(last, 33) > horizon)
    }

    // T101: 예상 구간의 판정 조합 — projected + menstrual
    @Test fun testT101_predictedWindowIsProjectedMenstrual() {
        val last = LocalDate.of(2026, 7, 1)
        for (offset in 28..32) {
            val r = CyclePredictor.cycleDay(day(last, offset), listOf(last), 28)
            assertEquals(true, r?.projected, "L+$offset")
            assertEquals(CyclePhase.MENSTRUAL, r?.let { CyclePredictor.phaseForDay(it.day, 28) }, "L+$offset")
        }
        val before = CyclePredictor.cycleDay(day(last, 27), listOf(last), 28)
        assertNotEquals(CyclePhase.MENSTRUAL, before?.let { CyclePredictor.phaseForDay(it.day, 28) })
    }

    // T102: h=3 — 세 번째 예상 구간 끝(L+3n+4)까지
    @Test fun testT102_threeCycles() {
        val last = LocalDate.of(2026, 1, 10)
        val horizon = CyclePredictor.projectionHorizon(last, 30, horizonCycles = 3)
        assertTrue(day(last, 3 * 30 + 4) <= horizon)
        assertTrue(day(last, 3 * 30 + 5) > horizon)
    }
}
