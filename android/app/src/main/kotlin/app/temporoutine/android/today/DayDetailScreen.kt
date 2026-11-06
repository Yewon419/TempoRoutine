// 템포루틴 Android — 하루 상세(iOS DayDetailView). 오늘 탭 「전날·다음날」 화살표(2026-10-27 베타)가 여는 화면.
// 화면 안에서 날짜를 옮기면 offset만 움직인다(iOS 2026-08-01) — 뒤로가기 한 번이면 오늘 탭.
// P0 범위 밖이라 없는 것: 구획 + 추가 시트·일정 수정 시트·기기 캘린더 오버레이·자기돌봄 줄(AxisProfile 미이식)·테마 지면.
@file:OptIn(ExperimentalFoundationApi::class)

package app.temporoutine.android.today

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.temporoutine.android.R
import app.temporoutine.android.cycle.seasonCopy
import app.temporoutine.android.data.InputItemEntity
import app.temporoutine.android.data.OutputItemEntity
import app.temporoutine.android.data.ScheduleItemEntity
import app.temporoutine.android.data.dayIndex
import app.temporoutine.android.data.occurs
import app.temporoutine.android.data.occursByCalendar
import app.temporoutine.android.data.onceShows
import app.temporoutine.android.data.orderedInputs
import app.temporoutine.android.data.sortedByTimeOfDay
import app.temporoutine.android.data.spanDays
import app.temporoutine.android.data.toLocalDate
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.MatteSwitchTrack
import app.temporoutine.android.theme.SeasonLight
import app.temporoutine.android.theme.chromeGlass
import app.temporoutine.core.InputSchedule
import app.temporoutine.core.KoreanHolidays
import app.temporoutine.core.OutputProgressKind
import app.temporoutine.core.OutputSchedule
import app.temporoutine.core.ProgressRule
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.rememberHazeState
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** 하단 날짜 이동 바 높이 = 44 터치 + 위아래 10(iOS dayNavBar) */
private val DAY_NAV_BAR_HEIGHT = 64.dp

@Composable
fun DayDetailScreen(anchorDay: LocalDate, state: TodayUiState, vm: TodayViewModel, hazeState: HazeState, bottomPadding: Dp, onBack: () -> Unit) {
    val ink = Ink
    val haptic = LocalHapticFeedback.current
    val density = LocalDensity.current
    var dayOffset by rememberSaveable(anchorDay) { mutableIntStateOf(0) }
    val day = anchorDay.plusDays(dayOffset.toLong())
    val isFuture = day > state.today
    val move: (Int) -> Unit = { days ->
        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)   // 월 이동과 같은 계층(확정 아님)
        dayOffset += days
    }
    BackHandler(onBack = onBack)
    // 이동 바는 지면+스크롤 콘텐츠를 흐린다 — 오늘 탭 컴팩트 바와 같은 층 분리(바는 소스 바깥)
    val navHaze = rememberHazeState()
    val swipeMin = with(density) { 50.dp.toPx() }
    val systemBackEdge = with(density) { 40.dp.toPx() }
    Box(Modifier.fillMaxSize().background(ink.paper)) {
        Box(Modifier.fillMaxSize().hazeSource(navHaze)) {
            SeasonLight(phase = state.snapshot.phaseInfo(day)?.phase, modifier = Modifier.fillMaxSize().hazeSource(hazeState))
            Column(
                Modifier
                    .fillMaxSize()
                    // 슬라이드로도 날짜 이동(iOS 2026-08-01). 좌측 가장자리에서 시작한 드래그는 시스템 뒤로가기 몫.
                    .pointerInput(Unit) {
                        var startX = 0f
                        var total = 0f
                        detectHorizontalDragGestures(
                            onDragStart = { startX = it.x; total = 0f },
                            onDragEnd = {
                                if (startX > systemBackEdge) {
                                    if (total < -swipeMin) move(1) else if (total > swipeMin) move(-1)
                                }
                            },
                        ) { change, dx ->
                            change.consume()
                            total += dx
                        }
                    }
                    .verticalScroll(rememberScrollState())
                    .windowInsetsPadding(WindowInsets.statusBars)
                    .padding(20.dp)
                    .padding(bottom = bottomPadding + DAY_NAV_BAR_HEIGHT),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                DayStepArrow(left = true, label = stringResource(R.string.day_back), width = 44.dp, onClick = onBack)
                DayHeader(day, state)
                DayPeriodToggle(isOn = state.periodDays.any { it.day == day }, enabled = !isFuture) { vm.togglePeriod(day) }
                DaySections(day, state, vm, hazeState)
                // 뒤늦은 기록·자정 넘긴 마무리 — 지난 날짜에도 체크인. 미래는 기록하지 않는다(iOS §5.5.4).
                if (!isFuture) key(day) {
                    CheckInCard(
                        day = day, record = state.checkIns.firstOrNull { it.day == day }, signals = state.trackedSignals,
                        phaseInfo = state.snapshot.phaseInfo(day), vm = vm, hazeState = hazeState, isToday = day == state.today,
                    )
                }
            }
        }
        DayNavBar(day, move, Modifier.align(Alignment.BottomCenter).padding(bottom = bottomPadding).chromeGlass(navHaze))
    }
}

