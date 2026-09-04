// 템포루틴 — CyclePredictor 테스트 (MASTER §5.6.1, T1~T16 = 25 assertions + T17~T18 백테스트)
// iOS TempoCoreTests/CyclePredictorTests.swift 1:1 이식 — 케이스·기대값 무변경.

package app.temporoutine.core

import org.junit.jupiter.api.Test
import java.time.LocalDate
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CyclePredictorTests {

    private val base: LocalDate = LocalDate.of(2025, 1, 1)
    private fun d(off: Int): LocalDate = base.plusDays(off.toLong())
    private val pred28 get() = CyclePrediction(d(0), 28, CyclePrediction.Confidence.HIGH)

    // T1 averageLength (§5.6 개정 2026-07-31: 유효 gap [21,35] 필터 + 최근 5개 + 반올림)
    @Test fun testT1AverageLength() {
        assertEquals(28, CyclePredictor.averageLength(listOf(d(0), d(28))), "T1 avg 28")
        assertEquals(28, CyclePredictor.averageLength(listOf(d(0))), "T1 avg <2 → 28")
        assertEquals(28, CyclePredictor.averageLength(listOf(d(0), d(60))), "T1 outlier-only long → 28")
        assertEquals(28, CyclePredictor.averageLength(listOf(d(0), d(10))), "T1 outlier-only short → 28")
        assertEquals(28, CyclePredictor.averageLength(listOf(d(0), d(28), d(84), d(112))), "T1 공백 gap 배제")
        assertEquals(26, CyclePredictor.averageLength(
            listOf(d(0), d(21), d(42), d(63), d(84), d(114), d(144), d(174))), "T1 최근 5개 평균")
        assertEquals(29, CyclePredictor.averageLength(listOf(d(0), d(28), d(57))), "T1 반올림")
    }

    // T1b prior (개정 M — 온보딩 ②-4 보고값. 실측 gap 없을 때만)
    @Test fun testT1bPriorLength() {
        assertEquals(30, CyclePredictor.averageLength(emptyList(), priorLength = 30), "T1b 기록 0 → prior")
        assertEquals(30, CyclePredictor.averageLength(listOf(d(0)), priorLength = 30), "T1b 기록 1 → prior")
        assertEquals(30, CyclePredictor.averageLength(listOf(d(0), d(60)), priorLength = 30), "T1b 유효 gap 0 → prior")
        assertEquals(26, CyclePredictor.averageLength(listOf(d(0), d(26)), priorLength = 30), "T1b 실측 gap 있으면 prior 무시")
        assertEquals(35, CyclePredictor.averageLength(emptyList(), priorLength = 40), "T1b prior 클램프 상한")
        assertEquals(21, CyclePredictor.averageLength(emptyList(), priorLength = 10), "T1b prior 클램프 하한")
        assertEquals(28, CyclePredictor.averageLength(emptyList()), "T1b prior 없음 → 28 불변")
    }

    // T17 predictionErrors — 백테스트
    @Test fun testT17PredictionErrors() {
        assertEquals(listOf(1, -2), CyclePredictor.predictionErrors(listOf(d(0), d(28), d(57), d(84))), "T17 기본 백테스트")
        assertEquals(listOf(0), CyclePredictor.predictionErrors(listOf(d(0), d(28), d(88), d(116))), "T17 무효 gap 배제")
        assertEquals(emptyList(), CyclePredictor.predictionErrors(listOf(d(0), d(28))), "T17 표본 부족")
        assertEquals(emptyList(), CyclePredictor.predictionErrors(emptyList()), "T17 기록 0")
        assertEquals(listOf(7, 6, 4, 3, 1), CyclePredictor.predictionErrors(
            listOf(d(0), d(21), d(42), d(63), d(84), d(112), d(140), d(168), d(196), d(224))), "T17 최근 5개 윈도")
    }

    // T18 predictionErrors + prior
    @Test fun testT18PredictionErrorsPrior() {
        assertEquals(listOf(-2), CyclePredictor.predictionErrors(listOf(d(0), d(60), d(88)), priorLength = 30), "T18 prior 예측")
        assertEquals(listOf(0), CyclePredictor.predictionErrors(listOf(d(0), d(60), d(88))), "T18 prior 없음 → 28")
    }

    // T2 phaseSpans(28)
    @Test fun testT2PhaseSpans28() {
        assertEquals(listOf(
            PhaseSpan(CyclePhase.MENSTRUAL, 1, 5),
            PhaseSpan(CyclePhase.FOLLICULAR, 6, 9),
            PhaseSpan(CyclePhase.OVULATION, 15, 3),
            PhaseSpan(CyclePhase.LUTEAL, 18, 11),
        ), CyclePredictor.phaseSpans(28), "T2 spans28")
    }

    // T3 phaseSpans(35) — 봄만 늘어남
    @Test fun testT3PhaseSpans35() {
        assertEquals(PhaseSpan(CyclePhase.FOLLICULAR, 6, 16), CyclePredictor.phaseSpans(35)[1], "T3 spans35 follicular 6·16")
    }

    // T4 phaseSpans(21)
    @Test fun testT4PhaseSpans21() {
        val s21 = CyclePredictor.phaseSpans(21)
        assertEquals(21, s21.sumOf { it.length }, "T4 spans21 sum=21")
        assertEquals(PhaseSpan(CyclePhase.FOLLICULAR, 6, 2), s21[1], "T4 spans21 follicular 6·2")
    }

    // T2b 층 2 M 파라미터(개정 M)
    @Test fun testT2b_menstrualLengthParameter() {
        val spans = CyclePredictor.phaseSpans(28, menstrualLength = 7)
        assertEquals(PhaseSpan(CyclePhase.MENSTRUAL, 1, 7), spans[0], "T2b 겨울 7일")
        assertEquals(PhaseSpan(CyclePhase.FOLLICULAR, 8, 7), spans[1], "T2b 봄 축소")
        assertEquals(PhaseSpan(CyclePhase.OVULATION, 15, 3), spans[2], "T2b 여름 불변")
        assertEquals(PhaseSpan(CyclePhase.LUTEAL, 18, 11), spans[3], "T2b 가을 불변")
        assertEquals(28, spans.sumOf { it.length }, "T2b 합 = N")
        assertEquals(CyclePhase.MENSTRUAL, CyclePredictor.phaseForDay(6, 28, menstrualLength = 7))
        assertEquals(CyclePhase.FOLLICULAR, CyclePredictor.phaseForDay(6, 28), "T2b 디폴트 5 불변")
        assertEquals(10, CyclePredictor.phaseSpans(28, menstrualLength = 99)[0].length)
    }

    // T2c 계절 일수 조정 전 그리드 — n 15...40 × m 0...12(338조합) 불변식 5종.
    @Test fun testT2c_phaseSpanGridInvariants() {
        for (n in 15..40) {
            for (mRaw in 0..12) {
                val spans = CyclePredictor.phaseSpans(n, menstrualLength = mRaw)
                assertEquals(n, spans.sumOf { it.length }, "n=$n m=$mRaw 합")
                assertTrue(spans.all { it.length >= 1 }, "n=$n m=$mRaw 0일 구간")
                var cursor = 1
                for (span in spans) {
                    assertEquals(cursor, span.startDay, "n=$n m=$mRaw ${span.phase} 연속성")
                    cursor = span.startDay + span.length
                }
                val mClamped = mRaw.coerceIn(1, 10)
                if ((n - 14) - mClamped >= 1) {
                    assertEquals(mClamped, spans[0].length, "n=$n m=$mRaw 겨울 = m")
                }
                for (d in 1..n) {
                    val hits = spans.filter { d >= it.startDay && d < it.startDay + it.length }
                    assertEquals(1, hits.size, "n=$n m=$mRaw d=$d 배정")
                    assertEquals(hits.first().phase, CyclePredictor.phaseForDay(d, n, menstrualLength = mRaw),
                        "n=$n m=$mRaw d=$d phaseForDay 정합")
                }
            }
        }
    }

    // T5 phaseForDay(28)
    @Test fun testT5PhaseForDay() {
        assertEquals(CyclePhase.MENSTRUAL, CyclePredictor.phaseForDay(1, 28), "T5 day1 menstrual")
        assertEquals(CyclePhase.OVULATION, CyclePredictor.phaseForDay(15, 28), "T5 day15 ovulation")
        assertEquals(CyclePhase.LUTEAL, CyclePredictor.phaseForDay(28, 28), "T5 day28 luteal")
    }

    // T6 resolve 정상: luteal(start18) + 2 = day20
    @Test fun testT6ResolveLutealOffset() {
        val r = CycleRecurrence(CycleAnchor.Phase(CyclePhase.LUTEAL), 2, true, OffsetOverflowRule.CLAMP)
        assertEquals(d(19), CyclePredictor.resolveDate(r, d(0), pred28), "T6 luteal+2 → day20")
    }

    // T7 overflow clamp: ovulation(len3) +5 → 마지막 day17
    @Test fun testT7OverflowClamp() {
        val r = CycleRecurrence(CycleAnchor.Phase(CyclePhase.OVULATION), 5, true, OffsetOverflowRule.CLAMP)
        assertEquals(d(16), CyclePredictor.resolveDate(r, d(0), pred28), "T7 clamp → day17")
    }

    // T8 overflow skip → null
    @Test fun testT8OverflowSkip() {
        val r = CycleRecurrence(CycleAnchor.Phase(CyclePhase.OVULATION), 5, true, OffsetOverflowRule.SKIP)
        assertNull(CyclePredictor.resolveDate(r, d(0), pred28), "T8 skip → nil")
    }

    // T9 overflow carry: 15+5 = day20
    @Test fun testT9OverflowCarry() {
        val r = CycleRecurrence(CycleAnchor.Phase(CyclePhase.OVULATION), 5, true, OffsetOverflowRule.CARRY)
        assertEquals(d(19), CyclePredictor.resolveDate(r, d(0), pred28), "T9 carry → day20")
    }

    // T10 cycleStart +0 → cycleStart
    @Test fun testT10CycleStartZero() {
        val r = CycleRecurrence(CycleAnchor.CycleStart, 0, true, OffsetOverflowRule.CLAMP)
        assertEquals(d(0), CyclePredictor.resolveDate(r, d(0), pred28), "T10 cycleStart+0 → day1")
    }

    // T11 carry 주기초과 → day28 클램프
    @Test fun testT11CarryPastCycle() {
        val r = CycleRecurrence(CycleAnchor.CycleStart, 40, true, OffsetOverflowRule.CARRY)
        assertEquals(d(27), CyclePredictor.resolveDate(r, d(0), pred28), "T11 carry past N → day28")
    }

    // T12 cycleDay 과거 실주기
    @Test fun testT12PastRealCycle() {
        assertEquals(DayResolution(31, false), CyclePredictor.cycleDay(d(30), listOf(d(0), d(33)), 28),
            "T12 past real cycle → day31 projected=false")
    }

    // T13 cycleDay 미래 투영
    @Test fun testT13FutureProjection() {
        assertEquals(DayResolution(4, true), CyclePredictor.cycleDay(d(31), listOf(d(0)), 28),
            "T13 future projection → day4 projected=true")
    }

    // T14 isOverdue
    @Test fun testT14Overdue() {
        assertTrue(CyclePredictor.isOverdue(d(30), listOf(d(0)), 28), "T14 overdue true")
        assertFalse(CyclePredictor.isOverdue(d(20), listOf(d(0)), 28), "T14 not overdue")
    }

    // T15 S0 콜드스타트 → null
    @Test fun testT15ColdStart() {
        assertNull(CyclePredictor.phase(d(5), emptyList(), 28), "T15 cold start → nil")
    }

    // T16 confidence
    @Test fun testT16Confidence() {
        assertEquals(CyclePrediction.Confidence.HIGH, CyclePredictor.confidence(listOf(d(0), d(28), d(56), d(84))), "T16 conf high")
        assertEquals(CyclePrediction.Confidence.LOW, CyclePredictor.confidence(listOf(d(0), d(25), d(61))), "T16 conf low")
        assertEquals(CyclePrediction.Confidence.MEDIUM, CyclePredictor.confidence(listOf(d(0), d(28))), "T16 conf medium")
    }
}
