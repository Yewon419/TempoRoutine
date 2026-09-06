// 온보딩 순수 규칙 — 캘린더 채움 캡·에피소드 분기·달 이동 상한·설문 canAdvance·저장 화이트리스트를 고정.

package app.temporoutine.android.onboarding

import app.temporoutine.core.SelfReportSurvey
import org.junit.jupiter.api.Test
import java.time.LocalDate
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class OnboardingLogicTests {

    private val today = LocalDate.of(2026, 9, 5)

    @Test fun fillDaysCapsAtToday() {
        assertEquals((20..24).map { LocalDate.of(2026, 8, it) }, BaselineLogic.fillDays(LocalDate.of(2026, 8, 20), 5, today))
        // 시작 9/3 + 5일 = 9/3..9/7 → 오늘(9/5) 이후 잘림
        assertEquals((3..5).map { LocalDate.of(2026, 9, it) }, BaselineLogic.fillDays(LocalDate.of(2026, 9, 3), 5, today))
        assertEquals(listOf(today), BaselineLogic.fillDays(today, 1, today))
    }

    @Test fun cycleQuestionOnlyForSingleEpisode() {
        assertFalse(BaselineLogic.asksCycleLength(0))
        assertTrue(BaselineLogic.asksCycleLength(1))
        assertFalse(BaselineLogic.asksCycleLength(2), "실측 gap 있음 → 안 묻는다")
    }

    @Test fun calendarForwardBound() {
        assertTrue(BaselineLogic.canGoForward(LocalDate.of(2026, 8, 1), today), "8월 → 9월 가능")
        assertFalse(BaselineLogic.canGoForward(LocalDate.of(2026, 9, 1), today), "9월 → 10월은 미래")
        assertTrue(BaselineLogic.canGoForward(LocalDate.of(2026, 8, 1), LocalDate.of(2026, 9, 1)), "다음 달 1일 = 오늘이면 가능")
    }

    @Test fun surveyAdvanceRules() {
        assertTrue(SurveyLogic.canAdvance(0, emptyMap()))
        assertFalse(SurveyLogic.canAdvance(1, emptyMap()))
        assertTrue(SurveyLogic.canAdvance(1, mapOf("C1" to "within1m")))
        val phase = SelfReportSurvey.phaseQuestions.associate { it.id to "menstrual" }
        assertFalse(SurveyLogic.canAdvance(2, phase - "P2"))
        assertTrue(SurveyLogic.canAdvance(2, phase))
        val symptoms = SelfReportSurvey.symptomQuestions.associate { it.id to "same" }
        assertTrue(SurveyLogic.canAdvance(3, symptoms))
        assertFalse(SurveyLogic.canAdvance(3, symptoms - symptoms.keys.first()))
        val amplitude = SelfReportSurvey.amplitudeQuestions.associate { it.id to it.choices.first().value }
        assertTrue(SurveyLogic.canAdvance(4, amplitude))
        assertTrue(SurveyLogic.canAdvance(5, emptyMap()), "선택 문항 단계는 빈 채로 제출 가능")
        assertTrue(SurveyLogic.isSingleQuestionStep(1)); assertFalse(SurveyLogic.isSingleQuestionStep(2))
    }

    @Test fun whitelistDropsUnknownKeys() {
        val cleaned = SurveyLogic.whitelist(mapOf("C1" to "within1m", "P1" to "mid", "bogus" to "x"))
        assertEquals(mapOf("C1" to "within1m", "P1" to "mid"), cleaned)
        assertTrue(SelfReportSurvey.allQuestionIDs.containsAll(cleaned.keys))
    }
}
