// 템포루틴 Android — 계절광 (iOS Almanac.swift SeasonLight 이식): 3겹 radial + 은필 모티프 2타일(multiply) + 마스크 + 다크 0.35.
// 지면 고정, 빛만 교체(§4). 콜드스타트(null)와 겨울은 같은 겨울광·겨울 모티프.
// 근사 2건(2026-09-04): 타일 가장자리 페더(5% blur 마스크)는 생략, contrast 0.95는 ColorMatrix로.
// ⚠ multiply는 실제 배경 위에 직접 그린다 — 오프스크린 레이어에 그리면 투명 위 multiply = 원본이라 흰 지면이 통째로 얹힌다(실측).
//   그래서 세로 마스크(상단 18% = 0.35, 32%까지 램프)는 가로 띠로 잘라 alpha를 달리 그린다.

package app.temporoutine.android.theme

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import app.temporoutine.android.R
import app.temporoutine.core.CyclePhase

private data class Light(val a: Color, val b: Color, val c: Color)

private fun rgba(r: Int, g: Int, b: Int, a: Float) = Color(r, g, b).copy(alpha = a)

private fun lightColors(phase: CyclePhase?): Light = when (phase) {
    CyclePhase.FOLLICULAR -> Light(rgba(226, 211, 186, 0.55f), rgba(238, 227, 206, 0.38f), rgba(219, 203, 176, 0.42f))
    CyclePhase.OVULATION -> Light(rgba(207, 221, 179, 0.55f), rgba(231, 237, 214, 0.38f), rgba(198, 214, 172, 0.42f))
    CyclePhase.LUTEAL -> Light(rgba(206, 158, 132, 0.52f), rgba(219, 184, 162, 0.36f), rgba(198, 152, 128, 0.40f))
    CyclePhase.MENSTRUAL, null -> Light(rgba(148, 172, 192, 0.72f), rgba(185, 199, 209, 0.42f), rgba(160, 182, 199, 0.52f))
}

private fun motifRes(phase: CyclePhase?): Int = when (phase) {
    CyclePhase.FOLLICULAR -> R.drawable.motif_spring
    CyclePhase.OVULATION -> R.drawable.motif_summer
    CyclePhase.LUTEAL -> R.drawable.motif_autumn
    CyclePhase.MENSTRUAL, null -> R.drawable.motif_winter
}

enum class MotifStyle { CARD, ONBOARDING }

@Composable
fun SeasonLight(phase: CyclePhase?, modifier: Modifier = Modifier, motif: MotifStyle = MotifStyle.CARD) {
    val chrome = LocalChrome.current
    val dark = isSystemInDarkTheme()
    val colors = lightColors(phase)
    val raw: ImageBitmap = ImageBitmap.imageResource(motifRes(phase))
    // iOS motifTile의 가장자리 페더(5% 안쪽 rect + 5% blur 마스크) — 두 타일이 겹치는 경계(topLeading 타일 하단)가
    // 직선으로 드러나는 걸 막는다. 비트맵 alpha에 한 번 구워 둔다(multiply는 레이어 마스크를 못 쓴다).
    val bitmap: ImageBitmap = remember(raw) { feathered(raw, 0.10f) }
    val layerAlpha = if (chrome.dimsInDarkMode && dark) 0.35f else 1f
    val motifAlpha = if (motif == MotifStyle.ONBOARDING) 0.14f else 0.46f
    val contrast = if (motif == MotifStyle.ONBOARDING) 0.88f else 0.95f

    Canvas(modifier.graphicsLayer(alpha = layerAlpha)) {
        if (chrome.showsSeasonLight) {
            radial(colors.a, 0.18f, -0.08f, 430.dp.toPx())
            radial(colors.b, 0.88f, 0.22f, 340.dp.toPx())
            radial(colors.c, 0.50f, 1.08f, 420.dp.toPx())
        }
        if (chrome.motifTexture) {
            drawMotifLayer(bitmap, motifAlpha, contrast, maskTopAlpha = 0.35f)
        }
    }
}

