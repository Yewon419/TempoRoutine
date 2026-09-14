// 템포루틴 Android — 온보딩 사계절 장 「렌즈가 창이 된다」 (iOS SeasonWindow.swift + FilmGrain.metal 이식)
// 브랜드 장의 렌즈 자리에서 원이 커지며 화면을 덮고, 그 안에 티저 광고 스틸(겨울 창가 · 봄 유채밭 · 여름 숲 · 가을 안락의자)이 찬다.
// 계절 사이 = 크로스페이드 0.6 + 느린 확대 드리프트(1.06 → 1.0, 1.6s). 위아래 먹 그라데이션은 흰 활자(J2) 자리.
// 필름 그레인은 셰이더 대신 사진을 불러올 때 한 번 굽는다 — 사진이 정지 이미지라 전 API에서 같게 나오고 프레임 비용이 없다.
// ⚠ 명시 크기를 주지 않는다(iOS 89-b: 부모가 커져 하단 CTA가 화면 밖으로 밀렸다) — 부모를 채우기만 한다.

package app.temporoutine.android.onboarding

import android.content.res.Resources
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import app.temporoutine.android.R
import app.temporoutine.core.CyclePhase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sin

private val inkShade = Color(18, 20, 23)
private const val GRAIN_AMOUNT = 0.09f   // 94차-3: 0.16은 영상 노이즈로 읽혔다

fun seasonPhotoRes(phase: CyclePhase): Int = when (phase) {
    CyclePhase.MENSTRUAL -> R.drawable.season_photo_winter
    CyclePhase.FOLLICULAR -> R.drawable.season_photo_spring
    CyclePhase.OVULATION -> R.drawable.season_photo_summer
    CyclePhase.LUTEAL -> R.drawable.season_photo_autumn
}

/**
 * @param center 창 중심(화면 전체 좌표 dp, 렌즈 hero 자리) · diameter 창 지름(dp, 바깥이 애니메이션)
 * @param photos 그레인을 구운 사진(rememberSeasonPhotos) — 아직 안 구워진 장은 창이 먹 그라데이션만 보인다
 */
@Composable
fun SeasonWindow(phase: CyclePhase, center: Offset, diameter: Float, photos: Map<CyclePhase, ImageBitmap>, reduceMotion: Boolean, modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxSize()
            .drawWithContent {
                val c = Offset(center.x.dp.toPx(), center.y.dp.toPx())
                clipPath(Path().apply { addOval(Rect(c, max(1f, diameter.dp.toPx()) / 2f)) }) { this@drawWithContent.drawContent() }
            }
            .clearAndSetSemantics { },
    ) {
        // 계절 사이 전환 = 크로스페이드 0.6(J2 — 카피 등장 스태거와 겹치게 조금 길게)
        Crossfade(targetState = phase, animationSpec = tween(if (reduceMotion) 0 else 600, easing = EaseOut), label = "seasonPhoto") { p ->
            SeasonPhotoDrift(photos[p], reduceMotion)
        }
        Box(
            Modifier.fillMaxSize().drawWithContent {
                drawRect(Brush.verticalGradient(0f to Color.Black.copy(alpha = 0.46f), 0.24f to Color.Black.copy(alpha = 0f)))
                drawRect(Brush.verticalGradient(
                    0.32f to inkShade.copy(alpha = 0f), 0.50f to inkShade.copy(alpha = 0.22f),
                    0.76f to inkShade.copy(alpha = 0.74f), 1f to inkShade.copy(alpha = 0.94f),
                ))
            },
        )
    }
}

/**
 * 그레인을 구운 사진 캐시 — wanted만 들고 나머지는 놓는다(1080×1920 ARGB 한 장 ≈ 8MB).
 * 브랜드 장에서 겨울을 미리 구워 두면 창이 열릴 때 빈 원이 안 보인다.
 */
