// 리듬 설문 순수 규칙 — canAdvance·단문항 장·복수 응답 토글·저장 화이트리스트를 고정.
// 2026-09-14 온보딩에서 설문 장이 빠지며 SurveyLogic과 함께 이리로 옮겼다.

package app.temporoutine.android.selfreport

import app.temporoutine.core.SelfReportSurvey
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SurveyLogicTests {

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

    /** P1·P2 복수 응답 토글(2026-09-09) — 선택지 순서 저장 · 배타 값 · 전부 해제 = 무응답. */
    @Test fun multiValueToggle() {
        val p1 = SelfReportSurvey.phaseQuestions.first()
        fun pick(value: String) = p1.choices.first { it.value == value }

        // 누른 순서와 무관하게 선택지 순서로 이어진다
        val a = SurveyLogic.toggledMultiValue(p1, pick("before"), null)
        assertEquals("before", a)
        assertEquals("menstrual,before", SurveyLogic.toggledMultiValue(p1, pick("menstrual"), a))
        // 재탭 해제, 마지막 하나까지 빼면 null
        assertEquals("menstrual", SurveyLogic.toggledMultiValue(p1, pick("before"), "menstrual,before"))
        assertEquals(null, SurveyLogic.toggledMultiValue(p1, pick("menstrual"), "menstrual"))
        // 배타 값을 고르면 나머지가 빠지고, 다른 값을 고르면 배타 값이 빠진다
        assertEquals("unknown", SurveyLogic.toggledMultiValue(p1, pick("unknown"), "menstrual,before"))
        assertEquals("mid", SurveyLogic.toggledMultiValue(p1, pick("mid"), "none"))
        // 복수 응답도 canAdvance에선 채워진 답이다
        assertTrue(SurveyLogic.canAdvance(2, mapOf("P1" to "menstrual,before", "P2" to "none")))
    }

    @Test fun whitelistDropsUnknownKeys() {
        val cleaned = SurveyLogic.whitelist(mapOf("C1" to "within1m", "P1" to "mid", "bogus" to "x"))
        assertEquals(mapOf("C1" to "within1m", "P1" to "mid"), cleaned)
        assertTrue(SelfReportSurvey.allQuestionIDs.containsAll(cleaned.keys))
    }
}
