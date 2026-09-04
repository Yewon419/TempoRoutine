// 카드 발생 판정 — iOS CardModels 규칙(월말 클램프·윤년 2/29·여러 날 일정·Output 디데이)을 고정.

package app.temporoutine.android.data

import app.temporoutine.core.InputSchedule
import app.temporoutine.core.OutputSchedule
import org.junit.jupiter.api.Test
import java.time.LocalDate
import java.time.ZoneId
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class OccurrenceTests {

    private val zone: ZoneId = ZoneId.of("Asia/Seoul")
    private fun at(y: Int, m: Int, d: Int, h: Int = 0) = LocalDate.of(y, m, d).atStartOfDay(zone).plusHours(h.toLong()).toInstant()

    @Test fun scheduleRepeatRules() {
        val monthly31 = ScheduleItemEntity(date = at(2026, 1, 31), repeatRule = "monthly")
        assertTrue(monthly31.startsOn(LocalDate.of(2026, 2, 28), zone), "31일 → 2월 말일 클램프")
        assertTrue(monthly31.startsOn(LocalDate.of(2026, 3, 31), zone))
        assertFalse(monthly31.startsOn(LocalDate.of(2026, 3, 30), zone))
        assertFalse(monthly31.startsOn(LocalDate.of(2025, 12, 31), zone), "시작일 이전은 안 뜬다")

        val leap = ScheduleItemEntity(date = at(2024, 2, 29), repeatRule = "yearly")
        assertTrue(leap.startsOn(LocalDate.of(2026, 2, 28), zone), "비윤년 2/28")
        assertFalse(leap.startsOn(LocalDate.of(2028, 2, 28), zone), "윤년엔 2/29에만")
        assertTrue(leap.startsOn(LocalDate.of(2028, 2, 29), zone))

        val weekly = ScheduleItemEntity(date = at(2026, 9, 4), repeatRule = "weekly")   // 금
        assertTrue(weekly.startsOn(LocalDate.of(2026, 9, 11), zone))
        assertFalse(weekly.startsOn(LocalDate.of(2026, 9, 10), zone))
    }

    @Test fun multiDaySpanAndIndex() {
        val trip = ScheduleItemEntity(date = at(2026, 9, 4), endDate = at(2026, 9, 6), isAllDay = true)
        assertEquals(3, trip.spanDays(zone))
        assertTrue(trip.occurs(LocalDate.of(2026, 9, 5), zone))
        assertEquals(2, trip.dayIndex(LocalDate.of(2026, 9, 5), zone))
        assertFalse(trip.occurs(LocalDate.of(2026, 9, 7), zone))
        assertNull(ScheduleItemEntity(date = at(2026, 9, 4)).dayIndex(LocalDate.of(2026, 9, 4), zone))
        // 밤 11시~다음날 1시 = 이틀
        val late = ScheduleItemEntity(date = at(2026, 9, 4, 23), endDate = at(2026, 9, 5, 1), isAllDay = false)
        assertEquals(2, late.spanDays(zone))
    }

    @Test fun inputCalendarRules() {
        val created = at(2026, 9, 4)
        val once = InputItemEntity(scheduleJson = InputItemEntity.encodeSchedule(InputSchedule.Once), createdAt = created)
        assertTrue(once.onceShows(LocalDate.of(2026, 9, 4), zone))
        assertFalse(once.onceShows(LocalDate.of(2026, 9, 5), zone))
        val monthly = InputItemEntity(scheduleJson = InputItemEntity.encodeSchedule(InputSchedule.Monthly), createdAt = at(2026, 8, 31))
        assertTrue(monthly.occursByCalendar(LocalDate.of(2026, 9, 30), zone))
        assertFalse(monthly.occursByCalendar(LocalDate.of(2026, 9, 29), zone))
        assertEquals(InputSchedule.Daily, InputItemEntity(scheduleJson = "").schedule, "빈 JSON = daily 폴백")
    }

    @Test fun outputOnceFollowsTargetDate() {
        val created = at(2026, 9, 4)
        val plain = OutputItemEntity(scheduleJson = OutputItemEntity.encodeSchedule(OutputSchedule.Once), createdAt = created)
        assertTrue(plain.occursByCalendar(LocalDate.of(2026, 9, 4), zone))
        assertFalse(plain.occursByCalendar(LocalDate.of(2026, 9, 5), zone))
        val dday = plain.copy(targetDate = at(2026, 9, 10))
        assertTrue(dday.occursByCalendar(LocalDate.of(2026, 9, 10), zone))
        assertFalse(dday.occursByCalendar(LocalDate.of(2026, 9, 11), zone))
    }

    @Test fun sortedByTimeOfDayIsStable() {
        val items = listOf("a" to null, "b" to 600, "c" to 540, "d" to null, "e" to 600)
        assertEquals(listOf("c", "b", "e", "a", "d"), sortedByTimeOfDay(items) { it.second }.map { it.first })
    }
}