/** 전날·다음날 바(iOS dayNavBar) — 화살표 + 가운데에 지금 보는 날짜 */
@Composable
private fun DayNavBar(day: LocalDate, move: (Int) -> Unit, modifier: Modifier) {
    val pattern = stringResource(R.string.day_nav_pattern)
    val locale = Locale.getDefault()
    Row(
        modifier.fillMaxWidth().height(DAY_NAV_BAR_HEIGHT).padding(horizontal = 24.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        DayStepArrow(left = true, label = stringResource(R.string.day_prev), width = 44.dp) { move(-1) }
        Spacer(Modifier.weight(1f))
        Text(day.format(DateTimeFormatter.ofPattern(pattern, locale)), style = Fonts.almanacBody(13), color = Ink.text.copy(alpha = 0.6f))
        Spacer(Modifier.weight(1f))
        DayStepArrow(left = false, label = stringResource(R.string.day_next), width = 44.dp) { move(1) }
    }
}

/** 셰브론 버튼 — 오늘 탭 생리 기록 줄(34 폭)·하루 상세 이동 바(44 폭)·뒤로 공용. 높이는 터치 44. */
@Composable
fun DayStepArrow(left: Boolean, label: String, width: Dp, onClick: () -> Unit) {
    Box(
        Modifier.size(width, 44.dp).semantics { contentDescription = label }.clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        ChevronGlyph(left, Ink.text.copy(alpha = 0.75f))
    }
}

@Composable
private fun ChevronGlyph(left: Boolean, color: Color) {
    Canvas(Modifier.size(7.dp, 12.dp)) {
        val p = Path().apply {
            if (left) { moveTo(size.width, 0f); lineTo(0f, size.height / 2); lineTo(size.width, size.height) }
            else { moveTo(0f, 0f); lineTo(size.width, size.height / 2); lineTo(0f, size.height) }
        }
        drawPath(p, color, style = Stroke(width = 1.8.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

// ── 상단: 날짜 표제 + 공휴일 + 계절·일차 ──

@Composable
private fun DayHeader(day: LocalDate, state: TodayUiState) {
    val ink = Ink
    val locale = Locale.getDefault()
    val pattern = stringResource(R.string.day_detail_header_pattern)
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("${day.dayOfMonth}", style = Fonts.almanac(56), color = ink.text, modifier = Modifier.alignByBaseline())
            Text(
                day.format(DateTimeFormatter.ofPattern(pattern, locale)),
                style = Fonts.almanacBody(15), color = ink.text.copy(alpha = 0.6f), modifier = Modifier.alignByBaseline(),
            )
        }
        // 내장 공휴일 표는 한국 지역 전용(iOS usesBuiltInKoreanHolidays, 캘린더와 같은 게이트)
        val holidays = if (locale.country == "KR") KoreanHolidays.holidays(day) else emptyList()
        if (holidays.isNotEmpty()) {
            Text(
                holidays.joinToString(" · ") { it.name },
                style = Fonts.almanacBody(13),
                color = if (holidays.any { it.isPublic }) ink.holiday else ink.text.copy(alpha = 0.55f),
            )
        }
        val info = state.snapshot.phaseInfo(day)
        if (info != null) {
            val suffix = if (info.projected) stringResource(R.string.calendar_projected_suffix) else ""
            Text(
                stringResource(R.string.day_detail_phase, seasonCopy(info.phase).name, info.dayInPhase) + suffix,
                style = Fonts.almanacBody(13),
                color = ink.season(info.phase).copy(alpha = if (info.projected) 0.7f else 1f),
            )
        } else {
            Text(stringResource(R.string.today_cold_title), style = Fonts.almanacBody(13), color = ink.text.copy(alpha = 0.5f))
        }
    }
}

/** 생리 기록 토글(iOS periodToggle) — 행 전체가 눌린다(CLAUDE.md 토글 행 규칙). 미래는 막는다. */
@Composable
private fun DayPeriodToggle(isOn: Boolean, enabled: Boolean, onToggle: () -> Unit) {
    val haptic = LocalHapticFeedback.current
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 44.dp)
            .toggleable(
                value = isOn,
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                enabled = enabled,
                role = Role.Switch,
                onValueChange = {
                    haptic.performHapticFeedback(HapticFeedbackType.Confirm)
                    onToggle()
                },
            )
            .alpha(if (enabled) 1f else 0.4f),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(stringResource(R.string.today_period_toggle), style = Fonts.almanacBody(15), color = Ink.text)
        Spacer(Modifier.weight(1f))
        MatteSwitchTrack(isOn)
    }
}

// ── 3구획 ──

@Composable
private fun DaySections(day: LocalDate, state: TodayUiState, vm: TodayViewModel, hazeState: HazeState) {
    val zone = ZoneId.systemDefault()
    val isFuture = day > state.today
    val isToday = day == state.today

    // ① 일정 — 시각순, 종일 맨 뒤(오늘 탭과 동형)
    val schedules = remember(state.schedules, day) {
        sortedByTimeOfDay(state.schedules.filter { it.occurs(day, zone) }) {
            if (it.isAllDay) null else it.date.atZone(zone).let { z -> z.hour * 60 + z.minute }
        }
    }
    // ② Input — 완료 우선(iOS §5.6.4): occurrence가 없어도 그날 완료 기록이 있으면 표시. 두 번째 값 = 예상(projected)
    val checkedIds = remember(state.completions, day) { state.completions.filter { it.occurredOn == day }.map { it.itemId }.toSet() }
    val inputs = remember(state.inputs, checkedIds, state.snapshot, day) {
        orderedInputs(state.inputs.mapNotNull { item ->
            when (val s = item.schedule) {
                InputSchedule.Once -> if (item.id in checkedIds || item.onceShows(day, zone)) item to false else null
                InputSchedule.Daily, InputSchedule.Weekly, InputSchedule.Monthly -> if (item.occursByCalendar(day, zone)) item to false else null
                is InputSchedule.CycleAnchored ->
                    state.snapshot.occurrence(s.recurrence, item.createdAt.toLocalDate(zone), day)?.let { item to it.projected }
                        ?: if (item.id in checkedIds) item to false else null
            }
        }) { it.first }
    }
    // ③ Output — 완료된 아이템의 미래 occurrence 미표시(iOS §5.5.2)
    val outputs = remember(state.outputs, state.outputSubtasks, state.snapshot, day, state.today) {
        sortedByTimeOfDay(state.outputs.mapNotNull { item ->
            val subs = state.outputSubtasks.filter { it.ownerId == item.id }
            val complete = ProgressRule.isFulfilled(item.progressGoal(subs.size), item.progressState(subs.count { it.isDone }))
            when (val s = item.schedule) {
                OutputSchedule.Once, OutputSchedule.Daily, OutputSchedule.Weekly, OutputSchedule.Monthly -> when {
                    !item.occursByCalendar(day, zone) -> null
                    complete && day > state.today -> null
                    else -> item to (day > state.today)
                }
                is OutputSchedule.CycleAnchored ->
                    state.snapshot.occurrence(s.recurrence, item.createdAt.toLocalDate(zone), day)
                        ?.takeIf { !(complete && it.projected) }
                        ?.let { item to it.projected }
            }
        }) { it.first.timeMinutes }
    }

    Section(CardKind.SCHEDULE, hazeState) {
        if (schedules.isEmpty()) EmptyRow(stringResource(R.string.empty_none))
        else schedules.forEach { DayScheduleRow(it, day, vm) }
    }
    Section(CardKind.INPUT, hazeState) {
        if (inputs.isEmpty()) EmptyRow(stringResource(R.string.empty_none))
        else inputs.forEach { (item, projected) ->
            DayInputRow(item, projected, item.id in checkedIds, day, isFuture, isToday, state, vm)
        }
    }
    Section(CardKind.OUTPUT, hazeState) {
        if (outputs.isEmpty()) {
            val cold = state.isColdStart && state.outputs.any { it.schedule is OutputSchedule.CycleAnchored }
            EmptyRow(stringResource(if (cold) R.string.empty_output_cold else R.string.empty_none))
        } else outputs.forEach { (item, projected) -> DayOutputRow(item, projected, day, isFuture, state, vm) }
    }
}

@Composable
private fun DayScheduleRow(item: ScheduleItemEntity, day: LocalDate, vm: TodayViewModel) {
    val ink = Ink
    val zone = ZoneId.systemDefault()
    QuickDeletable(kindLabel = stringResource(R.string.section_schedule), title = item.title, onDelete = { vm.deleteSchedule(item) }) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(item.title, style = Fonts.almanacBody(14), color = ink.text)
            item.dayIndex(day, zone)?.let { idx ->
                Text(stringResource(R.string.span_day_index, idx, item.spanDays(zone)), style = Fonts.system(11), color = ink.text.copy(alpha = 0.5f))
            }
            Spacer(Modifier.weight(1f))
            // 시간 지정이면 시작~종료(iOS 하루 상세는 종료 시각까지 보인다)
            val trailing = if (item.isAllDay) stringResource(R.string.all_day) else {
                val start = item.date.atZone(zone).toLocalTime().format(shortTime)
                item.endDate?.let { "$start~${it.atZone(zone).toLocalTime().format(shortTime)}" } ?: start
            }
            Text(trailing, style = Fonts.system(12), color = ink.text.copy(alpha = 0.5f))
        }
    }
}

