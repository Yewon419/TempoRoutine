// 템포루틴 Android — 오늘 체크인 카드 (iOS CheckInCard.swift 이식)
// 3칩 = 1·3·5, 길게 누르기 = 왼쪽 이웃과의 중간(2·4 — 첫 칩은 없음). 증상은 다중 선택, 길게 누르기 없음.
// 드래프트는 로컬, 변경마다 persist(전부 비면 삭제). 씨앗 연출은 지급 카운터로.

package app.temporoutine.android.today

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
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
import androidx.compose.ui.unit.sp
import app.temporoutine.android.R
import app.temporoutine.android.data.CheckInDraft
import app.temporoutine.android.data.CheckInSymptom
import app.temporoutine.android.data.DailyCheckInEntity
import app.temporoutine.android.cycle.PhaseInfo
import app.temporoutine.android.cycle.seasonCopy
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.SeasonGlyph
import app.temporoutine.android.theme.milkGlass
import app.temporoutine.android.theme.primeCard
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
fun CheckInCard(day: LocalDate, record: DailyCheckInEntity?, signals: TrackedSignals, phaseInfo: PhaseInfo?, vm: TodayViewModel, hazeState: HazeState, isToday: Boolean) {
    val ink = Ink
    var draft by remember(day) { mutableStateOf(vm.app.checkInStore.draftOf(record)) }
    // DB 반영 후 레코드가 바뀌면(도장·다른 화면 편집) 드래프트를 신호→노트 순으로 다시 읽는다
    LaunchedEffect(record?.id, record?.completedAt) { if (record != null) draft = vm.app.checkInStore.draftOf(record) }
    val burst by vm.seedBurst.collectAsState()

    fun commit(next: CheckInDraft) {
        draft = next
        vm.persistCheckIn(day, next.copy(symptoms = next.symptoms ?: emptySet()))
    }

    // 「오늘 한 줄」은 컨디션 기록과 다른 카드다(iOS 2026-09-05 베타 "오늘한줄이랑 사진넣는걸 아래칸에 따로 카드로 빼자")
    // — 척도 고르기와 글 남기기는 성격이 다른 일이다. 초안·저장은 한 드래프트라 저장 경로는 갈라지지 않는다.
    SeedBurstOverlay(trigger = burst, modifier = Modifier.fillMaxWidth()) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
    Column(
        Modifier.fillMaxWidth().primeCard().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        // 표찰 + 물음(iOS 은필 v2) — 컨디션 기록은 하루 루프의 주인공이라 카드도 한 단계 도드라진다
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                stringResource(if (isToday) R.string.checkin_title_today else R.string.checkin_title_day),
                style = Fonts.almanacBody(12).copy(letterSpacing = 2.sp),
                color = ink.text.copy(alpha = 0.55f),
            )
            Text(stringResource(if (isToday) R.string.checkin_question_today else R.string.checkin_question_day), style = Fonts.almanac(17), color = ink.text)
        }
        SignalRow(stringResource(R.string.checkin_energy), listOf(stringResource(R.string.checkin_energy_low), stringResource(R.string.checkin_mid), stringResource(R.string.checkin_energy_high)), draft.energy) { commit(draft.copy(energy = it)) }
        SignalRow(stringResource(R.string.checkin_mood), listOf(stringResource(R.string.checkin_mood_low), stringResource(R.string.checkin_mid), stringResource(R.string.checkin_mood_high)), draft.mood) { commit(draft.copy(mood = it)) }
        if (signals.sleep) SignalRow(stringResource(R.string.checkin_sleep), listOf(stringResource(R.string.checkin_sleep_low), stringResource(R.string.checkin_mid), stringResource(R.string.checkin_sleep_high)), draft.sleep) { commit(draft.copy(sleep = it)) }
        if (signals.appetite) SignalRow(stringResource(R.string.checkin_appetite), listOf(stringResource(R.string.checkin_appetite_low), stringResource(R.string.checkin_mid), stringResource(R.string.checkin_appetite_high)), draft.appetite) { commit(draft.copy(appetite = it)) }
        SymptomRow(draft.symptoms ?: emptySet()) { s ->
            val cur = draft.symptoms ?: emptySet()
            commit(draft.copy(symptoms = if (s in cur) cur - s else cur + s))
        }
        if (draft.energy > 0 && draft.mood > 0) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(6.dp).background(ink.winter, CircleShape))
                Text(stringResource(if (isToday) R.string.checkin_confirm_today else R.string.checkin_confirm_day), style = Fonts.almanacBody(13), color = ink.winter)
            }
        }
    }
    // 두 번째 카드 — 한 줄(사진 칸은 Android에 사진 기능이 없어 뺀다). 추적 항목 토글을 따른다.
    if (signals.note) Column(
        Modifier.fillMaxWidth().milkGlass(hazeState).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(stringResource(if (isToday) R.string.checkin_note_today else R.string.checkin_note_day), style = Fonts.almanac(17), color = ink.text)
        // 피드 머리줄(iOS feedHeader) — 계절 글리프 + 「계절 N일차」. 오늘 카드는 날짜를 안 적는다(표제 메타 줄과 중복).
        if (phaseInfo != null) {
            val seasonInk = ink.season(phaseInfo.phase)
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                SeasonGlyph(phaseInfo.phase, seasonInk, size = 11.dp)
                Text(
                    stringResource(R.string.checkin_feed_season_day, seasonCopy(phaseInfo.phase).name, phaseInfo.dayInPhase),
                    style = Fonts.almanacBody(12, bold = true),
                    color = seasonInk,
                )
            }
        }
        BasicTextField(
            value = draft.note,
            onValueChange = { commit(draft.copy(note = it)) },
            textStyle = Fonts.almanacBody(15).copy(color = ink.text),   // 본문 = 명조(피드와 동일)
            cursorBrush = SolidColor(ink.text),
            decorationBox = { inner ->
                if (draft.note.isEmpty()) Text(stringResource(R.string.checkin_note_prompt), style = Fonts.almanacBody(15), color = ink.text.copy(alpha = 0.35f))
                inner()
            },
            modifier = Modifier.fillMaxWidth(),
        )
    }
    }
    }
}
