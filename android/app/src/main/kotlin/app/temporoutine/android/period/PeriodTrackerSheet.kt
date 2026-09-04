// 템포루틴 Android — 생리 기록 시트 (iOS PeriodTrackerSheet.swift 이식, §5.5.4 트래커 시트 계약)
// 날짜 스트립(−90…+6) 칸 탭 = day 토글(로컬 드래프트, 애니메이션 없음) → 완료/닫기 시 실제 상태와의 차집합만 일괄 커밋.
// 미래 day 금지(칸 disabled + 커밋 시 재필터). 같은 시트에서 선택일 컨디션 체크인도 편집(CheckInEditor).

package app.temporoutine.android.period

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.temporoutine.android.R
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.SeasonLight
import app.temporoutine.android.today.CheckCircle
import app.temporoutine.android.today.TodayUiState
import app.temporoutine.android.today.TodayViewModel
import app.temporoutine.android.today.commitPeriodDraft
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.rememberHazeState
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale
import kotlinx.coroutines.launch

private const val PAST_DAYS = 90
private const val FUTURE_DAYS = 6

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun PeriodTrackerSheet(state: TodayUiState, vm: TodayViewModel, onDismiss: () -> Unit) {
    val ink = Ink
    val haptic = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val today = state.today
    val stripDays = remember(today) { (-PAST_DAYS..FUTURE_DAYS).map { today.plusDays(it.toLong()) } }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val hazeState = rememberHazeState()

    // 드래프트 — 열 때 1회 적재. 커밋은 완료/닫기 어느 경로든 정확히 1회.
    var draft by remember { mutableStateOf(state.periodDays.map { it.day }.toSet()) }
    var committed by remember { mutableStateOf(false) }
    fun commit() {
        if (committed) return
        committed = true
        val changed = vm.commitPeriodDraft(draft)
        if (changed) haptic.performHapticFeedback(HapticFeedbackType.Confirm)
    }
    DisposableEffect(Unit) { onDispose { commit() } }

    val listState = rememberLazyListState(initialFirstVisibleItemIndex = PAST_DAYS)
    val centeredIndex by remember {
        derivedStateOf {
            val info = listState.layoutInfo
            val center = (info.viewportStartOffset + info.viewportEndOffset) / 2
            info.visibleItemsInfo.minByOrNull { kotlin.math.abs(it.offset + it.size / 2 - center) }?.index ?: PAST_DAYS
        }
    }
    val selectedDay = stripDays[centeredIndex]
    val isSelectedFuture = selectedDay > today
    var showPicker by remember { mutableStateOf(false) }

    ModalBottomSheet(
        onDismissRequest = { commit(); onDismiss() },
        sheetState = sheetState,
        containerColor = ink.paper,
        dragHandle = null,
    ) {
        Box(Modifier.fillMaxSize()) {
            SeasonLight(phase = state.snapshot.phase(selectedDay), modifier = Modifier.fillMaxSize().hazeSource(hazeState))
            Column(Modifier.fillMaxSize()) {
                // 내비게이션 바 — 제목 중앙, 완료 우측
                Box(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp)) {
                    Text(stringResource(R.string.sheet_title), style = Fonts.system(17, FontWeight.SemiBold), color = ink.text, modifier = Modifier.align(Alignment.Center))
                    TextButton(onClick = { commit(); scope.launch { sheetState.hide() }.invokeOnCompletion { onDismiss() } }, modifier = Modifier.align(Alignment.CenterEnd)) {
                        Text(stringResource(R.string.sheet_confirm), style = Fonts.system(17, FontWeight.SemiBold), color = ink.text)
                    }
                }
                Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    // 날짜 제목 → 팝오버 대신 DatePickerDialog
                    val base = selectedDay.format(DateTimeFormatter.ofPattern("M월 d일", Locale.getDefault()))
                    val title = if (selectedDay == today) stringResource(R.string.sheet_day_today, base) else base
                    Text(
                        title, style = Fonts.almanac(22), color = ink.text, textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(top = 6.dp).clickable {
                            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            showPicker = true
                        },
                    )
                    // 스트립
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        DownTriangle(ink.text)
                        BoxWithConstraints(Modifier.fillMaxWidth().height(86.dp)) {
                            val side = ((maxWidth - 38.dp) / 2).coerceAtLeast(0.dp)
                            LazyRow(
                                state = listState,
                                contentPadding = PaddingValues(horizontal = side),
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                                flingBehavior = rememberSnapFlingBehavior(listState),
                                modifier = Modifier.fillMaxSize(),
                            ) {
                                items(stripDays.size, key = { stripDays[it].toString() }) { i ->
                                    val day = stripDays[i]
                                    DayPill(day, selected = day == selectedDay, recorded = day in draft, future = day > today) {
                                        if (day > today) return@DayPill
                                        haptic.performHapticFeedback(HapticFeedbackType.Confirm)
                                        draft = if (day in draft) draft - day else draft + day
                                    }
                                }
                            }
                        }
                    }
                    // 기록 구획
                    Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(stringResource(R.string.sheet_record_section), style = Fonts.almanac(17), color = ink.text)
                        PeriodRow(recorded = selectedDay in draft, enabled = !isSelectedFuture) {
                            haptic.performHapticFeedback(HapticFeedbackType.Confirm)
                            draft = if (selectedDay in draft) draft - selectedDay else draft + selectedDay
                        }
                        CheckInEditor(
                            day = selectedDay,
                            record = state.checkIns.firstOrNull { it.day == selectedDay },
                            signals = state.trackedSignals,
                            vm = vm,
                            hazeState = hazeState,
                            isFuture = isSelectedFuture,
                        )
                    }
                    Spacer(Modifier.height(24.dp))
                }
            }
        }
    }

    if (showPicker) {
        val zone = ZoneOffset.UTC
        val pickerState = rememberDatePickerState(
            initialSelectedDateMillis = selectedDay.atStartOfDay(zone).toInstant().toEpochMilli(),
            selectableDates = object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long): Boolean {
                    val d = Instant.ofEpochMilli(utcTimeMillis).atZone(zone).toLocalDate()
                    return d >= stripDays.first() && d <= stripDays.last()
                }
            },
        )
        DatePickerDialog(
            onDismissRequest = { showPicker = false },
            confirmButton = {
                TextButton(onClick = {
                    pickerState.selectedDateMillis?.let { ms ->
                        val d = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate()
                        val idx = stripDays.indexOf(d)
                        if (idx >= 0) scope.launch { listState.animateScrollToItem(idx) }
                    }
                    showPicker = false
                }) { Text(stringResource(R.string.ok)) }
            },
        ) { DatePicker(state = pickerState, title = { Text(stringResource(R.string.sheet_pick_date), modifier = Modifier.padding(24.dp)) }) }
    }
}

