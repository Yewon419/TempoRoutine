// 템포루틴 Android — 유리 재질 (iOS Almanac.swift MilkGlass 기본 분기 · compactBar ultraThin · groundHaze 이식)
// 재질 위계(§4 보강 I): 크롬 유리(blur 18) vs 밀크 글래스 지면(blur 8, 거의 불투명). 전 요소 동일 유리 금지.
// Haze 1.7.3: 배경 스택이 hazeSource, 카드·바는 hazeEffect.

package app.temporoutine.android.theme

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeStyle
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeEffect

/** 밀크 글래스 지면 — ultraThin blur + Ink.surface 스크림 + accent 18% 1dp 테두리. */
@Composable
fun Modifier.milkGlass(hazeState: HazeState, radius: Dp = 16.dp): Modifier {
    val ink = Ink
    val shape = RoundedCornerShape(radius)
    return this
        .clip(shape)
        .hazeEffect(state = hazeState, style = HazeStyle(
            backgroundColor = ink.paper,
            tint = HazeTint(ink.surface),
            blurRadius = 8.dp,
            noiseFactor = 0f,
        ))
        .border(1.dp, ink.accent.copy(alpha = 0.18f), shape)
}

/** 크롬 유리(컴팩트 바·탭바) — blur 18 + paper 60% 틴트. */
@Composable
fun Modifier.chromeGlass(hazeState: HazeState): Modifier {
    val ink = Ink
    return this.hazeEffect(state = hazeState, style = HazeStyle(
        backgroundColor = ink.paper,
        tint = HazeTint(ink.paper.copy(alpha = 0.6f)),
        blurRadius = 18.dp,
        noiseFactor = 0f,
    ))
}

/** iOS groundHaze — 텍스트 뒤 안개(paper 62%, 12/8 확장, blur 12). 모티프 위 활자 가독성용. */
@Composable
fun GroundHaze(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val paper = Ink.paper
    Box(modifier) {
        Box(
            Modifier
                .matchParentSize()
                .graphicsLayer { renderEffect = BlurEffect(12.dp.toPx(), 12.dp.toPx(), TileMode.Decal) }
                .drawBehind {
                    val dx = 12.dp.toPx()
                    val dy = 8.dp.toPx()
                    drawRoundRect(
                        color = paper.copy(alpha = 0.62f),
                        topLeft = Offset(-dx, -dy),
                        size = Size(size.width + dx * 2, size.height + dy * 2),
                        cornerRadius = CornerRadius(14.dp.toPx()),
                    )
                },
        )
        content()
    }
}
