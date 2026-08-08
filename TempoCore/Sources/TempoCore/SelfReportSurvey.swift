// 템포루틴 — 앱 내 자기보고 설문 (핸드오프 v1.6 §4 / MASTER §3.11)
//
// 웹 사전 설문과 **같은 17문항이되 응답은 연결하지 않는다.** 연결하지 않는 것이 이득이다 —
// 앱 내 응답이 독립 측정이 되면 "자기보고 위상 × 실측 위상" 대조가 가능해지고,
// 그것이 자기보고를 믿어도 되는지(D3)를 검증하는 유일한 경로다.
//
// 문항 순서 규칙(웹과 동일, 어기면 측정이 오염된다):
//   - P1을 P2보다 먼저. 뒤집으면 "생리 전" 통념이 P1까지 오염시킨다.
//   - 증상 8문항만 제시 순서 랜덤화.
//   - 증상의 시간 앵커는 P2 응답. 고정 문구를 쓰면 위상을 가정한 채 위상 이질성을 재게 된다.

import Foundation

public struct SurveyChoice: Equatable, Sendable {
    public let value: String
    public let label: String

    public init(_ value: String, _ label: String) {
        self.value = value
        self.label = label
    }
}

public struct SurveyQuestion: Equatable, Sendable {
    public let id: String
    public let text: String
    public let choices: [SurveyChoice]
    public let isOptional: Bool

    public init(id: String, text: String, choices: [SurveyChoice], isOptional: Bool = false) {
        self.id = id
        self.text = text
        self.choices = choices
        self.isOptional = isOptional
    }
}

public enum SelfReportSurvey {

    public static let phaseChoices = [
        SurveyChoice("menstrual", "생리 중"),
        SurveyChoice("after", "생리 끝난 직후"),
        SurveyChoice("mid", "생리와 다음 생리 중간쯤"),
        SurveyChoice("before", "다음 생리 오기 일주일쯤 전"),
        SurveyChoice("none", "딱히 없어요"),
        SurveyChoice("unknown", "잘 모르겠어요"),
    ]

    private static let symptomChoices = [
        SurveyChoice("worse", "심해져요"),
        SurveyChoice("same", "비슷해요"),
    ]

    private static let frequencyChoices = [
        SurveyChoice("none", "없어요"),
        SurveyChoice("sometimes", "가끔"),
        SurveyChoice("often", "자주"),
        SurveyChoice("monthly", "거의 매달"),
    ]

    private static let yesNoChoices = [
        SurveyChoice("yes", "예"),
        SurveyChoice("no", "아니오"),
        SurveyChoice("decline", "답하지 않을래요"),
    ]

    /// 캘리브레이션 — 문항이 아니라 시간 앵커 고정용이다. 뒤로 뺄 수 없다.
    public static let calibration = SurveyQuestion(
        id: "C1", text: "가장 최근 생리는 언제였나요",
        choices: [
            SurveyChoice("within1m", "한 달 이내"),
            SurveyChoice("1to3m", "1–3개월 전"),
            SurveyChoice("3to6m", "3–6개월 전"),
            SurveyChoice("over6m", "6개월 이상"),
            SurveyChoice("unknown", "잘 모르겠어요"),
        ])

    /// 순서 고정 — P1이 먼저다.
    public static let phaseQuestions = [
        SurveyQuestion(id: "P1", text: "한 주기 중에 컨디션이 가장 좋은 때는 언제인가요",
                       choices: phaseChoices),
        SurveyQuestion(id: "P2", text: "반대로, 가장 안 좋은 때는 언제인가요",
                       choices: phaseChoices),
    ]

    /// 제시 순서만 랜덤화한다. 저장 키는 원래 id라 분석에 영향이 없다.
    /// Q7은 프로브(합성점수 제외), Q8은 역문항(straight-lining 판별 장치라 제거 불가).
    public static let symptomQuestions = [
        SurveyQuestion(id: "Q1", text: "감정이 오르내려요", choices: symptomChoices),
        SurveyQuestion(id: "Q2", text: "사소한 일에 날카로워져요", choices: symptomChoices),
        SurveyQuestion(id: "Q3", text: "불안하거나 초조해요", choices: symptomChoices),
        SurveyQuestion(id: "Q4", text: "아랫배나 허리가 불편해요", choices: symptomChoices),
        SurveyQuestion(id: "Q5", text: "몸이 붓거나 무거워요", choices: symptomChoices),
        SurveyQuestion(id: "Q6", text: "가슴이 아프거나 불편해요", choices: symptomChoices),
        SurveyQuestion(id: "Q7", text: "쉽게 피곤해져요", choices: symptomChoices),
        SurveyQuestion(id: "Q8", text: "그때도 평소랑 거의 똑같아요", choices: symptomChoices),
    ]

