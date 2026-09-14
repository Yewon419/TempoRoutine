// 템포루틴 Android — 오늘 화면 (iOS TodayView.swift 은필 분기 이식, MASTER §8.2.2)
// 컬랩스는 font-size 보간이 아니라 임계 flip(−56/−40 히스테리시스) + 2레이어 crossfade(DESIGN.md v44).

package app.temporoutine.android.today

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.toggleable
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.lifecycle.viewmodel.compose.viewModel
import app.temporoutine.android.R
import app.temporoutine.android.TempoApp
import app.temporoutine.android.period.PeriodTrackerSheet
import app.temporoutine.android.theme.BrandMark
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.GroundHaze
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.MatteSwitchTrack
import app.temporoutine.android.theme.Radius
import app.temporoutine.android.theme.SeasonLight
import app.temporoutine.android.theme.chromeGlass
import app.temporoutine.core.CyclePhase
import androidx.compose.ui.unit.Dp
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.rememberHazeState
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.sp
import app.temporoutine.android.cycle.PhaseInfo
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
fun TodayRoute(app: TempoApp, vm: TodayViewModel, hazeState: HazeState, bottomPadding: Dp, openLogSheetInitially: Boolean = false) {
    val state by vm.state.collectAsState()
    var showLogSheet by remember { mutableStateOf(openLogSheetInitially) }
    TodayScreen(state = state, vm = vm, hazeState = hazeState, bottomPadding = bottomPadding,
        onTogglePeriod = vm::togglePeriodToday, onOpenLogSheet = { showLogSheet = true })
    if (showLogSheet && state.loaded) {
        PeriodTrackerSheet(state = state, vm = vm, onDismiss = { showLogSheet = false })
    }
}

@Composable
fun TodayScreen(state: TodayUiState, vm: TodayViewModel, hazeState: HazeState, bottomPadding: Dp, onTogglePeriod: () -> Unit, onOpenLogSheet: () -> Unit) {
    val ink = Ink
    val scroll = rememberScrollState()
    val density = LocalDensity.current

    // 임계 flip: −56dp 넘게 내려가면 접고, −40dp 위로 올라오면 편다.
    var collapsed by remember { mutableStateOf(false) }
    LaunchedEffect(scroll) {
        val collapseAt = with(density) { 56.dp.toPx() }
        val expandAt = with(density) { 40.dp.toPx() }
        snapshotFlow { scroll.value }.collect { y ->
            if (y > collapseAt && !collapsed) collapsed = true
            else if (y < expandAt && collapsed) collapsed = false
        }
    }

    // 컴팩트 바는 지면만이 아니라 스크롤 콘텐츠까지 흐려야 한다(iOS 동형) — 그 층의 소스를 따로 둔다.
    val compactHaze = rememberHazeState()
    Box(Modifier.fillMaxSize().background(ink.paper)) {
        // 첫 DB 방출 전엔 지면만 — 기본 상태(콜드)를 잠깐 보여줬다가 바뀌는 깜빡임 방지(iOS는 @Query가 동기라 없는 문제)
        if (!state.loaded) return@Box
        Box(Modifier.fillMaxSize().hazeSource(compactHaze)) {
            SeasonLight(
                phase = state.info?.phase,
                modifier = Modifier.fillMaxSize().hazeSource(hazeState),
            )
            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(scroll)
                    .windowInsetsPadding(WindowInsets.statusBars)
                    .padding(20.dp)
                    .padding(bottom = bottomPadding),
                verticalArrangement = Arrangement.spacedBy(12.dp),   // 16 → 12(iOS 86차)
            ) {
                LargeHeader(state, onTogglePeriod, onOpenLogSheet)
                StateSurfaces(state, onOpenLogSheet)
                TodaySections(state, vm, hazeState)
                val record = state.checkIns.firstOrNull { it.day == state.today }
                CheckInCard(day = state.today, record = record, signals = state.trackedSignals, phaseInfo = state.info, vm = vm, hazeState = hazeState, isToday = true)
            }
        }
        CompactBar(state, collapsed, Modifier.align(Alignment.TopCenter).zIndex(1f).chromeGlass(compactHaze))
    }
}

