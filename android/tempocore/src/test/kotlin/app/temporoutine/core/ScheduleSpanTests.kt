// 템포루틴 — ScheduleSpan 테스트 (여러 날 일정, T80~)
// iOS TempoCoreTests/ScheduleSpanTests.swift 1:1 이식.

package app.temporoutine.core

import org.junit.jupiter.api.Test
import java.time.LocalDateTime
import kotlin.test.assertEquals

class ScheduleSpanTests {

    private fun date(y: Int, m: Int, d: Int, hour: Int = 0, minute: Int = 0): LocalDateTime =
        LocalDateTime.of(y, m, d, hour, minute)

    private fun cells(count: Int, trueIndices: List<Int>): List<Boolean> = (0 until count).map { it in trueIndices }

    // T80: 기간 계산
    @Test fun testT80_dayCount() {
        assertEquals(1, ScheduleSpan.dayCount(date(2026, 8, 3), null))
        assertEquals(1, ScheduleSpan.dayCount(date(2026, 8, 3, hour = 9), date(2026, 8, 3, hour = 18)))
        assertEquals(3, ScheduleSpan.dayCount(date(2026, 8, 3), date(2026, 8, 5)))
        assertEquals(2, ScheduleSpan.dayCount(date(2026, 8, 3, hour = 23), date(2026, 8, 4, hour = 1)))
        assertEquals(1, ScheduleSpan.dayCount(date(2026, 8, 5), date(2026, 8, 3)))
        assertEquals(4, ScheduleSpan.dayCount(date(2026, 7, 30), date(2026, 8, 2)))
    }

    // T81: 한 주 안에서 이어지는 3일
    @Test fun testT81_singleWeekRun() {
        assertEquals(listOf(BandSegment(1, 1, 3, true, true)), ScheduleSpan.bandSegments(cells(14, listOf(8, 9, 10))))
    }

    // T82: 주 경계를 넘으면 조각 2개
    @Test fun testT82_weekBoundarySplit() {
        assertEquals(listOf(
            BandSegment(0, 5, 2, true, false),
            BandSegment(1, 0, 2, false, true),
        ), ScheduleSpan.bandSegments(cells(21, listOf(5, 6, 7, 8))))
    }

    // T83: 3주에 걸치면 가운데 조각은 양쪽 다 각지게
    @Test fun testT83_threeWeeks() {
        val segments = ScheduleSpan.bandSegments(cells(21, (6..15).toList()))
        assertEquals(3, segments.size)
        assertEquals(BandSegment(0, 6, 1, true, false), segments[0])
        assertEquals(BandSegment(1, 0, 7, false, false), segments[1])
        assertEquals(BandSegment(2, 0, 2, false, true), segments[2])
    }

    // T84: 달 밖에서 이어지면 그 끝은 둥글지 않다
    @Test fun testT84_monthBoundaryContinuation() {
        assertEquals(listOf(BandSegment(0, 0, 2, false, true)),
            ScheduleSpan.bandSegments(cells(7, listOf(0, 1)), continuesBefore = true))
        assertEquals(listOf(BandSegment(0, 5, 2, true, false)),
            ScheduleSpan.bandSegments(cells(7, listOf(5, 6)), continuesAfter = true))
    }

    // T85: 반복으로 끊긴 두 구간
    @Test fun testT85_repeatedRunsAreSeparate() {
        assertEquals(listOf(
            BandSegment(0, 1, 2, true, true),
            BandSegment(1, 1, 2, true, true),
        ), ScheduleSpan.bandSegments(cells(21, listOf(1, 2, 8, 9))))
    }

    // T86: 하루짜리·빈 배열·전 구간
    @Test fun testT86_edges() {
        assertEquals(listOf(BandSegment(0, 3, 1, true, true)), ScheduleSpan.bandSegments(cells(7, listOf(3))))
        assertEquals(emptyList(), ScheduleSpan.bandSegments(cells(7, emptyList())))
        assertEquals(emptyList(), ScheduleSpan.bandSegments(emptyList()))
        val full = ScheduleSpan.bandSegments(cells(14, (0..13).toList()))
        assertEquals(2, full.size)
        assertEquals(BandSegment(0, 0, 7, true, false), full[0])
        assertEquals(BandSegment(1, 0, 7, false, true), full[1])
    }
}
