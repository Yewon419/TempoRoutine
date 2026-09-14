// 템포루틴 Android — 온보딩 「템포 렌즈」 (iOS OnboardingFlow.swift 이식, 84~94차 구조)
// 흐름: 스플래시 → 브랜드(슬라이드 3) → 사계절 4장 → 내 주기(지속일 → 캘린더 → 에피소드 1개면 주기) → 저장 위치 → 「오늘」.
// iOS 대비 P0 축소(MASTER §5.13): 언어 장(ko만 출시)·테마 장(은필 1종)·건강 앱 연동 장(Health Connect P1) 없음.
// 진행 다이얼은 테마 장이 빠져 2칸(내 주기 1/2 · 저장 2/2). 입력은 하단 유리 시트, CTA 위치는 전 장 공통.
// 2026-09-09 다이어트에서 걷어낸 것 = 사이클 싱킹 강의·하루의 구성·기록할 것·리듬 설문 — 개념은 화면의 빈 상태·ⓘ가 말한다.

package app.temporoutine.android.onboarding

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import androidx.lifecycle.viewmodel.compose.viewModel
import app.temporoutine.android.R
import app.temporoutine.android.TempoApp
import app.temporoutine.android.cycle.seasonCopy
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.theme.LightAppearance
import app.temporoutine.android.theme.rememberReduceMotion
import app.temporoutine.android.theme.springStiffness
import app.temporoutine.core.CyclePhase
import kotlinx.coroutines.delay
import java.time.LocalDate
import kotlin.math.max
import kotlin.math.min

enum class OnboardingStep { BRAND, SEASONS, BASELINE, STORAGE }

enum class BaselinePage { DURATION, CALENDAR, CYCLE }

private const val COLUMN_MAX_DP = 560f   // 태블릿 중앙 조판(iOS centeredColumn(560))
private const val DIAL_TOTAL = 2

/** 사계절 장 순서 = 앱 순서(겨울·봄·여름·가을) */
val seasonOrder = listOf(CyclePhase.MENSTRUAL, CyclePhase.FOLLICULAR, CyclePhase.OVULATION, CyclePhase.LUTEAL)

@Composable
fun OnboardingFlow(app: TempoApp, isRevisit: Boolean = false) {
    LightAppearance { OnboardingBody(app, isRevisit) }
}

