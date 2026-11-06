// 템포루틴 Android — 카드 발생 판정 (iOS CardModels.swift `occurs`/`startsOn`/`dayIndex`/`occursByCalendar` 이식)
// 달력 기준만 여기. 주기 기준(.cycleAnchored)은 CycleSnapshot이 필요라 호출부 분기.

package app.temporoutine.android.data

import app.temporoutine.core.InputSchedule
import app.temporoutine.core.OutputSchedule
import app.temporoutine.core.ScheduleRepeat
import app.temporoutine.core.ScheduleSpan
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

fun Instant.toLocalDate(zone: ZoneId = ZoneId.systemDefault()): LocalDate = atZone(zone).toLocalDate()

private fun ScheduleRepeat.periodDayCap(): Int = when (this) {
    ScheduleRepeat.NONE, ScheduleRepeat.DAILY -> 1
    ScheduleRepeat.WEEKLY -> 7
    ScheduleRepeat.MONTHLY -> 31
    ScheduleRepeat.YEARLY -> 366
}

val ScheduleItemEntity.repeat: ScheduleRepeat
    get() = ScheduleRepeat.entries.firstOrNull { it.rawValue == repeatRule } ?: ScheduleRepeat.NONE

fun ScheduleItemEntity.startDay(zone: ZoneId = ZoneId.systemDefault()): LocalDate = date.toLocalDate(zone)

/** 걸치는 날 수 — 하루짜리는 1 (§8.2.3 여러 날 일정) */
fun ScheduleItemEntity.spanDays(zone: ZoneId = ZoneId.systemDefault()): Int =
    ScheduleSpan.dayCount(date.atZone(zone).toLocalDateTime(), endDate?.atZone(zone)?.toLocalDateTime())

fun ScheduleItemEntity.isMultiDay(zone: ZoneId = ZoneId.systemDefault()): Boolean = spanDays(zone) > 1

/** 발생(회차)의 시작일인가. 연반복 윤년 규칙: 2/29는 비윤년에 2/28로. */
fun ScheduleItemEntity.startsOn(day: LocalDate, zone: ZoneId = ZoneId.systemDefault()): Boolean {
    val start = startDay(zone)
    return when (repeat) {
        ScheduleRepeat.NONE -> start == day
        ScheduleRepeat.DAILY -> day >= start
        ScheduleRepeat.WEEKLY -> day >= start && start.dayOfWeek == day.dayOfWeek
        ScheduleRepeat.MONTHLY -> {
            if (day < start) return false
            val startDom = start.dayOfMonth
            val targetDom = day.dayOfMonth
            if (startDom == targetDom) true
            else startDom > day.lengthOfMonth() && targetDom == day.lengthOfMonth()
        }
        ScheduleRepeat.YEARLY -> {
            if (start.monthValue == day.monthValue && start.dayOfMonth == day.dayOfMonth) true
            else start.monthValue == 2 && start.dayOfMonth == 29 && day.monthValue == 2 && day.dayOfMonth == 28 && !day.isLeapYear
        }
    }
}

/** 이 날짜에 표시되는가 — 발생 시작일 + 기간 확장. 반복 일정도 회차마다 같은 길이. */
fun ScheduleItemEntity.occurs(day: LocalDate, zone: ZoneId = ZoneId.systemDefault()): Boolean {
    val span = spanDays(zone)
    if (span == 1) return startsOn(day, zone)
    return when (repeat) {
        ScheduleRepeat.NONE -> {
            val start = startDay(zone)
            val last = start.plusDays((span - 1).toLong())
            day >= start && day <= last
        }
        ScheduleRepeat.DAILY -> startsOn(day, zone)
        ScheduleRepeat.WEEKLY, ScheduleRepeat.MONTHLY, ScheduleRepeat.YEARLY -> {
            val limit = minOf(span, repeat.periodDayCap())
            (0 until limit).any { startsOn(day.minusDays(it.toLong()), zone) }
        }
    }
}

/** 여러 날 일정에서 그날이 몇 일차인가(1부터). 하루짜리거나 해당 없으면 null. */
fun ScheduleItemEntity.dayIndex(day: LocalDate, zone: ZoneId = ZoneId.systemDefault()): Int? {
    if (!isMultiDay(zone)) return null
    for (offset in 0 until spanDays(zone)) {
        if (startsOn(day.minusDays(offset.toLong()), zone)) return offset + 1
    }
    return null
}

