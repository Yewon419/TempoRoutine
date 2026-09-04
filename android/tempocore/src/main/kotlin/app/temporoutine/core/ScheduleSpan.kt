// 템포루틴 — 여러 날 일정의 기간·띠 세그먼트 (§8.2.3 다중일 일정)
// iOS TempoCore/ScheduleSpan.swift 1:1 이식. 월 그리드의 "이 칸에 걸치는가" 배열만 받아 주 단위 띠 조각으로 자른다.

package app.temporoutine.core

import java.time.LocalDateTime
import java.time.temporal.ChronoUnit

/** 월 그리드 한 행(주) 안에서 이어지는 띠 한 조각.
 *  isStart·isEnd = 일정의 실제 시작·끝(양 끝만 둥글게). 주 경계로 잘린 쪽은 false. */
data class BandSegment(
    val row: Int,
    val column: Int,
    val length: Int,
    val isStart: Boolean,
    val isEnd: Boolean,
)

object ScheduleSpan {

    /** 시작~종료가 걸치는 날 수(자정 기준). 종료가 없거나 시작보다 이르면 1.
     *  iOS는 Date+Calendar.startOfDay — 여기서는 호출자가 기기 시간대로 만든 LocalDateTime의 날짜부만 본다. */
    fun dayCount(start: LocalDateTime, end: LocalDateTime?): Int {
        if (end == null) return 1
        val diff = ChronoUnit.DAYS.between(start.toLocalDate(), end.toLocalDate()).toInt()
        return maxOf(1, diff + 1)
    }

    /** 그리드 칸별 포함 여부 → 주 단위 띠 조각.
     *  continuesBefore·continuesAfter = 그리드 밖(이전·다음 달)에서 이어지는지. */
    fun bandSegments(
        cells: List<Boolean>,
        columns: Int = 7,
        continuesBefore: Boolean = false,
        continuesAfter: Boolean = false,
    ): List<BandSegment> {
        if (columns <= 0) return emptyList()
        val out = mutableListOf<BandSegment>()
        var i = 0
        while (i < cells.size) {
            if (!cells[i]) { i += 1; continue }
            val row = i / columns
            var j = i
            while (j + 1 < cells.size && cells[j + 1] && (j + 1) / columns == row) j += 1
            val isStart = if (i == 0) !continuesBefore else !cells[i - 1]
            val isEnd = if (j == cells.size - 1) !continuesAfter else !cells[j + 1]
            out.add(BandSegment(row, i % columns, j - i + 1, isStart, isEnd))
            i = j + 1
        }
        return out
    }
}