@Composable
private fun OnboardingBody(app: TempoApp, isRevisit: Boolean) {
    val ink = Ink
    val vm: OnboardingViewModel = viewModel { OnboardingViewModel(app) }
    val baseline by vm.baseline.collectAsState()
    val haptic = LocalHapticFeedback.current
    val reduceMotion = rememberReduceMotion()
    val today = remember { LocalDate.now() }

    var step by rememberSaveable { mutableStateOf(OnboardingStep.BRAND) }
    var seasonPage by rememberSaveable { mutableIntStateOf(0) }
    var baselinePage by rememberSaveable { mutableStateOf(BaselinePage.DURATION) }
    val baselineStack = remember { mutableStateListOf<BaselinePage>() }
    var periodLength by rememberSaveable { mutableIntStateOf(5) }
    var cycleLengthAnswer by rememberSaveable { mutableIntStateOf(28) }
    var showSplash by remember { mutableStateOf(!SplashGate.shownThisLaunch) }
    var entering by remember { mutableStateOf(false) }
    var enterSubtitle by remember { mutableStateOf("") }
    var brandSlide by remember { mutableIntStateOf(0) }
    var seasonRevealed by remember { mutableStateOf(false) }
    // 은필 열림 — iOS는 언어 → 브랜드 순간 렌즈 중심에서 지면이 원형으로 열린다. Android는 언어 장이 없어 스플래시가 걷히는 순간.
    val reveal = remember { Animatable(if (showSplash) 0f else 1f) }

    fun tick() = haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
    val stageKey = StageKey(step, seasonPage, baselinePage)

    fun commitFinish() = vm.finish()
    /** 온보딩 종료 한 창구 — 마지막 연출(렌즈가 창이 된다) 뒤 커밋. 재진입·모션 축소는 즉시. */
    fun finishOnboarding() {
        if (entering) return
        if (reduceMotion || isRevisit) { commitFinish(); return }
        entering = true
    }
    fun pushBaseline(page: BaselinePage) { baselineStack.add(baselinePage); baselinePage = page }
    fun primaryAction() {
        tick()
        when (step) {
            OnboardingStep.BRAND -> { step = OnboardingStep.SEASONS; seasonPage = 0 }   // 사계절은 재진입에도 보여준다(설명 장)
            OnboardingStep.SEASONS -> if (seasonPage < 3) seasonPage += 1 else step = OnboardingStep.BASELINE
            OnboardingStep.BASELINE -> when (baselinePage) {
                BaselinePage.DURATION -> { vm.savePeriodLengthPrior(periodLength); pushBaseline(BaselinePage.CALENDAR) }   // §5.3 층 2 M 초기값
                BaselinePage.CALENDAR -> if (BaselineLogic.asksCycleLength(baseline.episodeCount)) pushBaseline(BaselinePage.CYCLE) else step = OnboardingStep.STORAGE
                BaselinePage.CYCLE -> { vm.saveCycleLengthPrior(cycleLengthAnswer); step = OnboardingStep.STORAGE }
            }
            OnboardingStep.STORAGE -> finishOnboarding()   // 저장 위치 = 마지막 장
        }
    }
    val showBack = step != OnboardingStep.BRAND
    fun back() {
        tick()
        when {
            step == OnboardingStep.SEASONS && seasonPage > 0 -> seasonPage -= 1   // 사계절 안에서는 장 단위로
            step == OnboardingStep.BASELINE && baselineStack.isNotEmpty() -> baselinePage = baselineStack.removeAt(baselineStack.lastIndex)
            else -> {
                step = OnboardingStep.entries[step.ordinal - 1]
                if (step == OnboardingStep.SEASONS) seasonPage = 3   // 사계절로 되돌아오면 마지막 장(가을)부터
            }
        }
    }
    val primaryEnabled = !(step == OnboardingStep.BASELINE && baselinePage == BaselinePage.CALENDAR) || baseline.episodeCount >= 1

    // 장마다 등장 연출을 처음부터: 사계절 = revealed 튕김, 브랜드 = 슬라이드 0부터 2.2초 간격.
    // 스플래시가 덮고 있는 동안은 소모하지 않는다(iOS는 언어 장이 앞에 있어 브랜드가 스플래시 밑에서 시작할 일이 없다).
    LaunchedEffect(stageKey, showSplash) {
        seasonRevealed = false
        brandSlide = 0
        if (showSplash) return@LaunchedEffect
        delay(60)
        seasonRevealed = true
        if (step != OnboardingStep.BRAND) return@LaunchedEffect
        for (i in 1..2) { delay(2_200); brandSlide = i }
    }
    LaunchedEffect(showSplash) {
        if (showSplash || reveal.value >= 1f) return@LaunchedEffect
        if (reduceMotion) reveal.snapTo(1f) else reveal.animateTo(1f, tween(1_250, easing = EaseOut))
    }
    LaunchedEffect(entering) {
        if (!entering) return@LaunchedEffect
        enterSubtitle = vm.todayPhase(today)?.let { seasonCopy(it.phase).name + " · " + app.getString(R.string.today_day_in_phase, it.dayInPhase) } ?: ""
        delay(1_500)
        commitFinish()
    }

    val contentAlpha by animateFloatAsState(if (entering) 0f else 1f, if (reduceMotion) snap() else tween(280, easing = EaseOut), label = "obContent")

    BoxWithConstraints(Modifier.fillMaxSize().background(OnboardingFlatColor)) {
        val density = LocalDensity.current
        val safeTop = with(density) { WindowInsets.statusBars.getTop(this).toDp().value }
        val safeBottom = with(density) { WindowInsets.navigationBars.getBottom(this).toDp().value }
        val fullW = maxWidth.value
        val fullH = maxHeight.value
        val safeH = fullH - safeTop - safeBottom
        val column = min(fullW, COLUMN_MAX_DP)
        val (heroCenter, heroDiameter) = LensSpot.hero.resolve(fullW, safeH, column)

        // ── 지면 — 평면 위에 은필(frost + 겨울 계절광 + 선화)이 렌즈 중심에서 원형으로 열린다 ──
        OnboardingGround(
            Modifier
                .fillMaxSize()
                .drawWithContent {
                    val radius = max(1f, reveal.value * max(size.width, size.height) * 2.6f) / 2f
                    val c = Offset(heroCenter.x.dp.toPx(), (heroCenter.y + safeTop).dp.toPx())
                    clipPath(Path().apply { addOval(Rect(c, radius)) }) { this@drawWithContent.drawContent() }
                },
        )

        // ── 사계절 창 — 브랜드 렌즈 자리에서 열려 화면을 덮는다. 사계절 장 밖에서는 덮인 채 사라지고, 브랜드로 돌아가면 오므라든다 ──
        val windowSpec = if (reduceMotion) snap() else spring<Float>(dampingRatio = 0.86f, stiffness = springStiffness(0.9f))
        val windowOpen = step == OnboardingStep.SEASONS && !entering
        val windowDiameter by animateFloatAsState(if (step != OnboardingStep.BRAND) max(fullW, safeH) * 2.2f else heroDiameter, windowSpec, label = "seasonWindowD")
        val windowAlpha by animateFloatAsState(if (windowOpen) 1f else 0f, windowSpec, label = "seasonWindowAlpha")
        val photos = rememberSeasonPhotos(
            wanted = when (step) {
                OnboardingStep.BRAND -> setOf(CyclePhase.MENSTRUAL)   // 창이 열릴 때 빈 원이 안 보이게 미리 굽는다
                OnboardingStep.SEASONS -> seasonNeighbors(seasonPage)
                else -> emptySet()
            },
            cellPx = rememberGrainCellPx(fullW, fullH),
        )
        if (windowOpen || windowAlpha > 0.001f) {
            SeasonWindow(
                phase = seasonOrder[seasonPage.coerceIn(0, 3)],
                center = Offset(heroCenter.x, heroCenter.y + safeTop),
                diameter = windowDiameter, photos = photos, reduceMotion = reduceMotion,
                modifier = Modifier.graphicsLayer { alpha = windowAlpha },
            )
        }

        // ── 템포 렌즈 — 단계가 자리·배율·속 그림을 고른다. 마지막엔 화면을 덮는 창이 된다 ──
        val lens = lensStage(stageKey, periodLength, cycleLengthAnswer)
        val (spotCenter, spotDiameter) = lens.spot.resolve(fullW, safeH, column)
        TempoLens(
            center = if (entering) Offset(fullW / 2, safeTop + safeH / 2) else Offset(spotCenter.x, spotCenter.y + safeTop),
            diameter = if (entering) max(fullW, safeH) * 2.2f else spotDiameter,
            magnify = if (entering) 1.02f else lens.spot.magnify,
            content = if (entering) LensContent() else lens.content,
            visible = entering || !lens.hidden,
            entering = entering,
            fullWidth = fullW, fullHeight = fullH, reduceMotion = reduceMotion,
        )

        Column(
            Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.statusBars)
                .windowInsetsPadding(WindowInsets.navigationBars)
                .graphicsLayer { alpha = contentAlpha },
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(Modifier.width(column.dp).weight(1f).padding(start = 24.dp, end = 24.dp, top = 8.dp)) {
                val photo = step == OnboardingStep.SEASONS
                OnboardingTopBar(
                    showBack = showBack, onBack = ::back,
                    onClose = if (isRevisit) ({ tick(); finishOnboarding() }) else null,
                    chrome = if (photo) ink.frost.copy(alpha = 0.85f) else ink.text.copy(alpha = 0.6f),
                    dialStep = dialStep(step),
                )
                AnimatedContent(
                    targetState = stageKey,
                    modifier = Modifier.weight(1f).fillMaxWidth(),
                    contentAlignment = Alignment.TopStart,
                    transitionSpec = {
                        when {
                            reduceMotion -> fadeIn(snap()) togetherWith fadeOut(snap())
                            // 사계절 장끼리 — 옛 장은 짧게 가라앉고(0.28) 새 장은 스태거가 등장을 맡는다
                            initialState.step == OnboardingStep.SEASONS && targetState.step == OnboardingStep.SEASONS ->
                                EnterTransition.None togetherWith (fadeOut(tween(280, easing = EaseOut)) + slideOutVertically(tween(280, easing = EaseOut)) { with(density) { 10.dp.roundToPx() } })
                            else -> (fadeIn(tween(420, easing = EaseOut)) + slideInVertically(tween(420, easing = EaseOut)) { with(density) { 12.dp.roundToPx() } }) togetherWith
                                (fadeOut(tween(420, easing = EaseOut)) + slideOutVertically(tween(420, easing = EaseOut)) { with(density) { -6.dp.roundToPx() } })
                        }
                    },
                    label = "obCopy",
                ) { key ->
                    if (key.step == OnboardingStep.SEASONS) {
                        // 사계절 장 = 편집 조판 J2 — 숫자·글리프·카피가 화면 전체를 쓴다. 하단 CTA 자리(52 + 여백)를 비운다
                        SeasonEditorial(seasonOrder[key.seasonPage.coerceIn(0, 3)], key.seasonPage, seasonRevealed, reduceMotion, Modifier.padding(bottom = 86.dp))
                    } else CopyBlock(
                        key = key, brandSlide = brandSlide, reduceMotion = reduceMotion,
                        modifier = Modifier.padding(top = 8.dp).then(
                            if (key.step == OnboardingStep.BRAND) Modifier.clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { primaryAction() }
                            else Modifier,
                        ),
                    )
                }
            }
        }

        // ── 하단 유리 시트 — 단계 콘텐츠 + 행동(전 장 공통 위치) ──
        val bare = step == OnboardingStep.BRAND || step == OnboardingStep.SEASONS
        Column(
            Modifier
                .align(Alignment.BottomCenter)
                .width(column.dp)
                .graphicsLayer { alpha = contentAlpha }
                .glassSheet(bare)
                .windowInsetsPadding(WindowInsets.navigationBars)
                .padding(start = 24.dp, end = 24.dp, top = if (bare) 0.dp else 22.dp, bottom = 10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            AnimatedContent(
                targetState = stageKey,
                transitionSpec = {
                    if (reduceMotion) fadeIn(snap()) togetherWith fadeOut(snap())
                    else (fadeIn(tween(420, easing = EaseOut)) + slideInVertically(tween(420, easing = EaseOut)) { with(density) { 12.dp.roundToPx() } }) togetherWith
                        (fadeOut(tween(420, easing = EaseOut)) + slideOutVertically(tween(420, easing = EaseOut)) { with(density) { 10.dp.roundToPx() } })
                },
                label = "obSheet",
            ) { key ->
                SheetBody(
                    key = key, periodLength = periodLength, cycleLength = cycleLengthAnswer, markedDays = baseline.markedDays, today = today,
                    onPeriodLength = { tick(); periodLength = it }, onCycleLength = { tick(); cycleLengthAnswer = it },
                    onTapDay = { day -> tick(); vm.tapCalendarDay(day, periodLength, today) },
                )
            }
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                InkCapsuleButton(
                    title = if (step == OnboardingStep.STORAGE) stringResource(R.string.ob_start) else stringResource(R.string.ob_next),   // 마지막 장 하나만 「시작하기」
                    inverted = step == OnboardingStep.SEASONS,   // 어두운 사진 위 = 지면색 알약(J2)
                    enabled = primaryEnabled,
                    onClick = ::primaryAction,
                )
                if (step == OnboardingStep.BASELINE && baselinePage == BaselinePage.CALENDAR) {
                    GhostUnderlineButton(stringResource(R.string.ob_calendar_later)) { tick(); step = OnboardingStep.STORAGE }   // 구 "기억 안 나요" 승계 — S0 처리
                }
                if (step == OnboardingStep.BASELINE && baselinePage == BaselinePage.CYCLE) {
                    GhostUnderlineButton(stringResource(R.string.ob_cycle_unknown)) { tick(); vm.saveCycleLengthPrior(null); step = OnboardingStep.STORAGE }
                }
                if (step == OnboardingStep.STORAGE) OnboardingCaption(stringResource(R.string.ob_storage_foot))
            }
        }

        if (entering) EnterTitle(enterSubtitle, reduceMotion)
        if (showSplash) {
            Box(Modifier.fillMaxSize().zIndex(1f)) { OnboardingSplash(reduceMotion) { showSplash = false } }
        }
    }
}