@Composable
fun rememberSeasonPhotos(wanted: Set<CyclePhase>, cellPx: Int): Map<CyclePhase, ImageBitmap> {
    val resources = LocalContext.current.resources
    val cache = remember { mutableStateMapOf<CyclePhase, ImageBitmap>() }
    LaunchedEffect(wanted, cellPx) {
        cache.keys.filter { it !in wanted }.forEach { cache.remove(it) }
        for (phase in wanted) {
            if (cache.containsKey(phase)) continue
            cache[phase] = withContext(Dispatchers.Default) { loadGrainedPhoto(resources, seasonPhotoRes(phase), cellPx) }
        }
    }
    return cache
}

/** 현재 장 ± 1 — 넘기거나 되돌아올 때 이미 구워져 있게 */
fun seasonNeighbors(index: Int): Set<CyclePhase> = setOf(index - 1, index, index + 1).mapNotNull { seasonOrder.getOrNull(it) }.toSet()

@Composable
private fun SeasonPhotoDrift(bitmap: ImageBitmap?, reduceMotion: Boolean) {
    // 사진마다 드리프트가 처음부터(1.06 → 1.0, 1.6s). 모션 축소 = 정지.
    val scale = remember { Animatable(if (reduceMotion) 1f else 1.06f) }
    LaunchedEffect(bitmap != null) {
        if (bitmap == null) return@LaunchedEffect
        if (reduceMotion) scale.snapTo(1f) else scale.animateTo(1f, tween(1_600, easing = EaseOut))
    }
    val image = bitmap ?: return
    Image(
        bitmap = image, contentDescription = null, contentScale = ContentScale.Crop,
        modifier = Modifier.fillMaxSize().graphicsLayer { scaleX = scale.value; scaleY = scale.value },
    )
}

/** 사진 디코딩 + 필름 그레인(iOS FilmGrain.metal과 같은 해시): 셀 좌표 해시 노이즈를 밝기에 ±amount/2 더한다. 정적 노이즈. */
private fun loadGrainedPhoto(resources: Resources, res: Int, cellPx: Int): ImageBitmap {
    val options = BitmapFactory.Options().apply { inMutable = true; inPreferredConfig = Bitmap.Config.ARGB_8888 }
    val bmp = BitmapFactory.decodeResource(resources, res, options)
    val w = bmp.width
    val h = bmp.height
    val pixels = IntArray(w * h)
    bmp.getPixels(pixels, 0, w, 0, 0, w, h)
    val cell = cellPx.coerceAtLeast(1)
    for (y in 0 until h) {
        val cy = (y / cell).toDouble()
        val row = y * w
        for (x in 0 until w) {
            val cx = (x / cell).toDouble()
            val n = fract(sin(cx * 12.9898 + cy * 78.233) * 43758.5453)
            val g = ((n - 0.5) * GRAIN_AMOUNT * 255.0).roundToInt()
            val p = pixels[row + x]
            val r = ((p shr 16 and 0xFF) + g).coerceIn(0, 255)
            val gr = ((p shr 8 and 0xFF) + g).coerceIn(0, 255)
            val b = ((p and 0xFF) + g).coerceIn(0, 255)
            pixels[row + x] = (p and -0x1000000) or (r shl 16) or (gr shl 8) or b
        }
    }
    bmp.setPixels(pixels, 0, w, 0, 0, w, h)
    return bmp.asImageBitmap()
}

private fun fract(v: Double): Double = v - floor(v)

/** iOS 그레인 셀 = 2pt(사진이 화면을 채우는 크롭 배율 기준 사용자 공간). 사진 픽셀로 환산한다. */
@Composable
fun rememberGrainCellPx(screenWidthDp: Float, screenHeightDp: Float): Int {
    val density = LocalDensity.current.density
    return remember(screenWidthDp, screenHeightDp, density) {
        val fill = max(screenWidthDp * density / 1080f, screenHeightDp * density / 1920f)   // 사진 1px → 화면 px
        (2f * density / fill).roundToInt().coerceAtLeast(1)
    }
}
