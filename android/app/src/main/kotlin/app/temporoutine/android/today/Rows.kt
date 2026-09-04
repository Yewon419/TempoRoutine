// 템포루틴 Android — 오늘 3구획 행 (iOS TodayView scheduleSection/inputSection/outputSection 이식, 은필 분기)
// 일정 행 = 조회 전용(편집 시트 P1). + 버튼 숨김(추가 시트 P1). 길게 누르기 삭제는 유지.

package app.temporoutine.android.today

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.temporoutine.android.R
import app.temporoutine.android.data.InputItemEntity
import app.temporoutine.android.data.InputSubtaskEntity
import app.temporoutine.android.data.OutputItemEntity
import app.temporoutine.android.data.OutputSubtaskEntity
import app.temporoutine.android.data.ScheduleItemEntity
import app.temporoutine.android.data.dayIndex
import app.temporoutine.android.data.occurs
import app.temporoutine.android.data.occursByCalendar
import app.temporoutine.android.data.onceShows
import app.temporoutine.android.data.sortedByTimeOfDay
import app.temporoutine.android.data.spanDays
import app.temporoutine.android.data.toLocalDate
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.core.InputSchedule
import app.temporoutine.core.OutputProgressKind
import app.temporoutine.core.OutputSchedule
import app.temporoutine.core.ProgressRule
import dev.chrisbanes.haze.HazeState
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.ChronoUnit

private val shortTime: DateTimeFormatter = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)

/** 자정 기준 분 → 로케일 시각 표기(iOS timeOfDayLabel) */
fun timeOfDayLabel(minutes: Int): String =
    java.time.LocalTime.of(minutes / 60, minutes % 60).format(shortTime)

@Composable
fun TodaySections(state: TodayUiState, vm: TodayViewModel, hazeState: HazeState) {
    val today = state.today
    val zone = ZoneId.systemDefault()

    // 일정 — occurs + 시간순(종일 맨 뒤)
    val schedules = remember(state.schedules, today) {
        sortedByTimeOfDay(state.schedules.filter { it.occurs(today, zone) }) {
            if (it.isAllDay) null else it.date.atZone(zone).let { z -> z.hour * 60 + z.minute }
        }
    }
    // Input — once는 적은 날 또는 체크된 날 / 달력 반복 / 주기 기준은 occurrence 또는 체크
    val checkedIds = remember(state.completions, today) { state.completions.filter { it.occurredOn == today }.map { it.itemId }.toSet() }
    val inputs = remember(state.inputs, checkedIds, state.snapshot, today) {
        sortedByTimeOfDay(state.inputs.filter { item ->
            when (val s = item.schedule) {
                InputSchedule.Once -> item.onceShows(today, zone) || item.id in checkedIds
                InputSchedule.Daily, InputSchedule.Weekly, InputSchedule.Monthly -> item.occursByCalendar(today, zone)
                is InputSchedule.CycleAnchored ->
                    state.snapshot.occurrence(s.recurrence, item.createdAt.toLocalDate(zone), today) != null || item.id in checkedIds
            }
        }) { it.timeMinutes }
    }
    val outputs = remember(state.outputs, state.outputSubtasks, state.snapshot, today) {
        sortedByTimeOfDay(state.outputs.filter { item ->
            when (val s = item.schedule) {
                OutputSchedule.Once, OutputSchedule.Daily, OutputSchedule.Weekly, OutputSchedule.Monthly -> item.occursByCalendar(today, zone)
                is OutputSchedule.CycleAnchored -> {
                    val occ = state.snapshot.occurrence(s.recurrence, item.createdAt.toLocalDate(zone), today)
                    val done = state.outputSubtasks.count { it.ownerId == item.id && it.isDone }
                    val complete = ProgressRule.isFulfilled(item.progressGoal(state.outputSubtasks.count { it.ownerId == item.id }), item.progressState(done))
                    occ != null && !(complete && occ.projected)
                }
            }
        }) { it.timeMinutes }
    }

    Section(CardKind.SCHEDULE, hazeState) {
        if (schedules.isEmpty()) EmptyRow(stringResource(R.string.empty_none))
        else schedules.forEach { ScheduleRow(it, state, vm) }
    }
    Section(CardKind.INPUT, hazeState) {
        if (inputs.isEmpty()) EmptyRow(stringResource(R.string.empty_none))
        else inputs.forEach { InputRow(it, it.id in checkedIds, state, vm) }
    }
    Section(CardKind.OUTPUT, hazeState) {
        if (outputs.isEmpty()) {
            val cold = state.isColdStart && state.outputs.any { it.schedule is OutputSchedule.CycleAnchored }
            EmptyRow(stringResource(if (cold) R.string.empty_output_cold else R.string.empty_none))
        } else {
            outputs.forEach { OutputRow(it, state, vm) }
            val copy = state.copy
            if (copy != null) Text(copy.lever, style = Fonts.almanacBody(13), color = Ink.text.copy(alpha = 0.55f), modifier = Modifier.padding(top = 2.dp))
        }
    }
}