/** 단계 정체성 — 카피·시트 전환(크로스페이드)과 렌즈 이동의 트리거 */
data class StageKey(val step: OnboardingStep, val seasonPage: Int, val baselinePage: BaselinePage)

private data class LensStage(val spot: LensSpot, val content: LensContent, val hidden: Boolean = false)

/** 단계 → 렌즈 자리·속 그림(iOS Stage.spot/content). 사계절 장은 렌즈 대신 사진 창이 뜬다. */
private fun lensStage(key: StageKey, periodLength: Int, cycleLength: Int): LensStage = when (key.step) {
    OnboardingStep.BRAND -> LensStage(LensSpot.hero, LensContent(ring = true, drawsRing = true, nodes = true, orbit = true))
    OnboardingStep.SEASONS -> LensStage(LensSpot.hero, LensContent(), hidden = true)
    OnboardingStep.BASELINE -> when (key.baselinePage) {
        BaselinePage.DURATION -> LensStage(LensSpot.mid, LensContent(ring = true, number = periodLength, arcFraction = periodLength.toFloat() / cycleLength.coerceAtLeast(1), progress = 1f / DIAL_TOTAL))
        BaselinePage.CALENDAR -> LensStage(LensSpot.dial, LensContent(progress = 1f / DIAL_TOTAL))
        BaselinePage.CYCLE -> LensStage(LensSpot.mid, LensContent(ring = true, number = cycleLength, ticks = cycleLength, progress = 1f / DIAL_TOTAL))
    }
    OnboardingStep.STORAGE -> LensStage(LensSpot.dial, LensContent(progress = 2f / DIAL_TOTAL))
}

