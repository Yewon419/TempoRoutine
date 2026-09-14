// 템포루틴 Android — 온보딩 사계절 장 편집 조판 「J2」 (iOS SeasonEditorial.swift 이식, 2026-09-13 대표님 확정)
// 화면이 세 층으로 읽힌다: 좌상단 호수 숫자 「01」 아웃라인 148 + 「/ 04」 → 우중단 계절 글리프 176 → 좌하단 킥커 → 표제 96 → 덱 → 크레딧.
// 오른쪽 가장자리엔 「한 달 안의 사계절」 세로쓰기(글자마다 한 줄 — 회전하면 한글이 눕는다). 활자는 전부 지면색(흰).
// 등장: 숫자는 왼쪽에서 밀려 들어오고, 글리프는 선이 그려지듯, 킥커·표제·덱·크레딧은 70ms 간격으로 올라온다. 모션 축소 = 페이드만.
// 조판이 사진 위 고정 배치라 글자 크기는 시스템 글꼴 배율을 따르지 않는다(iOS .system(size:) 고정과 같은 선택).

package app.temporoutine.android.onboarding

import android.graphics.Paint
import android.graphics.RectF
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asComposePath
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.res.ResourcesCompat
import app.temporoutine.android.R
import app.temporoutine.android.cycle.seasonCopy
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.SeasonGlyph
import app.temporoutine.android.theme.drawTrimmedContours
import app.temporoutine.android.theme.seasonGlyphContours
import app.temporoutine.core.CyclePhase

@Composable
fun SeasonEditorial(phase: CyclePhase, index: Int, revealed: Boolean, reduceMotion: Boolean, modifier: Modifier = Modifier) {
    val paper = Ink.frost
    val folio = "%02d".format(index + 1)
    Box(modifier.fillMaxSize()) {
        Numeral(folio, index, paper, revealed, reduceMotion)
        VerticalLabel(paper, revealed, reduceMotion)
        Glyph(phase, paper, revealed, reduceMotion)
        Block(phase, index, folio, paper, revealed, reduceMotion)
    }
}

/** 시스템 글꼴 배율과 무관한 고정 크기 — 사진 위 조판이 넘치지 않게 */
@Composable
private fun fixed(dp: Float): TextUnit = with(LocalDensity.current) { dp.dp.toSp() }

private fun serif(size: TextUnit, bold: Boolean) = TextStyle(
    fontFamily = Fonts.gowunBatang, fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal, fontSize = size, lineHeight = (size.value * 1.2f).sp,
)

private fun sans(size: TextUnit, lineExtra: TextUnit? = null) = TextStyle(
    fontFamily = FontFamily.Default, fontSize = size, lineHeight = (size.value * 1.35f + (lineExtra?.value ?: 0f)).sp,
)

@Composable
private fun rise(revealed: Boolean, reduceMotion: Boolean, order: Int): Float {
    val t by animateFloatAsState(
        if (revealed) 1f else 0f,
        if (reduceMotion) tween(300, easing = EaseOut) else tween(550, delayMillis = 80 + order * 70, easing = EaseOut),
        label = "editorialRise",
    )
    return t
}

// ── 좌상단 호수 숫자 ──
@Composable
private fun BoxScope.Numeral(folio: String, index: Int, paper: Color, revealed: Boolean, reduceMotion: Boolean) {
    val t by animateFloatAsState(if (revealed) 1f else 0f, tween(if (reduceMotion) 300 else 700, easing = EaseOut), label = "editorialNumeral")
    val context = LocalContext.current
    val density = LocalDensity.current
    val label = stringResource(R.string.ob_season_position_a11y, index + 1)
    // 글리프 외곽선 — Compose Text는 stroke가 없다. Paint.getTextPath 경로를 경계 상자 좌상단에 맞춘다(iOS TextOutline).
    val outline = remember(folio, density) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = ResourcesCompat.getFont(context, R.font.gowunbatang_bold)
            textSize = with(density) { 148.dp.toPx() }
        }
        val path = android.graphics.Path()
        paint.getTextPath(folio, 0, folio.length, 0f, 0f, path)
        val bounds = RectF()
        @Suppress("DEPRECATION") path.computeBounds(bounds, true)
        path.offset(-bounds.left, -bounds.top)
        path.asComposePath()
    }
    Column(
        Modifier
            .align(Alignment.TopStart)
            .padding(top = 8.dp)
            .offset(x = (-4).dp)
            .graphicsLayer { alpha = t; translationX = if (reduceMotion) 0f else (1f - t) * -18.dp.toPx() }
            .clearAndSetSemantics { contentDescription = label },
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Canvas(Modifier.size(200.dp, 150.dp)) {
            drawPath(outline, paper.copy(alpha = 0.62f), style = Stroke(width = 1.2.dp.toPx()))
        }
        Text("/ 04", style = serif(fixed(14f), bold = false).copy(letterSpacing = fixed(3f)), color = paper.copy(alpha = 0.7f), modifier = Modifier.padding(start = 6.dp))
    }
}

