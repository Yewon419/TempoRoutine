// 템포루틴 — occurrence 열거 (MASTER §5.6.4 LOCKED)
// iOS TempoCore/CycleOccurrences.swift 1:1 이식. resolveDate는 "한 주기 안"만 답한다 — 어느 주기들에 물을지가 이 계약.

package app.temporoutine.core

import java.time.LocalDate
import java.time.temporal.ChronoUnit

data class CycleWindow(
    val start: LocalDate,
    val length: Int,         // 과거=실측 간격, 현재/미래=평균 N
    val projected: Boolean,  // 미래 예측 주기
)

object CycleOccurrences {

    /** §5.6.4 주기 열거: ① 과거 = 연속 시작일 쌍(길이 실측) ② 현재 = 마지막 시작일 + N ③ 미래 = lastStart + k·N (k ≤ 투영 지평). */
    fun cycleWindows(periodStarts: List<LocalDate>, averageLength: Int, horizonCycles: Int): List<CycleWindow> {
        val n = averageLength
        val sorted = periodStarts.sorted()
        val last = sorted.lastOrNull() ?: return emptyList()
        val windows = mutableListOf<CycleWindow>()
        for ((a, b) in sorted.zipWithNext()) {
            val measured = ChronoUnit.DAYS.between(a, b).toInt()
            windows.add(CycleWindow(a, measured, projected = false))
        }
        windows.add(CycleWindow(last, n, projected = false))
        if (horizonCycles >= 1) {
            for (k in 1..horizonCycles) {
                windows.add(CycleWindow(last.plusDays((k * n).toLong()), n, projected = true))
            }
        }
        return windows
    }

    data class Occurrence(
        val date: LocalDate,
        val cycleStart: LocalDate,
        val projected: Boolean,
    )

    /** 주기 기준 반복의 occurrence 열거.
     *  repeatsEveryCycle=true → 창마다 resolve(skip이면 그 주기 미발생).
     *  one-shot(§5.5.3) → createdAt이 속한 주기에 바인딩, resolve 날짜가 createdAt 이전이면 다음 주기로 1회 이월.
     *  one-shot의 skip은 clamp로 해석(§5.5.3). */
    fun occurrences(
        of: CycleRecurrence,
        createdAt: LocalDate,
        periodStarts: List<LocalDate>,
        averageLength: Int,
        horizonCycles: Int,
        menstrualLength: Int = 5,
    ): List<Occurrence> {
        val r = of
        val windows = cycleWindows(periodStarts, averageLength, horizonCycles)
        if (windows.isEmpty()) return emptyList()

        fun resolve(w: CycleWindow, rule: OffsetOverflowRule): LocalDate? {
            val rec = r.copy(overflowRule = rule)
            val p = CyclePrediction(w.start, w.length, CyclePrediction.Confidence.LOW)
            return CyclePredictor.resolveDate(rec, w.start, p, menstrualLength)
        }

        // 계절 전체(2026-08-01): 한 주기에서 그 계절의 모든 날이 발생일 — dayOffset·overflowRule 무의미.
        val anchor = r.anchor
        if (r.spansWholePhase && anchor is CycleAnchor.Phase) {
            fun phaseDays(w: CycleWindow): List<Occurrence> {
                val span = CyclePredictor.phaseSpans(w.length, menstrualLength).firstOrNull { it.phase == anchor.phase }
                    ?: return emptyList()
                if (span.length <= 0) return emptyList()
                return (0 until span.length).map { i ->
                    // startDay는 1-indexed — 창 시작일이 1일차다
                    Occurrence(w.start.plusDays((span.startDay - 1 + i).toLong()), w.start, w.projected)
                }
            }
            if (r.repeatsEveryCycle) return windows.flatMap(::phaseDays)
            // one-shot = createdAt이 속한 창의 그 계절만. 이미 지난 계절이면 다음 창으로.
            var index = windows.size - 1
            for ((i, w) in windows.withIndex()) {
                val end = w.start.plusDays(w.length.toLong())
                if (createdAt < end) { index = i; break }
            }
            val days = phaseDays(windows[index])
            val lastDay = days.lastOrNull()?.date
            if (lastDay != null && lastDay < createdAt && index + 1 < windows.size) {
                return phaseDays(windows[index + 1])
            }
            return days
        }

        if (r.repeatsEveryCycle) {
            return windows.mapNotNull { w ->
                resolve(w, r.overflowRule)?.let { Occurrence(it, w.start, w.projected) }
            }
        }

        // one-shot: 바인딩 주기 = createdAt이 속한 창 (첫 창 이전 → 첫 창, 전부 지난 뒤 → 마지막 창)
        val effectiveRule = if (r.overflowRule == OffsetOverflowRule.SKIP) OffsetOverflowRule.CLAMP else r.overflowRule
        var bindingIndex = windows.size - 1
        for ((i, w) in windows.withIndex()) {
            val end = w.start.plusDays(w.length.toLong())
            if (createdAt < end) { bindingIndex = i; break }
        }
        val resolved = resolve(windows[bindingIndex], effectiveRule) ?: return emptyList()
        if (resolved < createdAt && bindingIndex + 1 < windows.size) {
            val rolled = resolve(windows[bindingIndex + 1], effectiveRule)
            if (rolled != null) {
                val w = windows[bindingIndex + 1]
                return listOf(Occurrence(rolled, w.start, w.projected))
            }
        }
        val w = windows[bindingIndex]
        return listOf(Occurrence(resolved, w.start, w.projected))
    }
}