private fun calendarOccurs(createdDay: LocalDate, day: LocalDate, weekly: Boolean, monthly: Boolean): Boolean {
    if (day < createdDay) return false
    if (weekly) return createdDay.dayOfWeek == day.dayOfWeek
    if (monthly) {
        val startDom = createdDay.dayOfMonth
        val targetDom = day.dayOfMonth
        if (startDom == targetDom) return true
        return startDom > day.lengthOfMonth() && targetDom == day.lengthOfMonth()
    }
    return true
}

/** .once가 이 날짜에 뜨는가 — 적어 넣은 그날에만. 완료된 날 표시는 호출부가 completion으로 판정. */
fun InputItemEntity.onceShows(day: LocalDate, zone: ZoneId = ZoneId.systemDefault()): Boolean =
    createdAt.toLocalDate(zone) == day

/** .once·.daily·.weekly·.monthly 판정(달력 기준). 생성일 이전은 발생 안 함. .cycleAnchored는 항상 false. */
fun InputItemEntity.occursByCalendar(day: LocalDate, zone: ZoneId = ZoneId.systemDefault()): Boolean {
    val created = createdAt.toLocalDate(zone)
    return when (schedule) {
        InputSchedule.Once, InputSchedule.Daily -> day >= created
        InputSchedule.Weekly -> calendarOccurs(created, day, weekly = true, monthly = false)
        InputSchedule.Monthly -> calendarOccurs(created, day, weekly = false, monthly = true)
        is InputSchedule.CycleAnchored -> false
    }
}

/** Output 달력 판정 — .once는 적어 넣은 그날만, 단 목표일이 있으면 그날까지 이어진다. */
fun OutputItemEntity.occursByCalendar(day: LocalDate, zone: ZoneId = ZoneId.systemDefault()): Boolean {
    val created = createdAt.toLocalDate(zone)
    if (day < created) return false
    return when (schedule) {
        OutputSchedule.Once -> {
            val target = targetDate?.toLocalDate(zone)
            if (target != null) day <= target else day == created
        }
        OutputSchedule.Daily -> true
        OutputSchedule.Weekly -> calendarOccurs(created, day, weekly = true, monthly = false)
        OutputSchedule.Monthly -> calendarOccurs(created, day, weekly = false, monthly = true)
        is OutputSchedule.CycleAnchored -> false
    }
}

/** 하루 안 정렬: 시각 있는 항목 = 시간순, 없는 항목 = 맨 뒤. 동률·무시각은 원래 순서(안정 정렬). */
fun <T> sortedByTimeOfDay(items: List<T>, time: (T) -> Int?): List<T> =
    items.withIndex().sortedWith { a, b ->
        val t1 = time(a.value)
        val t2 = time(b.value)
        when {
            t1 != null && t2 != null -> if (t1 == t2) a.index - b.index else t1 - t2
            t1 != null -> -1
            t2 != null -> 1
            else -> a.index - b.index
        }
    }.map { it.value }

/** 루틴 정렬(iOS orderedInputs, 2026-11-05): 직접 옮긴 순서(sortOrder) 먼저, 아직 안 옮긴 것은 그 뒤에 시각순. */
fun <T> orderedInputs(items: List<T>, input: (T) -> InputItemEntity): List<T> {
    val (manual, unordered) = items.withIndex().partition { input(it.value).sortOrder != null }
    val sortedManual = manual.sortedWith(compareBy({ input(it.value).sortOrder }, { it.index })).map { it.value }
    return sortedManual + sortedByTimeOfDay(unordered.map { it.value }) { input(it).timeMinutes }
}

/** iOS moveInput — 루틴 하나를 화면 목록의 `index` 자리로 옮긴다. 화면엔 그날 뜨는 것만 보이므로 전체 목록에서
 *  "옮긴 자리 바로 뒤에 오는 이웃" 앞에 끼워 넣고 전체를 0…n으로 다시 매긴다. 반환 = sortOrder가 바뀐 엔티티만. */
fun reorderedInputs(moving: InputItemEntity, toVisibleIndex: Int, visible: List<InputItemEntity>, all: List<InputItemEntity>): List<InputItemEntity> {
    val global = orderedInputs(all) { it }.filter { it.id != moving.id }.toMutableList()
    val others = visible.filter { it.id != moving.id }
    val atNeighbor = others.getOrNull(toVisibleIndex)?.let { n -> global.indexOfFirst { it.id == n.id } } ?: -1
    val afterLast = others.lastOrNull()?.let { l -> global.indexOfFirst { it.id == l.id } } ?: -1
    val insertAt = when {
        atNeighbor >= 0 -> atNeighbor
        afterLast >= 0 -> afterLast + 1
        else -> global.size
    }
    global.add(insertAt, moving)
    return global.withIndex().filter { (order, item) -> item.sortOrder != order }.map { (order, item) -> item.copy(sortOrder = order) }
}
