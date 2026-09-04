// 템포루틴 Android — 오늘 화면 쓰기 액션 (iOS TodayView의 toggleCheck·ensureProgress·outputProgress 콜백 + 삭제)
// ViewModel 확장으로 분리 — 상태 조합(TodayViewModel.build)과 쓰기를 한 파일에 섞지 않는다.

package app.temporoutine.android.today

import androidx.lifecycle.viewModelScope
import app.temporoutine.android.cycle.CycleSnapshot
import app.temporoutine.android.data.CheckInDraft
import app.temporoutine.android.data.InputItemEntity
import app.temporoutine.android.data.InputProgressEntity
import app.temporoutine.android.data.ItemCompletionEntity
import app.temporoutine.android.data.OutputItemEntity
import app.temporoutine.android.data.OutputSubtaskEntity
import app.temporoutine.android.data.ScheduleItemEntity
import app.temporoutine.core.OutputProgressKind
import app.temporoutine.core.ProgressRule
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate

fun TodayViewModel.isChecked(itemId: String): Boolean =
    state.value.completions.any { it.itemId == itemId && it.occurredOn == state.value.today }

/** Input 체크 토글 — 그날 ItemCompletion 삭제/삽입. */
fun TodayViewModel.toggleInputCheck(item: InputItemEntity) {
    val s = state.value
    viewModelScope.launch {
        val dao = app.db.inputs()
        val existing = dao.completions(item.id, s.today)
        if (existing.isNotEmpty()) dao.deleteCompletions(existing)
        else dao.insertCompletion(ItemCompletionEntity(itemId = item.id, occurredOn = s.today))
    }
}

/** 그날 진행 레코드 확보(없으면 생성) 후 변환 적용. 자동 체크 동기(목표 도달 ↔ 체크)까지. */
fun TodayViewModel.updateInputProgress(item: InputItemEntity, transform: (InputProgressEntity) -> InputProgressEntity) {
    val s = state.value
    viewModelScope.launch {
        val dao = app.db.inputs()
        val current = dao.progress(item.id, s.today)
        val next = transform(current ?: InputProgressEntity(itemId = item.id, occurredOn = s.today))
        if (current == null) dao.insertProgress(next) else dao.updateProgress(next)
        // 자동 완료 동기 — 스톱워치는 규칙상 항상 미도달이라 제외(iOS TodayView:839-845)
        val goal = item.progressGoal(s.inputSubtasks.count { it.ownerId == item.id }) ?: return@launch
        if (goal.kind == OutputProgressKind.STOPWATCH) return@launch
        val fulfilled = ProgressRule.isFulfilled(goal, next.state(Instant.now()))
        val checked = dao.completions(item.id, s.today).isNotEmpty()
        if (fulfilled != checked) {
            if (checked) dao.deleteCompletions(dao.completions(item.id, s.today))
            else dao.insertCompletion(ItemCompletionEntity(itemId = item.id, occurredOn = s.today))
        }
    }
}

fun TodayViewModel.updateOutput(item: OutputItemEntity) {
    viewModelScope.launch { app.db.outputs().update(item) }
}

fun TodayViewModel.toggleOutputSubtask(sub: OutputSubtaskEntity) {
    viewModelScope.launch { app.db.outputs().updateSubtask(sub.copy(isDone = !sub.isDone)) }
}

fun TodayViewModel.deleteSchedule(item: ScheduleItemEntity) {
    viewModelScope.launch { app.db.schedules().delete(item) }
}

/** Input 삭제 = 서브태스크·완료·진행까지(iOS QuickDelete:39-58). */
fun TodayViewModel.deleteInput(item: InputItemEntity) {
    viewModelScope.launch {
        val dao = app.db.inputs()
        dao.deleteSubtasks(item.id)
        dao.deleteCompletions(item.id)
        dao.deleteProgress(item.id)
        dao.delete(item)
    }
}

fun TodayViewModel.deleteOutput(item: OutputItemEntity) {
    viewModelScope.launch {
        app.db.outputs().deleteSubtasks(item.id)
        app.db.outputs().delete(item)
    }
}

/** 시트 드래프트 커밋 — 실제 상태와의 차집합만(제거 먼저, 추가는 오늘 이하). 반환 = 오늘 계절이 바뀌는가(성공 햅틱용). */
fun TodayViewModel.commitPeriodDraft(draft: Set<LocalDate>): Boolean {
    val s = state.value
    val actual = s.periodDays.map { it.day }.toSet()
    val adds = (draft - actual).filter { it <= s.today }
    val removeDays = actual - draft
    if (adds.isEmpty() && removeDays.isEmpty()) return false
    val records = s.periodDays.filter { it.day in removeDays }
    val before = s.snapshot.phase(s.today)
    val projected = actual.filter { it !in removeDays } + adds
    viewModelScope.launch {
        if (records.isNotEmpty()) app.periodStore.remove(records)
        if (adds.isNotEmpty()) app.periodStore.add(adds, s.periodDays.filter { it.day !in removeDays }, s.today)
    }
    val after = CycleSnapshot(projected, s.cycleLengthPrior, s.periodLengthPrior).phase(s.today)
    return before != after
}

/** 체크인 저장 — awarded면 씨앗 연출 카운터를 올린다. */
fun TodayViewModel.persistCheckIn(day: LocalDate, draft: CheckInDraft) {
    viewModelScope.launch {
        val result = app.checkInStore.persist(day, draft, state.value.today)
        if (result.awarded) seedBurst.value = seedBurst.value + 1
    }
}