@Composable
private fun LargeHeader(state: TodayUiState, onTogglePeriod: () -> Unit, onOpenLogSheet: () -> Unit) {
    val ink = Ink
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            BrandMark(diameter = 22.dp, color = ink.text.copy(alpha = 0.75f), modifier = Modifier.padding(start = 6.dp))
            Spacer(Modifier.weight(1f))
            SeedBadge(count = state.seeds)
        }
        val info = state.info
        val copy = state.copy
        if (info != null && copy != null) {
            val titleColor = ink.season(info.phase).copy(alpha = if (state.snapshot.isSingleRecord) 0.6f else 1f)
            // 표제는 하나(iOS 은필 v2 2026-09-07 — 계절명 58과 날짜 도장 44가 표제 둘로 경쟁했다). 날짜는 메타 줄로.
            Text(
                copy.name,
                style = Fonts.almanac(58),
                color = titleColor,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(top = 6.dp),
            )
            GroundHaze {
                // 한 Text로 잇는다(iOS 73차) — Row의 Text들은 줄을 못 바꿔 큰 글씨·좁은 폭에서 밀린다.
                Text(metaLine(state, info), style = Fonts.almanacBody(13))
            }
            val moodline = (state.moodline ?: copy.moodline).replace(". ", ".\n")
            GroundHaze(Modifier.padding(top = 8.dp)) {
                // 17 → 18 · 줄 간격 +3 · 0.88(iOS 은필 v2 — 표제 아래 둘째 목소리)
                val body = Fonts.almanacBody(18)
                Text(moodline, style = body.copy(lineHeight = (body.lineHeight.value + 3).sp), color = ink.text.copy(alpha = 0.88f))
            }
            PeriodRow(state.isPeriodToday, onTogglePeriod, onOpenLogSheet, Modifier.padding(top = 8.dp))
        } else {
            Text(stringResource(R.string.today_cold_title), style = Fonts.almanac(44), color = ink.text)
        }
    }
}

private fun seasonPlainRes(phase: CyclePhase): Int = when (phase) {
    CyclePhase.MENSTRUAL -> R.string.season_plain_winter
    CyclePhase.FOLLICULAR -> R.string.season_plain_spring
    CyclePhase.OVULATION -> R.string.season_plain_summer
    CyclePhase.LUTEAL -> R.string.season_plain_autumn
}

/** 메타 줄(iOS TodayView.metaLine) — 「생리 중 · 5일차 예상 · 9월 14일 월요일」. 뱃지는 dim 0.45, 날짜 0.6, 점 0.35. */
@Composable
private fun metaLine(state: TodayUiState, info: PhaseInfo): AnnotatedString {
    val ink = Ink
    val seasonInk = ink.season(info.phase).copy(alpha = 0.85f)
    val dot = ink.text.copy(alpha = 0.35f)
    val plain = stringResource(seasonPlainRes(info.phase))
    val day = stringResource(R.string.today_day_in_phase, info.dayInPhase)
    val badge = when {
        state.snapshot.isSingleRecord -> stringResource(R.string.today_badge_prediction)
        info.projected -> stringResource(R.string.today_badge_projected)
        else -> null
    }
    val datePattern = stringResource(R.string.today_meta_date_pattern)
    val locale = Locale.getDefault()
    val date = remember(state.today, datePattern, locale) { state.today.format(DateTimeFormatter.ofPattern(datePattern, locale)) }
    return buildAnnotatedString {
        withStyle(SpanStyle(color = seasonInk)) { append(plain) }
        withStyle(SpanStyle(color = dot)) { append(" · ") }
        withStyle(SpanStyle(color = seasonInk)) { append(day) }
        if (badge != null) {
            append(" ")
            withStyle(SpanStyle(color = ink.text.copy(alpha = 0.45f))) { append(badge) }
        }
        withStyle(SpanStyle(color = dot)) { append(" · ") }
        withStyle(SpanStyle(color = ink.text.copy(alpha = 0.6f))) { append(date) }
    }
}

