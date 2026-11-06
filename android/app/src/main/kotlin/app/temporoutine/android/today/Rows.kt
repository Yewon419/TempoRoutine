// 템포루틴 Android — 오늘 3구획 행 (iOS TodayView scheduleSection/inputSection/outputSection 이식, 은필 분기)
// 일정 행 = 조회 전용(편집 시트 P1). + 버튼 숨김(추가 시트 P1). 길게 누르기 삭제는 유지.

package app.temporoutine.android.today

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
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
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.AwaitPointerEventScope
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.zIndex
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
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
import app.temporoutine.android.data.orderedInputs
import app.temporoutine.android.data.sortedByTimeOfDay
import app.temporoutine.android.data.spanDays
import app.temporoutine.android.data.toLocalDate
import app.temporoutine.android.theme.rememberReduceMotion
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.core.InputSchedule
import app.temporoutine.core.OutputProgressKind
import app.temporoutine.core.OutputSchedule
import app.temporoutine.core.ProgressRule
import dev.chrisbanes.haze.HazeState
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.ChronoUnit

internal val shortTime: DateTimeFormatter = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)

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
        orderedInputs(state.inputs.filter { item ->
            when (val s = item.schedule) {
                InputSchedule.Once -> item.onceShows(today, zone) || item.id in checkedIds
                InputSchedule.Daily, InputSchedule.Weekly, InputSchedule.Monthly -> item.occursByCalendar(today, zone)
                is InputSchedule.CycleAnchored ->
                    state.snapshot.occurrence(s.recurrence, item.createdAt.toLocalDate(zone), today) != null || item.id in checkedIds
            }
        }) { it }
    }
    // 루틴 행 중심 y(루트 좌표) — 놓은 자리 계산용. 프레임마다 쓰이니 상태가 아닌 평범한 맵(iOS RowMidStore).
    val inputRowMids = remember { mutableMapOf<String, Float>() }
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
        else inputs.forEach { item ->
            InputRow(item, item.id in checkedIds, state, vm, inputRowMids) { landing ->
                val index = inputs.count { it.id != item.id && (inputRowMids[it.id] ?: Float.POSITIVE_INFINITY) < landing }
                vm.moveInput(item, index, inputs)
            }
        }
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
private fun InputRow(
    item: InputItemEntity, checked: Boolean, state: TodayUiState, vm: TodayViewModel,
    rowMids: MutableMap<String, Float>, onDrop: (landing: Float) -> Unit,
) {
    val ink = Ink
    val haptic = LocalHapticFeedback.current
    val subtasks = remember(state.inputSubtasks, item.id) { state.inputSubtasks.filter { it.ownerId == item.id }.sortedBy { it.order } }
    val progress = remember(state.inputProgress, item.id, state.today) { state.inputProgress.firstOrNull { it.itemId == item.id && it.occurredOn == state.today } }
    val goal = item.progressGoal(subtasks.size)
    ReorderableQuickRow(
        kindLabel = stringResource(R.string.section_input), title = item.title, onDelete = { vm.deleteInput(item) },
        onMeasured = { mid -> rowMids[item.id] = mid },
        liftedMid = { rowMids[item.id] ?: 0f },
        onDrop = onDrop,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(
                Modifier.fillMaxWidth().combinedClickable(onClick = {
                    haptic.performHapticFeedback(HapticFeedbackType.Confirm)
                    vm.toggleInputCheck(item, state.today)
                }),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                StampCheck(checked = checked)   // 먹 도장 체크(iOS 은필 v2 2026-09-07)
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
                InputProgressControl(item, goal, subtasks, progress, vm, state.today, Modifier.padding(start = 26.dp))
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
    // iOS OutputItem.isSingleCheck — 「체크만」 또는 항목 없는 체크리스트
    val singleCheck = item.kind == OutputProgressKind.CHECK_ONLY || (item.kind == OutputProgressKind.SUBTASKS && subtasks.isEmpty())
    QuickDeletable(kindLabel = stringResource(R.string.section_output), title = item.title, onDelete = { vm.deleteOutput(item) }) {
        Column(Modifier.padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                if (singleCheck) SingleCheckButton(item, vm)
                else Text(item.title, style = Fonts.almanacBody(14, bold = true), color = ink.text)
                item.targetDate?.let { DDayBadge(it, state.today) }
                if (complete && !singleCheck) Text(stringResource(R.string.done), style = Fonts.system(11, FontWeight.SemiBold), color = ink.text.copy(alpha = 0.6f))
                Spacer(Modifier.weight(1f))
                item.timeMinutes?.let { Text(timeOfDayLabel(it), style = Fonts.system(12), color = ink.text.copy(alpha = 0.5f)) }
            }
            if (!singleCheck) OutputProgressControl(item, subtasks, vm)
        }
    }
}

/** iOS singleCheckButton — 제목 앞 먹 도장(2026-09-23 베타), 제목 글씨도 눌린다(2026-10-23 베타). 저장은 percent 0↔1. */
@Composable
private fun SingleCheckButton(item: OutputItemEntity, vm: TodayViewModel) {
    val haptic = LocalHapticFeedback.current
    val done = item.percent >= 1
    val stateText = stringResource(if (done) R.string.done else R.string.not_done)
    Row(
        Modifier
            .combinedClickable(onClick = {
                haptic.performHapticFeedback(if (done) HapticFeedbackType.TextHandleMove else HapticFeedbackType.Confirm)
                vm.updateOutput(item.copy(percent = if (done) 0.0 else 1.0))
            })
            .semantics(mergeDescendants = true) { stateDescription = stateText },
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StampCheck(checked = done)
        Text(item.title, style = Fonts.almanacBody(14, bold = true), color = Ink.text)
    }
}

@Composable
fun DDayBadge(target: Instant, from: LocalDate) {
    val ink = Ink
    val remaining = ChronoUnit.DAYS.between(from, target.toLocalDate()).toInt()
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

/** iOS quickDeletable — 길게 누르기 → 확인 다이얼로그.
 *  Initial 패스로 본다 — 종전 combinedClickable(Main 패스)은 자식 탭이 up을 먼저 먹어, 길게 눌렀다 떼면 체크가 토글되고
 *  다이얼로그는 안 떴다(2026-11-06 에뮬레이터 실측). 스크린리더용 길게 누르기 동작은 semantics로 유지. */
@Composable
fun QuickDeletable(kindLabel: String, title: String, onDelete: () -> Unit, content: @Composable () -> Unit) {
    val haptic = LocalHapticFeedback.current
    var confirm by remember { mutableStateOf(false) }
    val deleteLabel = stringResource(R.string.delete)
    androidx.compose.foundation.layout.Box(
        Modifier
            .semantics { onLongClick(label = deleteLabel) { confirm = true; true } }
            .pointerInput(Unit) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                    if (!awaitLongPressInitial(down)) return@awaitEachGesture
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    confirm = true
                    // 뗄 때까지 전부 소비 — 자식 탭이 같이 눌리지 않게
                    do {
                        val event = awaitPointerEvent(PointerEventPass.Initial)
                        event.changes.forEach { it.consume() }
                    } while (event.changes.any { it.pressed })
                }
            },
    ) { content() }
    if (confirm) DeleteConfirmDialog(kindLabel, title, onDismiss = { confirm = false }, onDelete = onDelete)
}