private fun DrawScope.radial(color: Color, cx: Float, cy: Float, radiusPx: Float) {
    val center = Offset(size.width * cx, size.height * cy)
    drawRect(brush = Brush.radialGradient(listOf(color, Color.Transparent), center = center, radius = radiusPx))
}

/** 두 타일(1.75 topLeading / 2.40 bottomTrailing)을 multiply로 얹는다. 세로 마스크는 띠별 alpha로 근사. */
private fun DrawScope.drawMotifLayer(bitmap: ImageBitmap, alpha: Float, contrast: Float, maskTopAlpha: Float) {
    val base = minOf(size.width, 430.dp.toPx())
    val filter = ColorFilter.colorMatrix(contrastMatrix(contrast))
    val h = size.height
    // 0~18%: 0.35 / 18~32%: 6단 램프 / 32~100%: 1.0
    val bands = buildList {
        add(0f to 0.18f to maskTopAlpha)
        val steps = 6
        for (i in 0 until steps) {
            val t0 = 0.18f + (0.32f - 0.18f) * i / steps
            val t1 = 0.18f + (0.32f - 0.18f) * (i + 1) / steps
            val m = maskTopAlpha + (1f - maskTopAlpha) * (i + 0.5f) / steps
            add(t0 to t1 to m)
        }
        add(0.32f to 1f to 1f)
    }
    for ((range, mask) in bands) {
        val (t0, t1) = range
        clipRect(top = h * t0, bottom = h * t1) {
            tile(bitmap, base * 1.75f, topLeading = true, filter, alpha * mask)
            tile(bitmap, base * 2.40f, topLeading = false, filter, alpha * mask)
        }
    }
}

private fun DrawScope.tile(bitmap: ImageBitmap, side: Float, topLeading: Boolean, filter: ColorFilter, alpha: Float) {
    val sideInt = side.toInt()
    val offset = if (topLeading) IntOffset(0, 0) else IntOffset((size.width - side).toInt(), (size.height - side).toInt())
    drawImage(
        image = bitmap,
        dstOffset = offset,
        dstSize = IntSize(sideInt, sideInt),
        alpha = alpha,
        colorFilter = filter,
        blendMode = BlendMode.Multiply,
    )
}

/** 네 변에서 안쪽 `fraction`까지 alpha 0→1 램프(DST_IN 4회 = 램프의 곱). */
private fun feathered(source: ImageBitmap, fraction: Float): ImageBitmap {
    val src = source.asAndroidBitmap()
    val out = src.copy(android.graphics.Bitmap.Config.ARGB_8888, true)
    val canvas = android.graphics.Canvas(out)
    val w = out.width.toFloat()
    val h = out.height.toFloat()
    val fx = w * fraction
    val fy = h * fraction
    val paint = android.graphics.Paint().apply {
        xfermode = android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.DST_IN)
    }
    val edges = listOf(
        floatArrayOf(0f, 0f, fx, 0f), floatArrayOf(w, 0f, w - fx, 0f),
        floatArrayOf(0f, 0f, 0f, fy), floatArrayOf(0f, h, 0f, h - fy),
    )
    for (e in edges) {
        paint.shader = android.graphics.LinearGradient(
            e[0], e[1], e[2], e[3],
            android.graphics.Color.TRANSPARENT, android.graphics.Color.BLACK,
            android.graphics.Shader.TileMode.CLAMP,
        )
        canvas.drawRect(0f, 0f, w, h, paint)
    }
    return out.asImageBitmap()
}

private fun contrastMatrix(c: Float): ColorMatrix {
    val t = (1f - c) / 2f * 255f
    return ColorMatrix(floatArrayOf(
        c, 0f, 0f, 0f, t,
        0f, c, 0f, 0f, t,
        0f, 0f, c, 0f, t,
        0f, 0f, 0f, 1f, 0f,
    ))
}
