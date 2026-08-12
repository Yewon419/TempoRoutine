// Input 진행도 규칙 테스트 — 자동 체크가 "목표에 닿았을 때만" 걸리는지 막는다.
// 잘못 걸리면 하지도 않은 날이 완료로 적히고, 그 완료가 씨앗·위젯·내보내기까지 번진다.

import XCTest
@testable import TempoCore

final class ProgressRuleTests: XCTestCase {

    // ── 목표가 없으면 닿을 수도 없다 ──

    /// 세션 목표 0 = 자동 체크 없음. 종전 단순 체크 Input이 여기 해당한다.
    func testNoTargetNeverFulfills() {
        let goal = ProgressGoal(kind: .sessions, targetSessions: 0)
        let state = ProgressState(loggedSessions: 99)
        XCTAssertFalse(ProgressRule.isFulfilled(goal: goal, state: state))
        XCTAssertNil(ProgressRule.fraction(goal: goal, state: state))
    }

    /// 서브태스크가 하나도 없으면 "다 했다"가 성립하지 않는다(0 >= 0을 참으로 세면 안 된다).
    func testEmptySubtasksNeverFulfills() {
        let goal = ProgressGoal(kind: .subtasks, subtaskCount: 0)
        XCTAssertFalse(ProgressRule.isFulfilled(goal: goal, state: ProgressState()))
    }

    /// 스톱워치는 끝이 없다 — 얼마를 재든 앱이 완료를 대신 판정하지 않는다.
    func testStopwatchNeverAutoCompletes() {
        let goal = ProgressGoal(kind: .stopwatch)
        let state = ProgressState(elapsedSeconds: 36_000)
        XCTAssertFalse(ProgressRule.isFulfilled(goal: goal, state: state))
        XCTAssertNil(ProgressRule.fraction(goal: goal, state: state))
    }

    /// 타이머 목표가 비어 있으면 마찬가지다.
    func testTimerWithoutTargetNeverFulfills() {
        let goal = ProgressGoal(kind: .timer, targetSeconds: nil)
        let state = ProgressState(elapsedSeconds: 500)
        XCTAssertFalse(ProgressRule.isFulfilled(goal: goal, state: state))
    }

    // ── 경계 ──

    func testSessionsFulfillsAtTargetAndBeyond() {
        let goal = ProgressGoal(kind: .sessions, targetSessions: 8)
        XCTAssertFalse(ProgressRule.isFulfilled(
            goal: goal, state: ProgressState(loggedSessions: 7)))
        XCTAssertTrue(ProgressRule.isFulfilled(
            goal: goal, state: ProgressState(loggedSessions: 8)))
        XCTAssertTrue(ProgressRule.isFulfilled(
            goal: goal, state: ProgressState(loggedSessions: 9)))
    }

    func testTimerFulfillsAtTarget() {
        let goal = ProgressGoal(kind: .timer, targetSeconds: 300)
        XCTAssertFalse(ProgressRule.isFulfilled(
            goal: goal, state: ProgressState(elapsedSeconds: 299.9)))
        XCTAssertTrue(ProgressRule.isFulfilled(
            goal: goal, state: ProgressState(elapsedSeconds: 300)))
    }

    func testPercentFulfillsAtFull() {
        let goal = ProgressGoal(kind: .percent)
        XCTAssertFalse(ProgressRule.isFulfilled(
            goal: goal, state: ProgressState(percent: 0.995)))
        XCTAssertTrue(ProgressRule.isFulfilled(
            goal: goal, state: ProgressState(percent: 1)))
    }

    func testSubtasksFulfillWhenAllDone() {
        let goal = ProgressGoal(kind: .subtasks, subtaskCount: 3)
        XCTAssertFalse(ProgressRule.isFulfilled(
            goal: goal, state: ProgressState(doneSubtasks: 2)))
        XCTAssertTrue(ProgressRule.isFulfilled(
            goal: goal, state: ProgressState(doneSubtasks: 3)))
    }

    // ── 게이지 비율 ──

    /// 넘겨도 1을 넘지 않는다 — 막대가 칸을 뚫고 나가면 안 된다.
    func testFractionClampsToOne() {
        let goal = ProgressGoal(kind: .sessions, targetSessions: 4)
        XCTAssertEqual(ProgressRule.fraction(
            goal: goal, state: ProgressState(loggedSessions: 10)), 1)
    }

    /// 음수 퍼센트가 들어와도 0 아래로 내려가지 않는다.
    func testFractionClampsToZero() {
        let goal = ProgressGoal(kind: .percent)
        XCTAssertEqual(ProgressRule.fraction(
            goal: goal, state: ProgressState(percent: -0.2)), 0)
    }

    func testFractionMidway() {
        let goal = ProgressGoal(kind: .timer, targetSeconds: 600)
        XCTAssertEqual(ProgressRule.fraction(
            goal: goal, state: ProgressState(elapsedSeconds: 150)), 0.25)
    }
}
