// 템포루틴 Android — 주기 스냅샷 (iOS CycleSnapshot.swift + CycleParams 이식, 순수 Kotlin)
// 엔진(tempocore)은 그대로 쓰고, 앱 파라미터(prior·실측 M)만 여기서 묶는다. 렌더 경로에서 매번 새로 만들지 말 것.

package app.temporoutine.android.cycle

import app.temporoutine.core.CycleOccurrences
import app.temporoutine.core.CyclePhase
import app.temporoutine.core.CyclePrediction
import app.temporoutine.core.CyclePredictor
import app.temporoutine.core.CycleRecurrence
import app.temporoutine.core.PeriodMath
import java.time.LocalDate
import java.time.temporal.ChronoUnit

object CycleParams {
    fun averageLength(starts: List<LocalDate>, cycleLengthPrior: Int?): Int =
        CyclePredictor.averageLength(starts, cycleLengthPrior)

    /** §5.3 층 2 M — 실측 에피소드 길이(2...10, 1일짜리는 import 아티팩트로 제외) ≥2개면 중앙값, 아니면 prior, 없으면 5. */
    fun menstrualLength(days: List<LocalDate>, periodLengthPrior: Int?): Int {
        val measured = PeriodMath.episodeLengths(days).filter { it in 2..10 }.sorted()
        if (measured.size >= 2) {
            val mid = measured.size / 2
            val median = if (measured.size % 2 == 1) measured[mid].toDouble() else (measured[mid - 1] + measured[mid]) / 2.0
            return (median + 0.5).toInt().coerceIn(2, 10)
        }
        return periodLengthPrior?.coerceIn(1, 10) ?: 5
    }
}

data class PhaseInfo(
    val phase: CyclePhase,
    val dayInCycle: Int,   // 데이터 소비처용
    val dayInPhase: Int,   // UI 표시용("%d일차")
    val projected: Boolean,
)

class CycleSnapshot(
    days: List<LocalDate>,
    cycleLengthPrior: Int? = null,
    periodLengthPrior: Int? = null,
) {
    val starts: List<LocalDate> = PeriodMath.episodeStarts(days)
    private val episodeLengthByStart: Map<LocalDate, Int> = starts.zip(PeriodMath.episodeLengths(days)).toMap()
    val averageLength: Int = CycleParams.averageLength(starts, cycleLengthPrior)
    val menstrualLength: Int = CycleParams.menstrualLength(days, periodLengthPrior)
    val horizonCycles: Int = when (CyclePredictor.confidence(starts)) {
        CyclePrediction.Confidence.LOW -> 1
        CyclePrediction.Confidence.MEDIUM -> 2
        CyclePrediction.Confidence.HIGH -> 3
    }

    val isColdStart: Boolean get() = starts.isEmpty()
    /** S1 — 기록 1개뿐이라 예측이 prior 기반("예측 기반" hedge) */
    val isSingleRecord: Boolean get() = starts.size == 1

    /** 관측이 파라미터를 이긴다 — 진행 중 실제 에피소드 길이가 M보다 길면 그만큼 겨울. */
    fun effectiveMenstrualLength(on: LocalDate, projected: Boolean): Int {
        if (projected) return menstrualLength
        val start = starts.lastOrNull { it <= on } ?: return menstrualLength
        return minOf(10, maxOf(menstrualLength, episodeLengthByStart[start] ?: 0))
    }

    fun phase(on: LocalDate): CyclePhase? {
        val r = CyclePredictor.cycleDay(on, starts, averageLength) ?: return null
        return CyclePredictor.phaseForDay(r.day, averageLength, effectiveMenstrualLength(on, r.projected))
    }

    fun phaseInfo(on: LocalDate): PhaseInfo? {
        val r = CyclePredictor.cycleDay(on, starts, averageLength) ?: return null
        val m = effectiveMenstrualLength(on, r.projected)
        val phase = CyclePredictor.phaseForDay(r.day, averageLength, m)
        val spanStart = CyclePredictor.phaseSpans(averageLength, m).firstOrNull { it.phase == phase }?.startDay ?: 1
        return PhaseInfo(phase, r.day, maxOf(1, r.day - spanStart + 1), r.projected)
    }

    fun occurrences(of: CycleRecurrence, createdAt: LocalDate): List<CycleOccurrences.Occurrence> =
        CycleOccurrences.occurrences(of, createdAt, starts, averageLength, horizonCycles, menstrualLength)

    fun occurrence(of: CycleRecurrence, createdAt: LocalDate, on: LocalDate): CycleOccurrences.Occurrence? =
        occurrences(of, createdAt).firstOrNull { it.date == on }

    /** 다음 시작까지 남은 일수 — 창 밖이면 null. */
    fun daysUntilNextStart(on: LocalDate): Int? {
        for (w in CycleOccurrences.cycleWindows(starts, averageLength, horizonCycles)) {
            val offset = ChronoUnit.DAYS.between(w.start, on).toInt()
            if (offset in 0 until w.length) return w.length - offset
        }
        return null
    }
}
