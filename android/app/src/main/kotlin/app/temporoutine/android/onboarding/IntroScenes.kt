// 템포루틴 Android — 온보딩 ① 인트로 3장면 (iOS OnboardingFlow intro 이식)
// A 브랜드·원(은필 원 1.5s/1.3s 지연 + 4계절 노드 개별 페이드인 + 3.1s 후 26s 궤도 점) / B 에너지 곡선 드로잉 / C 네 계절.
// 자동 타이머 없음(탭·버튼 진행), Reduce Motion(애니메이터 배율 0) = 완성 상태 즉시.
// 스태거 등장(ob-in) = fade + translateY 10dp, 노드 페이드(node-in) = fade만.

package app.temporoutine.android.onboarding

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseInOut
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.temporoutine.android.R
import app.temporoutine.android.cycle.seasonCopy
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.SeasonGlyph
import app.temporoutine.core.CyclePhase
import kotlinx.coroutines.delay
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

// ── 모션 헬퍼 ──

/** 스태거 등장 — fade + translateY 10dp, ease-out + delay. reduceMotion이면 즉시. */
@Composable
fun Modifier.staggerIn(appeared: Boolean, delayMs: Int, durationMs: Int = 420, reduceMotion: Boolean): Modifier {
    val t by animateFloatAsState(
        if (appeared) 1f else 0f,
        if (reduceMotion) snap() else tween(durationMs, delayMs, EaseOut),
        label = "staggerIn",
    )
    return graphicsLayer { alpha = t; translationY = (1f - t) * 10.dp.toPx() }
}

/** 페이드만(오프셋 없음) — 이미 배치된 노드용. */
@Composable
fun Modifier.fadeIn(appeared: Boolean, delayMs: Int, durationMs: Int = 380, reduceMotion: Boolean): Modifier {
    val t by animateFloatAsState(
        if (appeared) 1f else 0f,
        if (reduceMotion) snap() else tween(durationMs, delayMs, EaseOut),
        label = "fadeIn",
    )
    return graphicsLayer { alpha = t }
}

/** 부모 크기 기준 비율 위치에 중심 정렬 — SwiftUI `.position(x:y:)` 대응. */
private fun Modifier.centeredAt(fx: Float, fy: Float): Modifier = layout { measurable, constraints ->
    val p = measurable.measure(Constraints())
    layout(constraints.maxWidth, constraints.maxHeight) {
        p.place((constraints.maxWidth * fx - p.width / 2f).roundToInt(), (constraints.maxHeight * fy - p.height / 2f).roundToInt())
    }
}

/** 한 틱 양보 뒤 appeared — iOS `.task` 30ms 패턴. active=false(스플래시 뒤)면 연출을 소모하지 않는다. */
@Composable
private fun rememberAppeared(active: Boolean, reduceMotion: Boolean): Boolean {
    var appeared by remember { mutableStateOf(false) }
    LaunchedEffect(active) {
        appeared = false
        if (!active) return@LaunchedEffect
        if (reduceMotion) { appeared = true; return@LaunchedEffect }
        delay(30)
        appeared = true
    }
    return appeared
}

// ── 공통 조판 ──

@Composable
fun Eyebrow(text: String) {
    Text(text, style = Fonts.almanacBody(13).copy(letterSpacing = 2.sp), color = Ink.text.copy(alpha = 0.5f))
}

@Composable
fun StepHeader(eyebrow: String, title: String, titleSize: Int = 30) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Eyebrow(eyebrow)
        Text(title, style = Fonts.almanac(titleSize), color = Ink.text)
    }
}

// ── 인트로 ──

@Composable
fun IntroStep(scene: Int, active: Boolean, reduceMotion: Boolean, onTap: () -> Unit) {
    Crossfade(
        targetState = scene,
        animationSpec = tween(if (reduceMotion) 0 else 500),
        label = "introScene",
        modifier = Modifier
            .fillMaxSize()
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onTap),
    ) { s ->
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            when (s) {
                0 -> SceneBrand(active, reduceMotion)
                1 -> SceneWave(active, reduceMotion)
                else -> SceneSeasons()
            }
        }
    }
}

