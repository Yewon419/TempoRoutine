// 템포루틴 Android — 온보딩 내 주기 월 캘린더 (iOS OnboardingBaseline.swift OnboardingCalendar 이식, 개정 M)
// 시작일 탭 = 지속일만큼 자동 채움, 칸 탭 = 개별 토글, 이전 달 이동 가능·미래 차단. 하단 유리 시트 안에 놓인다.
// 지속일·주기 입력은 자(RulerSlider, OnboardingControls.kt) — 2026-09-07 iOS 드럼 피커 은퇴를 따라 걷었다.

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
import app.temporoutine.android.theme.Radius
import app.temporoutine.android.theme.milkGlass
import dev.chrisbanes.haze.HazeState
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.WeekFields
import java.util.Locale

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
    val shape = RoundedCornerShape(Radius.inner)
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
