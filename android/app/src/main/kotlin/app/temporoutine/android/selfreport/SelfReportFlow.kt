// 템포루틴 Android — 앱 내 자기보고 설문 (iOS SelfReportFlow.swift 이식, v1.6 §4 / MASTER §3.11)
// 결과를 보여주지 않는다 — 앱은 기록에서 유형을 계산하는데(§5.12) 자기보고 유형까지 띄우면 산출 경로가 다른 두 값이 나란히 보인다.
// 문항 순서·선택지·판정은 tempocore SelfReportSurvey가 소유(증상 8문항만 제시 순서 셔플, 시간 앵커 = P2 응답).
// 단문항 장(1장)은 선택 즉시 자동 진행하되 최초 1회만(답 고치러 돌아온 사람을 다시 밀어내지 않는다, 2026-09-04 베타).

package app.temporoutine.android.selfreport

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.temporoutine.android.R
import app.temporoutine.android.onboarding.SurveyLogic
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.MotifStyle
import app.temporoutine.android.theme.SeasonLight
import app.temporoutine.core.CyclePhase
import app.temporoutine.core.SelfReportSurvey
import app.temporoutine.core.SurveyChoice
import app.temporoutine.core.SurveyQuestion
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.rememberHazeState
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * @param previousAnswers 다시 하기 — 이전 응답을 채운 채 연다(결과 화면이 없는 앱이라 이전 응답을 「보는」 유일한 길).
 * @param onSubmit 화이트리스트 필터 전 원본 응답. 저장은 호출자(VM)가 한다.
 * @param onDismiss 제출·건너뛰기·닫기 어느 경로든 시트가 걷힌 뒤 1회.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SelfReportFlow(previousAnswers: Map<String, String> = emptyMap(), onSubmit: (Map<String, String>) -> Unit, onDismiss: () -> Unit) {
    val ink = Ink
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val hazeState = rememberHazeState()
    val scroll = rememberScrollState()

    var step by rememberSaveable { mutableIntStateOf(0) }
    val answers = remember { mutableStateMapOf<String, String>().apply { putAll(previousAnswers) } }
    val prefilled = previousAnswers.isNotEmpty()
    /** 제시 순서만 섞는다. 한 번 섞은 순서를 유지해야 화면을 오갈 때 문항이 튀지 않는다. */
    val symptomOrder = remember { SelfReportSurvey.symptomQuestions.shuffled() }
    /** 자동 진행을 이미 태운 장 — 답을 고치러 돌아온 사람을 다시 밀어내면 고칠 방법이 없다. */
    var autoAdvanced by remember { mutableStateOf(setOf<Int>()) }
    /** 자동 진행 예약(장 번호) — 260ms 뒤 소비. 사이에 사용자가 직접 넘겼거나 답을 지웠으면 손대지 않는다. */
    var armedStep by remember { mutableStateOf<Int?>(null) }
    val canAdvance = SurveyLogic.canAdvance(step, answers)

    fun close() { scope.launch { sheetState.hide() }.invokeOnCompletion { onDismiss() } }
    fun finish() { onSubmit(answers.toMap()); close() }
    fun advance() { if (step < SurveyLogic.TOTAL_STEPS) step += 1 else finish() }
    /** 선택 반영 + 단문항 장이면 자동 진행 예약. 재탭 해제로는 넘어가지 않는다. */
    fun select(question: SurveyQuestion, choice: SurveyChoice) {
        val wasSelected = choice.value in SelfReportSurvey.values(answers[question.id])
        if (question.allowsMultiple) {
            val next = SurveyLogic.toggledMultiValue(question, choice, answers[question.id])
            if (next == null) answers.remove(question.id) else answers[question.id] = next
        } else if (wasSelected) {
            answers.remove(question.id)
        } else {
            answers[question.id] = choice.value
        }
        if (!wasSelected && SurveyLogic.isSingleQuestionStep(step) && step !in autoAdvanced) armedStep = step
    }

    // 장을 넘기면 맨 위부터(2026-08-12 베타 피드백)
    LaunchedEffect(step) { scroll.scrollTo(0) }
    // 한 박자 늦추는 이유 = 고른 표시(라디오 채움)를 보고 넘어가야 무엇을 골랐는지 남는다
    LaunchedEffect(armedStep) {
        val armed = armedStep ?: return@LaunchedEffect
        delay(260)
        armedStep = null
        if (step != armed || !SurveyLogic.isSingleQuestionStep(step) || !SurveyLogic.canAdvance(step, answers)) return@LaunchedEffect
        autoAdvanced = autoAdvanced + armed
        advance()
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState, containerColor = ink.paper, dragHandle = null) {
        Box(Modifier.fillMaxSize()) {
            // "설문지" 인상 걷어내기 — 온보딩과 같은 겨울 광 + 감쇠 텍스처로 지면 어휘를 잇는다
            SeasonLight(phase = CyclePhase.MENSTRUAL, modifier = Modifier.fillMaxSize().hazeSource(hazeState), motif = MotifStyle.ONBOARDING)
            Column(Modifier.fillMaxSize()) {
                Box(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp)) {
                    TextButton(onClick = ::close, modifier = Modifier.align(Alignment.CenterStart)) {
                        Text(stringResource(R.string.survey_close), style = Fonts.system(17), color = ink.text)
                    }
                    Text(stringResource(R.string.survey_title), style = Fonts.system(17, FontWeight.SemiBold), color = ink.text, modifier = Modifier.align(Alignment.Center))
                }
                Column(
                    Modifier
                        .fillMaxWidth()
                        .widthIn(max = 640.dp)
                        .align(Alignment.CenterHorizontally)
                        .verticalScroll(scroll)
                        .padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(18.dp),
                ) {
                    ProgressHeader(step)
                    when (step) {
                        0 -> Intro(prefilled)
                        1 -> QuestionGroup(null, listOf(stringResource(R.string.survey_note_calibration)), listOf(SelfReportSurvey.calibration), answers, ::select)
                        // 복수 응답 안내(2026-09-09) — 체크 모양만으로는 여러 개를 골라도 된다는 걸 모른다
                        2 -> QuestionGroup(null, listOf(stringResource(R.string.survey_note_multiple)), SelfReportSurvey.phaseQuestions, answers, ::select)
                        3 -> QuestionGroup(symptomAnchorTitle(answers["P2"]), listOf(stringResource(R.string.survey_note_symptom)), symptomOrder, answers, ::select)
                        4 -> QuestionGroup(null, emptyList(), SelfReportSurvey.amplitudeQuestions, answers, ::select)
                        // 저장 위치 재고지(2026-09-09 베타) — 인트로에 이미 한 줄 있지만, 답하기를 망설이는 자리는 이 페이지다
                        else -> QuestionGroup(
                            null,
                            listOf(stringResource(R.string.survey_note_optional), stringResource(R.string.survey_note_optional_local)),
                            SelfReportSurvey.optionalQuestions, answers, ::select,
                        )
                    }
                    // 다음 = 우하단 글씨만, 이전 = 모든 문항 단계에(2026-08-05 베타 피드백)
                    Row(Modifier.fillMaxWidth().padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                        if (step > 0) ActionText(stringResource(R.string.survey_prev), enabled = true, weight = FontWeight.Medium, alpha = 0.55f) { step -= 1 }
                        Spacer(Modifier.weight(1f))
                        if (step == SurveyLogic.TOTAL_STEPS) ActionText(stringResource(R.string.survey_skip), enabled = true, weight = FontWeight.Normal, alpha = 0.55f) { finish() }
                        ActionText(
                            if (step == SurveyLogic.TOTAL_STEPS) stringResource(R.string.survey_submit) else stringResource(R.string.ob_next),
                            enabled = canAdvance, weight = FontWeight.SemiBold, alpha = if (canAdvance) 1f else 0.3f,
                        ) { advance() }
                    }
                }
            }
        }
    }
}

