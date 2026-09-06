// 템포루틴 Android — 캘린더 탭 (iOS SeasonCalendarView.swift 은필 분기 이식, MASTER §8.2.3)
// 조회 전용 + 「생리 기록」 시트. 셀 탭·빠른 일정·하루 상세·소식란은 P1(Phase 2 계획 가정 3).
// 프레임 경로(드래그)는 MonthRender 조회만 — 파생 계산은 ViewModel(CLAUDE.md 프레임 규칙).

package app.temporoutine.android.calendar

import androidx.compose.animation.core.animate
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import app.temporoutine.android.R
import app.temporoutine.android.TempoApp
import app.temporoutine.android.cycle.displayOrder
import app.temporoutine.android.cycle.seasonCopy
import app.temporoutine.android.period.PeriodTrackerSheet
import app.temporoutine.android.theme.BrandMark
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.LocalChrome
import app.temporoutine.android.theme.SeasonGlyph
import app.temporoutine.android.theme.SeasonLight
import app.temporoutine.android.today.TodayViewModel
import app.temporoutine.core.CyclePhase
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlinx.coroutines.launch

private val MIN_CELL_HEIGHT = 54.dp
private val ROW_SPACING = 4.dp
private val BAND_HEIGHT = 11.dp
private val BAND_TOP = 33.5.dp
private val BAND_SLOT = 13.dp
private val NUMBER_BOX = 27.dp
private val SEASON_BAND_TOP = 25.5.dp
private val SEASON_BAND_HEIGHT = 4.dp

@Composable
fun CalendarRoute(app: TempoApp, todayVm: TodayViewModel, hazeState: HazeState, bottomPadding: Dp, hidePeriodEntry: Boolean = false) {
    val vm: CalendarViewModel = viewModel { CalendarViewModel(app) }
    val state by vm.state.collectAsState()
    val todayState by todayVm.state.collectAsState()
    var showLogSheet by remember { mutableStateOf(false) }
    // 숨기기 스위치(설정) — 진입점만 지운다. 오늘 화면 스위치로는 계속 기록할 수 있다.
    CalendarScreen(state, vm, hazeState, bottomPadding, onOpenLogSheet = if (hidePeriodEntry) null else ({ showLogSheet = true }))
    if (showLogSheet && todayState.loaded) {
        PeriodTrackerSheet(state = todayState, vm = todayVm, onDismiss = { showLogSheet = false })
    }
}

@Composable
fun CalendarScreen(state: CalendarUiState, vm: CalendarViewModel, hazeState: HazeState, bottomPadding: Dp, onOpenLogSheet: (() -> Unit)?) {
    val ink = Ink
    val chrome = LocalChrome.current
    Box(Modifier.fillMaxSize().background(ink.frost)) {
        if (!state.loaded) return@Box
        // 계절광 — 캘린더는 게이트를 자기가 따로 건다(iOS :293). 상단 0~22% 불투명 → 40% 투명 마스크.
        if (chrome.showsSeasonLight) {
            Box(
                Modifier
                    .fillMaxSize()
                    .hazeSource(hazeState)
                    .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
                    .drawWithContent {
                        drawContent()
                        drawRect(
                            brush = Brush.verticalGradient(0f to Color.Black, 0.22f to Color.Black, 0.40f to Color.Transparent),
                            blendMode = BlendMode.DstIn,
                        )
                    },
            ) {
                // 레이어 안이 투명하면 multiply가 흰 지면을 얹는다 — 지면을 레이어 안에 함께 둔다(SeasonLight.kt 주석)
                Box(Modifier.fillMaxSize().background(ink.frost))
                SeasonLight(phase = state.todayPhase, modifier = Modifier.fillMaxSize())
            }
        }
        Column(
            Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.statusBars)
                .padding(20.dp)
                .padding(bottom = bottomPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SeasonHeaderRow(state, onOpenLogSheet)
            Row(Modifier.fillMaxWidth().height(44.dp), verticalAlignment = Alignment.CenterVertically) {
                BrandMark(diameter = 22.dp, color = ink.text.copy(alpha = 0.75f), modifier = Modifier.padding(start = 6.dp))
            }
            MonthHeader(state, vm)
            WeekdayRow(state.firstDayOfWeek)
            MonthCarousel(state, vm, Modifier.weight(1f).fillMaxWidth())
            Legend()
        }
    }
}