/** 생리 기록 줄(iOS 91-3, 2026-09-12) = 왼쪽 시트 진입 캡슐(캘린더 SeasonHeaderRow와 같은 생김새) + 오른쪽 「오늘」 무광 스위치.
 *  캡슐이 「생리 기록」을 말하니 스위치 라벨은 「오늘」 — 한 줄이 "생리 기록 · 오늘 [스위치]"로 읽힌다. */
@Composable
private fun PeriodRow(isOn: Boolean, onToggle: () -> Unit, onOpenLogSheet: () -> Unit, modifier: Modifier = Modifier) {
    val ink = Ink
    val haptic = LocalHapticFeedback.current
    val hint = stringResource(R.string.today_period_log_hint)
    val toggleLabel = stringResource(R.string.today_period_today_a11y)
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Row(
            Modifier
                .heightIn(min = 44.dp)
                .clickable(onClickLabel = hint) {
                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    onOpenLogSheet()
                },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                Modifier.border(1.dp, ink.text.copy(alpha = 0.3f), CircleShape).padding(horizontal = 12.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(5.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.size(7.dp).background(ink.record, CircleShape))
                Text(stringResource(R.string.today_period_toggle), style = Fonts.system(12, FontWeight.SemiBold), color = ink.text)
            }
        }
        Spacer(Modifier.weight(1f).widthIn(min = 12.dp))
        // 라벨을 스위치 바로 앞에(2026-08-23 대표님 "오른쪽 버튼 앞에 바짝") — 라벨까지 한 토글
        Row(
            Modifier
                .heightIn(min = 44.dp)
                .semantics { contentDescription = toggleLabel }
                .toggleable(
                    value = isOn,
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    role = Role.Switch,
                    onValueChange = {
                        haptic.performHapticFeedback(HapticFeedbackType.Confirm)
                        onToggle()
                    },
                ),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(stringResource(R.string.today_period_today), style = Fonts.almanacBody(15), color = ink.text)
            MatteSwitchTrack(isOn)
        }
    }
}

@Composable
private fun StateSurfaces(state: TodayUiState, onOpenLogSheet: () -> Unit) {
    val ink = Ink
    when {
        state.isColdStart -> Column(
            Modifier.padding(vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(stringResource(R.string.today_cold_body), style = Fonts.almanacBody(17), color = ink.text.copy(alpha = 0.8f))
            TextButton(
                onClick = onOpenLogSheet,
                shape = CircleShape,
                colors = ButtonDefaults.textButtonColors(containerColor = ink.text, contentColor = ink.paper),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 20.dp, vertical = 12.dp),
            ) {
                Text(stringResource(R.string.today_cold_cta), style = Fonts.system(17, androidx.compose.ui.text.font.FontWeight.SemiBold))
            }
        }
        state.overdueDays != null -> Text(
            stringResource(R.string.today_overdue, state.overdueDays),
            style = Fonts.system(13),
            color = ink.text,
            modifier = Modifier
                .fillMaxWidth()
                .background(ink.record.copy(alpha = 0.12f), androidx.compose.foundation.shape.RoundedCornerShape(Radius.card))
                .padding(14.dp),
        )
    }
}

@Composable
private fun CompactBar(state: TodayUiState, collapsed: Boolean, modifier: Modifier) {
    val ink = Ink
    val alpha by animateFloatAsState(if (collapsed) 1f else 0f, label = "compactBar")
    if (alpha <= 0f) return
    Column(
        modifier
            .fillMaxWidth()
            .alpha(alpha),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
        Text(
            state.copy?.name ?: stringResource(R.string.app_name),
            style = Fonts.almanac(28),
            color = state.info?.let { ink.season(it.phase) } ?: ink.text,
            modifier = Modifier.padding(vertical = 10.dp),
        )
    }
}