@Composable
private fun ColumnScope.SceneBrand(active: Boolean, reduceMotion: Boolean) {
    val ink = Ink
    val appeared = rememberAppeared(active, reduceMotion)
    Eyebrow(stringResource(R.string.ob_brand))
    Text(stringResource(R.string.ob_intro_title), style = Fonts.almanac(38), color = ink.text)
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        val body = Fonts.almanacBody(17)
        val color = ink.text.copy(alpha = 0.75f)
        Text(stringResource(R.string.ob_intro_line1), style = body, color = color, modifier = Modifier.staggerIn(appeared, 300, 480, reduceMotion))
        // "생리 주기 기반"을 첫 화면에 명시한다(v1.6 §9 3-6)
        Text(stringResource(R.string.ob_intro_line2), style = body, color = color, modifier = Modifier.staggerIn(appeared, 560, 480, reduceMotion))
        Text(stringResource(R.string.ob_intro_line3), style = body, color = color, modifier = Modifier.staggerIn(appeared, 820, 480, reduceMotion))
    }
    // 비의료 고지(5.1.1(ix) 방어)
    Text(
        stringResource(R.string.ob_intro_disclaimer), style = Fonts.system(12).copy(lineHeight = 18.sp), color = ink.text.copy(alpha = 0.45f),
        modifier = Modifier.staggerIn(appeared, 1080, 480, reduceMotion),
    )
    Spacer(Modifier.weight(1f))
    CycleWheel(appeared, reduceMotion, Modifier.align(Alignment.CenterHorizontally))
    Spacer(Modifier.weight(1f))
}

private val wheelPhases = listOf(CyclePhase.MENSTRUAL, CyclePhase.FOLLICULAR, CyclePhase.OVULATION, CyclePhase.LUTEAL)
private val wheelNodeDelays = listOf(1360, 1680, 2060, 2440)
private const val WHEEL_RADIUS_DP = 95f

/** 주기 원 드로잉 — 은필 원(1.5s, 1.3s 지연) + 노드 4곳에서 잉크가 옅어지며 끊기는 각도 그라데이션 + 궤도 점. */
@Composable
private fun CycleWheel(appeared: Boolean, reduceMotion: Boolean, modifier: Modifier = Modifier) {
    val ink = Ink
    val ring by animateFloatAsState(
        if (appeared) 1f else 0f,
        if (reduceMotion) snap() else tween(1500, 1300, EaseInOut),
        label = "ring",
    )
    val orbit = remember { Animatable(0f) }
    LaunchedEffect(appeared, reduceMotion) {
        orbit.snapTo(0f)
        if (!appeared || reduceMotion) return@LaunchedEffect
        delay(3070)   // 원 완성(1.3+1.5=2.8s) 뒤 여유 두고 궤도 시작(총 3.1s)
        orbit.animateTo(360f, infiniteRepeatable(tween(26_000, easing = LinearEasing), RepeatMode.Restart))
    }
    val ringBrush = remember(ink.winter) { gappedRingBrush(ink.winter) }

    Box(modifier.size(WHEEL_RADIUS_DP.dp * 2).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
        // 궤도 점 — 원보다 아래 레이어. Reduce Motion엔 숨김.
        if (!reduceMotion) {
            Box(Modifier.fillMaxSize().graphicsLayer { rotationZ = orbit.value }) {
                Box(
                    Modifier
                        .align(Alignment.TopCenter)
                        .offset(y = (-2.5).dp)
                        .size(5.dp)
                        .fadeIn(appeared, 3100, 600, reduceMotion)
                        .drawBehind { drawCircle(ink.winter) },
                )
            }
        }
        Canvas(Modifier.fillMaxSize()) {
            rotate(-90f) {
                drawArc(
                    brush = ringBrush, startAngle = 0f, sweepAngle = 360f * ring, useCenter = false,
                    style = Stroke(width = 1.4.dp.toPx(), cap = StrokeCap.Round),
                )
            }
        }
        for ((index, phase) in wheelPhases.withIndex()) {
            val angle = (index * 90.0 - 90.0) * Math.PI / 180.0
            val meta = seasonCopy(phase)
            Column(
                Modifier
                    .offset(x = (WHEEL_RADIUS_DP * cos(angle)).dp, y = (WHEEL_RADIUS_DP * sin(angle)).dp)
                    .fadeIn(appeared, wheelNodeDelays[index], 380, reduceMotion),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                SeasonGlyph(phase, ink.season(phase), size = 14.dp)
                Text(meta.name, style = Fonts.almanacBody(11), color = ink.season(phase))
            }
        }
    }
}

