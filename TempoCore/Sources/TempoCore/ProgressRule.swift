// 템포루틴 — 진행도 규칙 (2026-08-12 사용자 지시 / MASTER §5.5.2 개정)
//
// **Input·Output 공용.** 판정 규칙은 한 벌이다 — 종전엔 같은 로직이 OutputItem.isComplete와
// 여기 두 곳에 각각 있었다(2026-08-13 통일).
//
// 두 카드가 갈리는 건 규칙이 아니라 **값이 어디 있느냐**다:
//   Output = 아이템에 누적(수명 전체, occurrence 리셋 없음 — §5.5.2 LOCKED)
//   Input  = 그날의 레코드(InputProgress). 매일 반복이 기본이라 아이템에 두면
//            이틀째부터 이미 목표 도달 상태가 된다.
//
// Input의 완료 판정은 종전 `ItemCompletion` 그대로다 — 목표에 닿는 순간 그 레코드를 만든다.
// 진행 값을 완료 레코드에 얹지 않는 이유: "레코드 존재 = 완료"에 씨앗 판정·위젯·내보내기가
// 전부 의존한다. 미완료 상태를 담는 순간 그 의미론이 무너진다.

import Foundation

/// 진행 상태 — 저장처는 카드마다 다르지만(Output=아이템 / Input=그날 레코드)
/// 판정은 이 값 타입으로만 한다.
public struct ProgressState: Equatable, Sendable {
    public let loggedSessions: Int
    /// **0~1 스케일** — OutputItem.percent와 같은 단위다(2026-08-12 통일).
    /// 같은 이름이 두 곳에서 다른 단위면 언젠가 100배 틀린다.
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

/// 목표 정의 — 두 카드 모두 아이템에 붙는다.
public struct ProgressGoal: Equatable, Sendable {
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

public enum ProgressRule {

    /// 진행이 목표에 닿았는가. Output은 완료 파생(isComplete), Input은 그날 자동 체크 판정.
    ///
    /// **목표가 없으면 닿을 수도 없다** — 목표 0·서브태스크 0은 false를 돌려준다.
    /// 스톱워치는 목표라는 게 성립하지 않아 항상 false다(잰 시간이 얼마든 "다 했다"는 판정을
    /// 앱이 대신 내릴 수 없다). 그 둘은 종전처럼 사용자가 직접 체크한다.
    public static func isFulfilled(goal: ProgressGoal, state: ProgressState) -> Bool {
        switch goal.kind {
        case .checkOnly:
            // 체크만(2026-08-18) — 저장을 percent 0↔1로 빌린다. 체크 = 1, 해제 = 0.
            return state.percent >= 1
        case .subtasks:
            return goal.subtaskCount > 0 && state.doneSubtasks >= goal.subtaskCount
        case .sessions:
            return goal.targetSessions > 0 && state.loggedSessions >= goal.targetSessions
        case .percent:
            return state.percent >= 1
        case .timer:
            guard let target = goal.targetSeconds, target > 0 else { return false }
            return state.elapsedSeconds >= Double(target)
        case .stopwatch:
            return false
        }
    }

    /// 진행 비율 [0, 1] — 행에 그릴 게이지용. 목표가 없으면 nil(막대를 그리지 않는다).
    /// 스톱워치는 끝이 없어 비율이 성립하지 않는다.
    public static func fraction(goal: ProgressGoal, state: ProgressState) -> Double? {
        switch goal.kind {
        case .checkOnly:
            return nil   // 이진 상태 — 게이지가 성립하지 않는다
        case .subtasks:
            guard goal.subtaskCount > 0 else { return nil }
            return clamp(Double(state.doneSubtasks) / Double(goal.subtaskCount))
        case .sessions:
            guard goal.targetSessions > 0 else { return nil }
            return clamp(Double(state.loggedSessions) / Double(goal.targetSessions))
        case .percent:
            return clamp(state.percent)
        case .timer:
            guard let target = goal.targetSeconds, target > 0 else { return nil }
            return clamp(state.elapsedSeconds / Double(target))
        case .stopwatch:
            return nil
        }
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
}