// ── 상단 ──

@Composable
private fun SeasonHeaderRow(state: CalendarUiState, onOpenLogSheet: (() -> Unit)?) {
    val ink = Ink
    val line = when (val s = state.seasonLine) {
        SeasonLine.Cold -> stringResource(R.string.calendar_season_cold)
        is SeasonLine.Overdue -> stringResource(R.string.calendar_season_overdue, s.daysPast.toString())
        is SeasonLine.Season -> stringResource(
            R.string.calendar_season_line, seasonCopy(s.phase).name, s.dayInPhase.toString(),
            if (s.projected) stringResource(R.string.calendar_projected_suffix) else "",
        )
    }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(line, style = Fonts.almanacBody(15), color = ink.text.copy(alpha = 0.65f), modifier = Modifier.weight(1f))
        if (onOpenLogSheet != null) {
            Row(
                Modifier
                    .heightIn(min = 44.dp)
                    .clickable(onClick = onOpenLogSheet),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(
                    Modifier.border(1.dp, ink.text.copy(alpha = 0.3f), CircleShape).padding(horizontal = 12.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(5.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.size(7.dp).background(ink.record, CircleShape))
                    Text(stringResource(R.string.calendar_period_button), style = Fonts.system(12, FontWeight.SemiBold), color = ink.text)
                }
            }
        }
    }
}

@Composable
private fun MonthHeader(state: CalendarUiState, vm: CalendarViewModel) {
    val ink = Ink
    val haptic = LocalHapticFeedback.current
    val locale = Locale.getDefault()
    val monthName = remember(state.anchor, locale) { state.anchor.format(DateTimeFormatter.ofPattern("LLL", locale)) }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(monthName, style = Fonts.almanac(58), color = ink.text)
        Text(
            state.anchor.year.toString(),
            style = Fonts.system(13).copy(fontFamily = FontFamily.Serif),
            color = ink.text.copy(alpha = 0.5f),
            modifier = Modifier.padding(bottom = 10.dp),
        )
        Spacer(Modifier.weight(1f))
        Chevron(left = true, label = stringResource(R.string.calendar_prev_month)) { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); vm.shiftMonth(-1) }
        Chevron(left = false, label = stringResource(R.string.calendar_next_month)) { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); vm.shiftMonth(1) }
    }
}

@Composable
private fun Chevron(left: Boolean, label: String, onClick: () -> Unit) {
    val ink = Ink
    Box(Modifier.size(44.dp).semantics { contentDescription = label }.clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(12.dp, 18.dp)) {
            val p = Path().apply {
                if (left) { moveTo(size.width, 0f); lineTo(0f, size.height / 2); lineTo(size.width, size.height) }
                else { moveTo(0f, 0f); lineTo(size.width, size.height / 2); lineTo(0f, size.height) }
            }
            drawPath(p, ink.text, style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round))
        }
    }
}

