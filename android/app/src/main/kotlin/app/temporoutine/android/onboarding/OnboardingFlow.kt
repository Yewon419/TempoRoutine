// 템포루틴 Android — 온보딩 (iOS OnboardingFlow.swift 이식, P0 축소: 언어·테마·건강 연동·튜토리얼 단계 없음)
// ① 인트로 탭 진행 3장면 → ② 기준일 순차(지속일 → 캘린더 → 에피소드 1개면 주기) → ③ 세 가지 카드(탭 진행 3장 + 예시 칩)
// → ④ 추적 항목 → ⑤ 저장 위치 → ⑥ 리듬 설문(primary 「시작하기」 + 「지금은 넘어가기」).
// 진행 점은 인트로 숨김·2단계부터. 하단 액션 바는 전 스텝 공통 위치. 라이트 고정(LightAppearance).

package app.temporoutine.android.onboarding

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.lifecycle.viewmodel.compose.viewModel
import app.temporoutine.android.R
import app.temporoutine.android.TempoApp
import app.temporoutine.android.selfreport.SelfReportFlow
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.LightAppearance
import app.temporoutine.android.theme.MotifStyle
import app.temporoutine.android.theme.SeasonLight
import app.temporoutine.core.CyclePhase
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.rememberHazeState
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.LocalDate

enum class OnboardingStep { INTRO, BASELINE, CARDS, SIGNALS, STORAGE, SURVEY }

private enum class BaselinePage { DURATION, CALENDAR, CYCLE }

private const val COLUMN_MAX_DP = 560   // 태블릿 중앙 조판(iOS centeredColumn(560))

