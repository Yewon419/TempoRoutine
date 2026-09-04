// 무드라인 픽 — iOS와 같은 날 같은 문장이 나오려면 dayNumber 절삭 규칙이 같아야 한다.

package app.temporoutine.android.cycle

import app.temporoutine.core.CyclePhase
import org.junit.jupiter.api.Test
import java.time.LocalDate
import java.time.ZoneId
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class MoodlinePoolTests {

    private val seoul: ZoneId = ZoneId.of("Asia/Seoul")

    @Test fun dayNumberTruncatesTowardZero() {
        // 2001-01-01 KST 자정 = 2000-12-31T15:00Z → −0.375일 → Int 절삭 0 (−1이 아니다)
        assertEquals(0u, MoodlinePool.dayNumber(LocalDate.of(2001, 1, 1), seoul))
        // 2001-01-02 KST 자정 = 2001-01-01T15:00Z → 0.625 → 0
        assertEquals(0u, MoodlinePool.dayNumber(LocalDate.of(2001, 1, 2), seoul))
        // 2001-01-03 KST 자정 → 1.625 → 1
        assertEquals(1u, MoodlinePool.dayNumber(LocalDate.of(2001, 1, 3), seoul))
        // UTC에선 정확히 일수
        assertEquals(2u, MoodlinePool.dayNumber(LocalDate.of(2001, 1, 3), ZoneId.of("UTC")))
    }

    @Test fun pickIsStablePerDayAndWithinPool() {
        val day = LocalDate.of(2026, 9, 4)
        for (phase in CyclePhase.entries) {
            val a = MoodlinePool.base(phase, day, seoul)
            assertEquals(a, MoodlinePool.base(phase, day, seoul))
            assertTrue(a.startsWith(seasonCopy(phase).name) || a.startsWith("이번 주는"), a)
            for (level in EnergyLevel.entries) {
                val p = MoodlinePool.personalized(phase, level, day, seoul)
                assertTrue(p.contains("기록상"), p)
                assertTrue(p.startsWith(seasonCopy(phase).name), p)
            }
        }
    }

    @Test fun knuthHashMatchesReference() {
        // dayNumber 9377 × 2654435761 mod 2^32 = 0x... — 손계산 대신 UInt 곱 wrap 성질을 고정
        val n = 9377u
        val seed = n * 2654435761u
        assertEquals(((9377L * 2654435761L) % 4294967296L).toUInt(), seed)
    }
}
