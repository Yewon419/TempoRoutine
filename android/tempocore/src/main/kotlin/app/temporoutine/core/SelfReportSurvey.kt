// 템포루틴 — 앱 내 자기보고 설문 (핸드오프 v1.6 §4 / MASTER §3.11)
// iOS TempoCore/SelfReportSurvey.swift 1:1 이식. 문항 순서 규칙(P1→P2, 증상 8문항만 랜덤화, 앵커 = P2 응답)은 웹과 동일.

package app.temporoutine.core

data class SurveyChoice(val value: String, val label: String)

data class SurveyQuestion(
    val id: String,
    val text: String,
    val choices: List<SurveyChoice>,
    val isOptional: Boolean = false,
)

object SelfReportSurvey {

    val phaseChoices = listOf(
        SurveyChoice("menstrual", "생리 중"),
        SurveyChoice("after", "생리 끝난 직후"),
        SurveyChoice("mid", "생리와 다음 생리 중간쯤"),
        SurveyChoice("before", "다음 생리 오기 일주일쯤 전"),
        SurveyChoice("none", "딱히 없어요"),
        SurveyChoice("unknown", "잘 모르겠어요"),
    )

    /** 2026-09-04 베타("중간에 조금 그래요 추가") — 이진 척도에 중간값을 넣는다.
     *  순서는 강도 내림차순. 옛 응답(worse·same)은 값이 그대로라 그대로 읽힌다. */
    private val symptomChoices = listOf(
        SurveyChoice("worse", "심해져요"),
        SurveyChoice("somewhat", "조금 그래요"),
        SurveyChoice("same", "비슷해요"),
    )

    private val frequencyChoices = listOf(
        SurveyChoice("none", "없어요"),
        SurveyChoice("sometimes", "가끔"),
        SurveyChoice("often", "자주"),
        SurveyChoice("monthly", "거의 매달"),
    )

    private val yesNoChoices = listOf(
        SurveyChoice("yes", "예"),
        SurveyChoice("no", "아니오"),
        SurveyChoice("decline", "답하지 않을래요"),
    )

    /** 캘리브레이션 — 문항이 아니라 시간 앵커 고정용. 뒤로 뺄 수 없다. */
    val calibration = SurveyQuestion(
        id = "C1", text = "가장 최근 생리는 언제였나요",
        choices = listOf(
            SurveyChoice("within1m", "한 달 이내"),
            SurveyChoice("1to3m", "1–3개월 전"),
            SurveyChoice("3to6m", "3–6개월 전"),
            SurveyChoice("over6m", "6개월 이상"),
            SurveyChoice("unknown", "잘 모르겠어요"),
        ),
    )

    /** 순서 고정 — P1이 먼저다. */
    val phaseQuestions = listOf(
        SurveyQuestion("P1", "한 주기 중에 컨디션이 가장 좋은 때는 언제인가요", phaseChoices),
        SurveyQuestion("P2", "반대로, 가장 안 좋은 때는 언제인가요", phaseChoices),
    )

    /** 제시 순서만 랜덤화한다. Q7은 프로브(합성점수 제외), Q8은 역문항. */
    val symptomQuestions = listOf(
        SurveyQuestion("Q1", "감정이 오르내려요", symptomChoices),
        SurveyQuestion("Q2", "사소한 일에 날카로워져요", symptomChoices),
        SurveyQuestion("Q3", "불안하거나 초조해요", symptomChoices),
        SurveyQuestion("Q4", "아랫배나 허리가 불편해요", symptomChoices),
        SurveyQuestion("Q5", "몸이 붓거나 무거워요", symptomChoices),
        SurveyQuestion("Q6", "가슴이 아프거나 불편해요", symptomChoices),
        SurveyQuestion("Q7", "쉽게 피곤해져요", symptomChoices),
        SurveyQuestion("Q8", "오히려 기운이 넘쳐요", symptomChoices),
    )

    /** 이 셋만 다점 척도 — 진폭과 기능 지장의 상관을 재는 유일한 쌍. */
    val amplitudeQuestions = listOf(
        SurveyQuestion(
            "Q9", "한 주기 안에서 가장 좋은 때와 가장 안 좋은 때, 얼마나 다른가요",
            listOf(
                SurveyChoice("same", "거의 비슷해요"),
                SurveyChoice("slight", "조금 달라요"),
                SurveyChoice("much", "꽤 달라요"),
                SurveyChoice("total", "완전히 다른 사람 같아요"),
                SurveyChoice("varies", "매번 달라요"),
            ),
        ),
        SurveyQuestion("Q10", "그것 때문에 할 일을 못 하거나 미룬 적 있나요", frequencyChoices),
        SurveyQuestion("Q11", "그것 때문에 사람들과 지내기 불편했던 적 있나요", frequencyChoices),
    )

