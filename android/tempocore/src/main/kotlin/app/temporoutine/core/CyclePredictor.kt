// 템포루틴 — 예측 엔진 (MASTER §5.6 / §5.6.1 / §5.6.2)
// iOS TempoCore/CyclePredictor.swift 1:1 이식 — 알고리즘 무변경. Date+Calendar 일수 차 → LocalDate+ChronoUnit.DAYS.

package app.temporoutine.core

import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlin.math.roundToInt

object CyclePredictor {

    private val validGapRange = 21..35

    private fun daysBetween(from: LocalDate, to: LocalDate): Int = ChronoUnit.DAYS.between(from, to).toInt()

    /** 평균 주기 길이 (§5.6 개정 2026-07-31).
     *  ① [21,35] 밖 gap = 기록 공백/스포팅으로 보고 제외 ② 유효 gap 중 최근 5개만 ③ 반올림 평균.
     *  기록<2개 또는 유효 gap 0개면 prior(온보딩 ②-4 보고값) → 없으면 28. prior는 실측 gap이 생기는 순간 무시. */
    fun averageLength(startDates: List<LocalDate>, priorLength: Int? = null): Int {
        val fallback = priorLength?.coerceIn(21, 35) ?: 28
        val sorted = startDates.sorted()
        if (sorted.size < 2) return fallback
        val validGaps = sorted.zipWithNext { a, b -> daysBetween(a, b) }
            .filter { it in validGapRange }
            .takeLast(5)
        if (validGaps.isEmpty()) return fallback
        val avg = validGaps.sum().toDouble() / validGaps.size
        return avg.roundHalfAwayFromZero().coerceIn(21, 35)
    }

    /** 예측 백테스트 오차 (2026-08-18). k번째 시작일까지의 기록으로 k+1번째 gap을 예측해 실제와 비교.
     *  실제 gap이 [21,35] 밖이면 표본 제외, 유효 오차 중 최근 5개만. 값 = 실제 − 예측. */
    fun predictionErrors(startDates: List<LocalDate>, priorLength: Int? = null): List<Int> {
        val sorted = startDates.sorted()
        if (sorted.size < 3) return emptyList()
        val errors = mutableListOf<Int>()
        for (k in 2 until sorted.size) {
            val predicted = averageLength(sorted.subList(0, k), priorLength)
            val actual = daysBetween(sorted[k - 1], sorted[k])
            if (actual !in validGapRange) continue
            errors.add(actual - predicted)
        }
        return errors.takeLast(5)
    }

    /** §5.3 LOCKED v2 경계(황체기 고정·양방향 앵커). 합은 항상 n. B=14/O=3 고정, M = 층 2 사용자값(디폴트 5). */
    fun phaseSpans(cycleLength: Int, menstrualLength: Int = 5): List<PhaseSpan> {
        val n = cycleLength
        val m = menstrualLength.coerceIn(1, 10)   // 온보딩 입력 범위와 동일한 안전 클램프
        val b = 14
        val o = 3
        var menLen = m
        var folLen = (n - b) - m       // N−B−M (탄력)
        var ovuLen = o
        var lutLen = b - o             // B−O
        // 짧은 주기 클램프: 난포기 <1이면 후반부(황체→배란→월경 순) 1일씩 양보.
        while (folLen < 1) {
            if (lutLen > 1) { lutLen -= 1; folLen += 1 }
            else if (ovuLen > 1) { ovuLen -= 1; folLen += 1 }
            else if (menLen > 1) { menLen -= 1; folLen += 1 }
            else break
        }
        val menStart = 1
        val folStart = menStart + menLen
        val ovuStart = folStart + folLen
        val lutStart = ovuStart + ovuLen
        return listOf(
            PhaseSpan(CyclePhase.MENSTRUAL, menStart, menLen),
            PhaseSpan(CyclePhase.FOLLICULAR, folStart, folLen),
            PhaseSpan(CyclePhase.OVULATION, ovuStart, ovuLen),
            PhaseSpan(CyclePhase.LUTEAL, lutStart, lutLen),
        )
    }

