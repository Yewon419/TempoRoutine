// 템포루틴 Android — 온보딩 「템포 렌즈」 (iOS TempoLens.swift + LensWarp.metal 이식)
// 유리 렌즈 하나가 온보딩 전 단계를 관통한다: 지면을 배율 m으로 재합성해 원으로 자르고(굴절 = AGSL, Android 13+),
// 서리 층·광택·림 그림자를 얹는다. 유리는 이 렌즈와 하단 시트뿐.
// Android 12(API 31~32)는 RuntimeShader가 없어 굴절 없이 색 보정만 — iOS도 모션 축소면 굴절을 끈다.

package app.temporoutine.android.onboarding

import android.graphics.BlurMaskFilter
import android.graphics.ColorMatrixColorFilter
import android.graphics.RenderEffect
import android.graphics.RuntimeShader
import android.os.Build
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asComposeRenderEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.temporoutine.android.R
import app.temporoutine.android.cycle.seasonCopy
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.SeasonGlyph
import app.temporoutine.android.theme.springStiffness
import app.temporoutine.core.CyclePhase
import kotlinx.coroutines.delay
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

/** 렌즈 안에 보이는 것 — 단계가 고른다. 숫자·호·눈금은 값이 자주 바뀌므로 드로잉 트리거(introKey)에서 뺀다. */
data class LensContent(
    val ring: Boolean = false,
    val drawsRing: Boolean = false,   // 브랜드 장면 = 원이 그려진다(1.5s, 0.9s 지연)
    val nodes: Boolean = false,       // 4계절 노드(글리프 + 라벨)
    val orbit: Boolean = false,
    val number: Int? = null,          // 큰 숫자(지속일·주기)
    val arcFraction: Float? = null,   // 겨울 호 = 지속일 / 주기
    val ticks: Int? = null,           // 눈금 수 = 주기
    val progress: Float? = null,      // 진행 다이얼(0~1)
) {
    val focus: Boolean get() = number != null
    val introKey: String get() = "$ring$drawsRing$nodes$orbit"
}

private val shade = Color(60, 75, 90)
private val frostBase = Color(238, 241, 242)
private val nodePhases = listOf(CyclePhase.MENSTRUAL to -90f, CyclePhase.FOLLICULAR to 0f, CyclePhase.OVULATION to 90f, CyclePhase.LUTEAL to 180f)

/** 볼록 렌즈 굴절(iOS LensWarp.metal) — 가장자리는 그대로, 중심으로 갈수록 샘플 지점을 안쪽으로 당겨 확대. strength 0.10 = 중심 배율 ≈1.11. */
private const val LENS_WARP_AGSL = """
uniform shader content;
uniform float2 size;
uniform float strength;
half4 main(float2 pos) {
    float2 center = size * 0.5;
    float radius = min(size.x, size.y) * 0.5;
    float2 p = (pos - center) / radius;
    float r = length(p);
    if (r >= 1.0) { return content.eval(pos); }
    float k = 1.0 - strength * (1.0 - r * r);
    return content.eval(center + p * k * radius);
}
"""

/** saturation 0.85 × contrast 1.05 (iOS .saturation(0.85).contrast(1.05)) */
private val glassColorFilter: ColorMatrixColorFilter by lazy {
    val m = ColorMatrix().apply { setToSaturation(0.85f) }
    val c = 1.05f
    val t = (1f - c) / 2f * 255f
    m.timesAssign(ColorMatrix(floatArrayOf(c, 0f, 0f, 0f, t, 0f, c, 0f, 0f, t, 0f, 0f, c, 0f, t, 0f, 0f, 0f, 1f, 0f)))
    ColorMatrixColorFilter(m.values)
}

/**
 * @param center 화면 전체 좌표(dp) — 지면이 화면 전체에 깔리므로 렌즈도 같은 좌표계를 쓴다(iOS 세이프 인셋 보정의 등가).
 * @param entering 마지막 「오늘」 — 렌즈가 화면을 덮는 느린 스프링(response 0.9).
 */
