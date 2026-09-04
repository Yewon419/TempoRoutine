// 사분면 커버리지 테스트 (MASTER §5.12 ⑤)
// iOS TempoCoreTests/QuadrantCoverageTests.swift 1:1 이식.

package app.temporoutine.core

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class QuadrantCoverageTests {

    private fun signal(day: Int, length: Int, emotional: Double? = 3.0, bodily: Double? = null): DailySignal =
        DailySignal(day, length, emotional, bodily)

    @Test fun testQuadrantBoundaries() {
        assertEquals(0, QuadrantCoverage.quadrant(1, 28))
        assertEquals(0, QuadrantCoverage.quadrant(7, 28))
        assertEquals(1, QuadrantCoverage.quadrant(8, 28))
        assertEquals(2, QuadrantCoverage.quadrant(21, 28))
        assertEquals(3, QuadrantCoverage.quadrant(22, 28))
    }

    @Test fun testLastDayStaysInRange() {
        for (length in 21..35) {
            assertEquals(3, QuadrantCoverage.quadrant(length, length), "length $length")
        }
    }

    @Test fun testOutOfRangeIsNil() {
        assertNull(QuadrantCoverage.quadrant(0, 28))
        assertNull(QuadrantCoverage.quadrant(29, 28))
        assertNull(QuadrantCoverage.quadrant(1, 0))
    }

    @Test fun testEveryQuadrantReachableForShortCycles() {
        for (length in 4..35) {
            val signals = (1..length).map { signal(it, length) }
            assertEquals(emptyList(), QuadrantCoverage.emptyQuadrants(signals), "length $length")
        }
    }

    @Test fun testCoverageCountsPerQuadrant() {
        val signals = listOf(1, 3, 9, 25).map { signal(it, 28) }
        assertEquals(listOf(2, 1, 0, 1), QuadrantCoverage.coverage(signals))
        assertEquals(listOf(2), QuadrantCoverage.emptyQuadrants(signals))
    }

    @Test fun testEmptySignalIsNotCounted() {
        val signals = listOf(signal(5, 28, emotional = null, bodily = null))
        assertEquals(listOf(0, 0, 0, 0), QuadrantCoverage.coverage(signals))
    }

    @Test fun testBodilyOnlyCounts() {
        val signals = listOf(signal(5, 28, emotional = null, bodily = 4.0))
        assertEquals(listOf(1, 0, 0, 0), QuadrantCoverage.coverage(signals))
    }

    @Test fun testDayRangeMatchesQuadrantFunction() {
        for (length in 21..35) {
            for (index in 0 until QuadrantCoverage.COUNT) {
                val range = QuadrantCoverage.dayRange(index, length)
                assertNotNull(range, "length $length q $index")
                for (day in range) {
                    assertEquals(index, QuadrantCoverage.quadrant(day, length), "length $length q $index day $day")
                }
            }
        }
    }

    @Test fun testReminderDayIsInsideAndNotLast() {
        for (length in 21..35) {
            for (index in 0 until QuadrantCoverage.COUNT) {
                val day = QuadrantCoverage.reminderDay(index, length)
                val range = QuadrantCoverage.dayRange(index, length)
                assertNotNull(day)
                assertNotNull(range)
                assertTrue(day in range, "length $length q $index")
                if (range.last - range.first + 1 > 1) {
                    assertTrue(day < range.last, "length $length q $index")
                }
            }
        }
    }

    @Test fun testDetectsPhaseClustering() {
        val clustered = (1..7).map { signal(it, 28) }
        assertTrue(clustered.size >= WindowStatsEngine.MIN_SAMPLES_PER_CYCLE)
        assertEquals(listOf(1, 2, 3), QuadrantCoverage.emptyQuadrants(clustered))
    }
}
