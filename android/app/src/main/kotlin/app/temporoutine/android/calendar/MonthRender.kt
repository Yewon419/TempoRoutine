// 템포루틴 Android — 월 렌더 캐시 (iOS SeasonCalendarView MonthLayout·MonthRender·computeRender·bandLayout·monthMarks·cellStyle 이식)
// 순수 Kotlin. 프레임 경로(드래그·스크롤)에서는 이 결과를 조회만 한다 — 파생 계산은 ViewModel에서 데이터 변경마다 한 번.

package app.temporoutine.android.calendar

import app.temporoutine.android.cycle.CycleSnapshot
import app.temporoutine.android.data.InputItemEntity
import app.temporoutine.android.data.OutputItemEntity
import app.temporoutine.android.data.OutputSubtaskEntity
import app.temporoutine.android.data.ScheduleItemEntity
import app.temporoutine.android.data.isMultiDay
import app.temporoutine.android.data.occurs
import app.temporoutine.android.data.toLocalDate
import app.temporoutine.core.BandSegment
import app.temporoutine.core.CyclePhase
import app.temporoutine.core.CyclePredictor
import app.temporoutine.core.InputSchedule
import app.temporoutine.core.KoreanHoliday
import app.temporoutine.core.KoreanHolidays
import app.temporoutine.core.OutputSchedule
import app.temporoutine.core.ProgressRule
import app.temporoutine.core.ScheduleSpan
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId

/** 월 배치 — 첫 요일(지역 설정) 기준 선행 빈칸, 후행 날짜는 그리지 않는다. */
data class MonthLayout(val start: LocalDate, val firstDayOfWeek: DayOfWeek) {
    val daysInMonth: Int = YearMonth.from(start).lengthOfMonth()
    val leadingBlanks: Int = (start.dayOfWeek.value - firstDayOfWeek.value + 7) % 7
    val rowCount: Int = (leadingBlanks + daysInMonth + 6) / 7
    val cellCount: Int get() = rowCount * 7
    val firstTrailing: Int get() = leadingBlanks + daysInMonth

    fun date(index: Int): LocalDate? {
        val day = index - leadingBlanks + 1
        return if (day in 1..daysInMonth) start.plusDays((day - 1).toLong()) else null
    }
}

data class CellStyle(val phase: CyclePhase?, val projected: Boolean)

data class Mark(val title: String, val projected: Boolean, val isSchedule: Boolean)

data class BandBar(val lane: Int, val segment: BandSegment, val title: String)

data class BandLayout(val bars: List<BandBar>, val countByIndex: Map<Int, Int>)

data class MonthRender(
    val layout: MonthLayout,
    val marks: Map<LocalDate, List<Mark>>,
    val bands: BandLayout,
    val style: Map<LocalDate, CellStyle>,
    val recorded: Set<LocalDate>,
    val predicted: Set<LocalDate>,
    val holidays: Map<LocalDate, KoreanHoliday>,
)

object MonthRenderer {

    const val LANES = 2

    /** 단계 → 스타일. S0·지평 밖·계산 불가 = 먹색(단계 없음). */
    fun cellStyle(date: LocalDate, snapshot: CycleSnapshot): CellStyle {
        val last = snapshot.starts.maxOrNull() ?: return CellStyle(null, false)
        val horizon = CyclePredictor.projectionHorizon(last, snapshot.averageLength, snapshot.horizonCycles, snapshot.menstrualLength)
        if (date > horizon) return CellStyle(null, false)
        val r = CyclePredictor.cycleDay(date, snapshot.starts, snapshot.averageLength) ?: return CellStyle(null, false)
        val m = snapshot.effectiveMenstrualLength(date, r.projected)
        return CellStyle(CyclePredictor.phaseForDay(r.day, snapshot.averageLength, m), r.projected)
    }

    /** 예상 생리일 — 오늘 이후·지평 안·투영·(effective 아닌) M 기준 겨울. a11y 전용(은필은 시각 표시 없음). */
    fun isPredictedPeriod(date: LocalDate, today: LocalDate, snapshot: CycleSnapshot): Boolean {
        if (date < today) return false
        val last = snapshot.starts.maxOrNull() ?: return false
        val horizon = CyclePredictor.projectionHorizon(last, snapshot.averageLength, snapshot.horizonCycles, snapshot.menstrualLength)
        if (date > horizon) return false
        val r = CyclePredictor.cycleDay(date, snapshot.starts, snapshot.averageLength) ?: return false
        if (!r.projected) return false
        return CyclePredictor.phaseForDay(r.day, snapshot.averageLength, snapshot.menstrualLength) == CyclePhase.MENSTRUAL
    }