@Composable
fun TempoLens(
    center: Offset, diameter: Float, magnify: Float, content: LensContent, visible: Boolean, entering: Boolean,
    fullWidth: Float, fullHeight: Float, reduceMotion: Boolean,
) {
    val ink = Ink
    val motif = ImageBitmap.imageResource(R.drawable.motif_winter)
    val spec = if (reduceMotion) snap() else spring<Float>(dampingRatio = 0.86f, stiffness = springStiffness(if (entering) 0.9f else 0.72f))
    val cx by animateFloatAsState(center.x, spec, label = "lensX")
    val cy by animateFloatAsState(center.y, spec, label = "lensY")
    val d by animateFloatAsState(diameter, spec, label = "lensD")
    val m by animateFloatAsState(magnify, spec, label = "lensM")
    val alpha by animateFloatAsState(if (visible) 1f else 0f, spec, label = "lensAlpha")
    if (alpha <= 0.001f && !visible) return

    val warp = remember {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) RuntimeShader(LENS_WARP_AGSL) else null
    }

    Box(
        Modifier
            // 화면보다 큰 지름(마지막 창)에서 requiredSize는 넘친 만큼 가운데로 밀린다 — 좌상단 기준 무제한 배치
            .wrapContentSize(Alignment.TopStart, unbounded = true)
            .offset { IntOffset(((cx - d / 2).dp.toPx()).roundToInt(), ((cy - d / 2).dp.toPx()).roundToInt()) }
            .requiredSize(d.dp)
            .graphicsLayer { this.alpha = alpha }
            .dropShadow(CircleShape, Shadow(radius = 18.dp, color = shade.copy(alpha = 0.14f), offset = DpOffset(0.dp, 12.dp)))
            .dropShadow(CircleShape, Shadow(radius = 3.dp, color = shade.copy(alpha = 0.08f), offset = DpOffset(0.dp, 2.dp)))
            .graphicsLayer { clip = true; shape = CircleShape }
            .clearAndSetSemantics { },
    ) {
        // 지면 재합성 — 렌즈 중심을 기준으로 배율 m, 렌즈 프레임 중심으로 옮겨 원으로 자른다
        Canvas(
            Modifier
                .fillMaxSize()
                .graphicsLayer {
                    val px = size.width
                    val colorFx = RenderEffect.createColorFilterEffect(glassColorFilter)
                    renderEffect = if (warp != null && !reduceMotion && px > 0f) {
                        warp.setFloatUniform("size", px, px)
                        warp.setFloatUniform("strength", 0.10f)
                        RenderEffect.createChainEffect(colorFx, RenderEffect.createRuntimeShaderEffect(warp, "content")).asComposeRenderEffect()
                    } else {
                        colorFx.asComposeRenderEffect()
                    }
                },
        ) {
            val gx = cx.dp.toPx()
            val gy = cy.dp.toPx()
            withTransform({
                translate(size.width / 2 - gx, size.height / 2 - gy)
                scale(m, m, pivot = Offset(gx, gy))
            }) {
                drawOnboardingGround(motif, ink.frost, 1f, fullWidth.dp.toPx(), fullHeight.dp.toPx())
            }
        }
        // 서리 층 — .36, 숫자 단계는 중앙 방사형(.78 → .5)으로 가독을 올린다
        Canvas(Modifier.fillMaxSize()) {
            drawRect(frostBase.copy(alpha = 0.36f))
            if (content.focus) {
                drawRect(Brush.radialGradient(
                    0f to ink.frost.copy(alpha = 0.78f), 0.7f to ink.frost.copy(alpha = 0.5f), 1f to ink.frost.copy(alpha = 0.5f),
                    center = Offset(size.width * 0.5f, size.height * 0.45f), radius = size.width * 0.55f,
                ))
            }
        }
        LensOverlays(d, content, reduceMotion)
        // 광 — 원형 그라데이션을 세로로 눌러 가장자리까지 스러지게(타원 클립은 흰 덩어리로 읽혔다)
        Canvas(Modifier.fillMaxSize()) {
            val w = size.width
            sheen(Color.White.copy(alpha = 0.45f), Offset(w * 0.3f, w * 0.22f), w * 0.3f, 0.66f)
            sheen(Color(120, 140, 160).copy(alpha = 0.12f), Offset(w * 0.7f, w * 0.9f), w * 0.4f, 0.75f)
            // 림 — 흰 테 + 상좌 안쪽 광 + 하우 안쪽 그림자(CSS inset 22 → stroke 10/blur 12, iOS 실기기 교정)
            val r = w / 2
            drawIntoCanvas { canvas ->
                val native = canvas.nativeCanvas
                val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { style = android.graphics.Paint.Style.STROKE }
                paint.color = Color.White.copy(alpha = 0.5f).toArgb(); paint.strokeWidth = 5.dp.toPx(); paint.maskFilter = BlurMaskFilter(6.dp.toPx(), BlurMaskFilter.Blur.NORMAL)
                native.drawCircle(r + 2.dp.toPx(), r + 3.dp.toPx(), r, paint)
                paint.color = shade.copy(alpha = 0.11f).toArgb(); paint.strokeWidth = 10.dp.toPx(); paint.maskFilter = BlurMaskFilter(12.dp.toPx(), BlurMaskFilter.Blur.NORMAL)
                native.drawCircle(r - 4.dp.toPx(), r - 7.dp.toPx(), r, paint)
            }
            val line = 1.dp.toPx()
            drawCircle(Color.White.copy(alpha = 0.55f), radius = r - line / 2, style = Stroke(width = line))
        }
    }
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.sheen(color: Color, at: Offset, radius: Float, squashY: Float) {
    scale(1f, squashY, pivot = at) {
        drawCircle(Brush.radialGradient(listOf(color, Color.Transparent), center = at, radius = radius), radius = radius, center = at)
    }
}

