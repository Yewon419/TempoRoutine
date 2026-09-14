// 템포루틴 Android — 오늘 구획 셸 (iOS TodayView.section(kind:)). 행은 Rows.kt.
// 껍데기(iOS Almanac.swift SectionChrome, §8.2.2): 일정 = 풀블리드 띠, 루틴·목표 = 밀크 글래스 카드.

package app.temporoutine.android.today

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.layout.layout
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.temporoutine.android.R
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.milkGlass
import dev.chrisbanes.haze.HazeState

/** briefRes = 제목 옆 한 줄 정의(iOS 91-5, 2026-09-12) — ⓘ는 눌러야 보여서 「루틴·목표가 뭔지」가 3초 안에 안 읽혔다. 일정은 말 그대로라 없음. */
enum class CardKind(val titleRes: Int, val infoRes: Int, val briefRes: Int?) {
    SCHEDULE(R.string.section_schedule, R.string.section_schedule_info, null),
    INPUT(R.string.section_input, R.string.section_input_info, R.string.section_input_brief),
    OUTPUT(R.string.section_output, R.string.section_output_info, R.string.section_output_brief),
}

/** 스크롤 컬럼 여백(20)을 상쇄해 화면 폭으로 편다 — iOS `.padding(.horizontal, -20)`. */
private fun Modifier.fullBleed(gutter: Dp): Modifier = layout { measurable, constraints ->
    val extra = gutter.roundToPx() * 2
    val width = constraints.maxWidth + extra
    val placeable = measurable.measure(constraints.copy(minWidth = width, maxWidth = width))
    layout(constraints.maxWidth, placeable.height) { placeable.place(-extra / 2, 0) }
}

@Composable
fun Section(kind: CardKind, hazeState: HazeState, rows: @Composable () -> Unit) {
    val ink = Ink
    val body: @Composable ColumnScope.() -> Unit = {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(kind.titleRes), style = Fonts.almanac(17), color = ink.text, modifier = Modifier.alignByBaseline())
                kind.briefRes?.let {
                    Text(stringResource(it), style = Fonts.system(12), color = ink.text.copy(alpha = 0.5f), modifier = Modifier.alignByBaseline())
                }
            }
            InfoBadge(kind)
            Spacer(Modifier.weight(1f))
            // + 버튼은 추가 시트(P1)와 함께 — Phase 1 가정 2
        }
        rows()
    }
    if (kind == CardKind.SCHEDULE) {
        // 풀블리드 띠(iOS 은필 v2) — 지면 0.6 → 0.88 · 괘선 0.24 → 0.32(베타 09-13 "일정 저거 너무 투명하다")
        Column(
            Modifier
                .fullBleed(20.dp)
                .background(ink.surface.copy(alpha = ink.surface.alpha * 0.88f))
                .drawBehind {
                    val line = 1.dp.toPx()
                    val color = ink.accent.copy(alpha = 0.32f)
                    drawRect(color, size = Size(size.width, line))
                    drawRect(color, topLeft = Offset(0f, size.height - line), size = Size(size.width, line))
                }
                .padding(horizontal = 20.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            content = body,
        )
    } else {
        Column(
            Modifier
                .fillMaxWidth()
                .milkGlass(hazeState)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            content = body,
        )
    }
}

@Composable
fun EmptyRow(text: String) {
    Text(text, style = Fonts.almanacBody(13), color = Ink.text.copy(alpha = 0.45f))
}