private fun dialStep(step: OnboardingStep): Int? = when (step) {
    OnboardingStep.BASELINE -> 1
    OnboardingStep.STORAGE -> 2
    else -> null
}

// ── 상단: X(재진입) · back · 진행 다이얼 VoiceOver 자리(다이얼 그림은 렌즈가 그린다) ──
@Composable
private fun OnboardingTopBar(showBack: Boolean, onBack: () -> Unit, onClose: (() -> Unit)?, chrome: Color, dialStep: Int?) {
    val backLabel = stringResource(R.string.ob_back)
    val closeLabel = stringResource(R.string.ob_close)
    Row(Modifier.fillMaxWidth().height(44.dp), verticalAlignment = Alignment.CenterVertically) {
        if (onClose != null) {
            Box(Modifier.size(44.dp).semantics { contentDescription = closeLabel }.clickable(onClick = onClose), contentAlignment = Alignment.Center) {
                Canvas(Modifier.size(14.dp)) {
                    val w = 1.8.dp.toPx()
                    drawLine(chrome, Offset(0f, 0f), Offset(size.width, size.height), w, StrokeCap.Round)
                    drawLine(chrome, Offset(size.width, 0f), Offset(0f, size.height), w, StrokeCap.Round)
                }
            }
        }
        if (showBack) {
            Box(Modifier.size(44.dp).semantics { contentDescription = backLabel }.clickable(onClick = onBack), contentAlignment = Alignment.Center) {
                Canvas(Modifier.size(10.dp, 17.dp)) {
                    val p = Path().apply { moveTo(size.width, 0f); lineTo(0f, size.height / 2); lineTo(size.width, size.height) }
                    drawPath(p, chrome, style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round))
                }
            }
        }
        Spacer(Modifier.weight(1f))
        if (dialStep != null) {
            val label = stringResource(R.string.ob_progress_a11y, dialStep, DIAL_TOTAL)
            Box(Modifier.size(44.dp).clearAndSetSemantics { contentDescription = label })
        }
    }
}

