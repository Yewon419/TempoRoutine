// 리듬 엔진(윈도우 통계) 테스트 — MASTER §5.12 개정 M.
// iOS TempoCoreTests/WindowStatsTests.swift 1:1 이식.

package app.temporoutine.core

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SignalConversionTests {

    @Test fun testMoodIsFlipped() {
        assertEquals(5.0, SignalConversion.emotional(mood = 1, irritability = null))
        assertEquals(1.0, SignalConversion.emotional(mood = 5, irritability = null))
    }

    @Test fun testIrritabilityIsNotFlipped() {
        assertEquals(5.0, SignalConversion.emotional(mood = null, irritability = 5))
        assertEquals(1.0, SignalConversion.emotional(mood = null, irritability = 1))
    }

    @Test fun testEmotionalAveragesBothItems() {
        assertEquals(5.0, SignalConversion.emotional(mood = 1, irritability = 5))
        assertEquals(1.0, SignalConversion.emotional(mood = 5, irritability = 1))
        assertEquals(3.0, SignalConversion.emotional(mood = 3, irritability = 3))
    }

    @Test fun testBodilyIsFlipped() {
        assertEquals(5.0, SignalConversion.bodily(pain = 1))
        assertEquals(1.0, SignalConversion.bodily(pain = 5))
    }

    @Test fun testUnrecordedIsNil() {
        assertNull(SignalConversion.emotional(mood = 0, irritability = 0))
        assertNull(SignalConversion.emotional(mood = null, irritability = null))
        assertNull(SignalConversion.bodily(pain = 0))
        assertNull(SignalConversion.bodily(pain = 9))
    }
}

class WindowStatsTests {

    /** 매일 기록된 완료 주기 하나. r = length − d + 1. */
    private fun cycle(
        length: Int = 28,
        energy: (Int) -> Int? = { null },
        mood: (Int) -> Int? = { null },
    ): WindowCycle = WindowCycle(length, (1..length).map { d ->
        WindowDaySample(d, length - d + 1, energy(d), mood(d))
    })

    /** 생리 전 dipDays일 energy 2, 나머지 4. */
    private fun dipCycle(dipDays: Int): WindowCycle = cycle(energy = { d -> if (d > 28 - dipDays) 2 else 4 })

    // ── 기초 통계

    @Test fun testMedian() {
        assertNull(WindowStatsEngine.median(emptyList()))
        assertEquals(3.0, WindowStatsEngine.median(listOf(3.0)))
        assertEquals(2.0, WindowStatsEngine.median(listOf(4.0, 1.0, 2.0)))
        assertEquals(2.5, WindowStatsEngine.median(listOf(4.0, 1.0, 2.0, 3.0)))
    }

    @Test fun testBaselineAndSuffixMedian() {
        val c = dipCycle(4)
        assertEquals(4.0, WindowStatsEngine.baseline(c, WindowSignal.ENERGY))
        assertEquals(2.0, WindowStatsEngine.suffixMedian(c, WindowSignal.ENERGY, p = 4))
        assertEquals(2.0, WindowStatsEngine.suffixMedian(c, WindowSignal.ENERGY, p = 6))
        assertNull(WindowStatsEngine.baseline(c, WindowSignal.MOOD))
    }

    @Test fun testPhaseMedianRespectsCycleLength() {
        val c = cycle(length = 35, mood = { d -> if (d in 22..24) 5 else 3 })
        assertEquals(5.0, WindowStatsEngine.phaseMedian(c, WindowSignal.MOOD, CyclePhase.OVULATION))
        assertEquals(3.0, WindowStatsEngine.phaseMedian(c, WindowSignal.MOOD, CyclePhase.FOLLICULAR))
    }

    @Test fun testPhaseMedianRespectsMenstrualLength() {
        val c = cycle(mood = { d -> if (d <= 7) 2 else 4 })
        assertEquals(2.0, WindowStatsEngine.phaseMedian(c, WindowSignal.MOOD, CyclePhase.MENSTRUAL, menstrualLength = 7))
        assertEquals(4.0, WindowStatsEngine.phaseMedian(c, WindowSignal.MOOD, CyclePhase.FOLLICULAR, menstrualLength = 7))
        assertEquals(4.0, WindowStatsEngine.phaseMedian(c, WindowSignal.MOOD, CyclePhase.FOLLICULAR))
    }

    // ── P 저컨디션 윈도우

    @Test fun testPreMenstrualWindowDetected() {
        val cycles = listOf(dipCycle(4), dipCycle(4), dipCycle(4))
        assertEquals(5, WindowStatsEngine.preMenstrualWindow(cycles))
    }

