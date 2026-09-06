// 템포루틴 Android — 온보딩 ② 기준일 (iOS OnboardingBaseline.swift + OnboardingFlow durationPage/calendarPage/cyclePage 이식, 개정 M)
// P0는 건강 연동이 없어 지속일 → 월 캘린더 → (에피소드 1개일 때만) 주기 순서.
// DrumPicker: 상시 노출 세로 스피너(이웃 값 흐림 + 가운데 선택값 + 사이 화살표). 끝값에선 이웃을 투명하게만(자리 유지).
// OnboardingCalendar: 시작일 탭 = 지속일만큼 자동 채움, 칸 탭 = 개별 토글, 이전 달 이동 가능·미래 차단.

package app.temporoutine.android.onboarding

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.temporoutine.android.R
import app.temporoutine.android.calendar.MonthLayout
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.milkGlass
import dev.chrisbanes.haze.HazeState
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.WeekFields
import java.util.Locale

// ── 세로 스피너 ──

@Composable
fun DrumPicker(value: Int, range: IntRange, unit: String, onChange: (Int) -> Unit) {
    val ink = Ink
    fun step(d: Int) {
        val next = (value + d).coerceIn(range)
        if (next != value) onChange(next)
    }
    val a11y = "$value$unit"
    Column(
        Modifier.fillMaxWidth().semantics { contentDescription = a11y },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Adjacent(value - 1, visible = value > range.first) { step(-1) }
        Arrow(up = true, enabled = value > range.first) { step(-1) }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            Text("$value", style = TextStyle(fontFamily = Fonts.gowunBatang, fontWeight = FontWeight.Bold, fontSize = 54.sp, lineHeight = 58.sp), color = ink.text)
            Text(unit, style = Fonts.system(17, FontWeight.Medium), color = ink.text.copy(alpha = 0.5f), modifier = Modifier.padding(bottom = 10.dp))
        }
        Arrow(up = false, enabled = value < range.last) { step(1) }
        Adjacent(value + 1, visible = value < range.last) { step(1) }
    }
}

@Composable
private fun Adjacent(n: Int, visible: Boolean, onClick: () -> Unit) {
    val ink = Ink
    Text(
        if (visible) "$n" else " ",
        style = TextStyle(fontFamily = Fonts.gowunBatang, fontSize = 22.sp, lineHeight = 26.sp), color = ink.text.copy(alpha = 0.25f),
        modifier = Modifier
            .heightIn(min = 30.dp)
            .alpha(if (visible) 1f else 0f)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, enabled = visible, onClick = onClick),
    )
}

@Composable
private fun Arrow(up: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val ink = Ink
    Box(
        Modifier
            .size(96.dp, 36.dp)
            .alpha(if (enabled) 1f else 0f)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(16.dp, 9.dp)) {
            val p = Path().apply {
                if (up) { moveTo(0f, size.height); lineTo(size.width / 2, 0f); lineTo(size.width, size.height) }
                else { moveTo(0f, 0f); lineTo(size.width / 2, size.height); lineTo(size.width, 0f) }
            }
            drawPath(p, ink.text.copy(alpha = 0.55f), style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round))
        }
    }
}

// ── 온보딩 월 캘린더 ──