@Composable
private fun QuestionGroup(
    title: String?, notes: List<String>, questions: List<SurveyQuestion>, answers: Map<String, String>,
    onSelect: (SurveyQuestion, SurveyChoice) -> Unit,
) {
    val ink = Ink
    Column(verticalArrangement = Arrangement.spacedBy(22.dp)) {
        if (title != null) Text(title, style = Fonts.almanac(19), color = ink.text)
        if (notes.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                for (note in notes) Text(note, style = Fonts.system(13), color = ink.text.copy(alpha = 0.55f))
            }
        }
        for (question in questions) {
            val picked = SelfReportSurvey.values(answers[question.id])
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(question.text, style = Fonts.almanacBody(16, bold = true), color = ink.text, modifier = Modifier.padding(bottom = 4.dp))
                for (choice in question.choices) {
                    ChoiceRow(choice, selected = choice.value in picked, multiple = question.allowsMultiple) { onSelect(question, choice) }
                }
            }
        }
    }
}

// 문항 = 세리프 표제 + 라디오·괘선 리스트(책력 개방 조판). 측정 로직·저장 키는 무변경.
@Composable
private fun ChoiceRow(choice: SurveyChoice, selected: Boolean, multiple: Boolean, onClick: () -> Unit) {
    val ink = Ink
    Row(
        Modifier
            .fillMaxWidth()
            .semantics { this.selected = selected }
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onClick)
            .drawBehind { drawRect(ink.text.copy(alpha = 0.12f), topLeft = Offset(0f, size.height - 1f), size = Size(size.width, 1f)) }
            .padding(vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        // 복수 문항은 라디오가 아니라 체크 — 하나만 고르는 줄로 읽히면 여러 개를 고를 생각을 못 한다
        if (multiple) CheckSquare(selected) else Radio(selected)
        Text(choice.label, style = Fonts.system(15, if (selected) FontWeight.SemiBold else FontWeight.Normal), color = ink.text.copy(alpha = if (selected) 1f else 0.75f))
    }
}

