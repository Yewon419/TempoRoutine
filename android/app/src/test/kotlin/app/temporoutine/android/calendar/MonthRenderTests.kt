// 월 렌더 — iOS 캘린더 계약(선행 빈칸·레인 2·countByIndex·마크 순서·지평 컷·예상 규칙·월 경계 띠 보정)을 고정.

package app.temporoutine.android.calendar

import app.temporoutine.android.cycle.CycleSnapshot
import app.temporoutine.android.data.InputItemEntity
import app.temporoutine.android.data.OutputItemEntity
import app.temporoutine.android.data.ScheduleItemEntity
import app.temporoutine.core.CycleAnchor
import app.temporoutine.core.CyclePhase
import app.temporoutine.core.CycleRecurrence
import app.temporoutine.core.InputSchedule
import app.temporoutine.core.OffsetOverflowRule
import org.junit.jupiter.api.Test
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MonthRenderTests {

    private val zone: ZoneId = ZoneId.of("Asia/Seoul")
    private fun at(d: LocalDate) = d.atStartOfDay(zone).toInstant()

    @Test fun layoutSundayStart() {
        val sep = MonthLayout(LocalDate.of(2026, 9, 1), DayOfWeek.SUNDAY)   // 2026-09-01 = 화
        assertEquals(2, sep.leadingBlanks)
        assertEquals(30, sep.daysInMonth)
        assertEquals(5, sep.rowCount)
        assertNull(sep.date(0)); assertNull(sep.date(1))
        assertEquals(LocalDate.of(2026, 9, 1), sep.date(2))
        assertEquals(LocalDate.of(2026, 9, 30), sep.date(31))
        assertNull(sep.date(32), "후행 날짜는 없다")
        val mon = MonthLayout(LocalDate.of(2026, 9, 1), DayOfWeek.MONDAY)
        assertEquals(1, mon.leadingBlanks)
        // 6행 달: 2026-08(토 시작, 31일) 일요일 기준 → 6+31 = 37 → 6행
        assertEquals(6, MonthLayout(LocalDate.of(2026, 8, 1), DayOfWeek.SUNDAY).rowCount)
    }

    @Test fun cellStyleAndHorizon() {
        val start = LocalDate.of(2026, 9, 2)
        val snap = CycleSnapshot((0 until 3).map { start.plusDays(it.toLong()) })   // 기록 1개 → low → 지평 1주기
        assertEquals(CellStyle(CyclePhase.MENSTRUAL, false), MonthRenderer.cellStyle(start, snap))
        assertEquals(CellStyle(CyclePhase.FOLLICULAR, false), MonthRenderer.cellStyle(start.plusDays(5), snap))
        // 다음 주기 1일차 = 투영 겨울
        assertEquals(CellStyle(CyclePhase.MENSTRUAL, true), MonthRenderer.cellStyle(start.plusDays(28), snap))
        // 지평 = last + 28 + 5 − 1 = +32 → +33부터 먹색
        assertEquals(CellStyle(CyclePhase.MENSTRUAL, true), MonthRenderer.cellStyle(start.plusDays(32), snap))
        assertEquals(CellStyle(null, false), MonthRenderer.cellStyle(start.plusDays(33), snap))
        // 첫 기록 이전은 역투영(projected)
        assertTrue(MonthRenderer.cellStyle(start.minusDays(3), snap).projected)
        assertEquals(CellStyle(null, false), MonthRenderer.cellStyle(start, CycleSnapshot(emptyList())), "S0 = 먹색")
    }

    @Test fun predictedPeriodRules() {
        val start = LocalDate.of(2026, 9, 2)
        val today = LocalDate.of(2026, 9, 10)
        val snap = CycleSnapshot((0 until 3).map { start.plusDays(it.toLong()) })
        assertTrue(MonthRenderer.isPredictedPeriod(start.plusDays(28), today, snap))
        assertTrue(MonthRenderer.isPredictedPeriod(start.plusDays(32), today, snap))
        assertFalse(MonthRenderer.isPredictedPeriod(start.plusDays(33), today, snap), "겨울 6일차 = 봄")
        assertFalse(MonthRenderer.isPredictedPeriod(start.plusDays(1), today, snap), "과거·실측은 예상이 아니다")
        assertFalse(MonthRenderer.isPredictedPeriod(start.minusDays(28), today, snap), "오늘 이전 소급 금지")
    }

    @Test fun bandLanesAndCount() {
        val layout = MonthLayout(LocalDate.of(2026, 9, 1), DayOfWeek.SUNDAY)
        fun trip(title: String, from: Int, to: Int) = ScheduleItemEntity(title = title, date = at(LocalDate.of(2026, 9, from)), endDate = at(LocalDate.of(2026, 9, to)), isAllDay = true)
        val a = trip("A", 4, 6)      // 금~일 → 주 경계에서 2조각
        val b = trip("B", 5, 7)      // A와 겹침 → 레인 1
        val c = trip("C", 6, 6)      // 하루짜리 → 띠 아님
        val d = trip("D", 5, 6)      // 레인 0·1 모두 점유 → 미표시
        val bands = MonthRenderer.bandLayout(layout, listOf(d, c, b, a), zone)
        val aBars = bands.bars.filter { it.title == "A" }
        assertEquals(2, aBars.size)
        assertTrue(aBars.all { it.lane == 0 })
        assertEquals(1, bands.bars.filter { it.title == "B" }.first().lane)
        assertTrue(bands.bars.none { it.title == "C" || it.title == "D" })
        // 9/5(index 6)은 A·B 겹침 → 2, 9/7(index 8)은 B만이지만 lane 1이라 슬롯 2
        assertEquals(2, bands.countByIndex[6])
        assertEquals(2, bands.countByIndex[8])
        assertEquals(1, bands.countByIndex[5], "9/4는 A만(lane 0)")
        // 주 경계 조각: 첫 조각 isEnd=false, 둘째 isStart=false
        assertFalse(aBars[0].segment.isEnd); assertFalse(aBars[1].segment.isStart)
    }

    @Test fun bandClampsAtMonthEdge() {
        val layout = MonthLayout(LocalDate.of(2026, 9, 1), DayOfWeek.SUNDAY)
        val span = ScheduleItemEntity(title = "X", date = at(LocalDate.of(2026, 8, 30)), endDate = at(LocalDate.of(2026, 9, 2)), isAllDay = true)
        val bar = MonthRenderer.bandLayout(layout, listOf(span), zone).bars.single()
        assertFalse(bar.segment.isStart, "전달에서 이어지면 각지게")
        assertTrue(bar.segment.isEnd)
    }

    @Test fun marksOrderAndCycleAnchoredOnly() {
        val layout = MonthLayout(LocalDate.of(2026, 9, 1), DayOfWeek.SUNDAY)
        val start = LocalDate.of(2026, 9, 2)
        val snap = CycleSnapshot((0 until 3).map { start.plusDays(it.toLong()) })
        val single = ScheduleItemEntity(title = "병원", date = at(LocalDate.of(2026, 9, 3)), isAllDay = true)
        val daily = InputItemEntity(title = "매일", scheduleJson = InputItemEntity.encodeSchedule(InputSchedule.Daily), createdAt = at(start))
        val winter = InputItemEntity(title = "겨울루틴", scheduleJson = InputItemEntity.encodeSchedule(InputSchedule.CycleAnchored(
            CycleRecurrence(CycleAnchor.Phase(CyclePhase.MENSTRUAL), 1, true, OffsetOverflowRule.CLAMP))), createdAt = at(start))
        val marks = MonthRenderer.monthMarks(layout, snap, listOf(single), listOf(daily, winter), emptyList(), emptyList(), zone)
        val sep3 = marks.getValue(LocalDate.of(2026, 9, 3))
        assertEquals(listOf("병원", "겨울루틴"), sep3.map { it.title }, "일정 먼저, 그다음 occurrence")
        assertTrue(sep3[0].isSchedule); assertFalse(sep3[1].isSchedule); assertFalse(sep3[1].projected)
        assertTrue(marks.values.flatten().none { it.title == "매일" }, "달력 반복은 캘린더에 안 그린다")
        // 다음 주기 겨울 2일차 = 9/30(다음 시작) + 1 = 10/1 → 10월 레이아웃에서 투영으로
        assertEquals(1, marks.values.flatten().count { it.title == "겨울루틴" }, "9월엔 현재 주기 1회만")
        val oct = MonthRenderer.monthMarks(MonthLayout(LocalDate.of(2026, 10, 1), DayOfWeek.SUNDAY), snap, emptyList(), listOf(winter), emptyList(), emptyList(), zone)
        val oct1 = oct.getValue(LocalDate.of(2026, 10, 1)).single()
        assertEquals("겨울루틴", oct1.title); assertTrue(oct1.projected)
    }

    @Test fun computeCollectsRecordedAndHolidays() {
        val layout = MonthLayout(LocalDate.of(2026, 9, 1), DayOfWeek.SUNDAY)
        val start = LocalDate.of(2026, 9, 2)
        val days = (0 until 3).map { start.plusDays(it.toLong()) }
        val render = MonthRenderer.compute(layout, CycleSnapshot(days), days.toSet(), LocalDate.of(2026, 9, 5),
            emptyList(), emptyList(), emptyList(), emptyList(), holidaysEnabled = true, zone = zone)
        assertEquals(days.toSet(), render.recorded)
        assertEquals("추석", render.holidays.getValue(LocalDate.of(2026, 9, 25)).name)
        assertTrue(render.style.containsKey(LocalDate.of(2026, 8, 31)), "앞 하루 여유")
        assertTrue(render.style.containsKey(LocalDate.of(2026, 10, 1)), "뒤 하루 여유")
        assertTrue(render.predicted.contains(start.plusDays(28)))
        val none = MonthRenderer.compute(layout, CycleSnapshot(days), days.toSet(), LocalDate.of(2026, 9, 5),
            emptyList(), emptyList(), emptyList(), emptyList(), holidaysEnabled = false, zone = zone)
        assertTrue(none.holidays.isEmpty())
        @Suppress("unused") val o: OutputItemEntity? = null
    }
}
