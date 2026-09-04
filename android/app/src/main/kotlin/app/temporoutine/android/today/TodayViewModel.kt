// 템포루틴 Android — 오늘 화면 상태 (iOS TodayView의 @Query·파생값을 한 곳에 모은다)
// 파생 계산(스냅샷·프로파일·무드라인)은 DB 변경마다 한 번. 렌더 경로에서 재계산하지 않는다(CLAUDE.md 프레임 규칙).

package app.temporoutine.android.today

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.temporoutine.android.TempoApp
import app.temporoutine.android.cycle.CycleSnapshot
import app.temporoutine.android.cycle.EnergyProfile
import app.temporoutine.android.cycle.EnergySample
import app.temporoutine.android.cycle.MoodlinePool
import app.temporoutine.android.cycle.PhaseInfo
import app.temporoutine.android.cycle.SeasonCopy
import app.temporoutine.android.cycle.seasonCopy
import app.temporoutine.android.data.DailyCheckInEntity
import app.temporoutine.android.data.InputItemEntity
import app.temporoutine.android.data.InputProgressEntity
import app.temporoutine.android.data.InputSubtaskEntity
import app.temporoutine.android.data.ItemCompletionEntity
import app.temporoutine.android.data.OutputItemEntity
import app.temporoutine.android.data.OutputSubtaskEntity
import app.temporoutine.android.data.PeriodDayEntity
import app.temporoutine.android.data.ScheduleItemEntity
import app.temporoutine.android.data.Seeds
import app.temporoutine.android.data.SettingsSnapshot
import app.temporoutine.core.TrackedSignals
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.temporal.ChronoUnit

data class TodayUiState(
    val loaded: Boolean = false,
    val today: LocalDate = LocalDate.now(),
    val snapshot: CycleSnapshot = CycleSnapshot(emptyList()),
    val info: PhaseInfo? = null,
    val copy: SeasonCopy? = null,
    val moodline: String? = null,
    val seeds: Int = 0,
    val isPeriodToday: Boolean = false,
    /** null = 배너 없음. 값 = 예정일에서 지난 일수(S4). */
    val overdueDays: Int? = null,
    val periodDays: List<PeriodDayEntity> = emptyList(),
    val checkIns: List<DailyCheckInEntity> = emptyList(),
    val trackedSignals: TrackedSignals = SettingsSnapshot.defaultSignals,
    val cycleLengthPrior: Int? = null,
    val periodLengthPrior: Int? = null,
    val schedules: List<ScheduleItemEntity> = emptyList(),
    val inputs: List<InputItemEntity> = emptyList(),
    val inputSubtasks: List<InputSubtaskEntity> = emptyList(),
    val inputProgress: List<InputProgressEntity> = emptyList(),
    val completions: List<ItemCompletionEntity> = emptyList(),
    val outputs: List<OutputItemEntity> = emptyList(),
    val outputSubtasks: List<OutputSubtaskEntity> = emptyList(),
) {
    val isColdStart: Boolean get() = snapshot.isColdStart
}

class TodayViewModel(internal val app: TempoApp) : ViewModel() {

    private val db = app.db

    /** 씨앗 지급 연출 트리거(증가 카운터) — 체크인 카드가 관찰. */
    val seedBurst = kotlinx.coroutines.flow.MutableStateFlow(0)

    private data class Planner(
        val schedules: List<ScheduleItemEntity>,
        val inputs: List<InputItemEntity>,
        val inputSubtasks: List<InputSubtaskEntity>,
        val inputProgress: List<InputProgressEntity>,
        val completions: List<ItemCompletionEntity>,
    )

    private val planner = combine(
        db.schedules().observeAll(), db.inputs().observeAll(), db.inputs().observeSubtasks(),
        db.inputs().observeProgress(), db.inputs().observeCompletions(),
    ) { s, i, st, p, c -> Planner(s, i, st, p, c) }

    private val outputs = combine(db.outputs().observeAll(), db.outputs().observeSubtasks()) { o, s -> o to s }

    val state: StateFlow<TodayUiState> = combine(
        db.periodDays().observeAll(), db.checkIns().observeAll(), app.settings.snapshot, planner, outputs,
    ) { periodDays, checkIns, settings, planner, outputs ->
        build(periodDays, checkIns, settings, planner, outputs)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), TodayUiState())

    private fun build(
        periodDays: List<PeriodDayEntity>, checkIns: List<DailyCheckInEntity>, settings: SettingsSnapshot,
        planner: Planner, outputs: Pair<List<OutputItemEntity>, List<OutputSubtaskEntity>>,
    ): TodayUiState {
        val today = LocalDate.now()
        val snapshot = CycleSnapshot(periodDays.map { it.day }, settings.cycleLengthPrior, settings.periodLengthPrior)
        val info = snapshot.phaseInfo(today)
        val copy = info?.let { seasonCopy(it.phase) }
        val moodline = info?.let {
            val profile = EnergyProfile(checkIns.map { c -> EnergySample(c.day, c.energy, c.aggregationWeight) }, snapshot)
            val level = profile.level(it.phase)
            if (level != null) MoodlinePool.personalized(it.phase, level, today) else MoodlinePool.base(it.phase, today)
        }
        val overdue = if (snapshot.isColdStart) null else {
            val last = snapshot.starts.max()
            val diff = ChronoUnit.DAYS.between(last, today).toInt()
            val avg = snapshot.averageLength
            if (diff >= avg + OVERDUE_GRACE_DAYS) diff - avg else null
        }
        return TodayUiState(
            loaded = true,
            today = today,
            snapshot = snapshot,
            info = info,
            copy = copy,
            moodline = moodline,
            seeds = Seeds.available(checkIns, settings.seedLedger),
            isPeriodToday = periodDays.any { it.day == today },
            overdueDays = overdue,
            periodDays = periodDays,
            checkIns = checkIns,
            trackedSignals = settings.trackedSignals,
            cycleLengthPrior = settings.cycleLengthPrior,
            periodLengthPrior = settings.periodLengthPrior,
            schedules = planner.schedules,
            inputs = planner.inputs,
            inputSubtasks = planner.inputSubtasks,
            inputProgress = planner.inputProgress,
            completions = planner.completions,
            outputs = outputs.first,
            outputSubtasks = outputs.second,
        )
    }

    fun togglePeriodToday() {
        val s = state.value
        viewModelScope.launch { app.periodStore.toggle(s.today, s.periodDays, s.today) }
    }

    companion object {
        /** S4 유예 — 예정일 + 2일까지는 배너를 띄우지 않는다(iOS overdueGraceDays). */
        const val OVERDUE_GRACE_DAYS = 2
    }
}
