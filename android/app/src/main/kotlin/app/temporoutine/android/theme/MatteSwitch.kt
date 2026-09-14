// 템포루틴 Android — 무광 스위치 (iOS Almanac.swift MatteToggleStyle 이식, 은필 v2 2026-09-07 + 실기기 교정).
// 은필 괘선 캡슐 + 지면색 원반. 켜지면 원반 뒤에서 먹(74%)이 번진다 — 순먹 100%는 시트 위에서 무거웠다.
// 원반 24 + 여백 4로 캡슐 괘선이 사방에 보이게 하고, 원반 정점에 브랜드 점(꺼짐 = 겨울색, 켜짐 = 지면색).

package app.temporoutine.android.theme

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp

/** 조작 가능한 스위치 — 트랙 자체가 토글이다(설정 행처럼 행도 따로 뒤집는 곳에 쓴다). */
@Composable
fun MatteSwitch(checked: Boolean, onCheckedChange: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    MatteSwitchTrack(
        checked,
        modifier.toggleable(
            value = checked,
            interactionSource = remember { MutableInteractionSource() },
            indication = null,
            role = Role.Switch,
            onValueChange = onCheckedChange,
        ),
    )
}

/** 그리기만 하는 트랙 — 라벨까지 한 토글로 묶는 행(오늘 탭 「오늘」)은 행이 toggleable을 갖고 이걸 둔다. */
@Composable
fun MatteSwitchTrack(checked: Boolean, modifier: Modifier = Modifier) {
    val ink = Ink
    val reduceMotion = rememberReduceMotion()
    // SwiftUI spring(response 0.3, damping 0.72) → ω = 2π/0.3, k = ω² ≈ 438.6
    val t by animateFloatAsState(
        targetValue = if (checked) 1f else 0f,
        animationSpec = if (reduceMotion) snap() else spring(dampingRatio = 0.72f, stiffness = 438.6f),
        label = "matteSwitch",
    )
    val on = t.coerceIn(0f, 1f)
    Box(
        modifier
            .size(54.dp, 32.dp)
            .clip(CircleShape)
            .drawBehind {
                val h = size.height
                val capsule = CornerRadius(h / 2)
                drawRoundRect(ink.text.copy(alpha = 0.07f), cornerRadius = capsule)
                // 번짐 — 32 원을 트랙 중심(x 27)에서 0.01 → 3배. 캡슐 clip이 가장자리를 가둔다
                val bloomScale = 0.01f + 2.99f * t.coerceAtLeast(0f)
                drawCircle(ink.text.copy(alpha = 0.74f), radius = 16.dp.toPx() * bloomScale, center = Offset(27.dp.toPx(), h / 2))
                val line = 1.dp.toPx()
                drawRoundRect(
                    ink.accent.copy(alpha = 0.5f),
                    topLeft = Offset(line / 2, line / 2),
                    size = Size(size.width - line, h - line),
                    cornerRadius = CornerRadius((h - line) / 2),
                    style = Stroke(width = line),
                )
                // 원반 24 + 여백 4, 켜짐 = x+22
                val knobR = 12.dp.toPx()
                val knob = Offset(16.dp.toPx() + 22.dp.toPx() * t, h / 2)
                drawCircle(Color.Black.copy(alpha = 0.10f + 0.08f * on), radius = knobR, center = knob + Offset(0f, 1.dp.toPx()))
                drawCircle(ink.paper.copy(alpha = 1f - 0.06f * on), radius = knobR, center = knob)
                val rim = 1.2.dp.toPx()
                drawCircle(lerp(ink.accent.copy(alpha = 0.7f), ink.paper.copy(alpha = 0.7f), on), radius = knobR - rim / 2, center = knob, style = Stroke(width = rim))
                drawCircle(lerp(ink.winter, ink.paper, on), radius = 2.dp.toPx(), center = knob + Offset(0f, -knobR + 6.dp.toPx()))
            },
    )
}
