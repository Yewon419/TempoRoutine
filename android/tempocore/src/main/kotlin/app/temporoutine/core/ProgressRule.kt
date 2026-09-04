// 템포루틴 — 진행도 규칙 (MASTER §5.5.2 개정) — Input·Output 공용.
// iOS TempoCore/ProgressRule.swift 1:1 이식.
// 두 카드가 갈리는 건 규칙이 아니라 값이 어디 있느냐: Output = 아이템 누적 / Input = 그날의 레코드.

package app.temporoutine.core

/** 진행 상태 — 저장처는 카드마다 다르지만 판정은 이 값 타입으로만 한다. */
data class ProgressState(
    val loggedSessions: Int = 0,
    /** 0~1 스케일 — OutputItem.percent와 같은 단위. */
    val percent: Double = 0.0,
    val elapsedSeconds: Double = 0.0,
    val doneSubtasks: Int = 0,
)

/** 목표 정의 — 두 카드 모두 아이템에 붙는다. */
data class ProgressGoal(
    val kind: OutputProgressKind,
    val targetSessions: Int = 0,
    val targetSeconds: Int? = null,
    val subtaskCount: Int = 0,
)

object ProgressRule {

    /** 진행이 목표에 닿았는가. 목표가 없으면 닿을 수도 없다 — 목표 0·서브태스크 0은 false.
     *  스톱워치는 항상 false(앱이 "다 했다"를 대신 판정하지 않는다). */
    fun isFulfilled(goal: ProgressGoal, state: ProgressState): Boolean = when (goal.kind) {
        OutputProgressKind.CHECK_ONLY -> state.percent >= 1   // 체크만 — 저장을 percent 0↔1로 빌린다
        OutputProgressKind.SUBTASKS -> goal.subtaskCount > 0 && state.doneSubtasks >= goal.subtaskCount
        OutputProgressKind.SESSIONS -> goal.targetSessions > 0 && state.loggedSessions >= goal.targetSessions
        OutputProgressKind.PERCENT -> state.percent >= 1
        OutputProgressKind.TIMER -> {
            val target = goal.targetSeconds
            target != null && target > 0 && state.elapsedSeconds >= target.toDouble()
        }
        OutputProgressKind.STOPWATCH -> false
    }

    /** 진행 비율 [0, 1] — 게이지용. 목표가 없으면 null(막대를 그리지 않는다). */
    fun fraction(goal: ProgressGoal, state: ProgressState): Double? = when (goal.kind) {
        OutputProgressKind.CHECK_ONLY -> null   // 이진 상태 — 게이지가 성립하지 않는다
        OutputProgressKind.SUBTASKS ->
            if (goal.subtaskCount <= 0) null else clamp(state.doneSubtasks.toDouble() / goal.subtaskCount)
        OutputProgressKind.SESSIONS ->
            if (goal.targetSessions <= 0) null else clamp(state.loggedSessions.toDouble() / goal.targetSessions)
        OutputProgressKind.PERCENT -> clamp(state.percent)
        OutputProgressKind.TIMER -> {
            val target = goal.targetSeconds
            if (target == null || target <= 0) null else clamp(state.elapsedSeconds / target.toDouble())
        }
        OutputProgressKind.STOPWATCH -> null
    }

    private fun clamp(value: Double): Double = minOf(1.0, maxOf(0.0, value))
}
