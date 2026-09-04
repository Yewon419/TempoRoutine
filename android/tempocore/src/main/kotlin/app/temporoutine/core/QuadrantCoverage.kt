// 템포루틴 — 주기 사분면 커버리지 (MASTER §5.12 ⑤) — 엔진 입력 결손 대책.
// iOS TempoCore/QuadrantCoverage.swift 1:1 이식. ⚠ 사분면 경계는 계절 경계와 일부러 다르다.

package app.temporoutine.core

object QuadrantCoverage {

    /** 위상 4등분. 계절 4개와 개수만 같고 경계가 다르다. */
    const val COUNT = 4

    /** cycleDay(1-indexed) → 사분면 인덱스 0...3. 마지막 날이 4로 넘어가지 않게 상한을 물린다. */
    fun quadrant(day: Int, cycleLength: Int): Int? {
        if (cycleLength <= 0 || day < 1 || day > cycleLength) return null
        val index = (day - 1) * COUNT / cycleLength
        return minOf(COUNT - 1, index)
    }

    /** 사분면별 기록 수. 두 계열 중 한쪽만 있어도 1건. */
    fun coverage(signals: List<DailySignal>): List<Int> {
        val counts = IntArray(COUNT)
        for (signal in signals) {
            if (signal.emotional == null && signal.bodily == null) continue
            val index = quadrant(signal.cycleDay, signal.cycleLength) ?: continue
            counts[index] += 1
        }
        return counts.toList()
    }

    /** 기록이 하나도 없는 사분면. */
    fun emptyQuadrants(signals: List<DailySignal>): List<Int> =
        coverage(signals).withIndex().filter { it.value == 0 }.map { it.index }

    /** 사분면이 차지하는 cycleDay 구간(양끝 포함). quadrant()의 역함수. */
    fun dayRange(quadrant: Int, cycleLength: Int): IntRange? {
        if (cycleLength <= 0 || quadrant < 0 || quadrant >= COUNT) return null
        val days = (1..cycleLength).filter { quadrant(it, cycleLength) == quadrant }
        val first = days.firstOrNull() ?: return null
        val last = days.lastOrNull() ?: return null
        return first..last
    }

    /** 사분면 안에서 알림을 걸 cycleDay — 구간의 중간 지점. */
    fun reminderDay(quadrant: Int, cycleLength: Int): Int? {
        val range = dayRange(quadrant, cycleLength) ?: return null
        val count = range.last - range.first + 1
        return range.first + (count - 1) / 2
    }
}
