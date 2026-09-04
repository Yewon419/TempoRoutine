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

    @Test fun testModalityRawRange() {
        val emotionalHeavy = mapOf("Q1" to "worse", "Q2" to "worse", "Q3" to "worse",
            "Q4" to "same", "Q5" to "same", "Q6" to "same", "Q9" to "much")
        assertEquals(3, SelfReportScoring.score(emotionalHeavy).modalityRaw)

        val bodilyHeavy = mapOf("Q1" to "same", "Q2" to "same", "Q3" to "same",
            "Q4" to "worse", "Q5" to "worse", "Q6" to "worse", "Q9" to "much")
        assertEquals(-3, SelfReportScoring.score(bodilyHeavy).modalityRaw)
    }

    @Test fun testRubatoTakesPrecedence() {
        assertEquals(RhythmType.RUBATO, SelfReportScoring.score(mapOf("C1" to "unknown", "Q9" to "total")).type)
        assertEquals(RhythmType.RUBATO, SelfReportScoring.score(mapOf("C1" to "within1m", "Q9" to "varies")).type)
    }

    @Test fun testAmplitudeSplit() {
        assertEquals(RhythmType.VIVACE, SelfReportScoring.score(mapOf("C1" to "within1m", "Q9" to "much")).type)
        assertEquals(RhythmType.VIVACE, SelfReportScoring.score(mapOf("C1" to "within1m", "Q9" to "total")).type)
        assertEquals(RhythmType.ANDANTE, SelfReportScoring.score(mapOf("C1" to "within1m", "Q9" to "same")).type)
        assertEquals(RhythmType.ANDANTE, SelfReportScoring.score(mapOf("C1" to "within1m", "Q9" to "slight")).type)
    }

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
