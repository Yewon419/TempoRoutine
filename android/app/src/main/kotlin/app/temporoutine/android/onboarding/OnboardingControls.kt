// 템포루틴 Android — 온보딩 컨트롤 (iOS TempoLens.swift GlassSheet·InkCapsuleButtonStyle·GhostUnderlineButtonStyle·HandUnderline·RulerSlider 이식)
// 컨트롤 언어(2026-09-07): 채움 = 먹 번짐, 엄지·원반 = 무광 지면. 유리는 렌즈·시트뿐.

package app.temporoutine.android.onboarding

import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import app.temporoutine.android.R
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.drawTrimmed
import app.temporoutine.android.theme.rememberReduceMotion
import kotlin.math.roundToInt

private val shade = Color(60, 75, 90)

/** 하단 유리 시트(앱 공식: 반투명 흰 그라데이션 + 윗선 스펙큘러, 블러 없음). bare = 유리 없이 CTA만(브랜드·사계절). */
fun Modifier.glassSheet(bare: Boolean): Modifier = if (bare) this else this
    .dropShadow(RoundedCornerShape(topStart = 30.dp, topEnd = 30.dp), Shadow(radius = 15.dp, color = shade.copy(alpha = 0.08f), offset = DpOffset(0.dp, (-10).dp)))
    .drawBehind {
        val r = 30.dp.toPx()
        val shape = Path().apply {
            addRoundRect(androidx.compose.ui.geometry.RoundRect(0f, 0f, size.width, size.height + r,
                topLeftCornerRadius = androidx.compose.ui.geometry.CornerRadius(r), topRightCornerRadius = androidx.compose.ui.geometry.CornerRadius(r)))
        }
        drawPath(shape, Brush.linearGradient(listOf(Color.White.copy(alpha = 0.62f), Color.White.copy(alpha = 0.34f)), start = Offset.Zero, end = Offset(size.width, size.height)))
        drawRect(Color.White.copy(alpha = 0.85f), topLeft = Offset(r, 0f), size = Size((size.width - 2 * r).coerceAtLeast(0f), 1.dp.toPx()))
    }

/** 주 행동 — 먹 캡슐 52. 누르면 흰 먹이 중심에서 번진다. inverted = 지면색 알약 + 먹 글자(사계절 장의 어두운 사진 위). */
@Composable
fun InkCapsuleButton(title: String, inverted: Boolean, enabled: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val ink = Ink
    val reduceMotion = rememberReduceMotion()
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val bleed by animateFloatAsState(if (pressed) 1f else 0f, if (reduceMotion) snap() else tween(550, easing = EaseOut), label = "inkBleed")
    val press by animateFloatAsState(if (pressed) 0.97f else 1f, tween(120, easing = EaseOut), label = "inkPress")
    Box(
        modifier
            .fillMaxWidth()
            .height(52.dp)
            .graphicsLayer { scaleX = press; scaleY = press; alpha = if (enabled) 1f else 0.35f }
            .dropShadow(CircleShape, Shadow(radius = 10.dp, color = ink.text.copy(alpha = 0.18f), offset = DpOffset(0.dp, 8.dp)))
            .clip(CircleShape)
            .background(if (inverted) ink.frost else ink.text)
            .drawBehind {
                if (bleed > 0f) drawCircle(Color.White.copy(alpha = 0.16f * bleed), radius = 10.dp.toPx() * (0.01f + 23.99f * bleed))
            }
            .border(1.dp, Color.White.copy(alpha = 0.10f), CircleShape)
            .clickable(interactionSource = source, indication = null, enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = Fonts.system(17, FontWeight.Medium), color = if (inverted) ink.text else ink.paper, textAlign = TextAlign.Center)
    }
}

