// 템포루틴 — occurrence 열거 테스트 (MASTER §5.6.4·§5.5.3, T30~)
// iOS TempoCoreTests/CycleOccurrencesTests.swift 1:1 이식.

package app.temporoutine.core

import org.junit.jupiter.api.Test
import java.time.LocalDate
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CycleOccurrencesTests {

    private fun day(offset: Int): LocalDate = LocalDate.now().plusDays(offset.toLong())

    // T30: 기록 0개 → 창·occurrence 없음
    @Test fun testT30_emptyStarts() {
        assertEquals(emptyList(), CycleOccurrences.cycleWindows(emptyList(), 28, 2))
        val r = CycleRecurrence(CycleAnchor.CycleStart, 0, true, OffsetOverflowRule.CLAMP)
        assertEquals(emptyList(), CycleOccurrences.occurrences(r, day(0), emptyList(), 28, 2))
    }

    // T31: 창 열거 — 과거=실측(27·29), 현재=N, 미래 k≤지평(projected)
    @Test fun testT31_windowEnumeration() {
        val starts = listOf(day(0), day(27), day(56))
        val windows = CycleOccurrences.cycleWindows(starts, 28, 2)
        assertEquals(5, windows.size)
        assertEquals(CycleWindow(day(0), 27, false), windows[0])
        assertEquals(CycleWindow(day(27), 29, false), windows[1])
        assertEquals(CycleWindow(day(56), 28, false), windows[2])
        assertEquals(CycleWindow(day(84), 28, true), windows[3])
        assertEquals(CycleWindow(day(112), 28, true), windows[4])
    }

    // T32: 매 주기 반복
    @Test fun testT32_repeatingOccurrences() {
        val starts = listOf(day(0), day(27))
        val r = CycleRecurrence(CycleAnchor.CycleStart, 2, true, OffsetOverflowRule.CLAMP)
        val occ = CycleOccurrences.occurrences(r, day(0), starts, 28, 1)
        assertEquals(listOf(day(2), day(29), day(57)), occ.map { it.date })
        assertEquals(listOf(false, false, true), occ.map { it.projected })
    }

    // T33: overflow skip — 배란기(3일) 밖 offset은 그 주기 미발생
    @Test fun testT33_skipDropsOccurrence() {
        val r = CycleRecurrence(CycleAnchor.Phase(CyclePhase.OVULATION), 5, true, OffsetOverflowRule.SKIP)
        val occ = CycleOccurrences.occurrences(r, day(0), listOf(day(0)), 28, 1)
        assertEquals(emptyList(), occ)
    }

    // T34: one-shot 바인딩 — resolve일이 이미 지났으면 다음 주기로 1회 이월
    @Test fun testT34_oneShotRollsToNextCycle() {
        val r = CycleRecurrence(CycleAnchor.CycleStart, 2, false, OffsetOverflowRule.CLAMP)
        val occ = CycleOccurrences.occurrences(r, day(10), listOf(day(0)), 28, 2)
        assertEquals(1, occ.size)
        assertEquals(day(30), occ[0].date)
        assertTrue(occ[0].projected)
    }

    // T34b: one-shot — resolve일이 createdAt 이후면 바인딩 주기 그대로
    @Test fun testT34b_oneShotStaysInBindingCycle() {
        val r = CycleRecurrence(CycleAnchor.CycleStart, 20, false, OffsetOverflowRule.CLAMP)
        val occ = CycleOccurrences.occurrences(r, day(10), listOf(day(0)), 28, 2)
        assertEquals(1, occ.size)
        assertEquals(day(20), occ[0].date)
        assertFalse(occ[0].projected)
    }

    // T35: one-shot의 skip은 clamp로 해석
    @Test fun testT35_oneShotSkipReadAsClamp() {
        val r = CycleRecurrence(CycleAnchor.Phase(CyclePhase.OVULATION), 10, false, OffsetOverflowRule.SKIP)
        val occ = CycleOccurrences.occurrences(r, day(0), listOf(day(0)), 28, 1)
        assertEquals(1, occ.size)
        assertEquals(day(16), occ[0].date)   // n=28: 배란기 15~17일차 → clamp = 17일차
    }

    // T36: InputSchedule 커스텀 직렬화 왕복 (§5.5.1 discriminator)
    @Test fun testT36_inputScheduleCodableRoundTrip() {
        val r = CycleRecurrence(CycleAnchor.Phase(CyclePhase.LUTEAL), 3, true, OffsetOverflowRule.CARRY)
        for (original in listOf(InputSchedule.Daily, InputSchedule.Weekly, InputSchedule.Monthly, InputSchedule.CycleAnchored(r))) {
            val text = ExportCodec.json.encodeToString(InputSchedule.serializer(), original)
            val decoded = ExportCodec.json.decodeFromString(InputSchedule.serializer(), text)
            assertEquals(original, decoded)
        }
    }
}