// ── 카피 블록 — 표제·본문은 Gowun Batang(프로토 활자) ──
@Composable
private fun CopyBlock(key: StageKey, brandSlide: Int, reduceMotion: Boolean, modifier: Modifier = Modifier) {
    val ink = Ink
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        when (key.step) {
            OnboardingStep.BRAND -> {
                Eyebrow(stringResource(R.string.ob_brand))
                Title(stringResource(R.string.ob_brand_title), hero = true)
                BrandSlides(brandSlide, reduceMotion)
            }
            OnboardingStep.SEASONS -> Unit   // SeasonEditorial이 그린다
            OnboardingStep.BASELINE -> {
                Eyebrow(stringResource(R.string.ob_baseline_eyebrow))
                when (key.baselinePage) {
                    BaselinePage.DURATION -> Title(stringResource(R.string.ob_duration_title))
                    BaselinePage.CALENDAR -> {
                        Title(stringResource(R.string.ob_calendar_title))
                        Body(listOf(stringResource(R.string.ob_calendar_line1), stringResource(R.string.ob_calendar_line2)))
                    }
                    BaselinePage.CYCLE -> {
                        Title(stringResource(R.string.ob_cycle_title))
                        Body(listOf(stringResource(R.string.ob_cycle_line)))
                    }
                }
            }
            OnboardingStep.STORAGE -> {
                Eyebrow(stringResource(R.string.ob_storage_eyebrow))
                Title(stringResource(R.string.ob_storage_title))
                Body(listOf(stringResource(R.string.ob_storage_line)))
            }
        }
    }
}

