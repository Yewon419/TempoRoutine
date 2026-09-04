// 템포루틴 Android — 브랜드 마크 (iOS BrandLogo.swift:83-125): 12시 방향이 끊긴 원 + 끊긴 자리의 점.

package app.temporoutine.android.theme

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

@Composable
fun BrandMark(diameter: Dp = 22.dp, color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.size(diameter)) {
        val d = size.minDimension
        val stroke = d * 0.07f
        val ring = d - stroke
        val gap = 0.0331f * 360f
        drawArc(
            color = color,
            startAngle = -90f + gap,
            sweepAngle = 360f - gap * 2,
            useCenter = false,
            topLeft = Offset(stroke / 2, stroke / 2),
            size = Size(ring, ring),
            style = Stroke(width = stroke, cap = StrokeCap.Round),
        )
        val dot = d * 0.085f
        drawCircle(color = color, radius = dot, center = Offset(d / 2, d / 2 - ring / 2))
    }
}
