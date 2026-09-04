// 템포루틴 — 리듬 엔진: 윈도우 통계 (MASTER §5.12 개정 M 2026-08-08)
// iOS TempoCore/WindowStats.swift 1:1 이식.
// 좌표계 = §5.3 양방향 앵커 공용: d(시작 후 일수) + r(다음 시작까지 남은 일수). 완료 주기만 받으므로 r도 실측.
// 실패 모드 = 침묵: 빈 윈도우·표본 미달이면 null (§7 "로그가 없으면 말하지 않는다").

package app.temporoutine.core

/** 완료된 한 주기의 하루 기록 — 양방향 앵커 좌표. */
data class WindowDaySample(
    val daysFromStart: Int,   // d — 1-indexed, 주기 시작(생리 1일차)부터
    val daysUntilNext: Int,   // r — 1-indexed, 다음 주기 시작 전날이 1
    val energy: Int?,         // 1...5 (범위 밖·0 = 미기록으로 무시)
    val mood: Int?,           // 1...5
)

/** 완료 주기 하나 — 길이는 실측(연속 시작일 간격). */
data class WindowCycle(
    val length: Int,
    val samples: List<WindowDaySample>,
)

enum class WindowSignal(val rawValue: String) {
    ENERGY("energy"),
    MOOD("mood"),
}

/** 서술·내보내기용 요약 — (계절 × 신호)의 최근 주기 중앙값. */
data class WindowSummary(
    val phase: CyclePhase,
    val signal: WindowSignal,
    val median: Double,        // 주기별 윈도우 중앙값들의 중앙값
    val cyclesWithData: Int,
)

object WindowStatsEngine {

    // ── 상수 (§5.12 루프 2 — 설문·문헌·파일럿으로 조정하고 앱 업데이트로 배포)

    /** 최근 K주기만 본다 — 예측 엔진 v1.1의 이동 윈도(최근 5 gap)와 정렬. */
    const val RECENT_CYCLES = 5
    /** 판정 게이트 — 유효 주기가 이만큼은 있어야 말한다(§5.3 학습 계약 ≥3주기). */
    const val MIN_CYCLES = 3
    /** 주기 하나가 판정에 들어가기 위한 최소 기록 일수. */
    const val MIN_SAMPLES_PER_CYCLE = 4
    /** "낮다/높다" 판정 여유 — 5점 척도 반 칸. */
    const val MARGIN = 0.5
    /** `P` 후보 범위(§5.3 클램프 [2,7]). */
    val PRE_WINDOW_RANGE: IntRange = 2..7
    /** suffix 판정에 필요한 최소 기록 일수. */
    const val MIN_SUFFIX_SAMPLES = 2
    /** suffix 안 "저컨디션 날" 비율 임계. 파일럿 조정 대상. */
    const val LOW_DAY_FRACTION = 0.75
    /** A축 판정 기준 range — peak-to-peak 1.0(5점 척도 한 칸). */
    const val BASELINE_RANGE = 1.0
    /** §5.3 층 2 `P` 디폴트 — 학습값이 게이트를 못 넘으면 이 값. */
    const val DEFAULT_PRE_WINDOW = 5

    // ── 기초 통계

    /** 중앙값. 빈 배열 = null(침묵). */
    internal fun median(values: List<Double>): Double? {
        if (values.isEmpty()) return null
        val sorted = values.sorted()
        val mid = sorted.size / 2
        return if (sorted.size % 2 == 1) sorted[mid] else (sorted[mid - 1] + sorted[mid]) / 2
    }

    /** 1...5 밖(0 = 미기록)은 null. */
    internal fun value(sample: WindowDaySample, signal: WindowSignal): Double? {
        val raw = when (signal) {
            WindowSignal.ENERGY -> sample.energy
            WindowSignal.MOOD -> sample.mood
        }
        if (raw == null || raw !in 1..AxisScale.MAX) return null
        return raw.toDouble()
    }

