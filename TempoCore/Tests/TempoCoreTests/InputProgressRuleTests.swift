// Input 진행도 규칙 테스트 — 자동 체크가 "목표에 닿았을 때만" 걸리는지 막는다.
// 잘못 걸리면 하지도 않은 날이 완료로 적히고, 그 완료가 씨앗·위젯·내보내기까지 번진다.

import XCTest
@testable import TempoCore

final class InputProgressRuleTests: XCTestCase {

    // ── 목표가 없으면 닿을 수도 없다 ──

    /// 세션 목표 0 = 자동 체크 없음. 종전 단순 체크 Input이 여기 해당한다.
    func testNoTargetNeverFulfills() {
        let goal = InputProgressGoal(kind: .sessions, targetSessions: 0)
        let state = InputProgressState(loggedSessions: 99)
        XCTAssertFalse(InputProgressRule.isFulfilled(goal: goal, state: state))
        XCTAssertNil(InputProgressRule.fraction(goal: goal, state: state))
    }

    /// 서브태스크가 하나도 없으면 "다 했다"가 성립하지 않는다(0 >= 0을 참으로 세면 안 된다).
    func testEmptySubtasksNeverFulfills() {
        let goal = InputProgressGoal(kind: .subtasks, subtaskCount: 0)
        XCTAssertFalse(InputProgressRule.isFulfilled(goal: goal, state: InputProgressState()))
    }

    /// 스톱워치는 끝이 없다 — 얼마를 재든 앱이 완료를 대신 판정하지 않는다.
    func testStopwatchNeverAutoCompletes() {
        let goal = InputProgressGoal(kind: .stopwatch)
        let state = InputProgressState(elapsedSeconds: 36_000)
        XCTAssertFalse(InputProgressRule.isFulfilled(goal: goal, state: state))
        XCTAssertNil(InputProgressRule.fraction(goal: goal, state: state))
    }

    /// 타이머 목표가 비어 있으면 마찬가지다.
    func testTimerWithoutTargetNeverFulfills() {
        let goal = InputProgressGoal(kind: .timer, targetSeconds: nil)
        let state = InputProgressState(elapsedSeconds: 500)
        XCTAssertFalse(InputProgressRule.isFulfilled(goal: goal, state: state))
    }

    // ── 경계 ──

    func testSessionsFulfillsAtTargetAndBeyond() {
        let goal = InputProgressGoal(kind: .sessions, targetSessions: 8)
        XCTAssertFalse(InputProgressRule.isFulfilled(
            goal: goal, state: InputProgressState(loggedSessions: 7)))
        XCTAssertTrue(InputProgressRule.isFulfilled(
            goal: goal, state: InputProgressState(loggedSessions: 8)))
        XCTAssertTrue(InputProgressRule.isFulfilled(
            goal: goal, state: InputProgressState(loggedSessions: 9)))
    }

    func testTimerFulfillsAtTarget() {
        let goal = InputProgressGoal(kind: .timer, targetSeconds: 300)
        XCTAssertFalse(InputProgressRule.isFulfilled(
            goal: goal, state: InputProgressState(elapsedSeconds: 299.9)))
        XCTAssertTrue(InputProgressRule.isFulfilled(
            goal: goal, state: InputProgressState(elapsedSeconds: 300)))
    }

    func testPercentFulfillsAtHundred() {
        let goal = InputProgressGoal(kind: .percent)
        XCTAssertFalse(InputProgressRule.isFulfilled(
            goal: goal, state: InputProgressState(percent: 99.5)))
        XCTAssertTrue(InputProgressRule.isFulfilled(
            goal: goal, state: InputProgressState(percent: 100)))
    }

    func testSubtasksFulfillWhenAllDone() {
        let goal = InputProgressGoal(kind: .subtasks, subtaskCount: 3)
        XCTAssertFalse(InputProgressRule.isFulfilled(
            goal: goal, state: InputProgressState(doneSubtasks: 2)))
        XCTAssertTrue(InputProgressRule.isFulfilled(
            goal: goal, state: InputProgressState(doneSubtasks: 3)))
    }

    // ── 게이지 비율 ──

    /// 넘겨도 1을 넘지 않는다 — 막대가 칸을 뚫고 나가면 안 된다.
    func testFractionClampsToOne() {
        let goal = InputProgressGoal(kind: .sessions, targetSessions: 4)
        XCTAssertEqual(InputProgressRule.fraction(
            goal: goal, state: InputProgressState(loggedSessions: 10)), 1)
    }

    /// 음수 퍼센트가 들어와도 0 아래로 내려가지 않는다.
    func testFractionClampsToZero() {
        let goal = InputProgressGoal(kind: .percent)
        XCTAssertEqual(InputProgressRule.fraction(
            goal: goal, state: InputProgressState(percent: -20)), 0)
    }

    func testFractionMidway() {
        let goal = InputProgressGoal(kind: .timer, targetSeconds: 600)
        XCTAssertEqual(InputProgressRule.fraction(
            goal: goal, state: InputProgressState(elapsedSeconds: 150)), 0.25)
    }
}
