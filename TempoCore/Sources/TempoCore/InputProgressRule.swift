// 템포루틴 — Input 진행도 규칙 (2026-08-12 사용자 지시 / MASTER §5.5.2 개정)
//
// **Output과 결정적으로 다른 점: 날짜별이다.**
// Output 진행도는 아이템 수명 전체 누적이라 occurrence별 리셋이 없다(§5.5.2 LOCKED).
// Input은 매일 반복이 기본이라 같은 모델을 쓰면 이틀째부터 이미 목표 도달 상태가 된다.
// 그래서 **정의(종류·목표·서브태스크 이름)는 아이템에, 상태는 그날의 레코드**에 둔다.
//
// 완료 판정은 종전 `ItemCompletion` 그대로다 — 목표에 닿는 순간 그 레코드를 만든다.
// 진행 값을 완료 레코드에 얹지 않는 이유: "레코드 존재 = 완료"에 씨앗 판정·위젯·내보내기가
// 전부 의존한다. 미완료 상태를 담는 순간 그 의미론이 무너진다.

import Foundation

/// 그날의 진행 상태 — 저장은 `InputProgress`(@Model), 판정은 이 값 타입으로만 한다.
public struct InputProgressState: Equatable, Sendable {
    public let loggedSessions: Int
    public let percent: Double
    public let elapsedSeconds: Double
    public let doneSubtasks: Int

    public init(loggedSessions: Int = 0, percent: Double = 0,
                elapsedSeconds: Double = 0, doneSubtasks: Int = 0) {
        self.loggedSessions = loggedSessions
        self.percent = percent
        self.elapsedSeconds = elapsedSeconds
        self.doneSubtasks = doneSubtasks
    }
}

/// 아이템에 붙는 정의 — 날짜가 바뀌어도 그대로다.
public struct InputProgressGoal: Equatable, Sendable {
    public let kind: OutputProgressKind
    public let targetSessions: Int
    public let targetSeconds: Int?
    public let subtaskCount: Int

    public init(kind: OutputProgressKind, targetSessions: Int = 0,
                targetSeconds: Int? = nil, subtaskCount: Int = 0) {
        self.kind = kind
        self.targetSessions = targetSessions
        self.targetSeconds = targetSeconds
        self.subtaskCount = subtaskCount
    }
}

public enum InputProgressRule {

    /// 그날의 진행이 목표에 닿았는가 = 자동 체크 판정(2026-08-12 사용자 결정).
    ///
    /// **목표가 없으면 닿을 수도 없다** — 목표 0·서브태스크 0은 false를 돌려준다.
    /// 스톱워치는 목표라는 게 성립하지 않아 항상 false다(잰 시간이 얼마든 "다 했다"는 판정을
    /// 앱이 대신 내릴 수 없다). 그 둘은 종전처럼 사용자가 직접 체크한다.
    public static func isFulfilled(goal: InputProgressGoal, state: InputProgressState) -> Bool {
        switch goal.kind {
        case .subtasks:
            return goal.subtaskCount > 0 && state.doneSubtasks >= goal.subtaskCount
        case .sessions:
            return goal.targetSessions > 0 && state.loggedSessions >= goal.targetSessions
        case .percent:
            return state.percent >= 100
        case .timer:
            guard let target = goal.targetSeconds, target > 0 else { return false }
            return state.elapsedSeconds >= Double(target)
        case .stopwatch:
            return false
        }
    }

    /// 진행 비율 [0, 1] — 행에 그릴 게이지용. 목표가 없으면 nil(막대를 그리지 않는다).
    /// 스톱워치는 끝이 없어 비율이 성립하지 않는다.
    public static func fraction(goal: InputProgressGoal, state: InputProgressState) -> Double? {
        switch goal.kind {
        case .subtasks:
            guard goal.subtaskCount > 0 else { return nil }
            return clamp(Double(state.doneSubtasks) / Double(goal.subtaskCount))
        case .sessions:
            guard goal.targetSessions > 0 else { return nil }
            return clamp(Double(state.loggedSessions) / Double(goal.targetSessions))
        case .percent:
            return clamp(state.percent / 100)
        case .timer:
            guard let target = goal.targetSeconds, target > 0 else { return nil }
            return clamp(state.elapsedSeconds / Double(target))
        case .stopwatch:
            return nil
        }
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
}
