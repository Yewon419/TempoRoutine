// 템포루틴 — "나의 리듬" 집계 엔진 (MASTER §5.6.3 계약)
// iOS TempoCore/RhythmEngine.swift 1:1 이식. (단계 × 신호) 버킷 평균 + 주기별 argmax. 카피는 앱 몫, 여기는 계산만.
// 계약(§5.6.3): energy·mood 둘 다 1...5인 행만 입력 · projected=true·null 단계는 집계 제외 · 옵션 신호는 non-null만.

package app.temporoutine.core

import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlin.math.floor

/** 리듬 탭이 다루는 신호(§8.2.5 — 에너지·기분·수면·식욕). pain은 M축 전용이라 여기 없다. */
enum class SignalKind(val rawValue: String) {
    ENERGY("energy"),
    MOOD("mood"),
    SLEEP("sleep"),
    APPETITE("appetite"),
}

/** 집계 입력 행 — 앱의 DailyCheckIn에서 변환해 넘긴다(tempocore는 DB를 모른다). */
data class SignalSample(
    val day: LocalDate,
    val energy: Int,
    val mood: Int,
    val sleep: Int?,
    val appetite: Int? = null,
    /** 집계 가중(2026-09-01 아픈 날) — 질병(0)은 앱이 아예 안 넘긴다. Σw 가중 평균 계약. */
    val weight: Double = 1.0,
) {
    internal fun value(of: SignalKind): Int? = when (of) {
        SignalKind.ENERGY -> energy
        SignalKind.MOOD -> mood
        SignalKind.SLEEP -> sleep
        SignalKind.APPETITE -> appetite
    }
}

/** 주기 일차 버킷 평균 한 점 — 일차 축 곡선(§8.2.5)의 입력. */
data class DayCurvePoint(
    val day: Int,          // 1-indexed 주기 일차
    val mean: Double,
    val sampleCount: Int,
)

/** §5.6.3 계약 그대로. */
data class PhaseSignalSummary(
    val phase: CyclePhase,
    val signal: SignalKind,
    val mean: Double,
    val sampleCount: Int,
)

object RhythmEngine {

    /** 신호별 이 개수 이상 쌓인 단계가 2개 이상일 때만 비교 서술(§5.6.3). */
    const val MIN_SAMPLES = 3

    private val validRange = 1..5

    private fun SignalSample.isValidRow(): Boolean =
        energy in validRange && mood in validRange && weight > 0

    /** (단계 × 신호) 버킷 평균. energy·mood 둘 다 1...5인 행만 입력. */
    fun summaries(
        samples: List<SignalSample>,
        periodStarts: List<LocalDate>,
        averageLength: Int,
        menstrualLength: Int = 5,
    ): List<PhaseSignalSummary> {
        if (averageLength <= 0) return emptyList()
        // 가중 누적 — sum = Σ(w·x), weight = Σw. 유효 표본 수 = ⌊Σw⌋.
        val buckets = linkedMapOf<CyclePhase, LinkedHashMap<SignalKind, Pair<Double, Double>>>()

        for (sample in samples) {
            if (!sample.isValidRow()) continue
            val r = CyclePredictor.cycleDay(sample.day, periodStarts, averageLength) ?: continue
            if (r.projected) continue
            val phase = CyclePredictor.phaseForDay(r.day, averageLength, menstrualLength)
            for (signal in SignalKind.entries) {
                val value = sample.value(signal) ?: continue
                if (value !in validRange) continue
                val perPhase = buckets.getOrPut(phase) { linkedMapOf() }
                val cur = perPhase[signal] ?: (0.0 to 0.0)
                perPhase[signal] = (cur.first + value * sample.weight) to (cur.second + sample.weight)
            }
        }

        return buckets.flatMap { (phase, signals) ->
            signals.map { (signal, acc) ->
                PhaseSignalSummary(phase, signal, acc.first / acc.second, floor(acc.second).toInt())
            }
        }
    }

