package app.temporoutine.android.data

import app.temporoutine.core.SeedLedgerDTO
import app.temporoutine.core.TrackedSignals
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SeedsTests {

    private val zone: ZoneId = ZoneId.of("Asia/Seoul")
    private val all = TrackedSignals(sleep = true, pain = false, appetite = true, note = true)
    private val minimal = TrackedSignals(sleep = false, pain = false, appetite = false, note = false)

    @Test fun completeRequiresTrackedOptionalSignals() {
        assertTrue(Seeds.isComplete(3, 3, null, null, minimal))
        assertFalse(Seeds.isComplete(3, 3, null, null, all), "수면·식욕 켜져 있으면 비면 미완성")
        assertTrue(Seeds.isComplete(3, 3, 1, 5, all))
        assertFalse(Seeds.isComplete(0, 3, 1, 5, all))
    }

    @Test fun awardedWithinNextDay() {
        val day = LocalDate.of(2026, 9, 4)
        val deadline = day.plusDays(2).atStartOfDay(zone).toInstant()
        assertTrue(Seeds.isAwarded(day, deadline.minusSeconds(1), zone))
        assertFalse(Seeds.isAwarded(day, deadline, zone))
        assertFalse(Seeds.isAwarded(day, null, zone))
    }

    @Test fun stampOnce() {
        val day = LocalDate.of(2026, 9, 4)
        val now = day.atStartOfDay(zone).toInstant().plusSeconds(3600)
        val record = DailyCheckInEntity(day = day, energy = 3, mood = 3)
        val (stamped, awarded) = assertNotNull(Seeds.stamp(record, minimal, now, zone))
        assertEquals(now, stamped.completedAt)
        assertTrue(awarded)
        assertNull(Seeds.stamp(stamped, minimal, now.plusSeconds(10), zone), "이미 찍힌 도장은 다시 안 찍는다")
        assertNull(Seeds.stamp(record.copy(energy = 0), minimal, now, zone))
    }

    @Test fun availableCountsDistinctAwardedDaysPlusLedger() {
        val d1 = LocalDate.of(2026, 9, 1)
        val d2 = LocalDate.of(2026, 9, 2)
        val checkIns = listOf(
            DailyCheckInEntity(day = d1, energy = 3, mood = 3, completedAt = d1.atStartOfDay(zone).toInstant()),
            DailyCheckInEntity(day = d2, energy = 3, mood = 3, completedAt = d2.plusDays(5).atStartOfDay(zone).toInstant()),  // 늦은 완성 = 미지급
        )
        assertEquals(1, Seeds.available(checkIns, SeedLedgerDTO(), zone))
        val ledger = Seeds.recordEarned(SeedLedgerDTO(), LocalDate.of(2026, 8, 20))
        assertEquals(2, Seeds.available(checkIns, ledger, zone), "원장 획득일은 행이 없어도 센다")
        assertEquals(2, Seeds.available(checkIns, Seeds.recordEarned(ledger, d1), zone), "같은 날 중복은 한 번")
        val spent = ledger.copy(purchases = mapOf("modern" to 7))
        assertEquals(0, Seeds.available(checkIns, spent, zone), "음수 방지")
        assertEquals(Instant.EPOCH, Instant.EPOCH)
    }
}