@Composable
fun seasonDeck(phase: CyclePhase): String = stringResource(
    when (phase) {
        CyclePhase.MENSTRUAL -> R.string.ob_season_deck_winter
        CyclePhase.FOLLICULAR -> R.string.ob_season_deck_spring
        CyclePhase.OVULATION -> R.string.ob_season_deck_summer
        CyclePhase.LUTEAL -> R.string.ob_season_deck_autumn
    },
)

@Composable
fun seasonTag(phase: CyclePhase): String = stringResource(
    when (phase) {
        CyclePhase.MENSTRUAL -> R.string.ob_season_tag_winter
        CyclePhase.FOLLICULAR -> R.string.ob_season_tag_spring
        CyclePhase.OVULATION -> R.string.ob_season_tag_summer
        CyclePhase.LUTEAL -> R.string.ob_season_tag_autumn
    },
)

@Composable
private fun Eyebrow(text: String) {
    Text(text, style = LensType.serif(12, bold = false).copy(letterSpacing = 2.sp), color = Ink.text.copy(alpha = 0.55f))
}

@Composable
private fun Title(text: String, hero: Boolean = false) {
    val size = if (hero) 36 else 30
    Text(text, style = LensType.serif(size).copy(lineHeight = (size * 1.2f + 5f).sp), color = Ink.text)
}

@Composable
private fun Body(lines: List<String>) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        for (line in lines) Text(line, style = Fonts.system(15).copy(lineHeight = (15 * 1.35f + 5f).sp), color = Ink.text.copy(alpha = 0.72f))
    }
}


/** 브랜드 장 슬라이드 — 무드(18 명조) → 본문(15) → 비의료 고지(10.5)가 한 자리에서 2.2초 간격으로 교체되고 고지에서 멈춘다.
 *  스크린리더는 타이머를 기다리지 않도록 세 블록을 한 라벨로 읽는다. */
@Composable
private fun BrandSlides(slide: Int, reduceMotion: Boolean) {
    val ink = Ink
    val mood = stringResource(R.string.ob_brand_mood)
    val body1 = stringResource(R.string.ob_brand_body1)
    val body2 = stringResource(R.string.ob_brand_body2)
    val fine = stringResource(R.string.ob_brand_fine)
    val all = listOf(mood, body1, body2, fine).joinToString(" ")
    Box(Modifier.fillMaxWidth().heightIn(min = 100.dp).clearAndSetSemantics { contentDescription = all }) {
        Slide(on = slide == 0, reduceMotion) { Text(mood, style = LensType.serif(18, bold = false), color = ink.text.copy(alpha = 0.92f)) }
        Slide(on = slide == 1, reduceMotion) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                val style = Fonts.system(15).copy(lineHeight = (15 * 1.35f + 5f).sp)
                Text(body1, style = style, color = ink.text.copy(alpha = 0.72f))
                Text(body2, style = style, color = ink.text.copy(alpha = 0.72f))
            }
        }
        Slide(on = slide == 2, reduceMotion) {
            Text(fine, style = Fonts.system(10).copy(fontSize = 10.5.sp, lineHeight = (10.5f * 1.35f + 3f).sp), color = ink.text.copy(alpha = 0.5f))
        }
    }
}

