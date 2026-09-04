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
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.graphics.Color
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
import app.temporoutine.android.theme.SeasonLight
import app.temporoutine.android.theme.chromeGlass
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.rememberHazeState
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
fun TodayRoute(app: TempoApp, openLogSheetInitially: Boolean = false) {
    val vm: TodayViewModel = viewModel { TodayViewModel(app) }
    val state by vm.state.collectAsState()
    var showLogSheet by remember { mutableStateOf(openLogSheetInitially) }
    TodayScreen(state = state, vm = vm, onTogglePeriod = vm::togglePeriodToday, onOpenLogSheet = { showLogSheet = true })
    if (showLogSheet && state.loaded) {
        PeriodTrackerSheet(state = state, vm = vm, onDismiss = { showLogSheet = false })
    }
}

@Composable
fun TodayScreen(state: TodayUiState, vm: TodayViewModel, onTogglePeriod: () -> Unit, onOpenLogSheet: () -> Unit) {
    val ink = Ink
    val hazeState = rememberHazeState()
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

    Box(Modifier.fillMaxSize().background(ink.paper)) {
        // 첫 DB 방출 전엔 지면만 — 기본 상태(콜드)를 잠깐 보여줬다가 바뀌는 깜빡임 방지(iOS는 @Query가 동기라 없는 문제)
        if (!state.loaded) return@Box
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
                .windowInsetsPadding(WindowInsets.navigationBars),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            LargeHeader(state, onTogglePeriod)
            StateSurfaces(state, onOpenLogSheet)
            TodaySections(state, vm, hazeState)
            val record = state.checkIns.firstOrNull { it.day == state.today }
            CheckInCard(day = state.today, record = record, signals = state.trackedSignals, vm = vm, hazeState = hazeState, isToday = true)
        }
        CompactBar(state, collapsed, Modifier.align(Alignment.TopCenter).zIndex(1f).chromeGlass(hazeState))
    }
}

@Composable
private fun LargeHeader(state: TodayUiState, onTogglePeriod: () -> Unit) {
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
            Row(
                Modifier.padding(top = 6.dp).fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.Bottom,
            ) {
                Text(
                    copy.name,
                    style = Fonts.almanac(58),
                    color = titleColor,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
                Spacer(Modifier.weight(1f))
                DateStamp(state)
            }
            GroundHaze {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        stringResource(R.string.today_day_in_phase, info.dayInPhase),
                        style = Fonts.almanacBody(13),
                        color = ink.season(info.phase).copy(alpha = 0.85f),
                    )
                    val badge = when {
                        state.snapshot.isSingleRecord -> stringResource(R.string.today_badge_prediction)
                        info.projected -> stringResource(R.string.today_badge_projected)
                        else -> null
                    }
                    if (badge != null) Text(badge, style = Fonts.almanacBody(13), color = ink.text.copy(alpha = 0.45f))
                }
            }
            val moodline = (state.moodline ?: copy.moodline).replace(". ", ".\n")
            GroundHaze(Modifier.padding(top = 2.dp)) {
                Text(moodline, style = Fonts.almanacBody(17), color = ink.text.copy(alpha = 0.85f))
            }
            PeriodToggle(state.isPeriodToday, onTogglePeriod, Modifier.padding(top = 8.dp))
        } else {
            Text(stringResource(R.string.today_cold_title), style = Fonts.almanac(44), color = ink.text)
        }
    }
}

@Composable
private fun DateStamp(state: TodayUiState) {
    val ink = Ink
    val locale = Locale.getDefault()
    val monthWeekday = remember(state.today, locale) {
        state.today.format(DateTimeFormatter.ofPattern("M월 E", locale))
    }
    Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.Bottom) {
        Text(state.today.dayOfMonth.toString(), style = Fonts.almanac(44), color = ink.text.copy(alpha = 0.85f))
        Text(monthWeekday, style = Fonts.almanacBody(12), color = ink.text.copy(alpha = 0.55f), modifier = Modifier.padding(bottom = 6.dp))
    }
}

@Composable
private fun PeriodToggle(isOn: Boolean, onToggle: () -> Unit, modifier: Modifier = Modifier) {
    val ink = Ink
    val haptic = LocalHapticFeedback.current
    Row(
        modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.End,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(stringResource(R.string.today_period_toggle), style = Fonts.almanacBody(15), color = ink.text)
        Spacer(Modifier.padding(horizontal = 6.dp))
        Switch(
            checked = isOn,
            onCheckedChange = {
                haptic.performHapticFeedback(HapticFeedbackType.Confirm)
                onToggle()
            },
            colors = SwitchDefaults.colors(
                checkedTrackColor = ink.text,
                checkedThumbColor = ink.paper,
                uncheckedTrackColor = ink.text.copy(alpha = 0.12f),
                uncheckedThumbColor = ink.text.copy(alpha = 0.6f),
                uncheckedBorderColor = Color.Transparent,
            ),
        )
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
                .background(ink.record.copy(alpha = 0.12f), androidx.compose.foundation.shape.RoundedCornerShape(14.dp))
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
