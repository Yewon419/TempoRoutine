package app.temporoutine.android

import android.content.pm.ApplicationInfo
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import app.temporoutine.android.theme.TempoTheme
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
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
