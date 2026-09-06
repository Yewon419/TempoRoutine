// 템포루틴 Android — 오늘 체크인 카드 (iOS CheckInCard.swift 이식)
// 3칩 = 1·3·5, 길게 누르기 = 왼쪽 이웃과의 중간(2·4 — 첫 칩은 없음). 증상은 다중 선택, 길게 누르기 없음.
// 드래프트는 로컬, 변경마다 persist(전부 비면 삭제). 씨앗 연출은 지급 카운터로.

package app.temporoutine.android.today

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.temporoutine.android.R
import app.temporoutine.android.data.CheckInDraft
import app.temporoutine.android.data.CheckInSymptom
import app.temporoutine.android.data.DailyCheckInEntity
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.milkGlass
import app.temporoutine.core.TrackedSignals
import dev.chrisbanes.haze.HazeState
import java.time.LocalDate

/** 3칩 신호 행 — value 0 = 미기록. halfStep: 길게 누르기 중간값 허용 여부(카드 O, 시트 편집기 X). */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SignalChips(options: List<String>, value: Int, halfStep: Boolean, compact: Boolean, onChange: (Int) -> Unit) {
    val ink = Ink
    val haptic = LocalHapticFeedback.current
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        options.forEachIndexed { index, option ->
            val mapped = index * 2 + 1
            val selected = value == mapped
            val half = halfStep && value > 0 && (value == mapped - 1 || value == mapped + 1)
            val bg = when {
                selected -> ink.text
                half -> ink.text.copy(alpha = 0.35f)
                else -> ink.text.copy(alpha = 0.08f)
            }
            val fg = if (selected) ink.paper else ink.text.copy(alpha = if (half) 0.9f else 0.7f)
            Text(
                option,
                style = Fonts.system(if (compact) 11 else 12),
                color = fg,
                maxLines = 1,
                modifier = Modifier
                    .background(bg, CircleShape)
                    .combinedClickable(
                        onClick = {
                            if (compact) haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            onChange(if (selected) 0 else mapped)
                        },
                        onLongClick = if (halfStep && mapped > 1) ({
                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                            onChange(if (value == mapped - 1) 0 else mapped - 1)
                        }) else null,
                    )
                    .padding(horizontal = if (compact) 9.dp else 10.dp, vertical = if (compact) 6.dp else 7.dp),
            )
        }
    }
}

@Composable
private fun SignalRow(label: String, options: List<String>, value: Int, onChange: (Int) -> Unit) {
    val ink = Ink
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(label, style = Fonts.system(15), color = ink.text.copy(alpha = 0.75f), modifier = Modifier.width(108.dp))
        SignalChips(options, value, halfStep = true, compact = false, onChange = onChange)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SymptomRow(selected: Set<CheckInSymptom>, onToggle: (CheckInSymptom) -> Unit) {
    val ink = Ink
    val titles = mapOf(
        CheckInSymptom.COLD to R.string.symptom_cold, CheckInSymptom.FEVER to R.string.symptom_fever,
        CheckInSymptom.STOMACH to R.string.symptom_stomach, CheckInSymptom.MUSCLE to R.string.symptom_muscle,
        CheckInSymptom.HEADACHE to R.string.symptom_headache,
    )
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(stringResource(R.string.checkin_symptoms), style = Fonts.system(15), color = ink.text.copy(alpha = 0.75f), modifier = Modifier.width(108.dp).padding(top = 7.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            CheckInSymptom.entries.forEach { s ->
                val on = s in selected
                Text(
                    stringResource(titles.getValue(s)),
                    style = Fonts.system(12),
                    color = if (on) ink.paper else ink.text.copy(alpha = 0.7f),
                    modifier = Modifier
                        .background(if (on) ink.text else ink.text.copy(alpha = 0.08f), CircleShape)
                        .combinedClickable(onClick = { onToggle(s) })
                        .padding(horizontal = 10.dp, vertical = 7.dp),
                )
            }
        }
    }
}

@Composable
fun CheckInCard(day: LocalDate, record: DailyCheckInEntity?, signals: TrackedSignals, vm: TodayViewModel, hazeState: HazeState, isToday: Boolean) {
    val ink = Ink
    var draft by remember(day) { mutableStateOf(vm.app.checkInStore.draftOf(record)) }
    // DB 반영 후 레코드가 바뀌면(도장·다른 화면 편집) 드래프트를 신호→노트 순으로 다시 읽는다
    LaunchedEffect(record?.id, record?.completedAt) { if (record != null) draft = vm.app.checkInStore.draftOf(record) }
    val burst by vm.seedBurst.collectAsState()

    fun commit(next: CheckInDraft) {
        draft = next
        vm.persistCheckIn(day, next.copy(symptoms = next.symptoms ?: emptySet()))
    }

    SeedBurstOverlay(trigger = burst, modifier = Modifier.fillMaxWidth()) {
    Column(
        Modifier.fillMaxWidth().milkGlass(hazeState).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(if (isToday) R.string.checkin_title_today else R.string.checkin_title_day), style = Fonts.almanac(17), color = ink.text)
        }
        SignalRow(stringResource(R.string.checkin_energy), listOf(stringResource(R.string.checkin_energy_low), stringResource(R.string.checkin_mid), stringResource(R.string.checkin_energy_high)), draft.energy) { commit(draft.copy(energy = it)) }
        SignalRow(stringResource(R.string.checkin_mood), listOf(stringResource(R.string.checkin_mood_low), stringResource(R.string.checkin_mid), stringResource(R.string.checkin_mood_high)), draft.mood) { commit(draft.copy(mood = it)) }
        if (signals.sleep) SignalRow(stringResource(R.string.checkin_sleep), listOf(stringResource(R.string.checkin_sleep_low), stringResource(R.string.checkin_mid), stringResource(R.string.checkin_sleep_high)), draft.sleep) { commit(draft.copy(sleep = it)) }
        if (signals.appetite) SignalRow(stringResource(R.string.checkin_appetite), listOf(stringResource(R.string.checkin_appetite_low), stringResource(R.string.checkin_mid), stringResource(R.string.checkin_appetite_high)), draft.appetite) { commit(draft.copy(appetite = it)) }
        SymptomRow(draft.symptoms ?: emptySet()) { s ->
            val cur = draft.symptoms ?: emptySet()
            commit(draft.copy(symptoms = if (s in cur) cur - s else cur + s))
        }
        if (signals.note) Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(stringResource(if (isToday) R.string.checkin_note_today else R.string.checkin_note_day), style = Fonts.system(12), color = ink.text.copy(alpha = 0.5f))
            BasicTextField(
                value = draft.note,
                onValueChange = { commit(draft.copy(note = it)) },
                textStyle = Fonts.system(15).copy(color = ink.text),
                cursorBrush = SolidColor(ink.text),
                decorationBox = { inner ->
                    if (draft.note.isEmpty()) Text(stringResource(R.string.checkin_note_prompt), style = Fonts.system(15), color = ink.text.copy(alpha = 0.35f))
                    inner()
                },
                modifier = Modifier.fillMaxWidth(),
            )
        }
        if (draft.energy > 0 && draft.mood > 0) {
            Text(stringResource(if (isToday) R.string.checkin_confirm_today else R.string.checkin_confirm_day), style = Fonts.almanacBody(13), color = ink.text.copy(alpha = 0.6f))
        }
    }
    }
}
