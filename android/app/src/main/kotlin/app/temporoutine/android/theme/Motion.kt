// 템포루틴 Android — 모션 공통 (iOS accessibilityReduceMotion · Shape.trim 대응)

package app.temporoutine.android.theme

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext

/** iOS accessibilityReduceMotion 대응 — 시스템 애니메이터 배율 0(개발자 옵션·접근성 「애니메이션 제거」). */
@Composable
fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember {
        android.provider.Settings.Global.getFloat(context.contentResolver, android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
}

/** SwiftUI spring(response:dampingFraction:) → Compose stiffness. ω = 2π/response, k = ω². */
fun springStiffness(response: Float): Float {
    val omega = (2.0 * Math.PI / response).toFloat()
    return omega * omega
}

/** 경로 부분 드로잉 — SwiftUI `.trim(from: 0, to:)` 대응. */
fun DrawScope.drawTrimmed(path: Path, progress: Float, color: Color, stroke: Stroke) {
    if (progress <= 0f) return
    if (progress >= 1f) { drawPath(path, color, style = stroke); return }
    val measure = PathMeasure()
    measure.setPath(path, false)
    val segment = Path()
    measure.getSegment(0f, measure.length * progress, segment, true)
    drawPath(segment, color, style = stroke)
}

/** 여러 컨투어를 하나의 경로처럼 순차 트림한다(누적 길이 기준) — Compose PathMeasure는 첫 컨투어만 잰다. */
fun DrawScope.drawTrimmedContours(contours: List<Path>, progress: Float, color: Color, stroke: Stroke) {
    if (progress <= 0f) return
    val measure = PathMeasure()
    val lengths = contours.map { measure.setPath(it, false); measure.length }
    val total = lengths.sum()
    var consumed = 0f
    for ((i, path) in contours.withIndex()) {
        val len = lengths[i]
        val local = if (len <= 0f) 1f else ((progress * total - consumed) / len).coerceIn(0f, 1f)
        drawTrimmed(path, local, color, stroke)
        consumed += len
    }
}
