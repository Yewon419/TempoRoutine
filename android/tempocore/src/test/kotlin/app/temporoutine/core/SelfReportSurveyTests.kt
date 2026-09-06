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
        assertEquals(6, SelfReportScoring.score(emotionalHeavy).modalityRaw)

        val bodilyHeavy = mapOf("Q1" to "same", "Q2" to "same", "Q3" to "same",
            "Q4" to "worse", "Q5" to "worse", "Q6" to "worse", "Q9" to "much")
        assertEquals(-6, SelfReportScoring.score(bodilyHeavy).modalityRaw)
    }

    /** 중간 선택지(2026-09-04) — 「조금 그래요」는 문항당 1점. 0으로 접히면 답이 사라진다. */
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
