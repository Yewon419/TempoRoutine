package app.temporoutine.android

import android.content.pm.ApplicationInfo
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import app.temporoutine.android.theme.TempoTheme
import app.temporoutine.android.today.TodayRoute
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
        // 디버그 검증용 진입(캘린더 탭의 「생리 기록」 버튼은 Phase 2) — `--ez openLogSheet true`
        val openSheet = debuggable && intent.getBooleanExtra("openLogSheet", false)
        setContent {
            TempoTheme {
                TodayRoute(app, openLogSheetInitially = openSheet)
            }
        }
    }
}
