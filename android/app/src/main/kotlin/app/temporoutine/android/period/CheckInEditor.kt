// 템포루틴 Android — 시트 안 컨디션 편집기 (iOS PeriodTrackerSheet.CheckInEditor 이식)
// 카드의 축소판: 증상 행·확인 문장·노트 라벨 없음, 라벨 84dp, 칩 caption2(11)·9/6, 중간값(2·4) 없음, 탭마다 light 햅틱.
// 증상은 건드리지 않는다(symptoms = null → 기존 값 보존).

package app.temporoutine.android.period

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.temporoutine.android.R
import app.temporoutine.android.data.CheckInDraft
import app.temporoutine.android.data.DailyCheckInEntity
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.milkGlass
import app.temporoutine.android.today.SignalChips
import app.temporoutine.android.today.TodayViewModel
import app.temporoutine.android.today.persistCheckIn
import app.temporoutine.core.TrackedSignals
import dev.chrisbanes.haze.HazeState
import java.time.LocalDate

@Composable
fun CheckInEditor(day: LocalDate, record: DailyCheckInEntity?, signals: TrackedSignals, vm: TodayViewModel, hazeState: HazeState, isFuture: Boolean) {
    val ink = Ink
    var draft by remember(day) { mutableStateOf(vm.app.checkInStore.draftOf(record).copy(symptoms = null)) }
    LaunchedEffect(day, record?.id) { draft = vm.app.checkInStore.draftOf(record).copy(symptoms = null) }

    fun commit(next: CheckInDraft) {
        draft = next
        if (!isFuture) vm.persistCheckIn(day, next)
    }

    Column(
        Modifier.fillMaxWidth().alpha(if (isFuture) 0.45f else 1f).milkGlass(hazeState, radius = 14.dp).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(8.dp).background(ink.winter, CircleShape))
            Text(stringResource(R.string.sheet_condition), style = Fonts.system(15, FontWeight.SemiBold), color = ink.text)
            Spacer(Modifier.weight(1f))
        }
        val enabled = !isFuture
        EditorRow(stringResource(R.string.checkin_energy), listOf(stringResource(R.string.checkin_energy_low), stringResource(R.string.checkin_mid), stringResource(R.string.checkin_energy_high)), draft.energy, enabled) { commit(draft.copy(energy = it)) }
        EditorRow(stringResource(R.string.checkin_mood), listOf(stringResource(R.string.checkin_mood_low), stringResource(R.string.checkin_mid), stringResource(R.string.checkin_mood_high)), draft.mood, enabled) { commit(draft.copy(mood = it)) }
        if (signals.sleep) EditorRow(stringResource(R.string.checkin_sleep), listOf(stringResource(R.string.checkin_sleep_low), stringResource(R.string.checkin_mid), stringResource(R.string.checkin_sleep_high)), draft.sleep, enabled) { commit(draft.copy(sleep = it)) }
        if (signals.appetite) EditorRow(stringResource(R.string.checkin_appetite), listOf(stringResource(R.string.checkin_appetite_low), stringResource(R.string.checkin_mid), stringResource(R.string.checkin_appetite_high)), draft.appetite, enabled) { commit(draft.copy(appetite = it)) }
        if (signals.note) BasicTextField(
            value = draft.note,
            onValueChange = { commit(draft.copy(note = it)) },
            enabled = enabled,
            textStyle = Fonts.system(13).copy(color = ink.text),
            cursorBrush = SolidColor(ink.text),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
private fun EditorRow(label: String, options: List<String>, value: Int, enabled: Boolean, onChange: (Int) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(label, style = Fonts.system(13), color = Ink.text.copy(alpha = 0.7f), modifier = Modifier.width(84.dp))
        SignalChips(options, value, halfStep = false, compact = true, onChange = { if (enabled) onChange(it) })
    }
}