@Composable
private fun Slide(on: Boolean, reduceMotion: Boolean, content: @Composable () -> Unit) {
    val t by animateFloatAsState(if (on) 1f else 0f, tween(if (reduceMotion) 300 else 500, easing = EaseOut), label = "brandSlide")
    Box(Modifier.graphicsLayer { alpha = t; translationY = if (reduceMotion) 0f else (1f - t) * 8.dp.toPx() }) { content() }
}

// ══ 시트 콘텐츠 ══
@Composable
private fun SheetBody(
    key: StageKey, periodLength: Int, cycleLength: Int, markedDays: Set<LocalDate>, today: LocalDate,
    onPeriodLength: (Int) -> Unit, onCycleLength: (Int) -> Unit, onTapDay: (LocalDate) -> Unit,
) {
    val unit = stringResource(R.string.ob_unit_days)
    when (key.step) {
        OnboardingStep.BRAND, OnboardingStep.SEASONS -> Unit   // 시트 없음(bare)
        OnboardingStep.BASELINE -> when (key.baselinePage) {
            BaselinePage.DURATION -> RulerSlider(periodLength, 1..10, unit, onPeriodLength)
            BaselinePage.CALENDAR -> OnboardingCalendar(markedDays, today, onTapDay)
            BaselinePage.CYCLE -> RulerSlider(cycleLength, 21..35, unit, onCycleLength)
        }
        OnboardingStep.STORAGE -> StorageRows()
    }
}

/** ⑤ 저장 위치 — P0는 기기 저장뿐(§7 privacy-washing 금지: 실제 활성인 저장처만 적는다) */
@Composable
private fun StorageRows() {
    val ink = Ink
    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Canvas(Modifier.width(20.dp).height(18.dp)) {
            val w = 12.dp.toPx()
            val c = ink.text.copy(alpha = 0.6f)
            drawRoundRect(c, topLeft = Offset((size.width - w) / 2, 0f), size = androidx.compose.ui.geometry.Size(w, size.height),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(2.5.dp.toPx()), style = Stroke(width = 1.4.dp.toPx()))
            drawCircle(c, radius = 0.9.dp.toPx(), center = Offset(size.width / 2, size.height - 2.5.dp.toPx()))
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(R.string.ob_storage_device), style = Fonts.system(16), color = ink.text)
            Text(stringResource(R.string.ob_storage_device_sub), style = Fonts.system(13), color = ink.text.copy(alpha = 0.55f))
        }
        Canvas(Modifier.size(12.dp)) {
            val p = Path().apply { moveTo(size.width * 0.05f, size.height * 0.55f); lineTo(size.width * 0.4f, size.height * 0.9f); lineTo(size.width * 0.95f, size.height * 0.15f) }
            drawPath(p, ink.text.copy(alpha = 0.6f), style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round))
        }
    }
}

// ── 마지막: 렌즈가 창이 되고 「오늘」이 뜬다 ──
@Composable
private fun EnterTitle(subtitle: String, reduceMotion: Boolean) {
    val ink = Ink
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    val t by animateFloatAsState(if (shown) 1f else 0f, if (reduceMotion) snap() else tween(500, delayMillis = 350, easing = EaseOut), label = "enterTitle")
    Column(
        Modifier.fillMaxSize().graphicsLayer { alpha = t }.clearAndSetSemantics { },
        verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(stringResource(R.string.ob_enter_title), style = LensType.serif(44), color = ink.text)
        Text(subtitle, style = Fonts.system(14), color = ink.text.copy(alpha = 0.55f))
    }
}

/** 온보딩 활자 = 프로토 그대로 Gowun Batang(표제·무드·큰 숫자 Bold, eyebrow·라벨 Regular) — iOS LensSpec.serif */
object LensType {
    fun serif(size: Int, bold: Boolean = true) = serif(size.toFloat(), bold)
    fun serif(size: Float, bold: Boolean = true) = androidx.compose.ui.text.TextStyle(
        fontFamily = Fonts.gowunBatang,
        fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal,
        fontSize = size.sp,
        lineHeight = (size * 1.2f).sp,
    )
}
