// 템포루틴 Android — 오늘 구획 셸 (iOS TodayView.section(kind:)). 행은 Rows.kt.

package app.temporoutine.android.today

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.temporoutine.android.R
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.milkGlass
import dev.chrisbanes.haze.HazeState

enum class CardKind(val titleRes: Int, val infoRes: Int) {
    SCHEDULE(R.string.section_schedule, R.string.section_schedule_info),
    INPUT(R.string.section_input, R.string.section_input_info),
    OUTPUT(R.string.section_output, R.string.section_output_info),
}

@Composable
fun Section(kind: CardKind, hazeState: HazeState, rows: @Composable () -> Unit) {
    val ink = Ink
    Column(
        Modifier
            .fillMaxWidth()
            .milkGlass(hazeState)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(kind.titleRes), style = Fonts.almanac(17), color = ink.text)
            InfoBadge(kind)
            Spacer(Modifier.weight(1f))
            // + 버튼은 추가 시트(P1)와 함께 — Phase 1 가정 2
        }
        rows()
    }
}

@Composable
fun EmptyRow(text: String) {
    Text(text, style = Fonts.almanacBody(13), color = Ink.text.copy(alpha = 0.45f))
}