    /** 여러 날 일정 → 레인 2개 띠. countByIndex = 그 칸이 예약해야 할 슬롯 수(max lane+1). 3중 겹침은 미표시(iOS 동일). */
    fun bandLayout(layout: MonthLayout, schedules: List<ScheduleItemEntity>, zone: ZoneId): BandLayout {
        val items = schedules.filter { it.isMultiDay(zone) }.sortedWith(compareBy({ it.date }, { it.title }))
        val laneCells = Array(LANES) { BooleanArray(layout.cellCount) }
        val countByIndex = mutableMapOf<Int, Int>()
        val bars = mutableListOf<BandBar>()
        for (item in items) {
            val cells = BooleanArray(layout.cellCount) { i -> layout.date(i)?.let { item.occurs(it, zone) } ?: false }
            val occupied = cells.indices.filter { cells[it] }
            if (occupied.isEmpty()) continue
            val lane = (0 until LANES).firstOrNull { l -> occupied.none { laneCells[l][it] } } ?: continue
            for (i in occupied) { laneCells[lane][i] = true; countByIndex[i] = maxOf(countByIndex[i] ?: 0, lane + 1) }
            val segments = ScheduleSpan.bandSegments(cells.toList()).map { clampToMonth(it, layout, item, zone) }
            bars += segments.map { BandBar(lane, it, item.title) }
        }
        return BandLayout(bars, countByIndex)
    }

    /** 월 경계 보정 — 1일에서 시작하는데 전날에도 있으면 각지게, 말일에서 끝나는데 다음날에도 있으면 각지게. */
    private fun clampToMonth(seg: BandSegment, layout: MonthLayout, item: ScheduleItemEntity, zone: ZoneId): BandSegment {
        val startIndex = seg.row * 7 + seg.column
        val endIndex = startIndex + seg.length - 1
        var isStart = seg.isStart
        var isEnd = seg.isEnd
        if (isStart && startIndex == layout.leadingBlanks && item.occurs(layout.start.minusDays(1), zone)) isStart = false
        if (isEnd && endIndex == layout.firstTrailing - 1 && item.occurs(layout.start.plusDays(layout.daysInMonth.toLong()), zone)) isEnd = false
        return seg.copy(isStart = isStart, isEnd = isEnd)
    }

    /** 이 달의 잉크 글줄 — 하루짜리 일정(박스) + 주기 기준 Input/Output occurrence. 달력 반복 Input·Output은 안 그린다. */
    fun monthMarks(
        layout: MonthLayout, snapshot: CycleSnapshot, schedules: List<ScheduleItemEntity>,
        inputs: List<InputItemEntity>, outputs: List<OutputItemEntity>, outputSubtasks: List<OutputSubtaskEntity>, zone: ZoneId,
    ): Map<LocalDate, List<Mark>> {
        val marks = mutableMapOf<LocalDate, MutableList<Mark>>()
        val monthEnd = layout.start.plusDays(layout.daysInMonth.toLong())
        for (dayNumber in 1..layout.daysInMonth) {
            val day = layout.start.plusDays((dayNumber - 1).toLong())
            for (s in schedules) {
                if (!s.occurs(day, zone) || s.isMultiDay(zone)) continue
                marks.getOrPut(day) { mutableListOf() }.add(Mark(s.title, false, true))
            }
        }
        for (item in inputs) {
            val r = (item.schedule as? InputSchedule.CycleAnchored)?.recurrence ?: continue
            for (occ in snapshot.occurrences(r, item.createdAt.toLocalDate(zone))) {
                if (occ.date < layout.start || occ.date >= monthEnd) continue
                marks.getOrPut(occ.date) { mutableListOf() }.add(Mark(item.title, occ.projected, false))
            }
        }
        for (item in outputs) {
            val r = (item.schedule as? OutputSchedule.CycleAnchored)?.recurrence ?: continue
            val subs = outputSubtasks.filter { it.ownerId == item.id }
            val complete = ProgressRule.isFulfilled(item.progressGoal(subs.size), item.progressState(subs.count { it.isDone }))
            for (occ in snapshot.occurrences(r, item.createdAt.toLocalDate(zone))) {
                if (occ.date < layout.start || occ.date >= monthEnd) continue
                if (complete && occ.projected) continue
                marks.getOrPut(occ.date) { mutableListOf() }.add(Mark(item.title, occ.projected, false))
            }
        }
        return marks
    }

    fun compute(
        layout: MonthLayout, snapshot: CycleSnapshot, recordedDays: Set<LocalDate>, today: LocalDate,
        schedules: List<ScheduleItemEntity>, inputs: List<InputItemEntity>, outputs: List<OutputItemEntity>,
        outputSubtasks: List<OutputSubtaskEntity>, holidaysEnabled: Boolean, zone: ZoneId,
    ): MonthRender {
        val style = mutableMapOf<LocalDate, CellStyle>()
        val recorded = mutableSetOf<LocalDate>()
        val predicted = mutableSetOf<LocalDate>()
        val holidays = mutableMapOf<LocalDate, KoreanHoliday>()
        for (offset in -1..layout.daysInMonth) {   // 달 앞뒤 하루 여유(밑줄 연결 판정)
            val day = layout.start.plusDays(offset.toLong())
            if (day in recordedDays) recorded.add(day)
            else if (isPredictedPeriod(day, today, snapshot)) predicted.add(day)
            if (offset in 0 until layout.daysInMonth || offset == -1 || offset == layout.daysInMonth) style[day] = cellStyle(day, snapshot)
            if (offset in 0 until layout.daysInMonth && holidaysEnabled) {
                KoreanHolidays.holidays(day).firstOrNull()?.let { holidays[day] = it }
            }
        }
        return MonthRender(
            layout = layout,
            marks = monthMarks(layout, snapshot, schedules, inputs, outputs, outputSubtasks, zone),
            bands = bandLayout(layout, schedules, zone),
            style = style,
            recorded = recorded,
            predicted = predicted,
            holidays = holidays,
        )
    }
}