@Composable
private fun DayInputRow(
    item: InputItemEntity, projected: Boolean, checked: Boolean, day: LocalDate,
    isFuture: Boolean, isToday: Boolean, state: TodayUiState, vm: TodayViewModel,
) {
    val ink = Ink
    val haptic = LocalHapticFeedback.current
    val subtasks = remember(state.inputSubtasks, item.id) { state.inputSubtasks.filter { it.ownerId == item.id }.sortedBy { it.order } }
    val progress = remember(state.inputProgress, item.id, day) { state.inputProgress.firstOrNull { it.itemId == item.id && it.occurredOn == day } }
    val goal = item.progressGoal(subtasks.size)
    val stateText = stringResource(if (checked) R.string.done else R.string.not_done)
    QuickDeletable(kindLabel = stringResource(R.string.section_input), title = item.title, onDelete = { vm.deleteInput(item) }) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .combinedClickable(enabled = !isFuture, onClick = {   // 미래 완료 금지(원칙 4)
                        haptic.performHapticFeedback(HapticFeedbackType.Confirm)
                        vm.toggleInputCheck(item, day)
                    })
                    .semantics { stateDescription = stateText },
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                StampCheck(checked = checked)
                Text(
                    item.title,
                    style = Fonts.almanacBody(14),
                    color = ink.text.copy(alpha = if (projected) 0.55f else 1f),
                    textDecoration = if (checked) TextDecoration.LineThrough else null,
                )
                if (projected) ProjectedTag()
                Spacer(Modifier.weight(1f))
                item.timeMinutes?.let { Text(timeOfDayLabel(it), style = Fonts.system(12), color = ink.text.copy(alpha = 0.5f)) }
            }
            // 미래는 조작 금지. 타이머·스톱워치는 오늘만(iOS 2026-08-20 — 지난날 실시간 측정은 의미가 없다)
            val timed = goal?.kind == OutputProgressKind.TIMER || goal?.kind == OutputProgressKind.STOPWATCH
            if (goal != null && !isFuture && (isToday || !timed)) {
                InputProgressControl(item, goal, subtasks, progress, vm, day, Modifier.padding(start = 26.dp))
            }
        }
    }
}

