// 앱 내 자기보고 설문 테스트 — 문항 계약과 채점이 웹 쪽과 어긋나지 않게 막는다.

import XCTest
@testable import TempoCore

final class SelfReportSurveyTests: XCTestCase {

    /// 필수 14 + 선택 3 = 17. 개수가 바뀌면 "2분" 약속과 분석 사양이 같이 흔들린다.
    func testQuestionCount() {
        XCTAssertEqual(SelfReportSurvey.requiredQuestionIDs.count, 14)
        XCTAssertEqual(SelfReportSurvey.optionalQuestions.count, 3)
        XCTAssertEqual(SelfReportSurvey.allQuestionIDs.count, 17)
    }

    /// P1이 P2보다 먼저여야 한다 — 뒤집으면 통념이 P1을 오염시킨다.
    func testPhaseOrderIsFixed() {
        XCTAssertEqual(SelfReportSurvey.phaseQuestions.map(\.id), ["P1", "P2"])
    }

    /// Q8은 역문항이라 제거 불가 — 이진 척도에서 유일한 무성의 판별 장치다.
    func testReverseItemExists() {
        XCTAssertTrue(SelfReportSurvey.symptomQuestions.contains { $0.id == "Q8" })
    }

    /// 증상 앵커는 P2 응답에서 온다. 고정 문구를 쓰면 위상을 가정한 채 위상 이질성을 재게 된다.
    func testAnchorUsesP2Answer() {
        let line = SelfReportSurvey.symptomAnchorLine(p2: "before")
        XCTAssertTrue(line.contains("다음 생리 오기 일주일쯤 전"))
    }

    /// "딱히 없어요"·"모르겠어요"·미응답은 폴백 문구로 — 앵커를 지어내지 않는다.
    func testAnchorFallback() {
        for value in ["none", "unknown", nil] {
            let line = SelfReportSurvey.symptomAnchorLine(p2: value)
            XCTAssertTrue(line.contains("그나마 힘들었던 때"))
        }
    }

    func testModalityRawRange() {
        let emotionalHeavy = ["Q1": "worse", "Q2": "worse", "Q3": "worse",
                              "Q4": "same", "Q5": "same", "Q6": "same", "Q9": "much"]
        XCTAssertEqual(SelfReportScoring.score(emotionalHeavy).modalityRaw, 6)

        let bodilyHeavy = ["Q1": "same", "Q2": "same", "Q3": "same",
                           "Q4": "worse", "Q5": "worse", "Q6": "worse", "Q9": "much"]
        XCTAssertEqual(SelfReportScoring.score(bodilyHeavy).modalityRaw, -6)
    }

    /// 중간 선택지(2026-09-04) — 「조금 그래요」는 문항당 1점. 0으로 접히면 답이 사라진다.
    func testSomewhatCountsAsHalf() {
        let mid = ["Q1": "somewhat", "Q2": "somewhat", "Q3": "somewhat",
                   "Q4": "same", "Q5": "same", "Q6": "same", "Q9": "much"]
        XCTAssertEqual(SelfReportScoring.score(mid).modalityRaw, 3)

        let mixed = ["Q1": "worse", "Q2": "somewhat", "Q3": "same",
                     "Q4": "somewhat", "Q5": "same", "Q6": "same", "Q9": "much"]
        XCTAssertEqual(SelfReportScoring.score(mixed).modalityRaw, 2)   // (2+1+0) − (1+0+0)
    }

    /// 루바토가 진폭 판정보다 먼저다 — 모르겠다고 답한 사람을 비바체로 밀지 않는다.
    func testRubatoTakesPrecedence() {
        XCTAssertEqual(SelfReportScoring.score(["C1": "unknown", "Q9": "total"]).type, .rubato)
        XCTAssertEqual(SelfReportScoring.score(["C1": "within1m", "Q9": "varies"]).type, .rubato)
    }

    func testAmplitudeSplit() {
        XCTAssertEqual(SelfReportScoring.score(["C1": "within1m", "Q9": "much"]).type, .vivace)
        XCTAssertEqual(SelfReportScoring.score(["C1": "within1m", "Q9": "total"]).type, .vivace)
        XCTAssertEqual(SelfReportScoring.score(["C1": "within1m", "Q9": "same"]).type, .andante)
        XCTAssertEqual(SelfReportScoring.score(["C1": "within1m", "Q9": "slight"]).type, .andante)
    }

    /// Q1~Q7 전부 "심해져요" + 역문항 Q8도 "심해져요" = 모순 → 무성의로 본다.
    func testStraightLiningDetection() {
        var all = [String: String]()
        for id in ["Q1", "Q2", "Q3", "Q4", "Q5", "Q6", "Q7", "Q8"] { all[id] = "worse" }
        XCTAssertTrue(SelfReportScoring.isStraightLining(all))

        all["Q8"] = "same"   // 역문항에서 방향을 바꿨으면 성실한 응답
        XCTAssertFalse(SelfReportScoring.isStraightLining(all))
    }

    /// 선택지 value가 중복되면 저장값이 뭉개진다.
    func testChoiceValuesAreUniquePerQuestion() {
        let all = [SelfReportSurvey.calibration]
            + SelfReportSurvey.phaseQuestions
            + SelfReportSurvey.symptomQuestions
            + SelfReportSurvey.amplitudeQuestions
            + SelfReportSurvey.optionalQuestions
        for question in all {
            let values = Set(question.choices.map(\.value))
            XCTAssertEqual(values.count, question.choices.count, "중복 value: \(question.id)")
            XCTAssertFalse(question.choices.isEmpty, "선택지 없음: \(question.id)")
        }
    }
}