// ── 렌즈 속 그림(설계 공간 200 → 지름 비례) ──
@Composable
private fun LensOverlays(d: Float, content: LensContent, reduceMotion: Boolean) {
    val ink = Ink
    val s = d / 200f
    val ringDraw = remember { Animatable(1f) }
    var nodesIn by remember { mutableStateOf(false) }
    var orbitOn by remember { mutableStateOf(false) }
    LaunchedEffect(content.introKey, reduceMotion) {
        ringDraw.snapTo(if (content.drawsRing) 0f else 1f)
        nodesIn = false
        orbitOn = false
        if (reduceMotion) { ringDraw.snapTo(1f); nodesIn = true; return@LaunchedEffect }
        delay(30)   // 상태 변화가 관측되도록 한 틱 양보
        nodesIn = true
        if (content.drawsRing) {
            delay(900)
            ringDraw.animateTo(1f, tween(1_500, easing = EaseOut))
        }
        if (!content.orbit) return@LaunchedEffect
        delay((3_100 - if (content.drawsRing) 2_400 else 0).toLong().coerceAtLeast(0))   // 원 완성 뒤 궤도 시작(프로토 3.1s)
        orbitOn = true
    }
    val arc by animateFloatAsState(content.arcFraction ?: 0f, if (reduceMotion) snap() else tween(600, easing = EaseOut), label = "lensArc")
    val progress by animateFloatAsState(content.progress ?: 0f, if (reduceMotion) snap() else tween(700, easing = EaseOut), label = "lensProgress")

    Canvas(Modifier.fillMaxSize()) {
        val c = Offset(size.width / 2, size.height / 2)
        val ringR = 86.dp.toPx() * s
        val topLeft = Offset(c.x - ringR, c.y - ringR)
        val ringSize = Size(ringR * 2, ringR * 2)
        if (content.ring && ringDraw.value > 0f) {
            drawArc(ink.winter.copy(alpha = 0.9f), -90f, 360f * ringDraw.value, false, topLeft, ringSize, style = Stroke(1.6.dp.toPx() * s, cap = StrokeCap.Round))
        }
        if (content.arcFraction != null) {
            drawArc(ink.winter, -90f, 360f * arc, false, topLeft, ringSize, style = Stroke(4.dp.toPx() * s, cap = StrokeCap.Round))
        }
        content.ticks?.let { n ->
            for (i in 0 until n) {
                val a = (-Math.PI / 2 + i * 2 * Math.PI / n).toFloat()
                val r2 = (if (i % 7 == 0) 74 else 79).dp.toPx() * s
                drawLine(ink.winter.copy(alpha = 0.55f), Offset(c.x + ringR * cos(a), c.y + ringR * sin(a)), Offset(c.x + r2 * cos(a), c.y + r2 * sin(a)), 1.2.dp.toPx() * s)
            }
        }
        if (content.progress != null) {
            drawArc(ink.text.copy(alpha = 0.85f), -90f, 360f * progress, false, topLeft, ringSize, style = Stroke(2.2.dp.toPx() * s, cap = StrokeCap.Round))
        }
    }
    if (content.nodes) {
        nodePhases.forEachIndexed { index, (phase, deg) -> LensNode(phase, deg, index, s, nodesIn, reduceMotion) }
    }
    if (content.orbit && !reduceMotion && orbitOn) Orbit(s)
    content.number?.let { n -> LensNumber(n, s) }
}

