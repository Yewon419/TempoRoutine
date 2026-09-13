package app.temporoutine.android

import android.content.pm.ApplicationInfo
import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import app.temporoutine.android.theme.TempoTheme
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // 다크 모드 제거(2026-09-09) — 기본값(auto)은 다크 기기에서 밝은 지면 위에 흰 시스템 바 아이콘을 띄운다.
        // 스크림은 기본값과 같은 값(activity 1.13.0 EdgeToEdge: 상태바 투명 · 내비바 argb(230,255,255,255)/argb(128,27,27,27)).
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.light(Color.argb(230, 255, 255, 255), Color.argb(128, 27, 27, 27)),
        )
        super.onCreate(savedInstanceState)
        val app = application as TempoApp
        val debuggable = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        if (debuggable && intent.getBooleanExtra("seedSample", false)) {
            lifecycleScope.launch { DevSampleData.seed(app) }
        }
        // 디버그 검증용 진입 — `--ez openLogSheet true`(생리 기록 시트), `--ez resetOnboarding true`(온보딩 다시)
        val openSheet = debuggable && intent.getBooleanExtra("openLogSheet", false)
        val resetOnboarding = debuggable && intent.getBooleanExtra("resetOnboarding", false)
        lifecycleScope.launch {
            // 리셋은 첫 프레임 전에 — 순서가 뒤집히면 오늘 탭이 한 번 그려진 뒤 온보딩이 덮는다
            if (resetOnboarding) app.settings.setOnboardingDone(false)
            setContent {
                TempoTheme {
                    RootScaffold(app, openLogSheetInitially = openSheet)
                }
            }
        }
    }
}
