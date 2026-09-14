// 템포루틴 Android — 온보딩 지면 (iOS TempoLens.swift OnboardingGround 이식)
// 프로토 `.world` 그대로: frost + 계절광 2겹(우상·좌하) + 겨울 선화 **한 장**(703.5 @ −36.2,13.6 · 11% multiply · contrast 0.88).
// 앱 지면(SeasonLight)은 선화 두 장이라 굵은 줄기가 가운데를 지나간다 — 온보딩은 프로토 구성을 따른다(iOS 2026-09-07 대조).
// DrawScope 함수로 둔 이유 = 렌즈가 같은 지면을 원본 농도(motifAlpha 1)로 한 번 더 그린다.

package app.temporoutine.android.onboarding

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import app.temporoutine.android.R
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.contrastMatrix
import kotlin.math.min
import kotlin.math.roundToInt

/** 온보딩 바탕 평면색 — 은필 지면이 열리기 전·렌즈가 평면일 때(iOS rgb 245,245,247) */
val OnboardingFlatColor = Color(0xFFF5F5F7)

private val lightTopRight = Color(185, 199, 209).copy(alpha = 0.42f)
private val lightBottomLeft = Color(160, 182, 199).copy(alpha = 0.52f)
private val motifFilter = ColorFilter.colorMatrix(contrastMatrix(0.88f))

@Composable
fun OnboardingGround(modifier: Modifier = Modifier, motifAlpha: Float = 0.11f) {
    val motif = ImageBitmap.imageResource(R.drawable.motif_winter)
    val frost = Ink.frost
    Canvas(modifier) { drawOnboardingGround(motif, frost, motifAlpha, size.width, size.height) }
}

/** w·h = 화면 전체 크기(px). 렌즈는 자기 크기가 아니라 화면 크기로 같은 지면을 그린 뒤 옮기고 키운다. */
fun DrawScope.drawOnboardingGround(motif: ImageBitmap, frost: Color, motifAlpha: Float, w: Float, h: Float) {
    drawRect(frost, size = androidx.compose.ui.geometry.Size(w, h))
    light(lightTopRight, rx = 0.9f * w, ry = 0.6f * h, at = Offset(0.8f * w, 0f))
    light(lightBottomLeft, rx = 0.7f * w, ry = 0.5f * h, at = Offset(0.1f * w, h))
    // 프로토 폭 402 기준 비례(태블릿은 430에서 캡)
    val k = min(w / density, 430f) / 402f
    val side = (703.5f * k).dp.toPx().roundToInt()
    drawImage(
        motif,
        dstOffset = IntOffset((-36.2f * k).dp.toPx().roundToInt(), (13.6f * k).dp.toPx().roundToInt()),
        dstSize = IntSize(side, side),
        alpha = motifAlpha,
        colorFilter = motifFilter,
        blendMode = BlendMode.Multiply,
    )
}

/** CSS `radial-gradient(rx ry at x y, color, transparent 70%)` — 원형 그라데이션을 세로로 눌러 타원으로 */
private fun DrawScope.light(color: Color, rx: Float, ry: Float, at: Offset) {
    scale(scaleX = 1f, scaleY = ry / rx.coerceAtLeast(1f), pivot = at) {
        drawCircle(Brush.radialGradient(listOf(color, Color.Transparent), center = at, radius = (rx * 0.7f).coerceAtLeast(1f)), radius = rx, center = at)
    }
}
