// 템포루틴 — 리듬 신호 값 타입 (MASTER §5.12 / §3.11)
// iOS TempoCore/AxisTypes.swift 1:1 이식.
// ⚠ SignalConversion의 규칙: 계열 값은 전부 "높을수록 힘듦"으로 통일한다.
//   mood 1 흐림 … 5 맑음 (뒤집는다) / irritability 1 잔잔 … 5 날카로움 (그대로) / pain 1 불편 … 5 괜찮음 (뒤집는다)

package app.temporoutine.core

object AxisScale {
    /** 체크인 저장 척도 상한(1...5). */
    const val MAX = 5
}

/** 하루치 관측 — 두 계열 중 한쪽만 있어도 유효하다. */
data class DailySignal(
    val cycleDay: Int,        // 1-indexed
    val cycleLength: Int,
    val emotional: Double?,   // y_정서 (높을수록 힘듦)
    val bodily: Double?,      // y_신체 (높을수록 힘듦)
    val isBackfilled: Boolean = false,
) {
    /** 주기 위상 θ = 2π(day−1)/length */
    val theta: Double
        get() = if (cycleLength <= 0) 0.0 else 2 * Math.PI * (cycleDay - 1) / cycleLength
}

object SignalConversion {
    /** 0 또는 null = 미기록. 저장 규약상 0이 미기록이다(§5.5). */
    private fun recorded(value: Int?): Double? {
        if (value == null || value < 1 || value > AxisScale.MAX) return null
        return value.toDouble()
    }

    private fun flipped(value: Double): Double = (AxisScale.MAX + 1) - value

    /** y_정서 = ((MAX+1 − mood) + irritability) / 2. 한쪽만 있으면 그 한쪽. */
    fun emotional(mood: Int?, irritability: Int?): Double? {
        val flippedMood = recorded(mood)?.let(::flipped)
        val rawIrritability = recorded(irritability)
        return when {
            flippedMood != null && rawIrritability != null -> (flippedMood + rawIrritability) / 2
            flippedMood != null -> flippedMood
            rawIrritability != null -> rawIrritability
            else -> null
        }
    }

    /** y_신체 = MAX+1 − pain */
    fun bodily(pain: Int?): Double? = recorded(pain)?.let(::flipped)
}

enum class RhythmType(val rawValue: String, val displayName: String) {
    VIVACE("vivace", "비바체"),     // 변동이 큰 편
    ANDANTE("andante", "안단테"),   // 잔잔한 편
    RUBATO("rubato", "루바토");     // 아직 정해지는 중
}
