// 템포루틴 Android — 진행 컨트롤 (iOS InputProgressControl / SessionProgressControl / TimerProgressControl / outputProgress 이식)
// Input = 그날 레코드에, Output = 아이템에 값이 있다. 판정은 tempocore ProgressRule 한 곳.
// 타이머·스톱워치는 앱 안에서만 진행(Live Activity 없음 — Phase 1 가정 4).

package app.temporoutine.android.today

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import app.temporoutine.android.R
import app.temporoutine.android.data.InputItemEntity
import app.temporoutine.android.data.InputProgressEntity
import app.temporoutine.android.data.InputSubtaskEntity
import app.temporoutine.android.data.OutputItemEntity
import app.temporoutine.android.data.OutputSubtaskEntity
import app.temporoutine.android.data.TimerBacking
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.core.OutputProgressKind
import app.temporoutine.core.ProgressGoal
import kotlinx.coroutines.delay
import java.time.Instant
import kotlin.math.roundToInt

// ── Input ──

@Composable
fun InputProgressControl(
    item: InputItemEntity, goal: ProgressGoal, subtasks: List<InputSubtaskEntity>,
    progress: InputProgressEntity?, vm: TodayViewModel, modifier: Modifier = Modifier,
) {
    val ink = Ink
    val haptic = LocalHapticFeedback.current
    val current = progress ?: InputProgressEntity(itemId = item.id, occurredOn = vm.state.value.today)
    Box(modifier) {
        when (goal.kind) {
            OutputProgressKind.CHECK_ONLY -> Unit   // Input의 "체크만"은 progressKind == null로 표현 — 도달 불가
            OutputProgressKind.SUBTASKS -> Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                val done = current.doneSubtaskIds
                subtasks.forEach { sub ->
                    val isDone = sub.id in done
                    Row(
                        Modifier.fillMaxWidth().clickable {
                            haptic.performHapticFeedback(HapticFeedbackType.Confirm)
                            val live = subtasks.map { it.id }.toSet()
                            vm.updateInputProgress(item) { p ->
                                val next = (p.doneSubtaskIds intersect live).toMutableSet()
                                if (isDone) next.remove(sub.id) else next.add(sub.id)
                                p.withDoneSubtaskIds(next)
                            }
                        }.padding(vertical = 5.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        CheckCircle(isDone, 12.dp, if (isDone) ink.text else ink.text.copy(alpha = 0.3f))
                        Text(sub.title, style = Fonts.system(13), color = ink.text.copy(alpha = if (isDone) 0.5f else 0.8f),
                            textDecoration = if (isDone) TextDecoration.LineThrough else null)
                    }
                }
            }
            OutputProgressKind.SESSIONS -> SessionProgressControl(current.loggedSessions, goal.targetSessions) { logged, completed ->
                haptic.performHapticFeedback(if (completed) HapticFeedbackType.Confirm else HapticFeedbackType.TextHandleMove)
                vm.updateInputProgress(item) { it.copy(loggedSessions = logged) }
            }
            OutputProgressKind.PERCENT -> PercentControl(current.percent, labelWidth = 40.dp) { v ->
                vm.updateInputProgress(item) { it.copy(percent = v.toDouble()) }
            }
            OutputProgressKind.TIMER, OutputProgressKind.STOPWATCH -> TimerProgressControl(
                backing = current, isTimer = goal.kind == OutputProgressKind.TIMER, targetSeconds = goal.targetSeconds ?: 0,
                onToggle = { running, now ->
                    vm.updateInputProgress(item) { p ->
                        if (running) p.copy(elapsedAccumSeconds = p.elapsedSeconds(now), timerStartedAt = null)
                        else p.copy(timerStartedAt = now)
                    }
                },
                onReset = { vm.updateInputProgress(item) { it.copy(elapsedAccumSeconds = 0.0, timerStartedAt = null) } },
            )
        }
    }
}

// ── Output ──