    /** 주기 기준 반복을 특정 주기(cycleStart=1일차)에서 절대 날짜로 resolve. ← 제품의 심장. */
    fun resolveDate(
        recurrence: CycleRecurrence,
        cycleStart: LocalDate,
        prediction: CyclePrediction,
        menstrualLength: Int = 5,
    ): LocalDate? {
        val n = prediction.averageLength
        // 1. 앵커 span(시작일 1-indexed, 길이)
        val spanStart: Int
        val spanLength: Int
        when (val anchor = recurrence.anchor) {
            CycleAnchor.CycleStart -> { spanStart = 1; spanLength = n }
            is CycleAnchor.Phase -> {
                val s = phaseSpans(n, menstrualLength).firstOrNull { it.phase == anchor.phase } ?: return null
                spanStart = s.startDay; spanLength = s.length
            }
        }
        // 2. dayOffset + overflow
        val offset = maxOf(0, recurrence.dayOffset)
        var targetDay: Int
        if (offset >= spanLength) {                       // overflow
            targetDay = when (recurrence.overflowRule) {
                OffsetOverflowRule.SKIP -> return null    // 이번 주기 미발생
                OffsetOverflowRule.CLAMP -> spanStart + spanLength - 1   // span 마지막 날
                OffsetOverflowRule.CARRY -> spanStart + offset           // 다음 단계로 이월(같은 주기 내)
            }
        } else {
            targetDay = spanStart + offset
        }
        // 3. 주기 경계로 가둠
        targetDay = targetDay.coerceIn(1, n)
        // 4. 절대 날짜 = cycleStart + (targetDay-1)일
        return cycleStart.plusDays((targetDay - 1).toLong())
    }

    /** 날짜의 단계 + projected 플래그. 기록 0개면 null(S0). */
    fun phase(on: LocalDate, periodStarts: List<LocalDate>, averageLength: Int, menstrualLength: Int = 5): Pair<CyclePhase, Boolean>? {
        val r = cycleDay(on, periodStarts, averageLength) ?: return null
        return phaseForDay(r.day, averageLength, menstrualLength) to r.projected
    }

    /** 기록 규칙성으로 신뢰도. <2 low / spread>7일 low / 4+개 & spread≤3일 high / 그 외 medium. */
    fun confidence(periodStarts: List<LocalDate>): CyclePrediction.Confidence {
        val sorted = periodStarts.sorted()
        if (sorted.size < 2) return CyclePrediction.Confidence.LOW
        val gaps = sorted.zipWithNext { a, b -> daysBetween(a, b) }
        val spread = (gaps.maxOrNull() ?: 0) - (gaps.minOrNull() ?: 0)
        if (sorted.size >= 4 && spread <= 3) return CyclePrediction.Confidence.HIGH
        if (spread <= 7) return CyclePrediction.Confidence.MEDIUM
        return CyclePrediction.Confidence.LOW
    }

    /** §5.6.2 예측 렌더 지평 — h번째 예상 월경 구간의 "끝"까지 포함(2026-07-28 off-by-one 정정). */
    fun projectionHorizon(lastStart: LocalDate, averageLength: Int, horizonCycles: Int, menstrualLength: Int = 5): LocalDate {
        val menstrualLen = phaseSpans(averageLength, menstrualLength).firstOrNull { it.phase == CyclePhase.MENSTRUAL }?.length ?: 5
        return lastStart.plusDays((horizonCycles * averageLength + menstrualLen - 1).toLong())
    }

    /** 예측 다음 생리일(마지막 기록 + 예측길이) 경과인데 새 기록 없음 = overdue. */
    fun isOverdue(on: LocalDate, periodStarts: List<LocalDate>, averageLength: Int): Boolean {
        val last = periodStarts.maxOrNull() ?: return false
        return daysBetween(last, on) >= averageLength
    }

    /** 날짜 → day-in-cycle(1-indexed) + projected. 과거=포함 실주기 앵커, 미래/overdue=예측 투영. */
    fun cycleDay(of: LocalDate, periodStarts: List<LocalDate>, averageLength: Int): DayResolution? {
        val n = averageLength
        val sorted = periodStarts.sorted()
        val first = sorted.firstOrNull() ?: return null            // 기록 0개(S0)
        val base = sorted.lastOrNull { it <= of }
        if (base == null) {                                        // 첫 기록 이전 → 역투영
            val diff = daysBetween(first, of)
            return DayResolution(((diff % n) + n) % n + 1, projected = true)
        }
        val diff = daysBetween(base, of)
        if (base == sorted.last() && diff >= n) {                  // 마지막 앵커+예측 초과 = 예측/overdue
            return DayResolution(diff % n + 1, projected = true)
        }
        return DayResolution(diff + 1, projected = false)          // 실제 주기 내
    }

    /** day-in-cycle → 단계. */
    fun phaseForDay(day: Int, cycleLength: Int, menstrualLength: Int = 5): CyclePhase {
        val d = day.coerceIn(1, cycleLength)
        for (s in phaseSpans(cycleLength, menstrualLength)) {
            if (d >= s.startDay && d < s.startDay + s.length) return s.phase
        }
        return CyclePhase.LUTEAL
    }
}

/** Swift `Double.rounded()` = schoolbook rounding(half away from zero). Kotlin `roundToInt`도 half-up이나 음수 처리 차이를 명시. */
internal fun Double.roundHalfAwayFromZero(): Int =
    if (this >= 0) (this + 0.5).toInt() else -((-this + 0.5).toInt())