@Composable
private fun DayOutputRow(item: OutputItemEntity, projected: Boolean, day: LocalDate, isFuture: Boolean, state: TodayUiState, vm: TodayViewModel) {
    val ink = Ink
    val haptic = LocalHapticFeedback.current
    val subtasks = remember(state.outputSubtasks, item.id) { state.outputSubtasks.filter { it.ownerId == item.id }.sortedBy { it.order } }
    val complete = ProgressRule.isFulfilled(item.progressGoal(subtasks.size), item.progressState(subtasks.count { it.isDone }))
    val singleCheck = item.kind == OutputProgressKind.CHECK_ONLY || (item.kind == OutputProgressKind.SUBTASKS && subtasks.isEmpty())
    val titleColor = ink.text.copy(alpha = if (projected) 0.55f else 1f)
    QuickDeletable(kindLabel = stringResource(R.string.section_output), title = item.title, onDelete = { vm.deleteOutput(item) }) {
        Column(Modifier.padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                if (singleCheck) {
                    // 단일 체크 = 제목 앞 도장, 제목 글씨도 눌린다(오늘 탭 SingleCheckButton과 동형). 미래는 막는다
                    val done = item.percent >= 1
                    val stateText = stringResource(if (done) R.string.done else R.string.not_done)
                    Row(
                        Modifier
                            .combinedClickable(enabled = !isFuture, onClick = {
                                haptic.performHapticFeedback(if (done) HapticFeedbackType.TextHandleMove else HapticFeedbackType.Confirm)
                                vm.updateOutput(item.copy(percent = if (done) 0.0 else 1.0))
                            })
                            .semantics(mergeDescendants = true) { stateDescription = stateText },
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        StampCheck(checked = done)
                        Text(item.title, style = Fonts.almanacBody(14, bold = true), color = titleColor)
                    }
                } else {
                    Text(item.title, style = Fonts.almanacBody(14, bold = true), color = titleColor)
                }
                item.targetDate?.let { DDayBadge(it, day) }
                if (projected) ProjectedTag()
                if (complete && !singleCheck) Text(stringResource(R.string.done), style = Fonts.system(11, FontWeight.SemiBold), color = ink.text.copy(alpha = 0.6f))
                Spacer(Modifier.weight(1f))
                item.timeMinutes?.let { Text(timeOfDayLabel(it), style = Fonts.system(12), color = ink.text.copy(alpha = 0.5f)) }
            }
            // 미래는 조작 금지(iOS 2026-08-20 감사 — 미래 날짜에서 만지면 아이템 누적에 즉시 반영되던 구멍)
            if (!isFuture && !singleCheck) OutputProgressControl(item, subtasks, vm)
        }
    }
}

@Composable
private fun ProjectedTag() {
    Text(stringResource(R.string.today_badge_projected), style = Fonts.system(11), color = Ink.text.copy(alpha = 0.45f))
}