    internal fun windowMedian(cycle: WindowCycle, signal: WindowSignal, predicate: (WindowDaySample) -> Boolean): Double? =
        median(cycle.samples.filter(predicate).mapNotNull { value(it, signal) })

    /** 주기 전체 중앙값 = 그 주기의 본인 베이스라인. */
    fun baseline(cycle: WindowCycle, signal: WindowSignal): Double? = windowMedian(cycle, signal) { true }

    /** suffix 윈도우(r ≤ p) 중앙값. */
    fun suffixMedian(cycle: WindowCycle, signal: WindowSignal, p: Int): Double? =
        windowMedian(cycle, signal) { it.daysUntilNext <= p }

    /** 계절 윈도우 중앙값 — 경계는 §5.3 실측 길이 기준(phaseSpans와 같은 단일 출처). */
    fun phaseMedian(cycle: WindowCycle, signal: WindowSignal, phase: CyclePhase, menstrualLength: Int = 5): Double? =
        windowMedian(cycle, signal) {
            CyclePredictor.phaseForDay(it.daysFromStart, cycle.length, menstrualLength) == phase
        }

    // ── 판정 공통

    /** 판정에 쓸 주기 — 최근 K개 중 기록 일수가 충분한 것만. */
    internal fun usable(cycles: List<WindowCycle>): List<WindowCycle> =
        cycles.takeLast(RECENT_CYCLES).filter { cycle ->
            cycle.samples.count { value(it, WindowSignal.ENERGY) != null || value(it, WindowSignal.MOOD) != null } >= MIN_SAMPLES_PER_CYCLE
        }

    /** 합의 임계 — n주기 중 max(MIN_CYCLES, n−1)주기가 같은 방향이어야 한다. */
    internal fun agreementThreshold(n: Int): Int = maxOf(MIN_CYCLES, n - 1)

    // ── `P` 저컨디션 윈도우 (§5.3 층 2 — 신호 = energy)

    /** 주기 하나의 suffix 길이 후보 — 저컨디션 비율(≤ 베이스라인 − MARGIN)이 LOW_DAY_FRACTION 이상인 가장 큰 p. */
    internal fun perCyclePreWindow(cycle: WindowCycle): Int? {
        val base = baseline(cycle, WindowSignal.ENERGY) ?: return null
        var best: Int? = null
        for (p in PRE_WINDOW_RANGE) {
            val days = cycle.samples.filter { it.daysUntilNext <= p }.mapNotNull { value(it, WindowSignal.ENERGY) }
            if (days.size < MIN_SUFFIX_SAMPLES) continue
            val lows = days.count { it <= base - MARGIN }
            if (lows.toDouble() / days.size >= LOW_DAY_FRACTION) best = p
        }
        return best
    }

    /** 학습된 `P` — 주기별 후보의 중앙값(합의 임계 충족 시). 없으면 null → 앱은 §5.3 디폴트 5. */
    fun preMenstrualWindow(cycles: List<WindowCycle>): Int? {
        val usable = usable(cycles)
        if (usable.size < MIN_CYCLES) return null
        val candidates = usable.mapNotNull(::perCyclePreWindow)
        if (candidates.size < agreementThreshold(usable.size)) return null
        val mid = median(candidates.map { it.toDouble() }) ?: return null
        return mid.roundHalfAwayFromZero().coerceIn(PRE_WINDOW_RANGE.first, PRE_WINDOW_RANGE.last)
    }

    /** 홀드아웃 적중률 — "suffix p일 윈도우" 예측과 "실제 저컨디션 날(energy ≤ 2)"의 F1. 기록된 날만 대상. */
    internal fun holdoutScore(cycle: WindowCycle, p: Int): Double? {
        val recorded = cycle.samples.mapNotNull { s ->
            value(s, WindowSignal.ENERGY)?.let { (s.daysUntilNext <= p) to (it <= 2) }
        }
        if (recorded.isEmpty()) return null
        val tp = recorded.count { it.first && it.second }.toDouble()
        val fp = recorded.count { it.first && !it.second }.toDouble()
        val fn = recorded.count { !it.first && it.second }.toDouble()
        if (tp + fp + fn == 0.0) return 1.0   // 저컨디션도 윈도우 기록도 없음 = 예측이 틀린 게 없다
        return 2 * tp / (2 * tp + fp + fn)
    }