    /// 이 셋만 다점 척도 — 진폭과 기능 지장의 상관을 재는 유일한 쌍이라 이진화하면 무의미해진다.
    public static let amplitudeQuestions = [
        SurveyQuestion(id: "Q9", text: "한 주기 안에서 가장 좋은 때와 가장 안 좋은 때, 얼마나 다른가요",
                       choices: [
                           SurveyChoice("same", "거의 비슷해요"),
                           SurveyChoice("slight", "조금 달라요"),
                           SurveyChoice("much", "꽤 달라요"),
                           SurveyChoice("total", "완전히 다른 사람 같아요"),
                           SurveyChoice("varies", "매번 달라요"),
                       ]),
        SurveyQuestion(id: "Q10", text: "그것 때문에 할 일을 못 하거나 미룬 적 있나요",
                       choices: frequencyChoices),
        SurveyQuestion(id: "Q11", text: "그것 때문에 사람들과 지내기 불편했던 적 있나요",
                       choices: frequencyChoices),
    ]

    public static let optionalQuestions = [
        SurveyQuestion(id: "O1", text: "호르몬 피임약이나 시술을 쓰고 있나요",
                       choices: yesNoChoices, isOptional: true),
        SurveyQuestion(id: "O2", text: "PMS·PMDD, 다낭성난소증후군, 자궁내막증 중 진단받은 게 있나요",
                       choices: yesNoChoices, isOptional: true),
        SurveyQuestion(id: "O3", text: "이 답들이 매달 비슷한가요",
                       choices: [
                           SurveyChoice("similar", "네, 비슷해요"),
                           SurveyChoice("varies", "달마다 달라요"),
                           SurveyChoice("unknown", "잘 모르겠어요"),
                       ], isOptional: true),
    ]

    /// 저장을 허용하는 키 — 임의 키가 섞이지 않게 한다(웹 서버의 화이트리스트와 동형).
    public static var allQuestionIDs: Set<String> {
        var ids: Set<String> = [calibration.id]
        for q in phaseQuestions + symptomQuestions + amplitudeQuestions + optionalQuestions {
            ids.insert(q.id)
        }
        return ids
    }

    public static var requiredQuestionIDs: Set<String> {
        var ids: Set<String> = [calibration.id]
        for q in phaseQuestions + symptomQuestions + amplitudeQuestions { ids.insert(q.id) }
        return ids
    }

    /// P2 응답을 증상 문항의 시간 앵커 문구로 바꾼다. "딱히 없어요"·"모르겠어요"는 폴백.
    public static func symptomAnchorLine(p2: String?) -> String {
        guard let p2,
              p2 != "none", p2 != "unknown",
              let choice = phaseChoices.first(where: { $0.value == p2 }) else {
            return "그나마 힘들었던 때를 떠올려서, 평소와 비교해서 답해주세요."
        }
        return "「\(choice.label)」, 평소와 비교해서 답해주세요."
    }
}

/// 자기보고 결과 — ⚠ 앱 리듬 엔진(WindowStatsEngine)의 유형과 **다른 양이다.**
/// 루바토라는 이름을 공유하지만 산출 경로가 다르므로 같은 필드에 담지 말 것(MASTER §3.11).
public struct SelfReportResult: Equatable, Sendable {
    public let type: RhythmType
    public let modalityRaw: Int      // (Q1+Q2+Q3) − (Q4+Q5+Q6), 범위 [-3, +3]

    public init(type: RhythmType, modalityRaw: Int) {
        self.type = type
        self.modalityRaw = modalityRaw
    }
}

public enum SelfReportScoring {
    /// 이진 척도라 "심해져요"의 개수가 곧 계열 점수다.
    private static func binary(_ value: String?) -> Int { value == "worse" ? 1 : 0 }

    private static let vivaceAnswers: Set<String> = ["much", "total"]
    private static let andanteAnswers: Set<String> = ["same", "slight"]

    public static func score(_ answers: [String: String]) -> SelfReportResult {
        let emotional = binary(answers["Q1"]) + binary(answers["Q2"]) + binary(answers["Q3"])
        let bodily = binary(answers["Q4"]) + binary(answers["Q5"]) + binary(answers["Q6"])
        return SelfReportResult(type: resolveType(answers), modalityRaw: emotional - bodily)
    }

    /// 루바토를 먼저 거른다 — 최근 생리를 모르거나 "매번 다름"이면 진폭을 판정하지 않는다.
    private static func resolveType(_ answers: [String: String]) -> RhythmType {
        if answers["C1"] == "unknown" || answers["Q9"] == "varies" { return .rubato }
        if let q9 = answers["Q9"] {
            if vivaceAnswers.contains(q9) { return .vivace }
            if andanteAnswers.contains(q9) { return .andante }
        }
        return .rubato
    }

    /// 무성의 응답 판별 — Q1~Q7 전부 "심해져요"인데 역문항 Q8도 "심해져요"면 모순이다.
    public static func isStraightLining(_ answers: [String: String]) -> Bool {
        let probes = ["Q1", "Q2", "Q3", "Q4", "Q5", "Q6", "Q7"]
        return probes.allSatisfy { answers[$0] == "worse" } && answers["Q8"] == "worse"
    }
}