/** Initial 패스 길게 누르기 대기 — 성립하면 true. 그 전에 떼거나 슬롭을 넘으면(스크롤) false. */
private suspend fun AwaitPointerEventScope.awaitLongPressInitial(down: PointerInputChange): Boolean =
    withTimeoutOrNull(viewConfiguration.longPressTimeoutMillis) {
        var c: PointerInputChange? = down
        while (c != null && c.pressed && !c.isConsumed && (c.position - down.position).getDistance() <= viewConfiguration.touchSlop) {
            c = awaitPointerEvent(PointerEventPass.Initial).changes.firstOrNull { it.id == down.id }
        }
        false
    } ?: true

/** iOS ReorderableQuickRow(2026-11-05 베타 "루틴 꾹누르면 순서 변경") — 길게 누르면 행이 들리고, 끌면 순서 변경,
 *  거의 안 움직이고 떼면 종전 삭제 확인. 들린 동안 이벤트를 소비해 바깥 스크롤이 따라오지 않는다. */
@Composable
private fun ReorderableQuickRow(
    kindLabel: String, title: String, onDelete: () -> Unit,
    onMeasured: (mid: Float) -> Unit, liftedMid: () -> Float, onDrop: (landing: Float) -> Unit,
    content: @Composable () -> Unit,
) {
    val haptic = LocalHapticFeedback.current
    val tapSlop = with(LocalDensity.current) { 10.dp.toPx() }
    var confirm by remember { mutableStateOf(false) }
    var lifted by remember { mutableStateOf(false) }
    var dragY by remember { mutableFloatStateOf(0f) }
    var startMid by remember { mutableFloatStateOf(0f) }
    // pointerInput(Unit)은 첫 합성의 람다를 붙든다 — 목록이 바뀐 뒤의 onDrop을 부르도록
    val currentDrop by rememberUpdatedState(onDrop)
    val currentMid by rememberUpdatedState(liftedMid)
    val deleteLabel = stringResource(R.string.delete)
    androidx.compose.foundation.layout.Box(
        Modifier
            .onGloballyPositioned { onMeasured(it.positionInRoot().y + it.size.height / 2f) }
            .semantics { onLongClick(label = deleteLabel) { confirm = true; true } }
            .zIndex(if (lifted) 1f else 0f)
            .graphicsLayer {
                translationY = dragY
                val s = if (lifted) 1.02f else 1f
                scaleX = s; scaleY = s
            }
            // Initial 패스 — 자식(체크·타이머 버튼)보다 먼저 본다. 들린 뒤엔 전부 소비해 자식 탭·바깥 스크롤을 끊는다.
            // (detectDragGesturesAfterLongPress는 Main 패스라 제자리에서 떼면 자식이 up을 먼저 먹어 체크가 토글되고 다이얼로그가 안 떴다.)
            .pointerInput(Unit) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                    if (!awaitLongPressInitial(down)) return@awaitEachGesture
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    startMid = currentMid()
                    dragY = 0f
                    lifted = true
                    var ended = false
                    try {
                        while (true) {
                            val event = awaitPointerEvent(PointerEventPass.Initial)
                            val c = event.changes.firstOrNull { it.id == down.id }
                            event.changes.forEach { it.consume() }
                            if (c == null || !c.pressed) { ended = c != null; break }
                            dragY += c.position.y - c.previousPosition.y
                        }
                    } finally {
                        val dy = dragY
                        lifted = false
                        dragY = 0f
                        if (ended) {
                            if (kotlin.math.abs(dy) < tapSlop) confirm = true
                            else {
                                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                currentDrop(startMid + dy)
                            }
                        }
                    }
                }
            },
    ) { content() }
    if (confirm) DeleteConfirmDialog(kindLabel, title, onDismiss = { confirm = false }, onDelete = onDelete)
}

