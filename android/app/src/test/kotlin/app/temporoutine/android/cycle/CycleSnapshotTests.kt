// CycleSnapshot·CycleParams — iOS 계약(관측이 파라미터를 이긴다, dayInPhase, prior 경로)을 못 박는다.

package app.temporoutine.android.cycle

import app.temporoutine.core.CycleAnchor
import app.temporoutine.core.CyclePhase
import app.temporoutine.core.CycleRecurrence
import app.temporoutine.core.OffsetOverflowRule
import org.junit.jupiter.api.Test
import java.time.LocalDate
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CycleSnapshotTests {

    private val base = LocalDate.of(2026, 1, 5)
    private fun d(off: Int) = base.plusDays(off.toLong())
    private fun episode(start: Int, length: Int) = (0 until length).map { d(start + it) }

    @Test fun coldStart() {
        val s = CycleSnapshot(emptyList())
        assertTrue(s.isColdStart)
        assertNull(s.phase(d(0)))
        assertNull(s.phaseInfo(d(0)))
        assertEquals(28, s.averageLength)
        assertEquals(5, s.menstrualLength)
    }

    @Test fun singleRecordUsesPriorsAndHedges() {
        val s = CycleSnapshot(episode(0, 5), cycleLengthPrior = 30, periodLengthPrior = 4)
        assertTrue(s.isSingleRecord)
        assertEquals(30, s.averageLength, "기록 1개 → 주기 prior")
        assertEquals(4, s.menstrualLength, "실측 에피소드 1개는 중앙값 조건(≥2) 미달 → prior 4")
        assertEquals(5, s.effectiveMenstrualLength(d(0), projected = false), "진행 중 에피소드 실측 5일이 M(4)을 이긴다")
        val info = assertNotNull(s.phaseInfo(d(0)))
        assertEquals(CyclePhase.MENSTRUAL, info.phase)
        assertEquals(1, info.dayInCycle)
        assertEquals(1, info.dayInPhase)
        assertFalse(info.projected)
    }

    @Test fun menstrualLengthMedianOfMeasured() {
        // 에피소드 5·4·6일 → 중앙값 5. 1일짜리는 아티팩트로 제외.
        val days = episode(0, 5) + episode(28, 4) + episode(56, 6) + listOf(d(84))
        assertEquals(5, CycleParams.menstrualLength(days, periodLengthPrior = 9))
        // 짝수 개 [4, 6] → 5.0 → 5
        assertEquals(5, CycleParams.menstrualLength(episode(0, 4) + episode(28, 6), null))
        // 실측 부족 → prior(클램프 1..10), 없으면 5
        assertEquals(10, CycleParams.menstrualLength(emptyList(), 12))
        assertEquals(1, CycleParams.menstrualLength(emptyList(), 0))
        assertEquals(5, CycleParams.menstrualLength(emptyList(), null))
    }

    @Test fun observationBeatsParameter() {
        // 진행 중 에피소드가 7일 기록됐고 M=5 → 6·7일차도 겨울(effective 7). 다음 예측 주기는 M(5)로 돌아간다.
        val s = CycleSnapshot(episode(0, 7), periodLengthPrior = 5)
        assertEquals(7, s.effectiveMenstrualLength(d(6), projected = false))
        assertEquals(CyclePhase.MENSTRUAL, s.phase(d(6)))
        assertEquals(7, s.phaseInfo(d(6))!!.dayInPhase)
        assertEquals(CyclePhase.FOLLICULAR, s.phase(d(7)))
        assertEquals(1, s.phaseInfo(d(7))!!.dayInPhase, "봄 1일차 = 8일차")
        // 다음 주기(투영) 6일차는 봄
        assertEquals(5, s.effectiveMenstrualLength(d(28 + 5), projected = true))
        val projected = assertNotNull(s.phaseInfo(d(28 + 5)))
        assertTrue(projected.projected)
        assertEquals(CyclePhase.FOLLICULAR, projected.phase)
    }

    @Test fun dayInPhaseCountsWithinSeason() {
        val s = CycleSnapshot(episode(0, 5) + episode(28, 5) + episode(56, 5) + episode(84, 5))
        assertEquals(3, s.horizonCycles, "규칙적 4회 → high → 지평 3")
        val summer = assertNotNull(s.phaseInfo(d(84 + 15)))   // 16일차 = 여름 2일차(15~17)
        assertEquals(CyclePhase.OVULATION, summer.phase)
        assertEquals(16, summer.dayInCycle)
        assertEquals(2, summer.dayInPhase)
    }

    @Test fun occurrenceOnDay() {
        val s = CycleSnapshot(episode(0, 5) + episode(28, 5))
        val r = CycleRecurrence(CycleAnchor.Phase(CyclePhase.LUTEAL), 2, true, OffsetOverflowRule.CLAMP)
        // n=28: 가을 18일차 + 2 = 20일차 → d(19), d(28+19), 투영 d(56+19)
        assertNotNull(s.occurrence(r, d(0), d(19)))
        assertNotNull(s.occurrence(r, d(0), d(28 + 19)))
        assertNull(s.occurrence(r, d(0), d(20)))
        assertEquals(28 - 3, s.daysUntilNextStart(d(3)))
    }
}