@Composable
fun OutputProgressControl(item: OutputItemEntity, subtasks: List<OutputSubtaskEntity>, vm: TodayViewModel) {
    val ink = Ink
    val haptic = LocalHapticFeedback.current
    when (item.kind) {
        OutputProgressKind.CHECK_ONLY -> {
            val done = item.percent >= 1
            Row(
                Modifier.fillMaxWidth().clickable {
                    haptic.performHapticFeedback(if (done) HapticFeedbackType.TextHandleMove else HapticFeedbackType.Confirm)
                    vm.updateOutput(item.copy(percent = if (done) 0.0 else 1.0))
                },
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CheckCircle(done, 16.dp, if (done) ink.text else ink.text.copy(alpha = 0.35f))
                Text(stringResource(if (done) R.string.done else R.string.check), style = Fonts.system(13), color = ink.text.copy(alpha = if (done) 1f else 0.6f))
                Spacer(Modifier.weight(1f))
            }
        }
        OutputProgressKind.SUBTASKS -> Column {
            subtasks.forEach { sub ->
                Row(
                    Modifier.fillMaxWidth().clickable {
                        haptic.performHapticFeedback(HapticFeedbackType.Confirm)
                        vm.toggleOutputSubtask(sub)
                    }.padding(vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CheckSquare(sub.isDone, 14.dp, if (sub.isDone) ink.text else ink.text.copy(alpha = 0.35f))
                    Text(sub.title, style = Fonts.almanacBody(13), color = ink.text,
                        textDecoration = if (sub.isDone) TextDecoration.LineThrough else null)
                    Spacer(Modifier.weight(1f))
                }
            }
        }
        OutputProgressKind.SESSIONS -> SessionProgressControl(item.loggedSessions, item.targetSessions) { logged, completed ->
            haptic.performHapticFeedback(if (completed) HapticFeedbackType.Confirm else HapticFeedbackType.TextHandleMove)
            vm.updateOutput(item.copy(loggedSessions = logged))
        }
        OutputProgressKind.PERCENT -> PercentControl(item.percent, labelWidth = 44.dp) { v -> vm.updateOutput(item.copy(percent = v.toDouble())) }
        OutputProgressKind.TIMER, OutputProgressKind.STOPWATCH -> TimerProgressControl(
            backing = item, isTimer = item.kind == OutputProgressKind.TIMER, targetSeconds = item.targetSeconds ?: 0,
            onToggle = { running, now ->
                vm.updateOutput(
                    if (running) item.copy(elapsedAccumSeconds = item.elapsedSeconds(now), timerStartedAt = null)
                    else item.copy(timerStartedAt = now),
                )
            },
            onReset = { vm.updateOutput(item.copy(elapsedAccumSeconds = 0.0, timerStartedAt = null)) },
        )
    }
}

// ── 공용 컨트롤 ──

/** 세션 — 목표 1~8은 점 행, 그 외는 카운터 행. 콜백 (logged, completed) */
@Composable
fun SessionProgressControl(logged: Int, target: Int, onChange: (Int, Boolean) -> Unit) {
    val ink = Ink
    fun completed(v: Int) = target > 0 && v >= target
    if (target in 1..8) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            for (index in 1..target) {
                val filled = index <= logged
                Box(Modifier.size(36.dp, 40.dp).clickable {
                    val next = if (logged == index) index - 1 else index
                    onChange(next, completed(next))
                }, contentAlignment = Alignment.Center) {
                    Canvas(Modifier.size(20.dp)) {
                        if (filled) drawCircle(ink.text)
                        else drawCircle(ink.text.copy(alpha = 0.3f), style = Stroke(width = 1.5.dp.toPx()))
                    }
                }
            }
            Text("$logged / $target", style = Fonts.system(13).copy(fontFeatureSettings = "tnum"), color = ink.text.copy(alpha = 0.55f), modifier = Modifier.padding(start = 6.dp))
        }
    } else {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            val label = if (target > 0) stringResource(R.string.sessions_of, logged.toString(), target.toString()) else stringResource(R.string.sessions_only, logged.toString())
            Text(label, style = Fonts.system(13).copy(fontFeatureSettings = "tnum"), color = ink.text.copy(alpha = 0.7f))
            if (target > 0) {
                Box(Modifier.weight(1f).height(5.dp).clip(CircleShape).background(ink.text.copy(alpha = 0.08f))) {
                    val fraction = minOf(1f, logged.toFloat() / target)
                    Box(Modifier.fillMaxWidth(fraction).height(5.dp).background(ink.text.copy(alpha = 0.55f), CircleShape))
                }
            } else Spacer(Modifier.weight(1f))
            PlusMinus(minus = { val n = maxOf(0, logged - 1); onChange(n, completed(n)) }, plus = { val n = logged + 1; onChange(n, completed(n)) })
        }
    }
}

