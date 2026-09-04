package app.temporoutine.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import app.temporoutine.core.CyclePredictor

// Phase 0 껍데기 — tempocore 링크가 앱 모듈까지 닿는지만 본다. 화면은 Phase 1부터.
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val spans = CyclePredictor.phaseSpans(cycleLength = 28)
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(text = spans.joinToString { "${it.phase}:${it.startDay}+${it.length}" })
            }
        }
    }
}