/** 보조 행동 — 활자 + 은필 손그림 밑줄(누르면 그어진다, 0.28s) */
@Composable
fun GhostUnderlineButton(title: String, onClick: () -> Unit) {
    val ink = Ink
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val draw by animateFloatAsState(if (pressed) 1f else 0f, tween(280, easing = EaseOut), label = "handUnderline")
    Box(
        Modifier.fillMaxWidth().height(44.dp).clickable(interactionSource = source, indication = null, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Box {
            Text(title, style = Fonts.system(15), color = ink.text.copy(alpha = 0.7f))
            // 밑줄 = 글자 폭 × 6, 아래로 4(iOS overlay(alignment: .bottom).offset(y: 4))
            Canvas(Modifier.matchParentSize()) {
                val band = 6.dp.toPx()
                translate(top = size.height - band + 4.dp.toPx()) {
                    drawTrimmed(handUnderline(Size(size.width, band)), draw, ink.winter, Stroke(width = 1.2.dp.toPx()))
                }
            }
        }
    }
}

/** 손그림 밑줄 — 프로토 100×6 path */
private fun handUnderline(s: Size): Path {
    fun x(v: Float) = v / 100f * s.width
    fun y(v: Float) = v / 6f * s.height
    return Path().apply {
        moveTo(x(1f), y(4f))
        cubicTo(x(20f), y(2f), x(40f), y(5f), x(60f), y(3f))
        cubicTo(x(80f), y(1f), x(90f), y(2f), x(99f), y(3.5f))
    }
}

@Composable
fun OnboardingCaption(text: String) {
    Text(text, style = Fonts.system(12), color = Ink.text.copy(alpha = 0.45f), modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
}

/** 자(ruler) 입력 — 먹 채움 트랙 + 눈금 + 무광 지면 엄지 44. 값이 렌즈 숫자·호·눈금에 그대로 비친다. */
@Composable
fun RulerSlider(value: Int, range: IntRange, unit: String, onChange: (Int) -> Unit) {
    val ink = Ink
    val count = range.last - range.first
    val current by rememberUpdatedState(value)
    val onChangeLatest by rememberUpdatedState(onChange)
    val a11y = "$value$unit"
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        BoxWithConstraints(
            Modifier
                .fillMaxWidth()
                .height(64.dp)
                .semantics {
                    contentDescription = a11y
                    progressBarRangeInfo = ProgressBarRangeInfo(value.toFloat(), range.first.toFloat()..range.last.toFloat(), steps = (count - 1).coerceAtLeast(0))
                    setProgress { target -> onChangeLatest(target.roundToInt().coerceIn(range)); true }
                },
        ) {
            val density = LocalDensity.current
            val widthPx = with(density) { maxWidth.toPx() }
            val edge = with(density) { 22.dp.toPx() }
            val usable = (widthPx - 2 * edge).coerceAtLeast(1f)
            fun update(x: Float) {
                val next = BaselineLogic.rulerValue(x, edge, usable, range)
                if (next != current) onChangeLatest(next)
            }
            val t = (value - range.first).toFloat() / count.coerceAtLeast(1)
            val thumbX by animateFloatAsState(edge + usable * t, tween(120, easing = EaseOut), label = "rulerThumb")
            Canvas(
                Modifier
                    .matchParentSize()
                    .pointerInput(range, usable) {
                        detectTapGestures { update(it.x) }
                    }
                    .pointerInput(range, usable) {
                        detectDragGestures(onDragStart = { update(it.x) }) { change, _ -> update(change.position.x) }
                    },
            ) {
                val cy = size.height / 2
                val line = 2.dp.toPx()
                drawRoundRect(ink.text.copy(alpha = 0.18f), topLeft = Offset(edge, cy - line / 2), size = Size(usable, line), cornerRadius = androidx.compose.ui.geometry.CornerRadius(line / 2))
                drawRoundRect(ink.text, topLeft = Offset(edge, cy - line / 2), size = Size((thumbX - edge).coerceAtLeast(0f), line), cornerRadius = androidx.compose.ui.geometry.CornerRadius(line / 2))
                for (i in 0..count) {
                    val x = edge + usable * i / count.coerceAtLeast(1)
                    val tall = (if (i % 5 == 0) 16.dp else 10.dp).toPx()
                    val tickCy = cy - 4.dp.toPx()
                    drawRect(ink.text.copy(alpha = 0.35f), topLeft = Offset(x - 0.5.dp.toPx(), tickCy - tall / 2), size = Size(1.dp.toPx(), tall))
                }
            }
            Box(
                Modifier
                    .offset { IntOffset((thumbX - edge).roundToInt(), 0) }
                    .align(Alignment.CenterStart)
                    .size(44.dp)
                    .dropShadow(CircleShape, Shadow(radius = 5.dp, color = shade.copy(alpha = 0.16f), offset = DpOffset(0.dp, 4.dp)))
                    .background(ink.frost, CircleShape)
                    .border(1.2.dp, ink.winter.copy(alpha = 0.6f), CircleShape),
            )
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp)) {
            Text(stringResource(R.string.ob_ruler_days, range.first), style = Fonts.system(12), color = ink.text.copy(alpha = 0.45f))
            Spacer(Modifier.weight(1f))
            Text(stringResource(R.string.ob_ruler_days, range.last), style = Fonts.system(12), color = ink.text.copy(alpha = 0.45f))
        }
    }
}
