// 템포루틴 — 생리 기간 파생 로직 (MASTER §5.5.4, I-2 LOCKED)
// iOS TempoCore/PeriodMath.swift 1:1 이식. PeriodDay(일별 기록) 집합 → 에피소드 도출. 저장하지 않는 순수 파생.

package app.temporoutine.core

import java.time.LocalDate
import java.time.temporal.ChronoUnit

object PeriodMath {

    /** §5.6.5 최소 에피소드 간격 — 이 미만 근접은 같은 에피소드로 묶는다. */
    const val MIN_PERIOD_GAP_DAYS = 14

    /** 일별 기록 → 에피소드(연속 덩어리) 배열. 각 에피소드는 day 오름차순.
     *  규칙(§5.5.4): day 오름차순 순회, 직전 에피소드 "시작일 + minGap" 미만이면 같은 에피소드.
     *  불연속 day 허용, 입력 중복·비정렬 허용. */
    fun episodes(days: List<LocalDate>, minGap: Int = MIN_PERIOD_GAP_DAYS): List<List<LocalDate>> {
        val sorted = days.toSet().sorted()
        if (sorted.isEmpty()) return emptyList()
        val result = mutableListOf<List<LocalDate>>()
        var current = mutableListOf<LocalDate>()
        var currentStart = sorted[0]
        for (day in sorted) {
            if (current.isEmpty()) {
                current = mutableListOf(day)
                currentStart = day
                continue
            }
            val gap = ChronoUnit.DAYS.between(currentStart, day).toInt()
            if (gap < minGap) {
                current.add(day)
            } else {
                result.add(current)
                current = mutableListOf(day)
                currentStart = day
            }
        }
        result.add(current)
        return result
    }

    /** 주기 시작일 배열 = 각 에피소드의 최소 day → §5.6 엔진 입력 `periodStarts`. */
    fun episodeStarts(days: List<LocalDate>, minGap: Int = MIN_PERIOD_GAP_DAYS): List<LocalDate> =
        episodes(days, minGap).mapNotNull { it.firstOrNull() }

    /** 에피소드 실측 길이(일) = 마지막 기록일 − 시작일 + 1 (개정 M — §5.3 층 2 `M`의 실측 소스). */
    fun episodeLengths(days: List<LocalDate>, minGap: Int = MIN_PERIOD_GAP_DAYS): List<Int> =
        episodes(days, minGap).mapNotNull { episode ->
            val first = episode.firstOrNull() ?: return@mapNotNull null
            val last = episode.lastOrNull() ?: return@mapNotNull null
            ChronoUnit.DAYS.between(first, last).toInt() + 1
        }
}