    /** 주기 일차별 버킷 평균 — 일차 축 곡선의 입력. 일차가 averageLength를 넘는 표본은 버린다. */
    fun dayCurve(
        signal: SignalKind,
        samples: List<SignalSample>,
        periodStarts: List<LocalDate>,
        averageLength: Int,
    ): List<DayCurvePoint> {
        if (averageLength <= 0) return emptyList()
        val buckets = mutableMapOf<Int, Pair<Double, Double>>()
        for (sample in samples) {
            if (!sample.isValidRow()) continue
            val value = sample.value(signal) ?: continue
            if (value !in validRange) continue
            val r = CyclePredictor.cycleDay(sample.day, periodStarts, averageLength) ?: continue
            if (r.projected || r.day !in 1..averageLength) continue
            val cur = buckets[r.day] ?: (0.0 to 0.0)
            buckets[r.day] = (cur.first + value * sample.weight) to (cur.second + sample.weight)
        }
        return buckets.entries.sortedBy { it.key }.map { (day, acc) ->
            DayCurvePoint(day, acc.first / acc.second, floor(acc.second).toInt())
        }
    }

    /** 한 신호의 비교 서술 가능 여부 — MIN_SAMPLES를 채운 단계가 2개 이상(§5.6.3). */
    fun narratable(summaries: List<PhaseSignalSummary>, signal: SignalKind): Boolean =
        summaries.count { it.signal == signal && it.sampleCount >= MIN_SAMPLES } >= 2

    /** 그 신호의 유효 표본이 든 완료 주기 수 — 서술의 "지난 N주기"에 쓴다. 전체 주기 수(starts−1)를 쓰면 안 된다. */
    fun cyclesWithData(signal: SignalKind, samples: List<SignalSample>, periodStarts: List<LocalDate>): Int {
        val starts = periodStarts.sorted()
        if (starts.size < 2) return 0
        var count = 0
        for (index in 0 until starts.size - 1) {
            val start = starts[index]
            val end = starts[index + 1]
            val hasData = samples.any { sample ->
                sample.isValidRow()
                    && sample.value(signal)?.let { it in validRange } == true
                    && sample.day >= start && sample.day < end
            }
            if (hasData) count += 1
        }
        return count
    }

    /** 완료 주기(연속 시작일 쌍, 실측 길이)별로 그 신호가 가장 높았던 단계 — 오래된 주기부터.
     *  주기 안에서 표본 있는 단계가 2개 미만이면 그 주기는 건너뛴다. */
    fun perCycleTopPhases(
        signal: SignalKind,
        samples: List<SignalSample>,
        periodStarts: List<LocalDate>,
        menstrualLength: Int = 5,
    ): List<CyclePhase> {
        val starts = periodStarts.sorted()
        if (starts.size < 2) return emptyList()

        val result = mutableListOf<CyclePhase>()
        for (index in 0 until starts.size - 1) {
            val start = starts[index]
            val end = starts[index + 1]
            val length = ChronoUnit.DAYS.between(start, end).toInt()
            if (length <= 0) continue

            val acc = mutableMapOf<CyclePhase, Pair<Double, Double>>()
            for (sample in samples) {
                if (!sample.isValidRow()) continue
                val value = sample.value(signal) ?: continue
                if (value !in validRange) continue
                if (sample.day < start || sample.day >= end) continue
                val offset = ChronoUnit.DAYS.between(start, sample.day).toInt()
                // 과거 주기의 단계는 실측 길이로 도출(§5.6.4 ① — 과거는 실주기)
                val phase = CyclePredictor.phaseForDay(offset + 1, length, menstrualLength)
                val cur = acc[phase] ?: (0.0 to 0.0)
                acc[phase] = (cur.first + value * sample.weight) to (cur.second + sample.weight)
            }
            if (acc.size < 2) continue
            val top = acc.maxByOrNull { it.value.first / it.value.second } ?: continue
            result.add(top.key)
        }
        return result
    }
}
