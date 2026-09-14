// 템포루틴 Android — 온보딩 상태 (iOS OnboardingFlow의 @Query·AppSettings 쓰기·PeriodStore 경유를 한 곳에)
// 분기의 유일한 기준 = 에피소드 수(§5.7). 캘린더 쓰기는 전부 PeriodStore(중앙 쓰기 경로) 경유.
// 2026-09-14 iOS 84차 이식: 예시 칩(하루의 구성)·추적 항목·설문 장이 빠져 그 쓰기 경로도 걷었다 — 추적 항목은 기본값, 설문은 설정 진입.

package app.temporoutine.android.onboarding

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.temporoutine.android.TempoApp
import app.temporoutine.android.cycle.CycleSnapshot
import app.temporoutine.android.cycle.PhaseInfo
import app.temporoutine.android.data.PeriodDayEntity
import app.temporoutine.core.PeriodMath
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.LocalDate

data class BaselineState(
    val periodDays: List<PeriodDayEntity> = emptyList(),
) {
    val markedDays: Set<LocalDate> get() = periodDays.map { it.day }.toSet()
    val episodeCount: Int get() = PeriodMath.episodeStarts(periodDays.map { it.day }).size
}

class OnboardingViewModel(private val app: TempoApp) : ViewModel() {

    val baseline: StateFlow<BaselineState> = app.db.periodDays().observeAll()
        .map { BaselineState(it) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), BaselineState())

    /** 캘린더 탭 직렬화 — iOS `busy` 플래그 대응. 잠금 안에서 DB를 다시 읽어 연타 중복 삽입을 막는다. */
    private val calendarLock = Mutex()

    fun savePeriodLengthPrior(days: Int) {
        viewModelScope.launch { app.settings.setPeriodLengthPrior(days) }
    }

    fun saveCycleLengthPrior(days: Int?) {
        viewModelScope.launch { app.settings.setCycleLengthPrior(days) }
    }

    /** 미기록 날 탭 = 시작일로 보고 지속일만큼 채움(오늘 이후 캡) / 기록 날 탭 = 그 하루만 해제 */
    fun tapCalendarDay(day: LocalDate, fillLength: Int, today: LocalDate = LocalDate.now()) {
        viewModelScope.launch {
            calendarLock.withLock {
                val existing = app.db.periodDays().all()
                val hits = existing.filter { it.day == day }
                if (hits.isNotEmpty()) app.periodStore.remove(hits)
                else app.periodStore.add(BaselineLogic.fillDays(day, fillLength, today), existing, today)
            }
        }
    }

    /** 마지막 「오늘」 전환의 부제 재료 — iOS enterSubtitle(계절 · N일차). 계절 기록 전이면 null. */
    suspend fun todayPhase(today: LocalDate): PhaseInfo? {
        val s = app.settings.current()
        return CycleSnapshot(app.db.periodDays().all().map { it.day }, s.cycleLengthPrior, s.periodLengthPrior).phaseInfo(today)
    }

    /** 온보딩 종료 한 창구 — 재진입 표식도 여기서 내린다(다음 첫 실행과 혼동 방지). */
    fun finish() {
        viewModelScope.launch { app.settings.finishOnboarding() }
    }
}

/** 순수 규칙 — 단위 테스트 대상. */
object BaselineLogic {
    /** 시작일부터 fillLength일, 오늘 이후는 잘라낸다. */
    fun fillDays(start: LocalDate, fillLength: Int, today: LocalDate): List<LocalDate> =
        (0 until fillLength).map { start.plusDays(it.toLong()) }.filter { it <= today }

    /** 캘린더 다음 → 에피소드 정확히 1개면 주기 질문, 2개 이상은 실측 gap이 있어 안 묻는다. */
    fun asksCycleLength(episodeCount: Int): Boolean = episodeCount == 1

    /** 다음 달 1일이 오늘 이후면 앞으로 못 간다. */
    fun canGoForward(monthStart: LocalDate, today: LocalDate): Boolean = monthStart.plusMonths(1) <= today

    /** 자(ruler) 드래그 위치 → 값. edge = 좌단 여백(엄지 반지름 22), usable = 트랙 폭 − 2·edge. 단위는 호출자가 맞춘다(px). */
    fun rulerValue(x: Float, edge: Float, usable: Float, range: IntRange): Int {
        val count = range.last - range.first
        val raw = (x - edge) / usable.coerceAtLeast(1f) * count
        return (range.first + Math.round(raw)).coerceIn(range)
    }
}