// ── 일정 ──

@Composable
private fun ScheduleRow(item: ScheduleItemEntity, state: TodayUiState, vm: TodayViewModel) {
    val ink = Ink
    val zone = ZoneId.systemDefault()
    QuickDeletable(kindLabel = stringResource(R.string.section_schedule), title = item.title, onDelete = { vm.deleteSchedule(item) }) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(item.title, style = Fonts.almanacBody(14), color = ink.text)
            item.dayIndex(state.today, zone)?.let { idx ->
                Text(stringResource(R.string.span_day_index, idx, item.spanDays(zone)), style = Fonts.system(11), color = ink.text.copy(alpha = 0.5f))
            }
            Spacer(Modifier.weight(1f))
            val trailing = if (item.isAllDay) stringResource(R.string.all_day) else item.date.atZone(zone).toLocalTime().format(shortTime)
            Text(trailing, style = Fonts.system(12), color = ink.text.copy(alpha = 0.5f))
        }
    }
}

// ── Input ──

@Composable
private fun InputRow(item: InputItemEntity, checked: Boolean, state: TodayUiState, vm: TodayViewModel) {
    val ink = Ink
    val haptic = LocalHapticFeedback.current
    val subtasks = remember(state.inputSubtasks, item.id) { state.inputSubtasks.filter { it.ownerId == item.id }.sortedBy { it.order } }
    val progress = remember(state.inputProgress, item.id, state.today) { state.inputProgress.firstOrNull { it.itemId == item.id && it.occurredOn == state.today } }
    val goal = item.progressGoal(subtasks.size)
    QuickDeletable(kindLabel = stringResource(R.string.section_input), title = item.title, onDelete = { vm.deleteInput(item) }) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(
                Modifier.fillMaxWidth().combinedClickable(onClick = {
                    haptic.performHapticFeedback(HapticFeedbackType.Confirm)
                    vm.toggleInputCheck(item)
                }),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CheckCircle(checked = checked, size = 16.dp, tint = if (checked) ink.text else ink.text.copy(alpha = 0.35f))
                Text(
                    item.title,
                    style = Fonts.almanacBody(14),
                    color = ink.text,
                    textDecoration = if (checked) TextDecoration.LineThrough else null,
                )
                Spacer(Modifier.weight(1f))
                item.timeMinutes?.let { Text(timeOfDayLabel(it), style = Fonts.system(12), color = ink.text.copy(alpha = 0.5f)) }
            }
            if (goal != null) {
                InputProgressControl(item, goal, subtasks, progress, vm, Modifier.padding(start = 26.dp))
            }
        }
    }
}

// ── Output ──

@Composable
private fun OutputRow(item: OutputItemEntity, state: TodayUiState, vm: TodayViewModel) {
    val ink = Ink
    val subtasks = remember(state.outputSubtasks, item.id) { state.outputSubtasks.filter { it.ownerId == item.id }.sortedBy { it.order } }
    val done = subtasks.count { it.isDone }
    val complete = ProgressRule.isFulfilled(item.progressGoal(subtasks.size), item.progressState(done))
    QuickDeletable(kindLabel = stringResource(R.string.section_output), title = item.title, onDelete = { vm.deleteOutput(item) }) {
        Column(Modifier.padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(item.title, style = Fonts.almanacBody(14, bold = true), color = ink.text)
                item.targetDate?.let { DDayBadge(it, state) }
                if (complete) Text(stringResource(R.string.done), style = Fonts.system(11, FontWeight.SemiBold), color = ink.text.copy(alpha = 0.6f))
                Spacer(Modifier.weight(1f))
                item.timeMinutes?.let { Text(timeOfDayLabel(it), style = Fonts.system(12), color = ink.text.copy(alpha = 0.5f)) }
            }
            OutputProgressControl(item, subtasks, vm)
        }
    }
}