/** 노드 중심 ±0.02 = 완전 공백, ±0.055까지 본색 복귀. sweep 0도 = +x, 호도 0도 = +x라 프랙션 공간이 그대로 정렬. */
private fun gappedRingBrush(winter: Color): Brush {
    val inkColor = winter.copy(alpha = 0.7f)
    val clear = winter.copy(alpha = 0f)
    val gapHalf = 0.02f
    val fadeHalf = 0.055f
    val stops = ArrayList<Pair<Float, Color>>()
    for (t in listOf(0f, 0.25f, 0.5f, 0.75f, 1f)) {
        if (t - fadeHalf > 0f) stops += (t - fadeHalf) to inkColor
        stops += maxOf(0f, t - gapHalf) to clear
        stops += minOf(1f, t + gapHalf) to clear
        if (t + fadeHalf < 1f) stops += (t + fadeHalf) to inkColor
    }
    return Brush.sweepGradient(*stops.toTypedArray())
}

@Composable
private fun ColumnScope.SceneWave(active: Boolean, reduceMotion: Boolean) {
    val ink = Ink
    val draw = rememberDrawProgress(active, reduceMotion)
    Eyebrow(stringResource(R.string.ob_cycle_eyebrow))
    Text(stringResource(R.string.ob_wave_title), style = Fonts.almanac(32), color = ink.text)
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        val style = Fonts.almanacBody(15)
        val color = ink.text.copy(alpha = 0.75f)
        Text(stringResource(R.string.ob_wave_line1), style = style, color = color)
        Text(stringResource(R.string.ob_wave_line2), style = style, color = color)
        Text(stringResource(R.string.ob_wave_line3), style = style, color = color)
    }
    Spacer(Modifier.weight(1f))
    EnergyWave(draw, Modifier.fillMaxWidth().height(150.dp))
    Spacer(Modifier.weight(1f))
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        val style = Fonts.almanacBody(13)
        val color = ink.text.copy(alpha = 0.55f)
        Text(stringResource(R.string.ob_wave_foot1), style = style, color = color)
        Text(stringResource(R.string.ob_wave_foot2), style = style, color = color)
    }
}