@Composable
private fun DownTriangle(color: Color) {
    androidx.compose.foundation.Canvas(Modifier.size(10.dp)) {
        val p = androidx.compose.ui.graphics.Path().apply {
            moveTo(0f, 0f); lineTo(size.width, 0f); lineTo(size.width / 2, size.height); close()
        }
        drawPath(p, color)
    }
}

@Composable
private fun DayPill(day: LocalDate, selected: Boolean, recorded: Boolean, future: Boolean, onTap: () -> Unit) {
    val ink = Ink
    Column(
        Modifier.alpha(if (future) 0.4f else 1f).clickable(enabled = !future, onClick = onTap),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(
            Modifier.size(22.dp).background(if (selected) ink.text else Color.Transparent, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                day.dayOfWeek.getDisplayName(TextStyle.NARROW, Locale.getDefault()),
                style = Fonts.system(11, if (selected) FontWeight.Bold else FontWeight.Normal),
                color = if (selected) ink.paper else ink.text.copy(alpha = 0.55f),
            )
        }
        Box(
            Modifier.size(38.dp, 52.dp).background(if (recorded) ink.record.copy(alpha = 0.38f) else ink.text.copy(alpha = 0.06f), RoundedCornerShape(19.dp)),
            contentAlignment = Alignment.BottomCenter,
        ) {
            Text(day.dayOfMonth.toString(), style = Fonts.system(11, FontWeight.Medium).copy(fontFeatureSettings = "tnum"),
                color = ink.text.copy(alpha = 0.55f), modifier = Modifier.padding(bottom = 6.dp))
        }
    }
}

@Composable
private fun PeriodRow(recorded: Boolean, enabled: Boolean, onTap: () -> Unit) {
    val ink = Ink
    Row(
        Modifier
            .fillMaxWidth()
            .alpha(if (enabled) 1f else 0.5f)
            .background(ink.record.copy(alpha = 0.10f), RoundedCornerShape(14.dp))
            .clickable(enabled = enabled, onClick = onTap)
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(8.dp).background(ink.record, CircleShape))
        Text(stringResource(R.string.sheet_period), style = Fonts.system(15, FontWeight.SemiBold), color = ink.text)
        Spacer(Modifier.weight(1f))
        if (recorded) CheckCircle(checked = true, size = 18.dp, tint = ink.record)
        else PlusGlyph(ink.text.copy(alpha = 0.5f))
    }
}

@Composable
private fun PlusGlyph(color: Color) {
    androidx.compose.foundation.Canvas(Modifier.size(16.dp)) {
        val w = 1.8.dp.toPx()
        drawLine(color, androidx.compose.ui.geometry.Offset(size.width / 2, 0f), androidx.compose.ui.geometry.Offset(size.width / 2, size.height), w)
        drawLine(color, androidx.compose.ui.geometry.Offset(0f, size.height / 2), androidx.compose.ui.geometry.Offset(size.width, size.height / 2), w)
    }
}