@Composable
private fun LensNode(phase: CyclePhase, deg: Float, index: Int, s: Float, shown: Boolean, reduceMotion: Boolean) {
    val ink = Ink
    val t by animateFloatAsState(if (shown) 1f else 0f, if (reduceMotion) snap() else tween(500, delayMillis = 1_360 + index * 360, easing = EaseOut), label = "lensNode")
    val a = Math.toRadians(deg.toDouble())
    val labelDX = when (deg) { 0f -> -24f; 180f -> 24f; else -> 0f }
    val labelDY = when (deg) { -90f -> 28f; 90f -> -18f; else -> 0f }
    Box(
        Modifier
            .fillMaxSize()
            .graphicsLayer {
                alpha = t
                translationX = (86f * s * cos(a).toFloat()).dp.toPx()
                translationY = (86f * s * sin(a).toFloat() + (1f - t) * 3f).dp.toPx()
            },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size((22f * s).dp)) { drawCircle(ink.frost) }
        SeasonGlyph(phase, ink.season(phase), size = (16f * s).dp)
        HaloText(seasonCopy(phase).name, LensType.serif(11f * s, bold = false), ink.season(phase), Modifier.offset((labelDX * s).dp, (labelDY * s).dp))
    }
}

@Composable
private fun Orbit(s: Float) {
    val ink = Ink
    val transition = rememberInfiniteTransition(label = "lensOrbit")
    val angle by transition.animateFloat(0f, 360f, infiniteRepeatable(tween(26_000, easing = LinearEasing), RepeatMode.Restart), label = "lensOrbitAngle")
    val shown by animateFloatAsState(1f, tween(600, easing = EaseOut), label = "lensOrbitIn")
    Canvas(Modifier.fillMaxSize().graphicsLayer { alpha = shown; rotationZ = angle }) {
        drawCircle(ink.winter, radius = 2.6.dp.toPx() * s, center = Offset(size.width / 2, size.height / 2 - 86.dp.toPx() * s))
    }
}

@Composable
private fun LensNumber(n: Int, s: Float) {
    val ink = Ink
    Box(Modifier.fillMaxSize().offset(y = (4f * s).dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy((2f * s).dp)) {
            HaloText("$n", LensType.serif(40f * s), ink.text)
            HaloText(stringResource(R.string.ob_unit_days), Fonts.system(12, FontWeight.Medium).copy(fontSize = (12f * s).sp, lineHeight = (16f * s).sp), ink.text.copy(alpha = 0.6f))
        }
    }
}

/** 지면색 헤일로 활자 — 프로토 paint-order:stroke 대역(렌즈 속 가독) */
@Composable
private fun HaloText(text: String, style: TextStyle, color: Color, modifier: Modifier = Modifier) {
    val ink = Ink
    Box(modifier, contentAlignment = Alignment.Center) {
        Text(text, style = style, color = ink.frost, modifier = Modifier.blur(2.5.dp))
        Text(text, style = style, color = ink.frost, modifier = Modifier.blur(1.dp))
        Text(text, style = style, color = color)
    }
}
