// 템포루틴 — PeriodMath 테스트 (MASTER §5.5.4, T20~)
// iOS TempoCoreTests/PeriodMathTests.swift 1:1 이식.

package app.temporoutine.core

import org.junit.jupiter.api.Test
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.test.assertEquals

class EpisodeLengthTests {
    private fun d(offset: Int): LocalDate =
        LocalDate.ofInstant(java.time.Instant.ofEpochSecond(1_780_000_000), ZoneOffset.UTC).plusDays(offset.toLong())

    /** 개정 M — §5.3 층 2 M의 실측 소스. 길이 = 마지막 기록일 − 시작일 + 1. */
    @Test fun testEpisodeLengths() {
        val days = (0 until 5).map(::d) + (28 until 32).map(::d)
        assertEquals(listOf(5, 4), PeriodMath.episodeLengths(days))
        assertEquals(listOf(5), PeriodMath.episodeLengths(listOf(d(0), d(1), d(4))))
        assertEquals(listOf(1, 1), PeriodMath.episodeLengths(listOf(d(0), d(28))))
        assertEquals(emptyList(), PeriodMath.episodeLengths(emptyList()))
    }
}

class PeriodMathTests {

    private fun day(offset: Int): LocalDate = LocalDate.now().plusDays(offset.toLong())

    // T20: 빈 배열 → 에피소드 없음
    @Test fun testT20_emptyDays() {
        assertEquals(0, PeriodMath.episodes(emptyList()).size)
        assertEquals(emptyList(), PeriodMath.episodeStarts(emptyList()))
    }

    // T21: 연속 5일 → 에피소드 1개
    @Test fun testT21_singleContiguousEpisode() {
        val days = (0 until 5).map { day(it) }
        assertEquals(listOf(day(0)), PeriodMath.episodeStarts(days))
    }

    // T22: 두 에피소드
    @Test fun testT22_twoEpisodes() {
        val days = (0 until 5).map { day(it) } + (28 until 32).map { day(it) }
        assertEquals(listOf(day(0), day(28)), PeriodMath.episodeStarts(days))
    }

    // T23: 시작일 + 13일 = 갭 14 미만 → 같은 에피소드
    @Test fun testT23_gapBelowMinIsSameEpisode() {
        val days = listOf(day(0), day(13))
        assertEquals(1, PeriodMath.episodes(days).size)
        assertEquals(listOf(day(0)), PeriodMath.episodeStarts(days))
    }

    // T24: 시작일 + 14일 = 경계 → 새 에피소드
    @Test fun testT24_gapAtMinIsNewEpisode() {
        assertEquals(listOf(day(0), day(14)), PeriodMath.episodeStarts(listOf(day(0), day(14))))
    }

    // T25: 비정렬·중복 입력 허용
    @Test fun testT25_unsortedDuplicatedInput() {
        val days = listOf(day(28), day(1), day(0), day(1), day(29), day(2))
        assertEquals(listOf(day(0), day(28)), PeriodMath.episodeStarts(days))
        val episodes = PeriodMath.episodes(days)
        assertEquals(listOf(day(0), day(1), day(2)), episodes[0])
        assertEquals(listOf(day(28), day(29)), episodes[1])
    }

    // T26: 불연속 day 허용
    @Test fun testT26_nonContiguousDaysWithinEpisode() {
        val days = listOf(day(0), day(2), day(4), day(30))
        val episodes = PeriodMath.episodes(days)
        assertEquals(2, episodes.size)
        assertEquals(listOf(day(0), day(2), day(4)), episodes[0])
        assertEquals(listOf(day(0), day(30)), PeriodMath.episodeStarts(days))
    }

    // T27: 파생 → 엔진 입력 연결
    @Test fun testT27_feedsEngine() {
        val days = (0 until 5).map { day(it) } + (28 until 33).map { day(it) } + (56 until 60).map { day(it) }
        val starts = PeriodMath.episodeStarts(days)
        assertEquals(3, starts.size)
        assertEquals(28, CyclePredictor.averageLength(starts))
    }
}