/** iOS accessibilityReduceMotion 대응 — 시스템 애니메이터 배율 0(개발자 옵션·접근성 「애니메이션 제거」). */
@Composable
fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember {
        android.provider.Settings.Global.getFloat(context.contentResolver, android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
}

@Composable
fun OnboardingFlow(app: TempoApp, isRevisit: Boolean = false) {
    LightAppearance { OnboardingBody(app, isRevisit) }
}

@Composable
private fun OnboardingBody(app: TempoApp, isRevisit: Boolean) {
    val ink = Ink
    val vm: OnboardingViewModel = viewModel { OnboardingViewModel(app) }
    val baseline by vm.baseline.collectAsState()
    val addedExamples by vm.addedExamples.collectAsState()
    val hasReport by vm.hasSelfReport.collectAsState()
    val scope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current
    val reduceMotion = rememberReduceMotion()
    val hazeState = rememberHazeState()
    val today = remember { LocalDate.now() }

    var step by rememberSaveable { mutableStateOf(OnboardingStep.INTRO) }
    var introScene by rememberSaveable { mutableIntStateOf(0) }
    var introEntered by remember { mutableStateOf(false) }
    var showSplash by remember { mutableStateOf(!SplashGate.shownThisLaunch) }
    var baselinePage by rememberSaveable { mutableStateOf(BaselinePage.DURATION) }
    val baselineStack = remember { mutableStateListOf<BaselinePage>() }
    var periodLength by rememberSaveable { mutableIntStateOf(5) }
    var cycleLengthAnswer by rememberSaveable { mutableIntStateOf(28) }
    var cardPage by rememberSaveable { mutableIntStateOf(0) }
    var toggles by remember { mutableStateOf(SignalToggles()) }
    var showSurvey by remember { mutableStateOf(false) }
    val exMeditation = stringResource(R.string.ob_ex_meditation)
    val exTea = stringResource(R.string.ob_ex_tea)
    val exStudy = stringResource(R.string.ob_ex_study_item)
    val exListening = stringResource(R.string.ob_ex_listening_item)
    val chapterFormat = stringResource(R.string.ob_ex_chapter)

    fun tick() = haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
    fun finish() = vm.finish()
    // 재진입(설정 「온보딩 다시 보기」)은 좌상단 X로 즉시 나갈 수 있다 — 첫 실행엔 X가 없다(최초 설정은 건너뛸 수 없다)
    fun close() { tick(); finish() }
    fun leaveBaseline() { step = OnboardingStep.CARDS }
    fun pushBaseline(page: BaselinePage) { tick(); baselineStack.add(baselinePage); baselinePage = page }
    fun advanceIntro() { tick(); if (introScene < 2) introScene += 1 else step = OnboardingStep.BASELINE }
    /** ③ 장 안에서 진행, 마지막 장이면 ④로(인트로와 같은 탭 진행 문법) */
    fun advanceCardPage() { tick(); if (cardPage < 2) cardPage += 1 else step = OnboardingStep.SIGNALS }
    fun toggleExample(chip: ExampleChip) {
        tick()
        val title = when (chip) {
            ExampleChip.INPUT_MEDITATION -> exMeditation
            ExampleChip.INPUT_TEA -> exTea
            ExampleChip.OUTPUT_STUDY -> exStudy
            ExampleChip.OUTPUT_LISTENING -> exListening
        }
        vm.toggleExample(chip, title) { n -> chapterFormat.format(n) }
    }
    // ④ 진입 시 현재 추적 항목을 토글 초기값으로(iOS onAppear)
    LaunchedEffect(step) {
        if (step != OnboardingStep.SIGNALS) return@LaunchedEffect
        val cur = vm.currentSignals()
        toggles = SignalToggles(sleep = cur.sleep, appetite = cur.appetite, note = cur.note)
    }

    // "시작/다음" 버튼 1000ms 지연 노출 — 인트로 (재)진입마다 리셋. 스플래시가 걷힌 뒤에야 시작.
    LaunchedEffect(step, showSplash) {
        if (step != OnboardingStep.INTRO || showSplash) return@LaunchedEffect
        introEntered = false
        if (reduceMotion) { introEntered = true; return@LaunchedEffect }
        delay(30)
        introEntered = true
    }

    val primaryEnabled = !(step == OnboardingStep.BASELINE && baselinePage == BaselinePage.CALENDAR) || baseline.episodeCount >= 1
    val primaryLabel = when {
        step == OnboardingStep.INTRO && introScene == 0 -> stringResource(R.string.ob_start)
        // ⑥ 설문 미답 = 설문 시작이 primary. 답이 있으면 마무리만 남는다.
        step == OnboardingStep.SURVEY -> if (hasReport) stringResource(R.string.ob_to_today) else stringResource(R.string.ob_survey_start)
        else -> stringResource(R.string.ob_next)
    }
    fun primaryAction() {
        when (step) {
            OnboardingStep.INTRO -> advanceIntro()
            OnboardingStep.BASELINE -> when (baselinePage) {
                BaselinePage.DURATION -> { vm.savePeriodLengthPrior(periodLength); pushBaseline(BaselinePage.CALENDAR) }   // §5.3 층 2 M 초기값
                BaselinePage.CALENDAR -> if (BaselineLogic.asksCycleLength(baseline.episodeCount)) pushBaseline(BaselinePage.CYCLE) else leaveBaseline()
                BaselinePage.CYCLE -> { vm.saveCycleLengthPrior(cycleLengthAnswer); leaveBaseline() }
            }
            OnboardingStep.CARDS -> advanceCardPage()
            OnboardingStep.SIGNALS -> { vm.saveTrackedSignals(toggles.sleep, toggles.appetite, toggles.note); step = OnboardingStep.STORAGE }
            OnboardingStep.STORAGE -> step = OnboardingStep.SURVEY
            OnboardingStep.SURVEY -> if (hasReport) finish() else showSurvey = true
        }
    }
    val showBack = step != OnboardingStep.INTRO || introScene > 0
    fun back() {
        tick()
        when {
            step == OnboardingStep.INTRO -> introScene -= 1
            step == OnboardingStep.BASELINE && baselineStack.isNotEmpty() -> baselinePage = baselineStack.removeAt(baselineStack.lastIndex)
            step == OnboardingStep.CARDS && cardPage > 0 -> cardPage -= 1
            else -> {
                step = OnboardingStep.entries[step.ordinal - 1]
                if (step == OnboardingStep.INTRO) introScene = 2
                if (step == OnboardingStep.CARDS) cardPage = 2   // ④에서 돌아오면 마지막 장부터(인트로와 동형)
            }
        }
    }

    Box(Modifier.fillMaxSize().background(ink.paper)) {
        SeasonLight(phase = CyclePhase.MENSTRUAL, modifier = Modifier.fillMaxSize().hazeSource(hazeState), motif = MotifStyle.ONBOARDING)   // 온보딩 = 겨울 배경 고정
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars)) {
            Column(
                Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .widthIn(max = COLUMN_MAX_DP.dp)
                    .align(Alignment.CenterHorizontally)
                    .padding(start = 24.dp, end = 24.dp, top = 8.dp, bottom = 24.dp),
            ) {
                TopBar(showBack, onBack = ::back, onClose = if (isRevisit) ::close else null)
                Column(Modifier.weight(1f).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    when (step) {
                        OnboardingStep.INTRO -> IntroStep(introScene, active = !showSplash, reduceMotion = reduceMotion, onTap = ::advanceIntro)
                        OnboardingStep.BASELINE -> Crossfade(baselinePage, animationSpec = tween(if (reduceMotion) 0 else 250), label = "baselinePage") { page ->
                            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                                when (page) {
                                    BaselinePage.DURATION -> DurationPage(periodLength) { tick(); periodLength = it }
                                    BaselinePage.CALENDAR -> CalendarPage(baseline.markedDays, today, hazeState) { day -> tick(); vm.tapCalendarDay(day, periodLength, today) }
                                    BaselinePage.CYCLE -> CyclePage(cycleLengthAnswer) { tick(); cycleLengthAnswer = it }
                                }
                            }
                        }
                        OnboardingStep.CARDS -> Crossfade(cardPage, animationSpec = tween(if (reduceMotion) 0 else 400), label = "cardPage") { page ->
                            Column(
                                Modifier
                                    .fillMaxSize()
                                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = ::advanceCardPage),
                                verticalArrangement = Arrangement.spacedBy(14.dp),
                            ) {
                                CardsStep(page, addedExamples, reduceMotion, onToggle = ::toggleExample)
                            }
                        }
                        OnboardingStep.SIGNALS -> SignalsStep(toggles, hazeState) { tick(); toggles = it }
                        OnboardingStep.STORAGE -> StorageStep(hazeState)
                        OnboardingStep.SURVEY -> SurveyStep(hasReport)
                    }
                }
            }
            // 하단 액션 바 — 전 스텝 공통 위치
            Column(
                Modifier
                    .fillMaxWidth()
                    .widthIn(max = COLUMN_MAX_DP.dp)
                    .align(Alignment.CenterHorizontally)
                    .padding(start = 24.dp, end = 24.dp, top = 14.dp, bottom = 10.dp)
                    .windowInsetsPadding(WindowInsets.navigationBars),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                val introGate = step != OnboardingStep.INTRO || introEntered || reduceMotion
                PrimaryButton(
                    primaryLabel, enabled = introGate && primaryEnabled,
                    modifier = Modifier
                        .staggerIn(if (step == OnboardingStep.INTRO) introEntered else true, if (step == OnboardingStep.INTRO) 1000 else 0, 420, reduceMotion)
                        .alpha(if (primaryEnabled) 1f else 0.35f),
                ) { tick(); primaryAction() }
                if (step == OnboardingStep.BASELINE && baselinePage == BaselinePage.CALENDAR) {
                    GhostButton(stringResource(R.string.ob_calendar_later)) { tick(); leaveBaseline() }   // 구 "기억 안 나요" 승계 — S0 처리
                }
                if (step == OnboardingStep.BASELINE && baselinePage == BaselinePage.CYCLE) {
                    GhostButton(stringResource(R.string.ob_cycle_unknown)) { tick(); vm.saveCycleLengthPrior(null); leaveBaseline() }
                }
                // ⑥ 설문 건너뛰기 — 설문은 primary로 승격하되 강요는 안 한다
                if (step == OnboardingStep.SURVEY && !hasReport) {
                    GhostButton(stringResource(R.string.ob_survey_skip)) { tick(); finish() }
                    Text(stringResource(R.string.ob_survey_skip_hint), style = Fonts.system(12), color = ink.text.copy(alpha = 0.45f), modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
                }
                if (step >= OnboardingStep.BASELINE) Dots(step)
            }
        }
        if (showSplash) {
            Box(Modifier.fillMaxSize().zIndex(1f)) { OnboardingSplash(reduceMotion) { showSplash = false } }
        }
    }
    // 설문을 제출하고 닫혔으면 온보딩도 끝낸다 — "오늘 화면으로"를 한 번 더 누르게 하지 않는다.
    if (showSurvey) {
        var submitted by remember { mutableStateOf(false) }
        SelfReportFlow(
            onSubmit = { submitted = true; vm.submitSelfReport(it) },
            onDismiss = { showSurvey = false; if (submitted) scope.launch { finish() } },
        )
    }
}

