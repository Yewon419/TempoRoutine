// 템포루틴 Android — 개발용 샘플 데이터 (iOS DevSampleData 대응). 디버그 빌드 + 런치 인자(`--ez seedSample true`)로만.
// 스크린샷 검증용: 일정(여러 날)·Input(체크/서브태스크/타이머)·Output(세션 점/퍼센트/주기 기준).
//   adb shell am start -n app.temporoutine/.android.MainActivity --ez seedSample true

package app.temporoutine.android

import app.temporoutine.android.data.InputItemEntity
import app.temporoutine.android.data.InputSubtaskEntity
import app.temporoutine.android.data.OutputItemEntity
import app.temporoutine.android.data.OutputSubtaskEntity
import app.temporoutine.android.data.ScheduleItemEntity
import app.temporoutine.core.CycleAnchor
import app.temporoutine.core.CyclePhase
import app.temporoutine.core.CycleRecurrence
import app.temporoutine.core.InputSchedule
import app.temporoutine.core.OffsetOverflowRule
import app.temporoutine.core.OutputProgressKind
import app.temporoutine.core.OutputSchedule
import java.time.LocalDate
import java.time.ZoneId

object DevSampleData {
    suspend fun seed(app: TempoApp) {
        val db = app.db
        if (db.inputs().all().isNotEmpty()) return
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now()
        val now = today.atStartOfDay(zone).toInstant()

        db.schedules().insert(ScheduleItemEntity(title = "여행", date = now, endDate = today.plusDays(2).atStartOfDay(zone).toInstant(), isAllDay = true))

        db.inputs().insert(InputItemEntity(title = "혼자만의 패션쇼", scheduleJson = InputItemEntity.encodeSchedule(InputSchedule.Daily), createdAt = now))
        db.inputs().insert(InputItemEntity(title = "공원 피크닉", scheduleJson = InputItemEntity.encodeSchedule(InputSchedule.Daily), createdAt = now, timeMinutes = 15 * 60))
        val checklist = InputItemEntity(title = "아침 루틴", scheduleJson = InputItemEntity.encodeSchedule(InputSchedule.Daily), createdAt = now, progressKindRaw = OutputProgressKind.SUBTASKS.rawValue)
        db.inputs().insert(checklist)
        db.inputs().insertSubtasks(listOf(InputSubtaskEntity(ownerId = checklist.id, title = "물 한 잔", order = 0), InputSubtaskEntity(ownerId = checklist.id, title = "스트레칭", order = 1)))
        db.inputs().insert(InputItemEntity(title = "영어 듣기", scheduleJson = InputItemEntity.encodeSchedule(InputSchedule.Daily), createdAt = now,
            progressKindRaw = OutputProgressKind.TIMER.rawValue, targetSeconds = 1800))

        val study = OutputItemEntity(title = "공부 한 챕터", scheduleJson = OutputItemEntity.encodeSchedule(OutputSchedule.Daily), progressKind = OutputProgressKind.SESSIONS.rawValue, targetSessions = 3, createdAt = now)
        db.outputs().insert(study)
        db.outputs().insert(OutputItemEntity(title = "포트폴리오 정리", scheduleJson = OutputItemEntity.encodeSchedule(OutputSchedule.Once), progressKind = OutputProgressKind.PERCENT.rawValue,
            percent = 0.4, createdAt = now, targetDate = today.plusDays(5).atStartOfDay(zone).toInstant()))
        val exam = OutputItemEntity(title = "시험공부", scheduleJson = OutputItemEntity.encodeSchedule(OutputSchedule.CycleAnchored(
            CycleRecurrence(CycleAnchor.Phase(CyclePhase.MENSTRUAL), 0, true, OffsetOverflowRule.CLAMP, wholePhase = true))),
            progressKind = OutputProgressKind.SUBTASKS.rawValue, createdAt = now)
        db.outputs().insert(exam)
        db.outputs().insertSubtasks(listOf(OutputSubtaskEntity(ownerId = exam.id, title = "1챕터", isDone = true, order = 0), OutputSubtaskEntity(ownerId = exam.id, title = "2챕터", order = 1)))
    }
}
