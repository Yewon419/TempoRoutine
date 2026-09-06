// 템포루틴 Android — 루트 탭 (iOS RootTabView 은필 분기): 하단바 = 블러 + paper 60%, 선택 text 100% / 미선택 45%, 알약 인디케이터 없음.
// Phase 2: 오늘·캘린더. 나의 템포·설정은 후속. 지면·계절광은 인셋 무시, 조판만 인셋 적용.
// Phase 3: 설정 로드 전엔 지면만(콜드 플래시 방지) → onboardingDone=false면 온보딩 전체 화면(iOS fullScreenCover 대응).

package app.temporoutine.android

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import app.temporoutine.android.calendar.CalendarRoute
import app.temporoutine.android.onboarding.OnboardingFlow
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.chromeGlass
import app.temporoutine.android.today.TodayRoute
import app.temporoutine.android.today.TodayViewModel
import dev.chrisbanes.haze.rememberHazeState

private val TAB_BAR_HEIGHT = 49.dp

enum class RootTab(val labelRes: Int) {
    TODAY(R.string.tab_today),
    CALENDAR(R.string.tab_calendar),
}

@Composable
fun RootScaffold(app: TempoApp, openLogSheetInitially: Boolean = false) {
    val ink = Ink
    val settings by app.settings.snapshot.collectAsState(initial = null)

    Box(Modifier.fillMaxSize().background(ink.paper)) {
        val loaded = settings ?: return@Box
        if (!loaded.onboardingDone) {
            OnboardingFlow(app)
            return@Box
        }
        val hazeState = rememberHazeState()
        var tab by rememberSaveable { mutableStateOf(RootTab.TODAY) }
        val todayVm: TodayViewModel = viewModel { TodayViewModel(app) }
        val navInset = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
        val bottomPadding = TAB_BAR_HEIGHT + navInset
        when (tab) {
            RootTab.TODAY -> TodayRoute(app, todayVm, hazeState, bottomPadding, openLogSheetInitially)
            RootTab.CALENDAR -> CalendarRoute(app, todayVm, hazeState, bottomPadding)
        }
        TabBar(tab, onSelect = { tab = it }, Modifier.align(Alignment.BottomCenter).chromeGlass(hazeState))
    }
}

@Composable
private fun TabBar(selected: RootTab, onSelect: (RootTab) -> Unit, modifier: Modifier) {
    val ink = Ink
    Column(
        modifier
            .fillMaxWidth()
            .drawBehind { drawRect(ink.text.copy(alpha = 0.12f), size = Size(size.width, 1f)) }   // 상단 헤어라인
            .windowInsetsPadding(WindowInsets.navigationBars),
    ) {
        Row(Modifier.fillMaxWidth().height(TAB_BAR_HEIGHT)) {
            for (t in RootTab.entries) {
                val on = t == selected
                val color = if (on) ink.text else ink.text.copy(alpha = 0.45f)
                Column(
                    Modifier
                        .weight(1f)
                        .fillMaxSize()
                        .semantics { role = Role.Tab; this.selected = on }
                        .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onSelect(t) },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
                ) {
                    TabIcon(t, color)
                    Text(stringResource(t.labelRes), style = Fonts.system(10, FontWeight.Medium), color = color, modifier = Modifier.padding(top = 2.dp))
                }
            }
        }
    }
}

/** SF Symbol 대용 — 오늘 = circle.inset.filled(링+중앙 채움), 캘린더 = calendar(둥근 사각 + 상단 띠 + 점). */
@Composable
private fun TabIcon(tab: RootTab, color: Color) {
    Canvas(Modifier.size(25.dp)) {
        val c = center
        when (tab) {
            RootTab.TODAY -> {
                drawCircle(color, radius = size.minDimension / 2 - 1.dp.toPx(), center = c, style = Stroke(width = 1.8.dp.toPx()))
                drawCircle(color, radius = size.minDimension * 0.3f, center = c)
            }
            RootTab.CALENDAR -> {
                val inset = 2.dp.toPx()
                val r = CornerRadius(3.dp.toPx())
                drawRoundRect(color, topLeft = Offset(inset, inset + 1.dp.toPx()), size = Size(size.width - inset * 2, size.height - inset * 2 - 1.dp.toPx()), cornerRadius = r, style = Stroke(width = 1.8.dp.toPx()))
                drawRect(color, topLeft = Offset(inset, inset + 1.dp.toPx()), size = Size(size.width - inset * 2, 5.dp.toPx()))
                val dot = 1.6.dp.toPx()
                for (row in 0 until 2) for (col in 0 until 3) {
                    drawCircle(color, dot, Offset(size.width * (0.28f + 0.22f * col), size.height * (0.55f + 0.2f * row)))
                }
            }
        }
    }
}
