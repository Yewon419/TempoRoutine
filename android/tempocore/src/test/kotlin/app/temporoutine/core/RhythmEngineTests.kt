// 리듬 집계 엔진 테스트 (MASTER §5.6.3)
// iOS TempoCoreTests/RhythmEngineTests.swift 1:1 이식.

package app.temporoutine.core

import org.junit.jupiter.api.Test
import java.time.LocalDate
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class RhythmEngineTests {

    private fun day(base: LocalDate, offset: Int): LocalDate = base.plusDays(offset.toLong())
    private val base: LocalDate = LocalDate.of(2026, 1, 5)

    /** 28일 주기 2개 + 진행 중 1개 — starts = 0, 28, 56일차. */
    private val starts: List<LocalDate> get() = listOf(base, day(base, 28), day(base, 56))

    @Test fun testBucketsMeanBySignalAndPhase() {
        val samples = listOf(
            SignalSample(day(base, 0), energy = 2, mood = 3, sleep = null),
            SignalSample(day(base, 1), energy = 2, mood = 3, sleep = null),
            SignalSample(day(base, 15), energy = 4, mood = 5, sleep = 2),
        )
        val result = RhythmEngine.summaries(samples, starts, 28)

        val menstrualEnergy = result.firstOrNull { it.phase == CyclePhase.MENSTRUAL && it.signal == SignalKind.ENERGY }
        assertEquals(2.0, menstrualEnergy?.mean)
        assertEquals(2, menstrualEnergy?.sampleCount)

        assertNull(result.firstOrNull { it.phase == CyclePhase.MENSTRUAL && it.signal == SignalKind.SLEEP })
        assertEquals(1, result.firstOrNull { it.signal == SignalKind.SLEEP }?.sampleCount)
    }

    @Test fun testNoteOnlyRowsAreExcluded() {
        val samples = listOf(
            SignalSample(day(base, 0), energy = 0, mood = 0, sleep = 5),
            SignalSample(day(base, 1), energy = 3, mood = 0, sleep = null),
        )
        assertTrue(RhythmEngine.summaries(samples, starts, 28).isEmpty())
    }

    @Test fun testProjectedDaysAreExcluded() {
        val samples = listOf(SignalSample(day(base, 56 + 30), energy = 5, mood = 5, sleep = null))
        assertTrue(RhythmEngine.summaries(samples, starts, 28).isEmpty())
    }

    @Test fun testNarratableRequiresTwoPhasesAtThreshold() {
        var samples = (0..2).map { SignalSample(day(base, it), energy = 2, mood = 3, sleep = null) }
        var result = RhythmEngine.summaries(samples, starts, 28)
        assertFalse(RhythmEngine.narratable(result, SignalKind.ENERGY))

        samples = samples + (6..8).map { SignalSample(day(base, it), energy = 4, mood = 4, sleep = null) }
        result = RhythmEngine.summaries(samples, starts, 28)
        assertTrue(RhythmEngine.narratable(result, SignalKind.ENERGY))
        assertFalse(RhythmEngine.narratable(result, SignalKind.SLEEP))
    }

    @Test fun testPerCycleTopPhases() {
        val samples = mutableListOf<SignalSample>()
        for (cycleStart in listOf(0, 28)) {
            samples.add(SignalSample(day(base, cycleStart + 1), energy = 2, mood = 3, sleep = null))
            samples.add(SignalSample(day(base, cycleStart + 15), energy = 5, mood = 4, sleep = null))
        }
        val tops = RhythmEngine.perCycleTopPhases(SignalKind.ENERGY, samples, starts)
        assertEquals(listOf(CyclePhase.OVULATION, CyclePhase.OVULATION), tops)
    }

    @Test fun testCycleWithSinglePhaseIsSkipped() {
        val samples = listOf(
            SignalSample(day(base, 1), energy = 2, mood = 3, sleep = null),
            SignalSample(day(base, 28 + 1), energy = 2, mood = 3, sleep = null),
            SignalSample(day(base, 28 + 15), energy = 5, mood = 4, sleep = null),
        )
        assertEquals(listOf(CyclePhase.OVULATION), RhythmEngine.perCycleTopPhases(SignalKind.ENERGY, samples, starts))
    }

    @Test fun testNoCompletedCycles() {
        val samples = listOf(SignalSample(day(base, 1), energy = 3, mood = 3, sleep = null))
        assertTrue(RhythmEngine.perCycleTopPhases(SignalKind.ENERGY, samples, listOf(base)).isEmpty())
    }

    @Test fun testCyclesWithDataCountsOnlySampledCycles() {
        val samples = listOf(SignalSample(day(base, 30), energy = 3, mood = 3, sleep = 4))
        assertEquals(1, RhythmEngine.cyclesWithData(SignalKind.ENERGY, samples, starts))
        assertEquals(1, RhythmEngine.cyclesWithData(SignalKind.SLEEP, samples, starts))
        val invalid = listOf(SignalSample(day(base, 30), energy = 3, mood = 0, sleep = null))
        assertEquals(0, RhythmEngine.cyclesWithData(SignalKind.ENERGY, invalid, starts))
    }

    @Test fun testDayCurveBucketsByCycleDay() {
        val samples = listOf(
            SignalSample(day(base, 0), energy = 2, mood = 3, sleep = null),
            SignalSample(day(base, 28), energy = 4, mood = 3, sleep = null),
            SignalSample(day(base, 15), energy = 5, mood = 4, sleep = null),
        )
        val curve = RhythmEngine.dayCurve(SignalKind.ENERGY, samples, starts, 28)
        assertEquals(listOf(1, 16), curve.map { it.day })
        assertEquals(3.0, curve.first().mean)
        assertEquals(2, curve.first().sampleCount)
        assertEquals(5.0, curve.last().mean)
    }

    @Test fun testDayCurveExcludesProjectedAndOverflow() {
        val samples = listOf(
            SignalSample(day(base, 56 + 30), energy = 5, mood = 5, sleep = null),
            SignalSample(day(base, 1), energy = 3, mood = 3, sleep = null),
        )
        val curve = RhythmEngine.dayCurve(SignalKind.ENERGY, samples, starts, 28)
        assertEquals(listOf(2), curve.map { it.day })
    }

    @Test fun testDayCurveDropsDaysBeyondAverageLength() {
        val longStarts = listOf(base, day(base, 32))
        val samples = listOf(SignalSample(day(base, 30), energy = 4, mood = 4, sleep = null))
        assertTrue(RhythmEngine.dayCurve(SignalKind.ENERGY, samples, longStarts, 28).isEmpty())
    }

    @Test fun testDayCurveFollowsAdjustedCycleLength() {
        val starts30 = listOf(base, day(base, 30), day(base, 60))
        val samples = listOf(SignalSample(day(base, 29), energy = 4, mood = 4, sleep = null))
        assertEquals(listOf(30), RhythmEngine.dayCurve(SignalKind.ENERGY, samples, starts30, 30).map { it.day })
        assertTrue(RhythmEngine.dayCurve(SignalKind.ENERGY, samples, starts30, 28).isEmpty(), "28 기준 x축엔 30일차 자리가 없다")
    }

    @Test fun testDayCurveSkipsNilOptionalSignal() {
        val samples = listOf(
            SignalSample(day(base, 1), energy = 3, mood = 3, sleep = null),
            SignalSample(day(base, 2), energy = 3, mood = 3, sleep = 4),
        )
        val curve = RhythmEngine.dayCurve(SignalKind.SLEEP, samples, starts, 28)
        assertEquals(listOf(3), curve.map { it.day })
        assertEquals(4.0, curve.first().mean)
    }
}