    /** §5.3 채택 게이트 — 마지막 완료 주기를 홀드아웃으로 두고, 학습 P가 디폴트보다 홀드아웃 F1이 나을 때만 채택. */
    fun adoptedPreWindow(cycles: List<WindowCycle>): Int? {
        if (cycles.size < MIN_CYCLES + 1) return null
        val holdout = cycles.lastOrNull() ?: return null
        val training = cycles.dropLast(1)
        val learned = preMenstrualWindow(training) ?: return null
        if (learned == DEFAULT_PRE_WINDOW) return null
        val learnedScore = holdoutScore(holdout, learned) ?: return null
        val defaultScore = holdoutScore(holdout, DEFAULT_PRE_WINDOW) ?: return null
        if (learnedScore <= defaultScore) return null
        return learned
    }

    // ── H1 배란 주변 기분 상승 (§2.3 가설 레지스트리 — 신호 = mood)

    /** true = 상승 합의 / false = 상승 없음 합의 / null = 불확정·표본 미달(침묵). */
    fun h1SummerMoodLift(cycles: List<WindowCycle>, menstrualLength: Int = 5): Boolean? {
        var up = 0
        var judged = 0
        for (cycle in usable(cycles)) {
            val base = baseline(cycle, WindowSignal.MOOD) ?: continue
            val summer = phaseMedian(cycle, WindowSignal.MOOD, CyclePhase.OVULATION, menstrualLength) ?: continue
            judged += 1
            if (summer >= base + MARGIN) up += 1
        }
        if (judged < MIN_CYCLES) return null
        val threshold = agreementThreshold(judged)
        if (up >= threshold) return true
        if (judged - up >= threshold) return false
        return null
    }

    // ── A축 유형 (신호 = mood)

    /** 주기 하나의 진폭 = 계절 윈도우 중앙값들의 range. 표본 있는 계절이 2개 미만이면 null. */
    internal fun perCycleRange(cycle: WindowCycle, signal: WindowSignal = WindowSignal.MOOD, menstrualLength: Int = 5): Double? {
        val medians = CyclePhase.entries.mapNotNull { phaseMedian(cycle, signal, it, menstrualLength) }
        if (medians.size < 2) return null
        return medians.max() - medians.min()
    }

    /** 유형 배정 — null = 데이터 부족, 루바토 = 표본은 충분한데 주기 간 불일치. */
    fun classify(cycles: List<WindowCycle>, menstrualLength: Int = 5): RhythmType? {
        val ranges = usable(cycles).mapNotNull { perCycleRange(it, menstrualLength = menstrualLength) }
        if (ranges.size < MIN_CYCLES) return null
        val threshold = agreementThreshold(ranges.size)
        val high = ranges.count { it >= BASELINE_RANGE }
        if (high >= threshold) return RhythmType.VIVACE
        if (ranges.size - high >= threshold) return RhythmType.ANDANTE
        return RhythmType.RUBATO
    }

    // ── 서술·내보내기 프로파일

    /** (계절 × 신호) 요약 — 표본 없는 칸은 조용히 빠진다. */
    fun profile(cycles: List<WindowCycle>, menstrualLength: Int = 5): List<WindowSummary> {
        val usable = usable(cycles)
        val result = mutableListOf<WindowSummary>()
        for (signal in WindowSignal.entries) {
            for (phase in CyclePhase.entries) {
                val medians = usable.mapNotNull { phaseMedian(it, signal, phase, menstrualLength) }
                val mid = median(medians) ?: continue
                result.add(WindowSummary(phase, signal, mid, medians.size))
            }
        }
        return result
    }
}
