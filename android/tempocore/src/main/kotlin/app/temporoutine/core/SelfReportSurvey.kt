// 템포루틴 — 앱 내 자기보고 설문 (핸드오프 v1.6 §4 / MASTER §3.11)
// iOS TempoCore/SelfReportSurvey.swift 1:1 이식. 문항 순서 규칙(P1→P2, 증상 8문항만 랜덤화, 앵커 = P2 응답)은 웹과 동일.

package app.temporoutine.core

data class SurveyChoice(val value: String, val label: String)

data class SurveyQuestion(
    val id: String,
    val text: String,
    val choices: List<SurveyChoice>,
    val isOptional: Boolean = false,
    /** 복수 응답 문항인가(2026-09-09 베타 "이거 복수답 가능하게 해줘" — P1·P2).
     *  저장은 선택한 value를 쉼표로 이은 한 문자열이다 — 응답 맵이 Map<String, String>이라
     *  배열을 담을 자리가 없고, 분석은 쉼표로 다시 가르면 된다(`SelfReportSurvey.values`). */
    val allowsMultiple: Boolean = false,
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
     *  순서는 강도 내림차순. 옛 응답(worse·same)은 값이 그대로라 그대로 읽힌다.
     *  2026-09-09 라벨 = 예/보통이에요/아니요(사용자 지시) — 종전 「심해져요/조금 그래요/비슷해요」는
     *  동의 축과 비교 축이 섞여 "기운이 넘쳐요 → 심해져요" 같은 조합이 나왔다. 값·채점은 무변경.
     *  2026-09-09 2차(베타 "예 아니요 늘 달라요 이렇게 고치자" → "늘 달라요 말고 그때그때 달라요 로"):
     *  중간 라벨만 「그때그때 달라요」로. ⚠ 라벨 축이 강도에서 변동성으로 바뀌지만 채점은 1점 유지
     *  (대표님 결정) — 0으로 접으면 그 답이 계열 점수에서 통째로 사라진다(2026-09-04와 같은 이유). */
    private val symptomChoices = listOf(
        SurveyChoice("worse", "예"),
        SurveyChoice("somewhat", "그때그때 달라요"),
        SurveyChoice("same", "아니요"),
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

    /** 순서 고정 — P1이 먼저다.
     *  2026-09-09 복수 응답 허용(베타) — 좋은 때·안 좋은 때가 한 곳으로 안 모이는 사람이 있다.
     *  ⚠ 웹 사전 설문은 단일 선택이라 이 문항만 형식이 갈린다. 대조할 때 앱 응답은 다치(多値)로
     *  들어온다고 보고 가를 것(`values`). 채점(SelfReportScoring)은 P1·P2를 쓰지 않아 무영향. */
    val phaseQuestions = listOf(
        SurveyQuestion("P1", "한 주기 중에 컨디션이 가장 좋은 때는 언제인가요", phaseChoices, allowsMultiple = true),
        SurveyQuestion("P2", "반대로, 가장 안 좋은 때는 언제인가요", phaseChoices, allowsMultiple = true),
    )

    /** 복수 응답 저장값을 개별 value로 가른다. 단일 응답이면 원소 하나짜리 리스트. */
    fun values(raw: String?): List<String> {
        if (raw.isNullOrEmpty()) return emptyList()
        return raw.split(",").filter { it.isNotEmpty() }
    }

    /** 다른 선택지와 같이 고를 수 없는 값 — 「딱히 없어요」·「잘 모르겠어요」.
     *  위상을 하나도 안 짚은 답과 여러 개를 짚은 답이 한 응답에 섞이면 해석이 불가능해진다. */
    val exclusivePhaseValues: Set<String> = setOf("none", "unknown")

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

    /** 이 셋만 다점 척도 — 진폭과 기능 지장의 상관을 재는 유일한 쌍.
     *  2026-09-09 Q9 5지 → 3지(베타 "이거 선택지 너무 많음", 대표님 「유형과 1:1」 선택):
     *  선택지가 곧 유형이다(비슷해요 = 안단테 · 많이 달라요 = 비바체 · 매번 달라요 = 루바토).
     *  ⚠ 대가 = 진폭 해상도가 4단에서 2단으로 내려가 Q10·Q11과의 상관 측정이 거의 무의미해진다.
     *  옛 응답값(slight·total)은 채점 집합에 그대로 남겨 과거 기록이 같은 유형으로 읽히게 한다. */
    val amplitudeQuestions = listOf(
        SurveyQuestion(
            "Q9", "한 주기 안에서 가장 좋은 때와 가장 안 좋은 때, 얼마나 다른가요",
            listOf(
                SurveyChoice("same", "비슷해요"),
                SurveyChoice("much", "많이 달라요"),
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

    /** P2 응답을 증상 문항의 시간 앵커 문구로 바꾼다. "딱히 없어요"·"모르겠어요"는 폴백.
     *  복수 응답(2026-09-09)이면 고른 것을 전부 나열한다 — 하나만 골라 앵커로 삼으면 나머지를
     *  고른 이유가 화면에서 사라진다. */
    fun symptomAnchorLine(p2: String?): String {
        val labels = values(p2)
            .filter { it !in exclusivePhaseValues }
            .mapNotNull { value -> phaseChoices.firstOrNull { it.value == value }?.label }
        if (labels.isEmpty()) return FALLBACK_ANCHOR
        return "「${labels.joinToString(" · ")}」, 평소와 비교해서 답해주세요."
    }

    private const val FALLBACK_ANCHOR = "그나마 힘들었던 때를 떠올려서, 평소와 비교해서 답해주세요."
}

/** 자기보고 결과 — ⚠ 앱 리듬 엔진(WindowStatsEngine)의 유형과 다른 양이다. 같은 필드에 담지 말 것. */
data class SelfReportResult(
    val type: RhythmType,
    val modalityRaw: Int,   // (Q1+Q2+Q3) − (Q4+Q5+Q6), 범위 [-6, +6]
)

object SelfReportScoring {
    /** 문항당 강도 점수 — 예 2 · 그때그때 달라요 1 · 아니요(무응답) 0.
     *  중간 선택지를 0으로 접으면 그 답이 계열 점수에서 통째로 사라진다(2026-09-04). */
    private fun weight(value: String?): Int = when (value) {
        "worse" -> 2
        "somewhat" -> 1
        else -> 0
    }

    /** `total`·`slight`는 2026-09-09 Q9 축소로 화면에서 사라진 값이다 — 그 전에 답한 기록이
     *  유형 없는 응답으로 떨어지지 않게 집합에는 남긴다. */
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

    /** 무성의 응답 판별 — Q1~Q7 전부 "예"(worse)인데 역문항 Q8도 "예"면 모순이다. */
    fun isStraightLining(answers: Map<String, String>): Boolean {
        val probes = listOf("Q1", "Q2", "Q3", "Q4", "Q5", "Q6", "Q7")
        return probes.all { answers[it] == "worse" } && answers["Q8"] == "worse"
    }
}