// ── 오른쪽 세로쓰기 ──
@Composable
private fun BoxScope.VerticalLabel(paper: Color, revealed: Boolean, reduceMotion: Boolean) {
    val t by animateFloatAsState(if (revealed) 1f else 0f, if (reduceMotion) tween(300, easing = EaseOut) else tween(800, delayMillis = 200, easing = EaseOut), label = "editorialVertical")
    val text = stringResource(R.string.ob_season_eyebrow)
    val style = serif(fixed(12f), bold = false)
    Column(
        Modifier.align(Alignment.TopEnd).padding(top = 4.dp).graphicsLayer { alpha = t }.clearAndSetSemantics { },   // 숫자 라벨이 같은 정보를 읽는다
        verticalArrangement = Arrangement.spacedBy(7.dp),
        horizontalAlignment = Alignment.End,
    ) {
        for (ch in text) Text(ch.toString(), style = style, color = paper.copy(alpha = 0.55f))
    }
}

// ── 우중단 글리프 — 선이 그려지듯 ──
@Composable
private fun BoxScope.Glyph(phase: CyclePhase, paper: Color, revealed: Boolean, reduceMotion: Boolean) {
    val t by animateFloatAsState(if (revealed) 1f else 0f, if (reduceMotion) tween(300, easing = EaseOut) else tween(900, delayMillis = 250, easing = EaseOut), label = "editorialGlyph")
    Canvas(
        Modifier.align(Alignment.TopEnd).padding(top = 246.dp).offset(x = 4.dp).size(176.dp).graphicsLayer { alpha = t }.clearAndSetSemantics { },
    ) {
        val contours = seasonGlyphContours(phase, size.minDimension / 16f)
        drawTrimmedContours(contours, if (reduceMotion) 1f else t, paper.copy(alpha = 0.9f), Stroke(width = 1.5.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

// ── 좌하단 카피 블록 ──
@Composable
private fun BoxScope.Block(phase: CyclePhase, index: Int, folio: String, paper: Color, revealed: Boolean, reduceMotion: Boolean) {
    val fine = if (index == 3) stringResource(R.string.ob_season_fine) else null
    Column(Modifier.align(Alignment.BottomStart).fillMaxWidth()) {
        Risen(revealed, reduceMotion, 0) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                SeasonGlyph(phase, lerp(Ink.season(phase), Color.White, 0.55f), size = 12.dp)
                Text(stringResource(seasonPlainOf(phase)), style = sans(fixed(12f)).copy(letterSpacing = fixed(3f)), color = paper.copy(alpha = 0.82f))
            }
        }
        Risen(revealed, reduceMotion, 1) {
            Text(seasonCopy(phase).name, style = serif(fixed(96f), bold = true), color = paper, modifier = Modifier.offset(x = (-5).dp).padding(top = 10.dp, bottom = 14.dp))
        }
        Risen(revealed, reduceMotion, 2) {
            Text(seasonDeck(phase), style = sans(fixed(15f), fixed(6f)), color = paper.copy(alpha = 0.8f), modifier = Modifier.widthIn(max = 290.dp))
        }
        if (fine != null) {
            Risen(revealed, reduceMotion, 3) {
                Text(fine, style = sans(fixed(10.5f), fixed(3f)), color = paper.copy(alpha = 0.5f), modifier = Modifier.padding(top = 10.dp))
            }
        }
        Risen(revealed, reduceMotion, if (fine == null) 3 else 4) {
            val hairline = paper.copy(alpha = 0.28f)
            Row(
                Modifier
                    .padding(top = 20.dp)
                    .fillMaxWidth()
                    .drawBehind { drawRect(hairline, size = Size(size.width, 1.dp.toPx())) }
                    .padding(top = 10.dp),
            ) {
                val style = sans(fixed(10.5f)).copy(letterSpacing = fixed(1.8f))
                Text(seasonTag(phase), style = style, color = paper.copy(alpha = 0.58f))
                Spacer(Modifier.weight(1f))
                Text("STILL $folio", style = style, color = paper.copy(alpha = 0.58f))
            }
        }
    }
}

@Composable
private fun Risen(revealed: Boolean, reduceMotion: Boolean, order: Int, content: @Composable () -> Unit) {
    val t = rise(revealed, reduceMotion, order)
    Box(Modifier.graphicsLayer { alpha = t; translationY = if (reduceMotion) 0f else (1f - t) * 14.dp.toPx() }) { content() }
}

private fun seasonPlainOf(phase: CyclePhase): Int = when (phase) {
    CyclePhase.MENSTRUAL -> R.string.season_plain_winter
    CyclePhase.FOLLICULAR -> R.string.season_plain_spring
    CyclePhase.OVULATION -> R.string.season_plain_summer
    CyclePhase.LUTEAL -> R.string.season_plain_autumn
}
