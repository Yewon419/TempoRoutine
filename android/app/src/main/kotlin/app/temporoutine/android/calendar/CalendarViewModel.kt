// 템포루틴 Android — 캘린더 상태. 앵커 달 ±1의 MonthRender를 데이터 변경마다 파생(iOS warmMonthCache의 구조적 해소).

package app.temporoutine.android.calendar

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.temporoutine.android.TempoApp
import app.temporoutine.android.cycle.CycleSnapshot
import app.temporoutine.android.cycle.seasonCopy
import app.temporoutine.android.data.DailyCheckInEntity
import app.temporoutine.android.data.PeriodDayEntity
import app.temporoutine.android.data.SettingsSnapshot
import app.temporoutine.android.today.TodayViewModel
import app.temporoutine.core.CyclePhase
import app.temporoutine.core.CyclePredictor
import app.temporoutine.core.TrackedSignals
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.time.temporal.WeekFields
import java.util.Locale

/** 계절 라인(S0/S1/S2/S4) — 문자열 조립은 화면이, 분기는 여기. */
sealed class SeasonLine {
    data object Cold : SeasonLine()
    data class Overdue(val daysPast: Int) : SeasonLine()
    data class Season(val phase: CyclePhase, val dayInPhase: Int, val projected: Boolean) : SeasonLine()
}

data class CalendarUiState(
    val loaded: Boolean = false,
    val today: LocalDate = LocalDate.now(),
    val anchor: LocalDate = LocalDate.now().withDayOfMonth(1),
    val snapshot: CycleSnapshot = CycleSnapshot(emptyList()),
    val todayPhase: CyclePhase? = null,
    val seasonLine: SeasonLine = SeasonLine.Cold,
    /** 앵커 달 −1·0·+1 (키 = 1일) */
    val renders: Map<LocalDate, MonthRender> = emptyMap(),
    val firstDayOfWeek: DayOfWeek = DayOfWeek.SUNDAY,
    val periodDays: List<PeriodDayEntity> = emptyList(),
    val checkIns: List<DailyCheckInEntity> = emptyList(),
    val trackedSignals: TrackedSignals = SettingsSnapshot.defaultSignals,
)

class CalendarViewModel(internal val app: TempoApp) : ViewModel() {

    private val db = app.db
    private val anchor = MutableStateFlow(LocalDate.now().withDayOfMonth(1))
    private val zone: ZoneId = ZoneId.systemDefault()
    private val firstDayOfWeek: DayOfWeek = WeekFields.of(Locale.getDefault()).firstDayOfWeek
    /** iOS `usesBuiltInKoreanHolidays` = 지역 KR */
    private val holidaysEnabled: Boolean = Locale.getDefault().country == "KR"

    private data class Data(
        val periodDays: List<PeriodDayEntity>, val checkIns: List<DailyCheckInEntity>, val settings: SettingsSnapshot,
        val schedules: List<app.temporoutine.android.data.ScheduleItemEntity>,
        val planner: Triple<List<app.temporoutine.android.data.InputItemEntity>, List<app.temporoutine.android.data.OutputItemEntity>, List<app.temporoutine.android.data.OutputSubtaskEntity>>,
    )

    private val data = combine(
        db.periodDays().observeAll(), db.checkIns().observeAll(), app.settings.snapshot, db.schedules().observeAll(),
        combine(db.inputs().observeAll(), db.outputs().observeAll(), db.outputs().observeSubtasks()) { i, o, s -> Triple(i, o, s) },
    ) { p, c, s, sch, planner -> Data(p, c, s, sch, planner) }

    val state: StateFlow<CalendarUiState> = combine(data, anchor) { d, anchor -> build(d, anchor) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), CalendarUiState())

    private fun build(d: Data, anchor: LocalDate): CalendarUiState {
        val today = LocalDate.now()
        val snapshot = CycleSnapshot(d.periodDays.map { it.day }, d.settings.cycleLengthPrior, d.settings.periodLengthPrior)
        val recorded = d.periodDays.map { it.day }.toSet()
        val renders = (-1..1).associate { off ->
            val start = anchor.plusMonths(off.toLong())
            start to MonthRenderer.compute(
                MonthLayout(start, firstDayOfWeek), snapshot, recorded, today,
                d.schedules, d.planner.first, d.planner.second, d.planner.third, holidaysEnabled, zone,
            )
        }
        return CalendarUiState(
            loaded = true,
            today = today,
            anchor = anchor,
            snapshot = snapshot,
            todayPhase = snapshot.phase(today),
            seasonLine = seasonLine(snapshot, today),
            renders = renders,
            firstDayOfWeek = firstDayOfWeek,
            periodDays = d.periodDays,
            checkIns = d.checkIns,
            trackedSignals = d.settings.trackedSignals,
        )
    }

    private fun seasonLine(snapshot: CycleSnapshot, today: LocalDate): SeasonLine {
        val last = snapshot.starts.maxOrNull() ?: return SeasonLine.Cold
        val diff = ChronoUnit.DAYS.between(last, today).toInt()
        if (diff >= snapshot.averageLength + TodayViewModel.OVERDUE_GRACE_DAYS) return SeasonLine.Overdue(diff - snapshot.averageLength)
        val info = snapshot.phaseInfo(today) ?: return SeasonLine.Cold
        return SeasonLine.Season(info.phase, info.dayInPhase, info.projected)
    }

    fun shiftMonth(delta: Int) {
        anchor.value = anchor.value.plusMonths(delta.toLong())
    }

    companion object {
        fun seasonName(phase: CyclePhase): String = seasonCopy(phase).name
        @Suppress("unused") private val keep = CyclePredictor
    }
}