@Composable
private fun TopBar(showBack: Boolean, onBack: () -> Unit, onClose: (() -> Unit)? = null) {
    val ink = Ink
    val label = stringResource(R.string.ob_back)
    val closeLabel = stringResource(R.string.ob_close)
    Row(Modifier.fillMaxWidth().height(44.dp), verticalAlignment = Alignment.CenterVertically) {
        if (onClose != null) {
            Box(Modifier.size(44.dp).semantics { contentDescription = closeLabel }.clickable(onClick = onClose), contentAlignment = Alignment.Center) {
                Canvas(Modifier.size(15.dp)) {
                    val s = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round)
                    drawLine(ink.text.copy(alpha = 0.6f), androidx.compose.ui.geometry.Offset(0f, 0f), androidx.compose.ui.geometry.Offset(size.width, size.height), s.width, StrokeCap.Round)
                    drawLine(ink.text.copy(alpha = 0.6f), androidx.compose.ui.geometry.Offset(size.width, 0f), androidx.compose.ui.geometry.Offset(0f, size.height), s.width, StrokeCap.Round)
                }
            }
        }
        if (showBack) {
            Box(Modifier.size(44.dp).semantics { contentDescription = label }.clickable(onClick = onBack), contentAlignment = Alignment.Center) {
                Canvas(Modifier.size(10.dp, 17.dp)) {
                    val p = Path().apply { moveTo(size.width, 0f); lineTo(0f, size.height / 2); lineTo(size.width, size.height) }
                    drawPath(p, ink.text.copy(alpha = 0.6f), style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round))
                }
            }
        }
    }
}

/** 진행 점 — 지난·현재 스텝 채움 + 현재 스텝만 알약형(시안 .ob-dot). */
@Composable
private fun Dots(step: OnboardingStep) {
    val ink = Ink
    Row(Modifier.fillMaxWidth().padding(bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally)) {
        for (s in OnboardingStep.entries) {
            Box(
                Modifier
                    .size(width = if (s == step) 16.dp else 6.dp, height = 6.dp)
                    .background(if (s <= step) ink.text else ink.text.copy(alpha = 0.22f), CircleShape),
            )
        }
    }
}

@Composable
fun PrimaryButton(title: String, enabled: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val ink = Ink
    Box(
        modifier
            .fillMaxWidth()
            .background(ink.text, CircleShape)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(vertical = 15.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = Fonts.system(17, FontWeight.SemiBold), color = ink.paper, textAlign = TextAlign.Center)
    }
}

@Composable
fun GhostButton(title: String, onClick: () -> Unit) {
    val ink = Ink
    Box(
        Modifier
            .fillMaxWidth()
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onClick)
            .padding(vertical = 13.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = Fonts.system(15), color = ink.text.copy(alpha = 0.55f), textAlign = TextAlign.Center)
    }
}
