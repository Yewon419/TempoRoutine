// 템포루틴 Android — 콜드 런치 스플래시 (iOS RootTabView 스플래시 overlay + BrandLogo.swift SplashGround 이식)
// iOS 2026-08-25 대표님 "앱 다시 켤 때 로딩화면" — 프로세스당 1회, 무음, 1.1s 뒤 0.4s 페이드, 탭하면 즉시 넘어간다.
// 은필 = 오늘 계절의 계절광 지면 + 검정 0.42 스크림 + 흰 심볼 148(그림 배경 테마 분기). 테마가 은필 하나라 그 분기만 옮겼다.
// 첫 실행(온보딩)은 사운드가 있는 온보딩 스플래시가 따로 있어 이건 뜨지 않는다(게이트를 온보딩이 먼저 세운다).

package app.temporoutine.android

import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.SeasonLight
import app.temporoutine.android.theme.rememberReduceMotion
import app.temporoutine.core.CyclePhase
import kotlinx.coroutines.delay

/** 프로세스당 1회. 쓰기는 메인뿐(SplashGate 전례). */
object LaunchSplashGate {
    var shown = false
}

/** @param onDismissed 페이드가 끝난 뒤 1회 — 호출자가 오버레이를 걷는다 */
@Composable
fun LaunchSplash(phase: CyclePhase?, onDismissed: () -> Unit) {
    val ink = Ink
    val reduceMotion = rememberReduceMotion()
    var leaving by remember { mutableStateOf(false) }
    val alpha by animateFloatAsState(
        if (leaving) 0f else 1f,
        if (reduceMotion) snap() else tween(400, easing = EaseOut),
        label = "launchSplash",
        finishedListener = { if (leaving) onDismissed() },
    )
    fun dismiss() {
        if (leaving) return
        LaunchSplashGate.shown = true
        leaving = true
    }
    LaunchedEffect(Unit) {
        delay(1_100)
        dismiss()
    }
    val label = stringResource(R.string.ob_splash_a11y) + ", " + stringResource(R.string.ob_splash_hint)
    Box(
        Modifier
            .fillMaxSize()
            .graphicsLayer { this.alpha = alpha }
            .background(ink.paper)
            .clearAndSetSemantics { contentDescription = label }
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { dismiss() },
        contentAlignment = Alignment.Center,
    ) {
        SeasonLight(phase = phase, modifier = Modifier.fillMaxSize())
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.42f)))   // 어두운 스크림 — 흰 심볼 가독
        Image(painterResource(R.drawable.splash_logo), contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.width(148.dp))
    }
}