@Composable
private fun WeekdayRow(firstDayOfWeek: DayOfWeek) {
    val ink = Ink
    val locale = Locale.getDefault()
    Row(
        Modifier
            .fillMaxWidth()
            .padding(bottom = 4.dp)
            .drawBehind { drawRect(ink.accent.copy(alpha = 0.28f), topLeft = Offset(0f, size.height - 1f), size = Size(size.width, 1f)) },
    ) {
        for (i in 0 until 7) {
            val dow = firstDayOfWeek.plus(i.toLong())
            val color = when (dow) {
                DayOfWeek.SUNDAY -> ink.holiday
                DayOfWeek.SATURDAY -> ink.saturday
                else -> ink.accent
            }
            Text(
                dow.getDisplayName(TextStyle.NARROW, locale), style = Fonts.system(11), color = color,
                modifier = Modifier.weight(1f).padding(bottom = 4.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }
}

// ── 캐러셀 ──

@Composable
private fun MonthCarousel(state: CalendarUiState, vm: CalendarViewModel, modifier: Modifier) {
    val scope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current
    BoxWithConstraints(modifier.clipToBounds()) {
        val w = with(LocalDensity.current) { maxWidth.toPx() }
        // 드래그 델타는 일반 상태로 누적(Animatable.snapTo를 델타마다 launch하면 MutatorMutex가 서로 취소해 델타가 유실된다 — 실측 2026-09-05).
        var dragX by remember { mutableFloatStateOf(0f) }
        var engaged by remember { mutableStateOf(false) }
        var animating by remember { mutableStateOf(false) }
        // iOS는 옆 달을 드래그 중에만 그리지만(:484), Android에선 첫 드래그 때 옆 달 첫 합성이 프레임을 먹어
        // 델타가 유실됐다(실측 2026-09-05: 700px 스와이프가 −61px로 정착). MonthRender가 캐시라 항상 합성해도 싸다.
        val sidesVisible = true

        fun settle(velocity: Float) {
            engaged = false
            val translation = dragX
            val predicted = translation + velocity * 0.25f
            val effective = if (abs(predicted) > abs(translation)) predicted else translation
            val delta = when {
                effective < -w * 0.25f -> 1
                effective > w * 0.25f -> -1
                else -> 0
            }
            scope.launch {
                animating = true
                if (delta == 0) {
                    animate(translation, 0f, animationSpec = tween(250, easing = FastOutSlowInEasing)) { v, _ -> dragX = v }
                } else {
                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    animate(translation, if (delta > 0) -w else w, animationSpec = tween(280, easing = FastOutSlowInEasing)) { v, _ -> dragX = v }
                    vm.shiftMonth(delta)
                    dragX = 0f
                }
                animating = false
            }
        }

        val dragState = rememberDraggableState { dx -> dragX += dx }
        val panelWidth = maxWidth   // LayoutScopeMarker — Row 안에서 외부 수신자 암묵 접근 불가
        Row(
            Modifier
                .fillMaxHeight()
                // 3w짜리 Row를 w 상자 안에 — unbounded로 재고 Start 정렬(required 초과분을 가운데 맞추는 기본 동작 회피, 실측 2026-09-05)
                .wrapContentWidth(Alignment.Start, unbounded = true)
                .offset { IntOffset((-w + dragX).roundToInt(), 0) }
                .draggable(
                    state = dragState,
                    orientation = Orientation.Horizontal,
                    enabled = !animating,
                    onDragStarted = { engaged = true },
                    onDragStopped = { v -> settle(v) },
                ),
        ) {
            for (off in -1..1) {
                val render = state.renders[state.anchor.plusMonths(off.toLong())]
                Box(Modifier.width(panelWidth).fillMaxHeight()) {
                    if (render != null && (off == 0 || sidesVisible)) MonthGrid(render, state.today, interactive = off == 0)
                }
            }
        }
    }
}

// ── 격자 ──

@Composable
private fun MonthGrid(render: MonthRender, today: LocalDate, interactive: Boolean) {
    val layout = render.layout
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(ROW_SPACING)) {
        for (row in 0 until layout.rowCount) {
            BoxWithConstraints(Modifier.fillMaxWidth().weight(1f).heightIn(min = MIN_CELL_HEIGHT)) {
                val unit = maxWidth / 7
                Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.Top) {
                    for (col in 0 until 7) {
                        val index = row * 7 + col
                        Box(Modifier.weight(1f).fillMaxHeight()) { CellOrBlank(render, index, today, interactive) }
                    }
                }
                // 여러 날 띠 — 행 오버레이(셀 밖 좌표계). y = 33.5 + lane*13, x = unit*col + 1, w = unit*len − 2
                for (bar in render.bands.bars) {
                    if (bar.segment.row != row) continue
                    BandBarView(bar, unit)
                }
            }
        }
    }
}

@Composable
private fun BandBarView(bar: BandBar, unit: Dp) {
    val ink = Ink
    val seg = bar.segment
    val width = (unit * seg.length - 2.dp).coerceAtLeast(0.dp)
    val r = 2.dp
    Box(
        Modifier
            .offset(x = unit * seg.column + 1.dp, y = BAND_TOP + BAND_SLOT * bar.lane)
            .width(width)
            .height(BAND_HEIGHT)
            .drawBehind {
                val rr = RoundRect(
                    rect = androidx.compose.ui.geometry.Rect(0f, 0f, size.width, size.height),
                    topLeft = if (seg.isStart) CornerRadius(r.toPx()) else CornerRadius.Zero,
                    topRight = if (seg.isEnd) CornerRadius(r.toPx()) else CornerRadius.Zero,
                    bottomRight = if (seg.isEnd) CornerRadius(r.toPx()) else CornerRadius.Zero,
                    bottomLeft = if (seg.isStart) CornerRadius(r.toPx()) else CornerRadius.Zero,
                )
                drawPath(Path().apply { addRoundRect(rr) }, ink.text.copy(alpha = 0.13f))
            }
            .clearAndSetSemantics { },
        contentAlignment = Alignment.CenterStart,
    ) {
        if (seg.isStart) {
            Text(bar.title, style = Fonts.system(9, FontWeight.SemiBold), color = ink.text.copy(alpha = 0.85f),
                maxLines = 1, overflow = TextOverflow.Clip, modifier = Modifier.padding(horizontal = 4.dp))
        }
    }
}

@Composable
private fun CellOrBlank(render: MonthRender, index: Int, today: LocalDate, interactive: Boolean) {
    val layout = render.layout
    val date = layout.date(index)
    if (date != null) { Cell(render, index, date, today, interactive); return }
    // 마지막 주 후행 빈칸 = 계절 꼬리 페이드(0.25 → 0)
    val firstTrailing = layout.firstTrailing
    val lastDay = layout.start.plusDays((layout.daysInMonth - 1).toLong())
    val meta = render.style[lastDay]?.phase
    if (index >= firstTrailing && index / 7 == (firstTrailing - 1) / 7 && meta != null) {
        val ink = Ink
        val total = layout.cellCount - firstTrailing
        val position = index - firstTrailing
        val base = 0.25f
        val from = base * (1f - position.toFloat() / total)
        val to = base * (1f - (position + 1).toFloat() / total)
        Box(
            Modifier
                .fillMaxWidth()
                .padding(top = SEASON_BAND_TOP)
                .height(SEASON_BAND_HEIGHT)
                .background(Brush.horizontalGradient(listOf(ink.glow(meta).copy(alpha = from), ink.glow(meta).copy(alpha = to)))),
        )
    }
}

@Composable
private fun Cell(render: MonthRender, index: Int, date: LocalDate, today: LocalDate, interactive: Boolean) {
    val ink = Ink
    val style = render.style[date] ?: CellStyle(null, false)
    val isToday = date == today
    val bandCount = render.bands.countByIndex[index] ?: 0
    val holiday = render.holidays[date]
    val markBudget = maxOf(0, 2 - bandCount - (if (holiday == null) 0 else 1))
    val marks = render.marks[date].orEmpty()
    val recorded = date in render.recorded
    val predicted = date in render.predicted

    val numberColor = when {
        isToday -> ink.paper
        holiday?.isPublic == true -> ink.holiday
        date.dayOfWeek == DayOfWeek.SUNDAY -> ink.holiday
        date.dayOfWeek == DayOfWeek.SATURDAY -> ink.saturday
        else -> ink.text
    }
    val locale = Locale.getDefault()
    val a11y = buildList {
        add(date.format(DateTimeFormatter.ofPattern("M월 d일", locale)))
        style.phase?.let { p -> add(if (style.projected) stringResource(R.string.calendar_a11y_projected, seasonCopy(p).name) else seasonCopy(p).name) }
        if (recorded) add(stringResource(R.string.calendar_a11y_recorded))
        if (predicted) add(stringResource(R.string.calendar_a11y_predicted))
    }.joinToString(", ")

    // 계절 밑줄 연결 판정 — 이웃 날의 캐시된 phase(달 밖은 여유 하루로 들어 있음)
    val prevSame = render.style[date.minusDays(1)]?.phase == style.phase && style.phase != null
    val nextSame = render.style[date.plusDays(1)]?.phase == style.phase && style.phase != null
    val col = index % 7
    val roundLeft = !prevSame || col == 0
    val roundRight = !nextSame || col == 6

    Column(
        Modifier
            .fillMaxSize()
            .then(if (interactive) Modifier.semantics { contentDescription = a11y } else Modifier.clearAndSetSemantics { })
            .drawBehind {
                val phase = style.phase ?: return@drawBehind
                val inset = 3.dp.toPx()
                drawRect(
                    color = ink.glow(phase).copy(alpha = if (style.projected) 0.25f else 0.5f),
                    topLeft = Offset(if (roundLeft) inset else 0f, SEASON_BAND_TOP.toPx()),
                    size = Size(size.width - (if (roundLeft) inset else 0f) - (if (roundRight) inset else 0f), SEASON_BAND_HEIGHT.toPx()),
                )
            }
            .padding(top = 3.dp)
            .padding(horizontal = 1.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.size(NUMBER_BOX), contentAlignment = Alignment.Center) {
            if (isToday) Box(Modifier.size(NUMBER_BOX).background(ink.text, CircleShape))
            Text(date.dayOfMonth.toString(), style = Fonts.calendarNumber(isToday), color = numberColor)
        }
        Spacer(Modifier.height(3.5.dp))
        if (bandCount > 0) Spacer(Modifier.height(BAND_SLOT * bandCount))
        if (holiday != null) {
            Text(
                holiday.name, style = Fonts.system(9, FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Clip,
                color = if (holiday.isPublic) ink.holiday else ink.text.copy(alpha = 0.5f),
            )
        }
        for (mark in marks.take(markBudget)) {
            if (mark.isSchedule) {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 1.dp)
                        .padding(bottom = 1.dp)
                        .height(11.dp)
                        .background(ink.text.copy(alpha = 0.13f), androidx.compose.foundation.shape.RoundedCornerShape(2.dp)),
                    contentAlignment = Alignment.CenterStart,
                ) {
                    Text(mark.title, style = Fonts.system(9, FontWeight.SemiBold), color = ink.text.copy(alpha = 0.85f),
                        maxLines = 1, overflow = TextOverflow.Clip, modifier = Modifier.padding(horizontal = 4.dp))
                }
            } else {
                Text(mark.title, style = Fonts.system(9, FontWeight.Medium), maxLines = 1, overflow = TextOverflow.Clip,
                    color = ink.text.copy(alpha = if (mark.projected) 0.45f else 0.78f))
            }
        }
    }
}

// ── 범례 ──

@Composable
private fun Legend() {
    val ink = Ink
    Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
        for (phase in CyclePhase.displayOrder) {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                SeasonGlyph(phase, ink.season(phase), size = 12.dp)
                Text(seasonCopy(phase).name, style = Fonts.almanacBody(12, bold = true), color = ink.season(phase))
            }
        }
        Spacer(Modifier.weight(1f))
    }
}