    val optionalQuestions = listOf(
        SurveyQuestion("O1", "호르몬 피임약이나 시술을 쓰고 있나요", yesNoChoices, isOptional = true),
        SurveyQuestion("O2", "PMS·PMDD, 다낭성난소증후군, 자궁내막증 중 진단받은 게 있나요", yesNoChoices, isOptional = true),
        SurveyQuestion(
            "O3", "이 답들이 매달 비슷한가요",
            listOf(
                SurveyChoice("similar", "네, 비슷해요"),
                SurveyChoice("varies", "달마다 달라요"),
                SurveyChoice("unknown", "잘 모르겠어요"),
            ),
            isOptional = true,
        ),
    )

    /** 저장을 허용하는 키 — 임의 키가 섞이지 않게 한다. */
    val allQuestionIDs: Set<String>
        get() = buildSet {
            add(calibration.id)
            for (q in phaseQuestions + symptomQuestions + amplitudeQuestions + optionalQuestions) add(q.id)
        }

    val requiredQuestionIDs: Set<String>
        get() = buildSet {
            add(calibration.id)
            for (q in phaseQuestions + symptomQuestions + amplitudeQuestions) add(q.id)
        }

    /** P2 응답을 증상 문항의 시간 앵커 문구로 바꾼다. "딱히 없어요"·"모르겠어요"는 폴백. */
    fun symptomAnchorLine(p2: String?): String {
        if (p2 == null || p2 == "none" || p2 == "unknown") return FALLBACK_ANCHOR
        val choice = phaseChoices.firstOrNull { it.value == p2 } ?: return FALLBACK_ANCHOR
        return "「${choice.label}」, 평소와 비교해서 답해주세요."
    }

    private const val FALLBACK_ANCHOR = "그나마 힘들었던 때를 떠올려서, 평소와 비교해서 답해주세요."
}

/** 자기보고 결과 — ⚠ 앱 리듬 엔진(WindowStatsEngine)의 유형과 다른 양이다. 같은 필드에 담지 말 것. */
data class SelfReportResult(
    val type: RhythmType,
    val modalityRaw: Int,   // (Q1+Q2+Q3) − (Q4+Q5+Q6), 범위 [-6, +6]
)

object SelfReportScoring {
    /** 문항당 강도 점수 — 심해져요 2 · 조금 그래요 1 · 비슷해요(무응답) 0.
     *  중간 선택지를 0으로 접으면 그 답이 계열 점수에서 통째로 사라진다(2026-09-04). */
    private fun weight(value: String?): Int = when (value) {
        "worse" -> 2
        "somewhat" -> 1
        else -> 0
    }

    private val vivaceAnswers = setOf("much", "total")
    private val andanteAnswers = setOf("same", "slight")

    fun score(answers: Map<String, String>): SelfReportResult {
        val emotional = weight(answers["Q1"]) + weight(answers["Q2"]) + weight(answers["Q3"])
        val bodily = weight(answers["Q4"]) + weight(answers["Q5"]) + weight(answers["Q6"])
        return SelfReportResult(resolveType(answers), emotional - bodily)
    }

    /** 루바토를 먼저 거른다 — 최근 생리를 모르거나 "매번 다름"이면 진폭을 판정하지 않는다. */
    private fun resolveType(answers: Map<String, String>): RhythmType {
        if (answers["C1"] == "unknown" || answers["Q9"] == "varies") return RhythmType.RUBATO
        val q9 = answers["Q9"]
        if (q9 != null) {
            if (q9 in vivaceAnswers) return RhythmType.VIVACE
            if (q9 in andanteAnswers) return RhythmType.ANDANTE
        }
        return RhythmType.RUBATO
    }

    /** 무성의 응답 판별 — Q1~Q7 전부 "심해져요"인데 역문항 Q8도 "심해져요"면 모순이다. */
    fun isStraightLining(answers: Map<String, String>): Boolean {
        val probes = listOf("Q1", "Q2", "Q3", "Q4", "Q5", "Q6", "Q7")
        return probes.all { answers[it] == "worse" } && answers["Q8"] == "worse"
    }
}
