// 템포루틴 Android — 씨앗 배지 (iOS Seeds.swift SeedBadge/SeedGlyph). Phase 1: 개수 표시만, 탭 무동작(상점 P1).

package app.temporoutine.android.today

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.temporoutine.android.R
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink

/** 씨앗 글리프 — (0.5w,0) → 오른쪽 배 → (0.5w,h) → 왼쪽 배 → 닫힘. */
@Composable
fun SeedGlyph(color: Color, width: Dp, height: Dp, modifier: Modifier = Modifier) {
    Canvas(modifier.size(width, height).rotate(16f)) {
        val w = size.width
        val h = size.height
        val path = Path().apply {
            moveTo(0.5f * w, 0f)
            quadraticTo(1.12f * w, 0.68f * h, 0.5f * w, h)
            quadraticTo(-0.12f * w, 0.68f * h, 0.5f * w, 0f)
            close()
        }
        drawPath(path, color)
    }
}

@Composable
fun SeedBadge(count: Int, modifier: Modifier = Modifier) {
    val ink = Ink
    val label = stringResource(R.string.seeds_count_a11y, count)
    Row(
        modifier
            .semantics { contentDescription = label }
            .background(ink.surface, CircleShape)
            .border(1.dp, ink.text.copy(alpha = 0.15f), CircleShape)
            .padding(horizontal = 10.dp, vertical = 5.dp),
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SeedGlyph(color = ink.text.copy(alpha = 0.75f), width = 9.dp, height = 12.dp)
        Text(
            count.toString(),
            style = Fonts.almanacBody(13).copy(fontFeatureSettings = "tnum"),
            color = ink.text.copy(alpha = 0.8f),
        )
    }
}
