package app.temporoutine.android.cycle

import app.temporoutine.core.CyclePhase
import org.junit.jupiter.api.Test
import java.time.LocalDate
import kotlin.test.assertEquals
import kotlin.test.assertNull

class EnergyProfileTests {

    private val base = LocalDate.of(2026, 1, 5)
    private fun d(off: Int) = base.plusDays(off.toLong())
    private val snapshot = CycleSnapshot((0 until 5).map { d(it) } + (28 until 33).map { d(it) })

    @Test fun levelNeedsThreeSamples() {
        val two = EnergyProfile(listOf(EnergySample(d(0), 2, 1.0), EnergySample(d(1), 2, 1.0)), snapshot)
        assertNull(two.level(CyclePhase.MENSTRUAL))
        val three = EnergyProfile((0..2).map { EnergySample(d(it), 2, 1.0) }, snapshot)
        assertEquals(EnergyLevel.LOW, three.level(CyclePhase.MENSTRUAL))
        assertEquals(3, three.sampleCount(CyclePhase.MENSTRUAL))
    }

    @Test fun thresholds() {
        fun levelFor(values: List<Int>) =
            EnergyProfile(values.mapIndexed { i, v -> EnergySample(d(i), v, 1.0) }, snapshot).level(CyclePhase.MENSTRUAL)
        assertEquals(EnergyLevel.LOW, levelFor(listOf(2, 3, 2)))     // 2.33
        assertEquals(EnergyLevel.MID, levelFor(listOf(3, 3, 3)))
        assertEquals(EnergyLevel.MID, levelFor(listOf(3, 3, 4)))     // 3.33
        assertEquals(EnergyLevel.HIGH, levelFor(listOf(4, 3, 4)))    // 3.67
    }

    @Test fun illnessAndProjectedAreExcluded() {
        val samples = listOf(
            EnergySample(d(0), 5, 0.0),          // 질병 가중 0
            EnergySample(d(1), 2, 1.0),
            EnergySample(d(2), 2, 1.0),
            EnergySample(d(56 + 1), 5, 1.0),     // 마지막 앵커 + 28 초과 = 투영
        )
        val p = EnergyProfile(samples, snapshot)
        assertEquals(2, p.sampleCount(CyclePhase.MENSTRUAL))
        assertNull(p.level(CyclePhase.MENSTRUAL))
    }
}
