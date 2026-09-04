// 템포루틴 Android — 구획 ⓘ (iOS DayDetailView.InfoBadge): 탭 → 구획 이름 제목 + 설명 + 「확인」.

package app.temporoutine.android.today

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.temporoutine.android.R
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink

@Composable
fun InfoBadge(kind: CardKind) {
    val ink = Ink
    var open by remember { mutableStateOf(false) }
    val title = stringResource(kind.titleRes)
    val label = stringResource(R.string.section_info_a11y, title)
    Box(
        Modifier
            .size(24.dp, 28.dp)
            .semantics { contentDescription = label }
            .clickable { open = true },
        contentAlignment = Alignment.Center,
    ) {
        // questionmark.circle 대용 — 원 + "?" 텍스트
        val c = ink.text.copy(alpha = 0.35f)
        Canvas(Modifier.size(13.dp)) {
            drawCircle(color = c, style = Stroke(width = 1.2.dp.toPx()), center = Offset(size.width / 2, size.height / 2), radius = size.minDimension / 2 - 1)
        }
        Text("?", style = Fonts.system(9), color = c)
    }
    if (open) {
        AlertDialog(
            onDismissRequest = { open = false },
            confirmButton = { TextButton(onClick = { open = false }) { Text(stringResource(R.string.ok)) } },
            title = { Text(title) },
            text = { Text(stringResource(kind.infoRes)) },
        )
    }
}
