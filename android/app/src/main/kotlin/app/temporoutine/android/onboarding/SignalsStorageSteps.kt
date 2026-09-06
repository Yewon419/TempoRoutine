// 템포루틴 Android — 온보딩 ④ 추적 항목 · ⑤ 저장 위치 · ⑥ 설문 안내 (iOS OnboardingFlow signalsStep/storageStep/surveyStep 이식)
// ④ 에너지·기분 기본 + 수면·식욕·오늘 한 줄 토글(항목 ⓘ 설명 = 체크인 행에서 걷어낸 설명의 새 자리).
// ⑤ P0는 기기 저장뿐(건강 앱·iCloud 행 없음) — §7 privacy-washing 금지: 실제 활성인 저장처만 적는다.

package app.temporoutine.android.onboarding

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.temporoutine.android.R
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.milkGlass
import app.temporoutine.android.today.InfoBadge
import dev.chrisbanes.haze.HazeState

data class SignalToggles(val sleep: Boolean = true, val appetite: Boolean = true, val note: Boolean = true)

// ══ ④ 추적 항목 ══
@Composable
fun ColumnScope.SignalsStep(toggles: SignalToggles, hazeState: HazeState, onChange: (SignalToggles) -> Unit) {
    val ink = Ink
    StepHeader(stringResource(R.string.ob_signals_eyebrow), stringResource(R.string.ob_signals_title))
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        val style = Fonts.almanacBody(13)
        val color = ink.text.copy(alpha = 0.55f)
        Text(stringResource(R.string.ob_signals_line1), style = style, color = color)
        Text(stringResource(R.string.ob_signals_line2), style = style, color = color)
    }
    Column(Modifier.fillMaxWidth().milkGlass(hazeState).padding(horizontal = 16.dp, vertical = 6.dp)) {
        BaseRow(stringResource(R.string.ob_sig_energy), stringResource(R.string.ob_sig_energy_info))
        BaseRow(stringResource(R.string.ob_sig_mood), stringResource(R.string.ob_sig_mood_info))
        ToggleRow(stringResource(R.string.ob_sig_sleep), stringResource(R.string.ob_sig_sleep_info), toggles.sleep) { onChange(toggles.copy(sleep = it)) }
        ToggleRow(stringResource(R.string.ob_sig_appetite), stringResource(R.string.ob_sig_appetite_info), toggles.appetite) { onChange(toggles.copy(appetite = it)) }
        ToggleRow(stringResource(R.string.ob_sig_note), stringResource(R.string.ob_sig_note_info), toggles.note) { onChange(toggles.copy(note = it)) }
    }
}

@Composable
private fun BaseRow(name: String, info: String) {
    val ink = Ink
    Row(Modifier.fillMaxWidth().padding(vertical = 11.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        InfoBadge(title = name, message = info)
        Text(name, style = Fonts.system(15), color = ink.text)
        Text(
            stringResource(R.string.ob_sig_default), style = Fonts.system(11), color = ink.text.copy(alpha = 0.5f),
            modifier = Modifier.border(1.dp, ink.text.copy(alpha = 0.25f), CircleShape).padding(horizontal = 7.dp, vertical = 2.dp),
        )
    }
}

@Composable
private fun ToggleRow(name: String, info: String, value: Boolean, onChange: (Boolean) -> Unit) {
    val ink = Ink
    Row(Modifier.fillMaxWidth().padding(vertical = 7.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        InfoBadge(title = name, message = info)
        Text(name, style = Fonts.system(15), color = ink.text)
        Spacer(Modifier.weight(1f))
        Switch(
            checked = value, onCheckedChange = onChange,
            colors = SwitchDefaults.colors(
                checkedTrackColor = ink.text, checkedThumbColor = ink.paper,
                uncheckedTrackColor = ink.text.copy(alpha = 0.12f), uncheckedThumbColor = ink.text.copy(alpha = 0.6f),
                uncheckedBorderColor = Color.Transparent,
            ),
        )
    }
}

// ══ ⑤ 저장 위치 ══
@Composable
fun ColumnScope.StorageStep(hazeState: HazeState) {
    val ink = Ink
    StepHeader(stringResource(R.string.ob_storage_eyebrow), stringResource(R.string.ob_storage_title))
    Text(stringResource(R.string.ob_storage_line), style = Fonts.almanacBody(13), color = ink.text.copy(alpha = 0.65f))
    Column(Modifier.fillMaxWidth().milkGlass(hazeState).padding(horizontal = 16.dp, vertical = 6.dp)) {
        Row(Modifier.fillMaxWidth().padding(vertical = 11.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            PhoneGlyph(ink.text.copy(alpha = 0.6f))
            Text(stringResource(R.string.ob_storage_device), style = Fonts.system(15), color = ink.text)
            Spacer(Modifier.weight(1f))
            CheckGlyph(ink.text.copy(alpha = 0.6f))
        }
    }
    Text(stringResource(R.string.ob_storage_foot), style = Fonts.almanacBody(13), color = ink.text.copy(alpha = 0.55f))
}

/** SF `iphone` 대용 — 둥근 사각 + 하단 홈 점 */
@Composable
private fun PhoneGlyph(color: Color) {
    Canvas(Modifier.size(12.dp, 18.dp)) {
        drawRoundRect(color, cornerRadius = CornerRadius(2.5.dp.toPx()), style = Stroke(width = 1.4.dp.toPx()))
        drawCircle(color, radius = 0.9.dp.toPx(), center = Offset(size.width / 2, size.height - 2.5.dp.toPx()))
    }
}

@Composable
private fun CheckGlyph(color: Color) {
    Canvas(Modifier.size(12.dp)) {
        val p = Path().apply { moveTo(size.width * 0.05f, size.height * 0.55f); lineTo(size.width * 0.4f, size.height * 0.9f); lineTo(size.width * 0.95f, size.height * 0.15f) }
        drawPath(p, color, style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round))
    }
}

// ══ ⑥ 리듬 설문 안내 ══
@Composable
fun ColumnScope.SurveyStep(hasReport: Boolean) {
    val ink = Ink
    StepHeader(stringResource(R.string.ob_survey_eyebrow), stringResource(R.string.ob_survey_title))
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        val style = Fonts.almanacBody(13)
        val color = ink.text.copy(alpha = 0.55f)
        Text(stringResource(R.string.ob_survey_line1), style = style, color = color)
        Text(stringResource(R.string.ob_survey_line2), style = style, color = color)
        Text(stringResource(R.string.ob_survey_line3), style = style, color = color)
    }
    if (hasReport) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            SealGlyph(ink.text.copy(alpha = 0.6f))
            Text(stringResource(R.string.ob_survey_done), style = Fonts.system(13), color = ink.text.copy(alpha = 0.6f))
        }
    }
}

/** SF `checkmark.seal` 대용 — 원 + 체크 */
@Composable
private fun SealGlyph(color: Color) {
    Canvas(Modifier.size(14.dp)) {
        drawCircle(color, radius = size.minDimension / 2 - 1f, style = Stroke(width = 1.3.dp.toPx()))
        val p = Path().apply { moveTo(size.width * 0.28f, size.height * 0.52f); lineTo(size.width * 0.45f, size.height * 0.68f); lineTo(size.width * 0.74f, size.height * 0.34f) }
        drawPath(p, color, style = Stroke(width = 1.5.dp.toPx(), cap = StrokeCap.Round))
    }
}
