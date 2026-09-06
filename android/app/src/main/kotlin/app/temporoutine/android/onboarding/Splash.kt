// 템포루틴 Android — 온보딩 브랜드 스플래시 (iOS OnboardingFlow.splash 이식): 정적 이미지 + 시그니처 사운드, 탭 = 건너뛰기.
// 프로세스당 1회(iOS splashShownThisLaunch) — 액티비티 재생성마다 소리가 다시 나면 안 된다.
// 타이밍: 30ms 뒤 로고 페이드인 0.7s → +250ms 사운드 → 2.45s 뒤 걷힘(음원 2.83s, 페이드아웃 0.5s 겹침).

package app.temporoutine.android.onboarding

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import app.temporoutine.android.R
import app.temporoutine.android.theme.Ink
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

object SplashGate {
    /** 프로세스당 1회. 쓰기는 메인뿐. */
    var shownThisLaunch = false
}

/**
 * @param reduceMotion 페이드 생략(즉시 표시·즉시 걷힘)
 * @param onDismissed 걷힘 애니메이션이 끝난 뒤 1회
 */
@Composable
fun OnboardingSplash(reduceMotion: Boolean, onDismissed: () -> Unit) {
    val ink = Ink
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val sound = remember { SignatureSound(context.applicationContext) }
    var logoIn by remember { mutableStateOf(false) }
    var leaving by remember { mutableStateOf(false) }
    val logoAlpha by animateFloatAsState(if (logoIn) 1f else 0f, tween(if (reduceMotion) 0 else 700), label = "splashLogo")
    val veilAlpha by animateFloatAsState(if (leaving) 0f else 1f, tween(if (reduceMotion) 0 else 500), label = "splashVeil",
        finishedListener = { if (leaving) onDismissed() })

    /** silencing = 사용자가 건너뛴 경우에만 true. 끝까지 재생된 소리는 건드리지 않는다. */
    fun dismiss(silencing: Boolean) {
        if (leaving) return
        SplashGate.shownThisLaunch = true
        if (silencing) scope.launch { sound.fadeOut() }
        leaving = true
    }

    LaunchedEffect(Unit) {
        delay(30)
        logoIn = true
        delay(250)
        if (leaving) return@LaunchedEffect
        sound.play()
        delay(2_450)
        dismiss(silencing = false)
    }

    val a11y = stringResource(R.string.ob_splash_a11y) + ", " + stringResource(R.string.ob_splash_hint)
    Box(
        Modifier
            .fillMaxSize()
            .alpha(veilAlpha)
            .background(ink.paper)
            .semantics { contentDescription = a11y }
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { dismiss(silencing = true) },
    ) {
        Image(
            painter = painterResource(R.drawable.onboarding_splash),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize().alpha(logoAlpha),
        )
    }
}
