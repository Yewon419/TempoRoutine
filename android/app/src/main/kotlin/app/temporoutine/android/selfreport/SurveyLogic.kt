// 템포루틴 Android — 리듬 설문 순수 규칙 (iOS SelfReportFlow.canAdvance·finish 필터). 단위 테스트 대상.
// 2026-09-14 온보딩에서 설문 장이 빠지며(iOS 84차) 온보딩 VM에서 이리로 옮겼다 — 설정·설문 시트가 쓴다.

package app.temporoutine.android.selfreport

import app.temporoutine.core.SelfReportSurvey
import app.temporoutine.core.SurveyChoice
import app.temporoutine.core.SurveyQuestion

object SurveyLogic {
    const val TOTAL_STEPS = 5

    /** 선택 문항 단계 말고는 그 화면의 문항이 전부 채워져야 넘어간다. */
    fun canAdvance(step: Int, answers: Map<String, String>): Boolean = when (step) {
        0 -> true
        1 -> answers[SelfReportSurvey.calibration.id] != null
        2 -> SelfReportSurvey.phaseQuestions.all { answers[it.id] != null }
        3 -> SelfReportSurvey.symptomQuestions.all { answers[it.id] != null }
        4 -> SelfReportSurvey.amplitudeQuestions.all { answers[it.id] != null }
        else -> true
    }

    /** 문항이 하나뿐인 장 — 선택이 곧 그 장의 답. 1장 = 캘리브레이션 단문항. */
    fun isSingleQuestionStep(step: Int): Boolean = step == 1

    /** 복수 문항 토글(iOS SelfReportFlow.toggledMultiValue, 2026-09-09) — 선택 순서가 아니라 **선택지 순서**로
     *  이어 저장한다(같은 답이면 같은 문자열). 「딱히 없어요」·「잘 모르겠어요」는 배타 — 고르면 나머지가 빠지고,
     *  반대로 다른 것을 고르면 빠진다. 전부 해제되면 null(= 무응답). */
    fun toggledMultiValue(question: SurveyQuestion, choice: SurveyChoice, current: String?): String? {
        val picked = SelfReportSurvey.values(current).toMutableSet()
        when {
            choice.value in picked -> picked.remove(choice.value)
            choice.value in SelfReportSurvey.exclusivePhaseValues -> { picked.clear(); picked.add(choice.value) }
            else -> { picked.removeAll(SelfReportSurvey.exclusivePhaseValues); picked.add(choice.value) }
        }
        val ordered = question.choices.map { it.value }.filter { it in picked }
        return ordered.takeIf { it.isNotEmpty() }?.joinToString(",")
    }

    fun whitelist(answers: Map<String, String>): Map<String, String> {
        val allowed = SelfReportSurvey.allQuestionIDs
        return answers.filterKeys { it in allowed }
    }
}