/** SF circle / circle.inset.filled 대용 */
@Composable
private fun Radio(selected: Boolean) {
    val ink = Ink
    val color = if (selected) ink.text else ink.text.copy(alpha = 0.3f)
    Box(
        Modifier.size(16.dp).drawBehind {
            drawCircle(color, style = androidx.compose.ui.graphics.drawscope.Stroke(width = 1.5.dp.toPx()), radius = size.minDimension / 2 - 1f)
            if (selected) drawCircle(color, radius = size.minDimension * 0.28f)
        },
    )
}

/** SF square / checkmark.square.fill 대용 */
@Composable
private fun CheckSquare(selected: Boolean) {
    val ink = Ink
    val color = if (selected) ink.text else ink.text.copy(alpha = 0.3f)
    val paper = ink.paper
    Box(
        Modifier.size(16.dp).drawBehind {
            val inset = 1.5.dp.toPx()
            val corner = androidx.compose.ui.geometry.CornerRadius(3.dp.toPx())
            if (selected) {
                drawRoundRect(color, topLeft = Offset(inset / 2, inset / 2), size = Size(size.width - inset, size.height - inset), cornerRadius = corner)
                val check = androidx.compose.ui.graphics.Path().apply {
                    moveTo(size.width * 0.27f, size.height * 0.52f)
                    lineTo(size.width * 0.44f, size.height * 0.69f)
                    lineTo(size.width * 0.74f, size.height * 0.35f)
                }
                drawPath(check, paper, style = androidx.compose.ui.graphics.drawscope.Stroke(width = 1.8.dp.toPx(), cap = androidx.compose.ui.graphics.StrokeCap.Round, join = androidx.compose.ui.graphics.StrokeJoin.Round))
            } else {
                drawRoundRect(color, topLeft = Offset(inset, inset), size = Size(size.width - inset * 2, size.height - inset * 2), cornerRadius = corner, style = androidx.compose.ui.graphics.drawscope.Stroke(width = inset))
            }
        },
    )
}

@Composable
private fun ActionText(title: String, enabled: Boolean, weight: FontWeight, alpha: Float, onClick: () -> Unit) {
    val ink = Ink
    Text(
        title, style = Fonts.system(17, weight), color = ink.text.copy(alpha = alpha),
        modifier = Modifier.clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, enabled = enabled, onClick = onClick).padding(4.dp),
    )
}

// 진행도 명시(2026-08-08 베타 피드백 "진행도도 표시해줘")
@Composable
private fun ProgressHeader(step: Int) {
    val ink = Ink
    val total = SurveyLogic.TOTAL_STEPS
    val label = stringResource(R.string.survey_progress_a11y, step, total)
    Row(Modifier.fillMaxWidth().semantics { contentDescription = label }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(
            Modifier.weight(1f).height(4.dp).background(ink.text.copy(alpha = 0.12f), CircleShape).drawBehind {
                val w = maxOf(if (step > 0) 6.dp.toPx() else 0f, size.width * step / total)
                drawRoundRect(ink.text.copy(alpha = 0.65f), size = Size(w, size.height), cornerRadius = androidx.compose.ui.geometry.CornerRadius(size.height / 2))
            },
        )
        if (step > 0) Text(stringResource(R.string.survey_progress, step, total), style = Fonts.system(12).copy(fontFeatureSettings = "tnum"), color = ink.text.copy(alpha = 0.55f))
    }
}

@Composable
private fun Intro(prefilled: Boolean) {
    val ink = Ink
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.survey_intro_title), style = Fonts.almanac(26), color = ink.text)
        Text(stringResource(R.string.survey_intro_body), style = Fonts.almanacBody(17), color = ink.text.copy(alpha = 0.75f))
        Text(stringResource(R.string.survey_intro_local), style = Fonts.system(13), color = ink.text.copy(alpha = 0.5f))
        if (prefilled) Text(stringResource(R.string.survey_intro_prefilled), style = Fonts.system(13), color = ink.text.copy(alpha = 0.5f))
    }
}

/** 증상 문항의 시간 앵커 — TempoCore `symptomAnchorLine`은 라벨을 문장에 합성하므로 번역 키가 아니다. 합성만 앱으로 가져온다. */
@Composable
private fun symptomAnchorTitle(p2: String?): String {
    // 복수 응답(2026-09-09)이면 고른 것을 전부 나열한다 — tempocore symptomAnchorLine과 같은 규칙.
    val labels = SelfReportSurvey.values(p2)
        .filter { it !in SelfReportSurvey.exclusivePhaseValues }
        .mapNotNull { value -> SelfReportSurvey.phaseChoices.firstOrNull { it.value == value }?.label }
    if (labels.isEmpty()) return stringResource(R.string.survey_anchor_fallback)
    return stringResource(R.string.survey_anchor_format, labels.joinToString(" · "))
}