@Composable
private fun DDayBadge(target: Instant, state: TodayUiState) {
    val ink = Ink
    val remaining = ChronoUnit.DAYS.between(state.today, target.toLocalDate()).toInt()
    val label = when {
        remaining == 0 -> "D-DAY"
        remaining > 0 -> "D-$remaining"
        else -> "D+${-remaining}"
    }
    val a11y = if (remaining >= 0) stringResource(R.string.dday_until, remaining) else stringResource(R.string.dday_past, -remaining)
    Text(
        label,
        style = Fonts.system(11, FontWeight.SemiBold).copy(fontFeatureSettings = "tnum"),
        color = ink.text.copy(alpha = if (remaining < 0) 0.45f else 0.7f),
        modifier = Modifier
            .background(ink.text.copy(alpha = 0.08f), CircleShape)
            .padding(horizontal = 7.dp, vertical = 3.dp)
            .semantics { contentDescription = a11y },
    )
}

// ── 공용 ──

/** iOS quickDeletable — 길게 누르기(0.45s) → 확인 다이얼로그. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun QuickDeletable(kindLabel: String, title: String, onDelete: () -> Unit, content: @Composable () -> Unit) {
    val haptic = LocalHapticFeedback.current
    var confirm by remember { mutableStateOf(false) }
    androidx.compose.foundation.layout.Box(
        Modifier.combinedClickable(
            onClick = {},
            onLongClick = {
                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                confirm = true
            },
        ),
    ) { content() }
    if (confirm) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            title = { Text("$kindLabel 「$title」") },
            text = { Text(stringResource(R.string.delete_confirm_body)) },
            confirmButton = { TextButton(onClick = { confirm = false; onDelete() }) { Text(stringResource(R.string.delete), color = Ink.danger) } },
            dismissButton = { TextButton(onClick = { confirm = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

/** checkmark.circle.fill / circle */
@Composable
fun CheckCircle(checked: Boolean, size: Dp, tint: Color, modifier: Modifier = Modifier) {
    val paper = Ink.paper
    Canvas(modifier.size(size)) {
        val r = this.size.minDimension / 2
        val c = center
        if (checked) {
            drawCircle(tint, r, c)
            val p = Path().apply {
                moveTo(c.x - r * 0.45f, c.y + r * 0.02f)
                lineTo(c.x - r * 0.12f, c.y + r * 0.36f)
                lineTo(c.x + r * 0.5f, c.y - r * 0.32f)
            }
            drawPath(p, paper, style = Stroke(width = r * 0.22f, cap = StrokeCap.Round))
        } else {
            drawCircle(tint, r - 1.dp.toPx() / 2, c, style = Stroke(width = 1.dp.toPx()))
        }
    }
}

/** checkmark.square.fill / square */
@Composable
fun CheckSquare(checked: Boolean, size: Dp, tint: Color, modifier: Modifier = Modifier) {
    val paper = Ink.paper
    Canvas(modifier.size(size)) {
        val s = this.size.minDimension
        val rad = androidx.compose.ui.geometry.CornerRadius(s * 0.2f)
        if (checked) {
            drawRoundRect(tint, cornerRadius = rad)
            val p = Path().apply {
                moveTo(s * 0.26f, s * 0.52f)
                lineTo(s * 0.43f, s * 0.7f)
                lineTo(s * 0.76f, s * 0.34f)
            }
            drawPath(p, paper, style = Stroke(width = s * 0.11f, cap = StrokeCap.Round))
        } else {
            val inset = 1.dp.toPx() / 2
            drawRoundRect(tint, topLeft = androidx.compose.ui.geometry.Offset(inset, inset),
                size = androidx.compose.ui.geometry.Size(s - inset * 2, s - inset * 2), cornerRadius = rad, style = Stroke(width = 1.dp.toPx()))
        }
    }
}
