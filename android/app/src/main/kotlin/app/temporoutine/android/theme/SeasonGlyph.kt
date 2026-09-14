// 템포루틴 Android — 계절 글리프 4종 (iOS Almanac.swift SeasonGlyphShape, 16단위 뷰박스) — 색맹 담보: 색+형태.
// 획 단위 컨투어 목록으로 둔다 — 온보딩 사계절 장(J2)은 같은 글리프를 선이 그려지듯 순차 trim한다(drawTrimmedContours).

package app.temporoutine.android.theme

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.temporoutine.core.CyclePhase

@Composable
fun SeasonGlyph(phase: CyclePhase, color: Color, size: Dp = 13.dp, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) {
        val stroke = Stroke(width = 1.4.dp.toPx(), cap = StrokeCap.Round)
        for (contour in seasonGlyphContours(phase, this.size.minDimension / 16f)) drawPath(contour, color, style = stroke)
    }
}

/** 16단위 좌표 × s(px/단위). 획 순서 = iOS SeasonGlyphShape의 move 순서. */
fun seasonGlyphContours(phase: CyclePhase, s: Float): List<Path> {
    fun line(x1: Float, y1: Float, x2: Float, y2: Float) = Path().apply { moveTo(x1 * s, y1 * s); lineTo(x2 * s, y2 * s) }
    return when (phase) {
        CyclePhase.MENSTRUAL -> listOf(line(8f, 2f, 8f, 14f), line(2.8f, 5f, 13.2f, 11f), line(13.2f, 5f, 2.8f, 11f))   // 겨울 = 눈결정 3획
        CyclePhase.FOLLICULAR -> listOf(   // 봄 = 새싹
            line(8f, 14f, 8f, 6f),
            Path().apply { moveTo(8f * s, 8f * s); cubicTo(8f * s, 5.4f * s, 6f * s, 4f * s, 4f * s, 4f * s); cubicTo(4f * s, 6.6f * s, 6f * s, 8f * s, 8f * s, 8f * s) },
            Path().apply { moveTo(8f * s, 6.6f * s); cubicTo(8f * s, 4.2f * s, 10f * s, 3f * s, 12f * s, 3f * s); cubicTo(12f * s, 5.4f * s, 10f * s, 6.6f * s, 8f * s, 6.6f * s) },
        )
        CyclePhase.OVULATION -> listOf(   // 여름 = 해
            Path().apply { addOval(Rect(4.8f * s, 4.8f * s, 11.2f * s, 11.2f * s)) },
            line(8f, 1.5f, 8f, 3.2f), line(8f, 12.8f, 8f, 14.5f), line(1.5f, 8f, 3.2f, 8f), line(12.8f, 8f, 14.5f, 8f),
        )
        CyclePhase.LUTEAL -> listOf(   // 가을 = 잎
            Path().apply { moveTo(13f * s, 3f * s); cubicTo(8f * s, 3f * s, 4f * s, 6f * s, 3f * s, 12f * s); cubicTo(9f * s, 11f * s, 12f * s, 8f * s, 13f * s, 3f * s); close() },
            line(3f, 12f, 9f, 6f),
        )
    }
}
