// 앱 내 자기보고 설문 테스트 — 문항 계약과 채점이 웹 쪽과 어긋나지 않게 막는다.
// iOS TempoCoreTests/SelfReportSurveyTests.swift 1:1 이식.

package app.temporoutine.core

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SelfReportSurveyTests {

    @Test fun testQuestionCount() {
        assertEquals(14, SelfReportSurvey.requiredQuestionIDs.size)
        assertEquals(3, SelfReportSurvey.optionalQuestions.size)
        assertEquals(17, SelfReportSurvey.allQuestionIDs.size)
    }

    @Test fun testPhaseOrderIsFixed() {
        assertEquals(listOf("P1", "P2"), SelfReportSurvey.phaseQuestions.map { it.id })
    }

    @Test fun testReverseItemExists() {
        assertTrue(SelfReportSurvey.symptomQuestions.any { it.id == "Q8" })
    }

    @Test fun testAnchorUsesP2Answer() {
        val line = SelfReportSurvey.symptomAnchorLine("before")
        assertTrue(line.contains("다음 생리 오기 일주일쯤 전"))
    }

    @Test fun testAnchorFallback() {
        for (value in listOf("none", "unknown", null)) {
            val line = SelfReportSurvey.symptomAnchorLine(value)
            assertTrue(line.contains("그나마 힘들었던 때"))
        }
    }

    /** P1·P2는 복수 응답(2026-09-09) — 저장은 쉼표로 이은 한 문자열이다. */
    @Test fun testPhaseQuestionsAllowMultiple() {
        assertTrue(SelfReportSurvey.phaseQuestions.all { it.allowsMultiple })
        assertFalse(SelfReportSurvey.symptomQuestions.any { it.allowsMultiple })
        assertEquals(listOf("menstrual", "before"), SelfReportSurvey.values("menstrual,before"))
        assertEquals(emptyList<String>(), SelfReportSurvey.values(null))
        assertEquals(emptyList<String>(), SelfReportSurvey.values(""))
    }

    /** 복수로 고른 위상은 앵커에 전부 나열한다 — 하나만 골라 쓰면 나머지가 화면에서 사라진다. */
    @Test fun testAnchorListsEveryPickedPhase() {
        val line = SelfReportSurvey.symptomAnchorLine("menstrual,before")
        assertTrue(line.contains("생리 중"))
        assertTrue(line.contains("다음 생리 오기 일주일쯤 전"))
        // 배타 값이 섞여 들어와도 문구에는 실제 위상만 남는다
        val mixed = SelfReportSurvey.symptomAnchorLine("menstrual,unknown")
        assertTrue(mixed.contains("생리 중"))
        assertFalse(mixed.contains("잘 모르겠어요"))
    }

    /** Q9는 3지(2026-09-09) — 선택지가 곧 유형이다. 늘리면 판정 경계가 다시 흐려진다. */
    @Test fun testAmplitudeChoicesMapOneToOne() {
        val q9 = SelfReportSurvey.amplitudeQuestions.firstOrNull { it.id == "Q9" }
        assertEquals(listOf("same", "much", "varies"), q9?.choices?.map { it.value })
    }

    @Test fun testModalityRawRange() {
        val emotionalHeavy = mapOf("Q1" to "worse", "Q2" to "worse", "Q3" to "worse",
            "Q4" to "same", "Q5" to "same", "Q6" to "same", "Q9" to "much")
        assertEquals(6, SelfReportScoring.score(emotionalHeavy).modalityRaw)

        val bodilyHeavy = mapOf("Q1" to "same", "Q2" to "same", "Q3" to "same",
            "Q4" to "worse", "Q5" to "worse", "Q6" to "worse", "Q9" to "much")
        assertEquals(-6, SelfReportScoring.score(bodilyHeavy).modalityRaw)
    }

    /** 중간 선택지(2026-09-04) — 「그때그때 달라요」(somewhat)는 문항당 1점. 0으로 접히면 답이 사라진다.
     *  2026-09-09 라벨이 바뀌어도 채점은 1점 유지(대표님 결정). */
    @Test fun testSomewhatCountsAsHalf() {
        val mid = mapOf("Q1" to "somewhat", "Q2" to "somewhat", "Q3" to "somewhat",
            "Q4" to "same", "Q5" to "same", "Q6" to "same", "Q9" to "much")
        assertEquals(3, SelfReportScoring.score(mid).modalityRaw)
        val mixed = mapOf("Q1" to "worse", "Q2" to "somewhat", "Q3" to "same",
            "Q4" to "somewhat", "Q5" to "same", "Q6" to "same", "Q9" to "much")
        assertEquals(2, SelfReportScoring.score(mixed).modalityRaw)
        // 증상 문항 선택지는 3개(강도 내림차순) — 옛 응답(worse·same)은 값이 그대로라 계속 읽힌다
        for (q in SelfReportSurvey.symptomQuestions) {
            assertEquals(listOf("worse", "somewhat", "same"), q.choices.map { it.value })
        }
    }

    @Test fun testRubatoTakesPrecedence() {
        assertEquals(RhythmType.RUBATO, SelfReportScoring.score(mapOf("C1" to "unknown", "Q9" to "total")).type)
        assertEquals(RhythmType.RUBATO, SelfReportScoring.score(mapOf("C1" to "within1m", "Q9" to "varies")).type)
    }

    /** `total`·`slight`는 화면에서 내린 옛 값이다(2026-09-09 Q9 축소) — 그 전에 답한 기록이
     *  유형 없이 떨어지지 않게 채점 집합에는 남아 있어야 한다. */
    @Test fun testAmplitudeSplit() {
        assertEquals(RhythmType.VIVACE, SelfReportScoring.score(mapOf("C1" to "within1m", "Q9" to "much")).type)
        assertEquals(RhythmType.VIVACE, SelfReportScoring.score(mapOf("C1" to "within1m", "Q9" to "total")).type)
        assertEquals(RhythmType.ANDANTE, SelfReportScoring.score(mapOf("C1" to "within1m", "Q9" to "same")).type)
        assertEquals(RhythmType.ANDANTE, SelfReportScoring.score(mapOf("C1" to "within1m", "Q9" to "slight")).type)
    }

    /** Q1~Q7 전부 "예"(worse) + 역문항 Q8도 "예" = 모순 → 무성의로 본다. */
    @Test fun testStraightLiningDetection() {
        val all = mutableMapOf<String, String>()
        for (id in listOf("Q1", "Q2", "Q3", "Q4", "Q5", "Q6", "Q7", "Q8")) all[id] = "worse"
        assertTrue(SelfReportScoring.isStraightLining(all))

        all["Q8"] = "same"
        assertFalse(SelfReportScoring.isStraightLining(all))
    }

    @Test fun testChoiceValuesAreUniquePerQuestion() {
        val all = listOf(SelfReportSurvey.calibration) +
            SelfReportSurvey.phaseQuestions +
            SelfReportSurvey.symptomQuestions +
            SelfReportSurvey.amplitudeQuestions +
            SelfReportSurvey.optionalQuestions
        for (question in all) {
            val values = question.choices.map { it.value }.toSet()
            assertEquals(question.choices.size, values.size, "중복 value: ${question.id}")
            assertFalse(question.choices.isEmpty(), "선택지 없음: ${question.id}")
        }
    }
}
