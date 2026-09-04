// Input 진행도 규칙 테스트 — 자동 체크가 "목표에 닿았을 때만" 걸리는지 막는다.
// iOS TempoCoreTests/ProgressRuleTests.swift 1:1 이식.

package app.temporoutine.core

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ProgressRuleTests {

    @Test fun testNoTargetNeverFulfills() {
        val goal = ProgressGoal(OutputProgressKind.SESSIONS, targetSessions = 0)
        val state = ProgressState(loggedSessions = 99)
        assertFalse(ProgressRule.isFulfilled(goal, state))
        assertNull(ProgressRule.fraction(goal, state))
    }

    @Test fun testEmptySubtasksNeverFulfills() {
        val goal = ProgressGoal(OutputProgressKind.SUBTASKS, subtaskCount = 0)
        assertFalse(ProgressRule.isFulfilled(goal, ProgressState()))
    }

    @Test fun testStopwatchNeverAutoCompletes() {
        val goal = ProgressGoal(OutputProgressKind.STOPWATCH)
        val state = ProgressState(elapsedSeconds = 36_000.0)
        assertFalse(ProgressRule.isFulfilled(goal, state))
        assertNull(ProgressRule.fraction(goal, state))
    }

    @Test fun testTimerWithoutTargetNeverFulfills() {
        val goal = ProgressGoal(OutputProgressKind.TIMER, targetSeconds = null)
        assertFalse(ProgressRule.isFulfilled(goal, ProgressState(elapsedSeconds = 500.0)))
    }

    @Test fun testSessionsFulfillsAtTargetAndBeyond() {
        val goal = ProgressGoal(OutputProgressKind.SESSIONS, targetSessions = 8)
        assertFalse(ProgressRule.isFulfilled(goal, ProgressState(loggedSessions = 7)))
        assertTrue(ProgressRule.isFulfilled(goal, ProgressState(loggedSessions = 8)))
        assertTrue(ProgressRule.isFulfilled(goal, ProgressState(loggedSessions = 9)))
    }

    @Test fun testTimerFulfillsAtTarget() {
        val goal = ProgressGoal(OutputProgressKind.TIMER, targetSeconds = 300)
        assertFalse(ProgressRule.isFulfilled(goal, ProgressState(elapsedSeconds = 299.9)))
        assertTrue(ProgressRule.isFulfilled(goal, ProgressState(elapsedSeconds = 300.0)))
    }

    @Test fun testPercentFulfillsAtFull() {
        val goal = ProgressGoal(OutputProgressKind.PERCENT)
        assertFalse(ProgressRule.isFulfilled(goal, ProgressState(percent = 0.995)))
        assertTrue(ProgressRule.isFulfilled(goal, ProgressState(percent = 1.0)))
    }

    @Test fun testSubtasksFulfillWhenAllDone() {
        val goal = ProgressGoal(OutputProgressKind.SUBTASKS, subtaskCount = 3)
        assertFalse(ProgressRule.isFulfilled(goal, ProgressState(doneSubtasks = 2)))
        assertTrue(ProgressRule.isFulfilled(goal, ProgressState(doneSubtasks = 3)))
    }

    @Test fun testFractionClampsToOne() {
        val goal = ProgressGoal(OutputProgressKind.SESSIONS, targetSessions = 4)
        assertEquals(1.0, ProgressRule.fraction(goal, ProgressState(loggedSessions = 10)))
    }

    @Test fun testFractionClampsToZero() {
        val goal = ProgressGoal(OutputProgressKind.PERCENT)
        assertEquals(0.0, ProgressRule.fraction(goal, ProgressState(percent = -0.2)))
    }

    @Test fun testFractionMidway() {
        val goal = ProgressGoal(OutputProgressKind.TIMER, targetSeconds = 600)
        assertEquals(0.25, ProgressRule.fraction(goal, ProgressState(elapsedSeconds = 150.0)))
    }
}