@Composable
private fun DeleteConfirmDialog(kindLabel: String, title: String, onDismiss: () -> Unit, onDelete: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("$kindLabel 「$title」") },
        text = { Text(stringResource(R.string.delete_confirm_body)) },
        confirmButton = { TextButton(onClick = { onDismiss(); onDelete() }) { Text(stringResource(R.string.delete), color = Ink.danger) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

/** 먹 도장 체크(iOS Almanac.swift StampCheck) — 22 원 안에 먹이 차오르고 체크가 찍힌다(루틴 행). 지우면 원만 남는다.
 *  spring(response 0.32, damping 0.62) → k = (2π/0.32)² ≈ 385.5. 상태는 행의 접근성 값이 말한다. */
@Composable
fun StampCheck(checked: Boolean, modifier: Modifier = Modifier) {
    val ink = Ink
    val reduceMotion = rememberReduceMotion()
    val t by animateFloatAsState(
        targetValue = if (checked) 1f else 0f,
        animationSpec = if (reduceMotion) snap() else spring(dampingRatio = 0.62f, stiffness = 385.5f),
        label = "stampCheck",
    )
    Canvas(modifier.size(22.dp)) {
        val r = size.minDimension / 2
        val c = center
        val rim = 1.4.dp.toPx()
        drawCircle(ink.text.copy(alpha = 0.35f), r - rim / 2, c, style = Stroke(width = rim))
        drawCircle(ink.text, r * (0.01f + 0.99f * t.coerceAtLeast(0f)), c)
        // 체크 = SF checkmark 11 bold 대용 — 불투명도·크기 0.5→1·회전 −12°→0
        val shown = t.coerceIn(0f, 1f)
        withTransform({
            rotate(-12f * (1f - t), c)
            scale(0.5f + 0.5f * t, 0.5f + 0.5f * t, c)
        }) {
            val p = Path().apply {
                moveTo(c.x - 4.2.dp.toPx(), c.y + 0.2.dp.toPx())
                lineTo(c.x - 1.2.dp.toPx(), c.y + 3.2.dp.toPx())
                lineTo(c.x + 4.4.dp.toPx(), c.y - 3.0.dp.toPx())
            }
            drawPath(p, ink.paper.copy(alpha = shown), style = Stroke(width = 1.9.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
        }
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