    @Test fun testPreMenstrualWindowSilentWhenFlat() {
        val flat = cycle(energy = { 4 })
        assertNull(WindowStatsEngine.preMenstrualWindow(listOf(flat, flat, flat)))
    }

    @Test fun testPreMenstrualWindowNeedsThreeCycles() {
        assertNull(WindowStatsEngine.preMenstrualWindow(listOf(dipCycle(4), dipCycle(4))))
    }

    @Test fun testEnergyMissingSilencesPreWindow() {
        val moodOnly = cycle(mood = { 3 })
        assertNull(WindowStatsEngine.preMenstrualWindow(listOf(moodOnly, moodOnly, moodOnly)))
    }

    // ── 홀드아웃 채택 게이트

    @Test fun testHoldoutScore() {
        val c = dipCycle(4)
        assertEquals(1.0, WindowStatsEngine.holdoutScore(c, p = 4))
        val p5 = WindowStatsEngine.holdoutScore(c, p = 5)
        assertNotNull(p5)
        assertTrue(p5 < 1.0)
        assertNull(WindowStatsEngine.holdoutScore(cycle(), p = 5))
    }

    @Test fun testAdoptedPreWindowWhenBetter() {
        val cycles = List(4) { dipCycle(6) }
        assertEquals(7, WindowStatsEngine.adoptedPreWindow(cycles))
    }

    @Test fun testAdoptedPreWindowRejectedWhenDefaultBetter() {
        val cycles = List(3) { dipCycle(6) } + listOf(dipCycle(4))
        assertNull(WindowStatsEngine.adoptedPreWindow(cycles))
    }

    @Test fun testAdoptedPreWindowNeedsFourCycles() {
        assertNull(WindowStatsEngine.adoptedPreWindow(List(3) { dipCycle(6) }))
    }

    // ── H1 배란 주변 기분 상승

    @Test fun testH1ConfirmedWhenSummerLifts() {
        val lift = cycle(mood = { d -> if (d in 15..17) 5 else 3 })
        assertEquals(true, WindowStatsEngine.h1SummerMoodLift(listOf(lift, lift, lift)))
    }

    @Test fun testH1RefutedWhenFlat() {
        val flat = cycle(mood = { 3 })
        assertEquals(false, WindowStatsEngine.h1SummerMoodLift(listOf(flat, flat, flat)))
    }

    @Test fun testH1SilentUnderThreeCycles() {
        val lift = cycle(mood = { d -> if (d in 15..17) 5 else 3 })
        assertNull(WindowStatsEngine.h1SummerMoodLift(listOf(lift, lift)))
    }

    // ── A축 유형

    private val swingCycle: WindowCycle get() = cycle(mood = { d -> if (d <= 5) 2 else 4 })
    private val flatCycle: WindowCycle get() = cycle(mood = { 3 })

    @Test fun testClassifyVivace() {
        assertEquals(RhythmType.VIVACE, WindowStatsEngine.classify(listOf(swingCycle, swingCycle, swingCycle)))
    }

    @Test fun testClassifyAndante() {
        assertEquals(RhythmType.ANDANTE, WindowStatsEngine.classify(listOf(flatCycle, flatCycle, flatCycle)))
    }

    @Test fun testClassifyRubatoOnDisagreement() {
        assertEquals(RhythmType.RUBATO, WindowStatsEngine.classify(listOf(swingCycle, swingCycle, flatCycle, flatCycle)))
    }

    @Test fun testClassifyNilUnderThreeCycles() {
        assertNull(WindowStatsEngine.classify(listOf(swingCycle, swingCycle)))
    }

    @Test fun testSparseCyclesAreExcluded() {
        val sparse = WindowCycle(28, (1..3).map { d -> WindowDaySample(d, 28 - d + 1, null, 2) })
        assertNull(WindowStatsEngine.classify(listOf(sparse, sparse, sparse)))
    }

    @Test fun testOnlyRecentCyclesAreUsed() {
        val cycles = listOf(swingCycle) + List(5) { flatCycle }
        assertEquals(RhythmType.ANDANTE, WindowStatsEngine.classify(cycles))
    }

    // ── 프로파일

    @Test fun testProfileSummaries() {
        val profile = WindowStatsEngine.profile(listOf(swingCycle, swingCycle, swingCycle))
        val winterMood = profile.firstOrNull { it.phase == CyclePhase.MENSTRUAL && it.signal == WindowSignal.MOOD }
        assertEquals(2.0, winterMood?.median)
        assertEquals(3, winterMood?.cyclesWithData)
        assertFalse(profile.any { it.signal == WindowSignal.ENERGY })
    }
}