@Composable
fun OnboardingCalendar(markedDays: Set<LocalDate>, today: LocalDate, onTapDay: (LocalDate) -> Unit) {
    val ink = Ink
    val locale = Locale.getDefault()
    val firstDayOfWeek = remember(locale) { WeekFields.of(locale).firstDayOfWeek }
    var monthStart by rememberSaveable { mutableStateOf(today.withDayOfMonth(1)) }
    val layout = remember(monthStart, firstDayOfWeek) { MonthLayout(monthStart, firstDayOfWeek) }
    val canGoForward = BaselineLogic.canGoForward(monthStart, today)

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            MonthChevron(left = true, label = stringResource(R.string.calendar_prev_month), enabled = true) { monthStart = monthStart.minusMonths(1) }
            Spacer(Modifier.weight(1f))
            Text(
                monthStart.format(DateTimeFormatter.ofPattern(stringResource(R.string.ob_month_format), locale)),
                style = Fonts.almanacBody(15, bold = true), color = ink.text,
            )
            Spacer(Modifier.weight(1f))
            MonthChevron(left = false, label = stringResource(R.string.calendar_next_month), enabled = canGoForward) { monthStart = monthStart.plusMonths(1) }
        }
        Row(Modifier.fillMaxWidth()) {
            for (i in 0 until 7) {
                val dow: DayOfWeek = firstDayOfWeek.plus(i.toLong())
                Text(
                    dow.getDisplayName(java.time.format.TextStyle.NARROW, locale), style = Fonts.system(11), color = ink.text.copy(alpha = 0.4f),
                    modifier = Modifier.weight(1f), textAlign = TextAlign.Center,
                )
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            for (row in 0 until layout.rowCount) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    for (col in 0 until 7) {
                        val day = layout.date(row * 7 + col)
                        if (day == null) {
                            Spacer(Modifier.weight(1f).height(40.dp))
                        } else {
                            DayCell(day, marked = day in markedDays, future = day > today, modifier = Modifier.weight(1f)) { onTapDay(day) }
                        }
                    }
                }
            }
        }
        Text(
            stringResource(R.string.ob_calendar_note), style = Fonts.almanacBody(12), color = ink.text.copy(alpha = 0.5f),
            modifier = Modifier.fillMaxWidth().padding(top = 4.dp), textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun DayCell(day: LocalDate, marked: Boolean, future: Boolean, modifier: Modifier, onTap: () -> Unit) {
    val ink = Ink
    val shape = RoundedCornerShape(10.dp)
    Box(
        modifier
            .height(40.dp)
            .background(if (marked) ink.text else androidx.compose.ui.graphics.Color.Transparent, shape)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, enabled = !future, onClick = onTap),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            "${day.dayOfMonth}", style = Fonts.almanacBody(15),
            color = when {
                future -> ink.text.copy(alpha = 0.2f)
                marked -> ink.paper
                else -> ink.text
            },
        )
    }
}

@Composable
private fun MonthChevron(left: Boolean, label: String, enabled: Boolean, onClick: () -> Unit) {
    val ink = Ink
    Box(
        Modifier.size(44.dp).alpha(if (enabled) 1f else 0f).semantics { contentDescription = label }.clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(10.dp, 16.dp)) {
            val p = Path().apply {
                if (left) { moveTo(size.width, 0f); lineTo(0f, size.height / 2); lineTo(size.width, size.height) }
                else { moveTo(0f, 0f); lineTo(size.width, size.height / 2); lineTo(0f, size.height) }
            }
            drawPath(p, ink.text.copy(alpha = 0.6f), style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round))
        }
    }
}

// ── 페이지 3장 ──

/** ②-2 지속일 스피너 — 가운데 고정·무게중심 위(프로토: padding-bottom 72) */
@Composable
fun ColumnScope.DurationPage(value: Int, onChange: (Int) -> Unit) {
    StepHeader(stringResource(R.string.ob_baseline_eyebrow), stringResource(R.string.ob_duration_title))
    Spacer(Modifier.weight(1f))
    DrumPicker(value, 1..10, stringResource(R.string.ob_unit_days), onChange)
    Spacer(Modifier.weight(1f).heightIn(min = 72.dp))
}

/** ②-3 월 캘린더 — 시작일 탭 = 자동 채움·개별 토글·지난달 이동 */
@Composable
fun ColumnScope.CalendarPage(markedDays: Set<LocalDate>, today: LocalDate, hazeState: HazeState, onTapDay: (LocalDate) -> Unit) {
    val ink = Ink
    StepHeader(stringResource(R.string.ob_baseline_eyebrow), stringResource(R.string.ob_calendar_title))
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        val style = Fonts.almanacBody(13)
        val color = ink.text.copy(alpha = 0.55f)
        Text(stringResource(R.string.ob_calendar_line1), style = style, color = color)
        Text(stringResource(R.string.ob_calendar_line2), style = style, color = color)
    }
    Box(Modifier.fillMaxWidth().milkGlass(hazeState).padding(12.dp)) {
        OnboardingCalendar(markedDays, today, onTapDay)
    }
}

/** ②-4 주기 스피너 — 에피소드 정확히 1개일 때만 도달. 답 → N prior(T1b). */
@Composable
fun ColumnScope.CyclePage(value: Int, onChange: (Int) -> Unit) {
    val ink = Ink
    StepHeader(stringResource(R.string.ob_baseline_eyebrow), stringResource(R.string.ob_cycle_title))
    Text(stringResource(R.string.ob_cycle_line), style = Fonts.almanacBody(13), color = ink.text.copy(alpha = 0.55f))
    Spacer(Modifier.weight(1f))
    DrumPicker(value, 21..35, stringResource(R.string.ob_unit_days), onChange)
    Spacer(Modifier.weight(1f).heightIn(min = 72.dp))
}
