// 템포루틴 Android — 씨앗 획득 연출 (iOS Seeds.swift SeedBurst 이식)
// 도장이 찍히는 순간, 편집기 위로 씨앗이 스프링으로 피어올랐다가 잦아든다(스티커 등장과 같은 놀이 언어 —
// 데이터 상태 표시가 아니라서 §4 "상태 전환은 즉시" 원칙과 별개 층). trigger 증가 = 1회 재생, 성공 햅틱 동반.
// 값은 iOS 그대로: 15×20 글리프 · 위로 26dp · 등장 spring(0.34/0.55) · 1.2초 유지 · 퇴장 spring(0.3/0.85).

package app.temporoutine.android.today

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import app.temporoutine.android.onboarding.rememberReduceMotion
import app.temporoutine.android.theme.Ink
import kotlinx.coroutines.delay

private const val HOLD_MS = 1_200L

/**
 * 체크인 편집기 위에 씨앗 연출을 얹는다. iOS `.seedBurst(trigger:)` 대응.
 * @param trigger 증가할 때 1회 재생. 첫 합성 값으로는 재생하지 않는다(화면에 들어오자마자 터지면 안 된다).
 */
@Composable
fun SeedBurstOverlay(trigger: Int, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val ink = Ink
    val haptic = LocalHapticFeedback.current
    val reduceMotion = rememberReduceMotion()
    // 등장 진행도 0→1 — 스케일(0.1→1)·위치(아래 18dp→제자리)·투명도를 한 값으로 몬다
    val progress = remember { Animatable(0f) }
    var seen by remember { mutableStateOf<Int?>(null) }

    LaunchedEffect(trigger) {
        val previous = seen
        seen = trigger
        if (previous == null || trigger <= previous) return@LaunchedEffect
        haptic.performHapticFeedback(HapticFeedbackType.Confirm)
        if (reduceMotion) {
            progress.animateTo(1f, tween(120))
            delay(HOLD_MS)
            progress.animateTo(0f, tween(120))
            return@LaunchedEffect
        }
        progress.animateTo(1f, spring(dampingRatio = 0.55f, stiffness = springStiffness(0.34f)))
        delay(HOLD_MS)
        progress.animateTo(0f, spring(dampingRatio = 0.85f, stiffness = springStiffness(0.3f)))
    }

    Box(modifier) {
        content()
        val t = progress.value
        if (t > 0.001f) {
            Box(
                Modifier
                    .align(Alignment.TopCenter)
                    .offset(y = (-26).dp)
                    .graphicsLayer {
                        alpha = t
                        val scale = if (reduceMotion) 1f else 0.1f + 0.9f * t
                        scaleX = scale
                        scaleY = scale
                        translationY = if (reduceMotion) 0f else (1f - t) * 18.dp.toPx()
                    }
                    .clearAndSetSemantics { },
            ) {
                SeedGlyph(color = ink.text.copy(alpha = 0.85f), width = 15.dp, height = 20.dp)
            }
        }
    }
}

/** SwiftUI `spring(response:)` → Compose stiffness. ω = 2π/response, k = ω². */
private fun springStiffness(response: Float): Float {
    val omega = (2.0 * Math.PI / response).toFloat()
    return omega * omega
}
