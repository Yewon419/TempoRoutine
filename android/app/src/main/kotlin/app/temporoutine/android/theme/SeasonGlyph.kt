// 템포루틴 Android — 계절 글리프 4종 (iOS Almanac.swift SeasonGlyphShape, 16단위 뷰박스) — 색맹 담보: 색+형태.

package app.temporoutine.android.theme

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.temporoutine.core.CyclePhase

@Composable
fun SeasonGlyph(phase: CyclePhase, color: Color, size: Dp = 13.dp, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) {
        val s = this.size.minDimension / 16f
        val stroke = Stroke(width = 1.4.dp.toPx(), cap = StrokeCap.Round)
        fun line(x1: Float, y1: Float, x2: Float, y2: Float) =
            drawLine(color, Offset(x1 * s, y1 * s), Offset(x2 * s, y2 * s), stroke.width, StrokeCap.Round)
        when (phase) {
            CyclePhase.MENSTRUAL -> { line(8f, 2f, 8f, 14f); line(2.8f, 5f, 13.2f, 11f); line(13.2f, 5f, 2.8f, 11f) }
            CyclePhase.FOLLICULAR -> {
                line(8f, 14f, 8f, 6f)
                val p = Path().apply {
                    moveTo(8f * s, 8f * s); cubicTo(8f * s, 5.4f * s, 6f * s, 4f * s, 4f * s, 4f * s); cubicTo(4f * s, 6.6f * s, 6f * s, 8f * s, 8f * s, 8f * s)
                    moveTo(8f * s, 6.6f * s); cubicTo(8f * s, 4.2f * s, 10f * s, 3f * s, 12f * s, 3f * s); cubicTo(12f * s, 5.4f * s, 10f * s, 6.6f * s, 8f * s, 6.6f * s)
                }
                drawPath(p, color, style = stroke)
            }
            CyclePhase.OVULATION -> {
                drawOval(color, topLeft = Offset(4.8f * s, 4.8f * s), size = Size(6.4f * s, 6.4f * s), style = stroke)
                line(8f, 1.5f, 8f, 3.2f); line(8f, 12.8f, 8f, 14.5f); line(1.5f, 8f, 3.2f, 8f); line(12.8f, 8f, 14.5f, 8f)
            }
            CyclePhase.LUTEAL -> {
                val p = Path().apply {
                    moveTo(13f * s, 3f * s); cubicTo(8f * s, 3f * s, 4f * s, 6f * s, 3f * s, 12f * s); cubicTo(9f * s, 11f * s, 12f * s, 8f * s, 13f * s, 3f * s); close()
                }
                drawPath(p, color, style = stroke)
                line(3f, 12f, 9f, 6f)
            }
        }
    }
}

@Suppress("unused")
private fun DrawScope.noop() = Unit