@Composable
private fun PlusMinus(minus: () -> Unit, plus: () -> Unit) {
    val ink = Ink
    Row {
        for ((isPlus, action) in listOf(false to minus, true to plus)) {
            Box(Modifier.size(40.dp).clickable(onClick = action), contentAlignment = Alignment.Center) {
                Canvas(Modifier.size(20.dp)) {
                    val r = size.minDimension / 2
                    drawCircle(ink.text.copy(alpha = 0.6f), r - 1.dp.toPx() / 2, style = Stroke(1.dp.toPx()))
                    val w = 1.6.dp.toPx()
                    drawLine(ink.text.copy(alpha = 0.6f), Offset(center.x - r * 0.45f, center.y), Offset(center.x + r * 0.45f, center.y), w, StrokeCap.Round)
                    if (isPlus) drawLine(ink.text.copy(alpha = 0.6f), Offset(center.x, center.y - r * 0.45f), Offset(center.x, center.y + r * 0.45f), w, StrokeCap.Round)
                }
            }
        }
    }
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun PercentControl(percent: Double, labelWidth: androidx.compose.ui.unit.Dp, onChange: (Float) -> Unit) {
    val ink = Ink
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        // M3 기본 슬라이더는 트랙이 두껍고 손잡이가 커서 은필의 가는 선과 부딪힌다 —
        // iOS 시스템 슬라이더 비례(트랙 3dp · 손잡이 지름 16dp)로 얇게 그린다(2026-09-07 대표님 위임 결정).
        Slider(
            value = percent.toFloat(), onValueChange = onChange, valueRange = 0f..1f,
            colors = SliderDefaults.colors(thumbColor = ink.text, activeTrackColor = ink.text, inactiveTrackColor = ink.text.copy(alpha = 0.15f)),
            track = { state ->
                val fraction = ((state.value - state.valueRange.start) / (state.valueRange.endInclusive - state.valueRange.start)).coerceIn(0f, 1f)
                Canvas(Modifier.fillMaxWidth().height(3.dp)) {
                    val r = size.height / 2f
                    drawRoundRect(ink.text.copy(alpha = 0.15f), cornerRadius = CornerRadius(r))
                    if (fraction > 0f) drawRoundRect(ink.text, size = Size(size.width * fraction, size.height), cornerRadius = CornerRadius(r))
                }
            },
            thumb = { Box(Modifier.size(16.dp).background(ink.text, CircleShape)) },
            modifier = Modifier.weight(1f),
        )
        Text("${(percent * 100).roundToInt()}%", style = Fonts.system(13).copy(fontFeatureSettings = "tnum"), color = ink.text.copy(alpha = 0.7f),
            textAlign = TextAlign.End, modifier = Modifier.width(labelWidth))
    }
}

/** 타이머(카운트다운)·스톱워치(카운트업). 실행 중엔 1초 틱으로 표시만 갱신, 저장은 일시정지·초기화 때만. */
@Composable
fun TimerProgressControl(backing: TimerBacking, isTimer: Boolean, targetSeconds: Int, onToggle: (running: Boolean, now: Instant) -> Unit, onReset: () -> Unit) {
    val ink = Ink
    val running = backing.isTimerRunning
    var nowMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(running) {
        while (running) { nowMs = System.currentTimeMillis(); delay(1000) }
    }
    val elapsed = backing.elapsedSeconds(Instant.ofEpochMilli(nowMs))
    val shown = if (isTimer) maxOf(0.0, targetSeconds - elapsed) else elapsed
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(32.dp).clickable { onToggle(running, Instant.now()) }, contentAlignment = Alignment.Center) {
            Canvas(Modifier.size(28.dp)) {
                val c = ink.text.copy(alpha = if (running) 0.9f else 0.7f)
                drawCircle(c)
                val r = size.minDimension / 2
                if (running) {
                    val w = r * 0.18f
                    drawRoundRect(ink.paper, Offset(center.x - r * 0.38f, center.y - r * 0.4f), androidx.compose.ui.geometry.Size(w, r * 0.8f))
                    drawRoundRect(ink.paper, Offset(center.x + r * 0.2f, center.y - r * 0.4f), androidx.compose.ui.geometry.Size(w, r * 0.8f))
                } else {
                    val p = Path().apply {
                        moveTo(center.x - r * 0.28f, center.y - r * 0.42f)
                        lineTo(center.x + r * 0.46f, center.y)
                        lineTo(center.x - r * 0.28f, center.y + r * 0.42f)
                        close()
                    }
                    drawPath(p, ink.paper)
                }
            }
        }
        Text(formatClock(shown), style = Fonts.system(20, FontWeight.SemiBold).copy(fontFeatureSettings = "tnum"), color = ink.text)
        if (isTimer) Text("/ " + formatClock(targetSeconds.toDouble()), style = Fonts.system(13).copy(fontFeatureSettings = "tnum"), color = ink.text.copy(alpha = 0.5f))
        Spacer(Modifier.weight(1f))
        if (backing.accumSeconds > 0 || running) {
            Text(stringResource(R.string.timer_reset), style = Fonts.system(12), color = ink.text.copy(alpha = 0.45f), modifier = Modifier.clickable(onClick = onReset).padding(4.dp))
        }
    }
}

/** H:MM:SS(≥1시간) / M:SS */
fun formatClock(seconds: Double): String {
    val total = seconds.toInt()
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}