/** 장 진입 시 0→1 드로잉(easeInOut 1.1s). Reduce Motion = 완성 상태 즉시 스왑(§8.2.1). */
@Composable
fun rememberDrawProgress(active: Boolean, reduceMotion: Boolean, durationMs: Int = 1100, delayMs: Int = 0): Float {
    val draw = remember { Animatable(0f) }
    LaunchedEffect(active, reduceMotion) {
        draw.snapTo(0f)
        if (!active) return@LaunchedEffect
        if (reduceMotion) { draw.snapTo(1f); return@LaunchedEffect }
        if (delayMs > 0) delay(delayMs.toLong())
        draw.animateTo(1f, tween(durationMs, easing = EaseInOut))
    }
    return draw.value
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

/** 에너지 흐름 곡선(겨울 저점→봄 상승→여름 정점→가을 하강) + 글리프 라벨 4점. 원본 viewBox 280×152. */
@Composable
private fun EnergyWave(progress: Float, modifier: Modifier) {
    val ink = Ink
    Box(modifier.clearAndSetSemantics { }) {
        Canvas(Modifier.fillMaxSize()) {
            val w = size.width
            val h = size.height
            fun pt(x: Float, y: Float) = Offset(x / 280f * w, (y + 8f) / 152f * h)
            val path = Path().apply {
                val p0 = pt(12f, 92f); moveTo(p0.x, p0.y)
                curve(pt(45f, 100f), pt(62f, 92f), pt(86f, 66f))
                curve(pt(108f, 43f), pt(130f, 30f), pt(150f, 28f))
                curve(pt(176f, 26f), pt(196f, 42f), pt(216f, 62f))
                curve(pt(236f, 80f), pt(254f, 88f), pt(268f, 86f))
            }
            drawTrimmed(path, progress, ink.winter.copy(alpha = 0.7f), Stroke(width = 1.4.dp.toPx(), cap = StrokeCap.Round))
        }
        WaveLabel(CyclePhase.MENSTRUAL, progress > 0.05f, Modifier.centeredAt(0.07f, 0.86f))
        WaveLabel(CyclePhase.FOLLICULAR, progress > 0.35f, Modifier.centeredAt(0.33f, 0.28f))
        WaveLabel(CyclePhase.OVULATION, progress > 0.55f, Modifier.centeredAt(0.54f, 0.06f))
        WaveLabel(CyclePhase.LUTEAL, progress > 0.85f, Modifier.centeredAt(0.81f, 0.76f))
    }
}

private fun Path.curve(c1: Offset, c2: Offset, to: Offset) = cubicTo(c1.x, c1.y, c2.x, c2.y, to.x, to.y)

@Composable
private fun WaveLabel(phase: CyclePhase, visible: Boolean, modifier: Modifier) {
    val ink = Ink
    Column(modifier.graphicsLayer { alpha = if (visible) 1f else 0f }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        SeasonGlyph(phase, ink.season(phase), size = 12.dp)
        Text(seasonCopy(phase).name, style = Fonts.almanacBody(11), color = ink.season(phase))
    }
}

@Composable
private fun ColumnScope.SceneSeasons() {
    val ink = Ink
    Eyebrow(stringResource(R.string.ob_cycle_eyebrow))
    Text(stringResource(R.string.ob_seasons_title), style = Fonts.almanac(32), color = ink.text, modifier = Modifier.padding(bottom = 6.dp))
    // 나열 순서 = 표시 순서(봄여름가을겨울), 카피 = 사용자 지정 문안 그대로
    SeasonRow(CyclePhase.FOLLICULAR, stringResource(R.string.ob_season_spring))
    SeasonRow(CyclePhase.OVULATION, stringResource(R.string.ob_season_summer))
    SeasonRow(CyclePhase.LUTEAL, stringResource(R.string.ob_season_autumn))
    SeasonRow(CyclePhase.MENSTRUAL, stringResource(R.string.ob_season_winter))
    Spacer(Modifier.weight(1f))
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        val style = Fonts.almanacBody(13)
        val color = ink.text.copy(alpha = 0.55f)
        Text(stringResource(R.string.ob_seasons_foot1), style = style, color = color)
        Text(stringResource(R.string.ob_seasons_foot2), style = style, color = color)
    }
}

@Composable
private fun SeasonRow(phase: CyclePhase, desc: String) {
    val ink = Ink
    Row(
        Modifier
            .fillMaxWidth()
            .drawBehind { drawRect(ink.text.copy(alpha = 0.18f), topLeft = Offset(0f, size.height - 1f), size = Size(size.width, 1f)) }
            .padding(vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        SeasonGlyph(phase, ink.season(phase), size = 14.dp)
        Text(seasonCopy(phase).name, style = Fonts.almanacBody(17, bold = true), color = ink.season(phase), modifier = Modifier.width(40.dp))
        Text(desc, style = Fonts.almanacBody(15), color = ink.text.copy(alpha = 0.7f), modifier = Modifier.weight(1f))
    }
}
