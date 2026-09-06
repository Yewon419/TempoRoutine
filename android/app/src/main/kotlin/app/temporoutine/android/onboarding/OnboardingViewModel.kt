// 템포루틴 Android — 온보딩 상태 (iOS OnboardingFlow의 @Query·AppSettings 쓰기·PeriodStore 경유를 한 곳에)
// 분기의 유일한 기준 = 에피소드 수(§5.7). 캘린더 쓰기는 전부 PeriodStore(중앙 쓰기 경로) 경유.
// ③ 예시 칩은 실제 아이템을 담고, 재탭 = 빠짐 — 지우려면 참조가 필요해 담은 id를 VM이 들고 있는다(회전 생존).

package app.temporoutine.android.onboarding

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.temporoutine.android.TempoApp
import app.temporoutine.android.data.InputItemEntity
import app.temporoutine.android.data.OutputItemEntity
import app.temporoutine.android.data.OutputSubtaskEntity
import app.temporoutine.android.data.PeriodDayEntity
import app.temporoutine.android.data.SelfReportEntity
import app.temporoutine.core.ExportCodec
import app.temporoutine.core.InputSchedule
import app.temporoutine.core.OutputProgressKind
import app.temporoutine.core.OutputSchedule
import app.temporoutine.core.PeriodMath
import app.temporoutine.core.SelfReportSurvey
import app.temporoutine.core.TrackedSignals
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import java.time.LocalDate

data class BaselineState(
    val periodDays: List<PeriodDayEntity> = emptyList(),
) {
    val markedDays: Set<LocalDate> get() = periodDays.map { it.day }.toSet()
    val episodeCount: Int get() = PeriodMath.episodeStarts(periodDays.map { it.day }).size
}

/** ③ 예시 칩 키 — iOS와 동일 문자열. */
enum class ExampleChip(val key: String) {
    INPUT_MEDITATION("input-meditation"), INPUT_TEA("input-tea"), OUTPUT_STUDY("output-study"), OUTPUT_LISTENING("output-listening"),
}

class OnboardingViewModel(private val app: TempoApp) : ViewModel() {

    val baseline: StateFlow<BaselineState> = app.db.periodDays().observeAll()
        .map { BaselineState(it) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), BaselineState())

    /** ⑥ 설문 응답 존재 — 있으면 primary가 「오늘 화면으로」로 바뀐다. */
    val hasSelfReport: StateFlow<Boolean> = app.db.selfReports().observeAll()
        .map { it.isNotEmpty() }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)

    /** 담긴 예시 칩 → 실제 아이템 id */
    private val exampleIds = MutableStateFlow<Map<ExampleChip, String>>(emptyMap())
    val addedExamples: StateFlow<Set<ExampleChip>> = exampleIds.map { it.keys }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptySet())

    /** 캘린더 탭 직렬화 — iOS `busy` 플래그 대응. 잠금 안에서 DB를 다시 읽어 연타 중복 삽입을 막는다. */
    private val calendarLock = Mutex()
    private val exampleLock = Mutex()

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

    /** ③ 예시 칩 탭 = 실제 아이템 추가, 다시 탭 = 빠짐. 문안·카테고리·스케줄은 iOS toggleExample 그대로. */
    fun toggleExample(chip: ExampleChip, title: String, subtaskTitle: (Int) -> String) {
        viewModelScope.launch {
            exampleLock.withLock {
                val current = exampleIds.value
                val existingId = current[chip]
                if (existingId != null) {
                    removeExample(chip, existingId)
                    exampleIds.value = current - chip
                    return@withLock
                }
                val id = when (chip) {
                    ExampleChip.INPUT_MEDITATION -> insertInput(title, category = "other")
                    ExampleChip.INPUT_TEA -> insertInput(title, category = "food")
                    ExampleChip.OUTPUT_STUDY -> {
                        val item = OutputItemEntity(title = title, scheduleJson = OutputItemEntity.encodeSchedule(OutputSchedule.Once),
                            progressKind = OutputProgressKind.SUBTASKS.rawValue)
                        app.db.outputs().insert(item)
                        app.db.outputs().insertSubtasks((1..6).map { OutputSubtaskEntity(ownerId = item.id, title = subtaskTitle(it), order = it - 1) })
                        item.id
                    }
                    ExampleChip.OUTPUT_LISTENING -> {
                        val item = OutputItemEntity(title = title, scheduleJson = OutputItemEntity.encodeSchedule(OutputSchedule.Once),
                            progressKind = OutputProgressKind.TIMER.rawValue, targetSeconds = 30 * 60)
                        app.db.outputs().insert(item)
                        item.id
                    }
                }
                exampleIds.value = current + (chip to id)
            }
        }
    }

    private suspend fun insertInput(title: String, category: String): String {
        val item = InputItemEntity(title = title, category = category, scheduleJson = InputItemEntity.encodeSchedule(InputSchedule.Daily))
        app.db.inputs().insert(item)
        return item.id
    }

    private suspend fun removeExample(chip: ExampleChip, id: String) {
        when (chip) {
            ExampleChip.INPUT_MEDITATION, ExampleChip.INPUT_TEA -> {
                val dao = app.db.inputs()
                val item = dao.all().firstOrNull { it.id == id } ?: return
                dao.deleteSubtasks(id); dao.deleteCompletions(id); dao.deleteProgress(id); dao.delete(item)
            }
            ExampleChip.OUTPUT_STUDY, ExampleChip.OUTPUT_LISTENING -> {
                val dao = app.db.outputs()
                val item = dao.all().firstOrNull { it.id == id } ?: return
                dao.deleteSubtasks(id); dao.delete(item)
            }
        }
    }

    /** ④ 현재 추적 항목(재진입·회전 시 토글 초기값) */
    suspend fun currentSignals(): TrackedSignals = app.settings.current().trackedSignals

    /** ④ pain·irritability = false 고정(2026-08-05 병합) — 입력 행이 없는데 켜두면 백업 복원 경로에서 유령 행이 부활한다. */
    fun saveTrackedSignals(sleep: Boolean, appetite: Boolean, note: Boolean) {
        viewModelScope.launch {
            app.settings.setTrackedSignals(TrackedSignals(sleep = sleep, pain = false, appetite = appetite, note = note, irritability = false))
        }
    }

    /** ⑥ 설문 제출 — 화이트리스트 밖 키가 섞이지 않게 한 번 거른다(웹 서버와 같은 규칙). */
    fun submitSelfReport(answers: Map<String, String>) {
        viewModelScope.launch {
            val cleaned = SurveyLogic.whitelist(answers)
            val json = ExportCodec.json.encodeToString(MapSerializer(String.serializer(), String.serializer()), cleaned)
            app.db.selfReports().insert(SelfReportEntity(answersJson = json))
        }
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
}

/** 설문 순수 규칙(iOS SelfReportFlow.canAdvance·finish 필터) — 단위 테스트 대상. */
object SurveyLogic {
    const val TOTAL_STEPS = 5

    /** 선택 문항 단계 말고는 그 화면의 문항이 전부 채워져야 넘어간다. */
    fun canAdvance(step: Int, answers: Map<String, String>): Boolean = when (step) {
        0 -> true
        1 -> answers[SelfReportSurvey.calibration.id] != null
        2 -> SelfReportSurvey.phaseQuestions.all { answers[it.id] != null }
        3 -> SelfReportSurvey.symptomQuestions.all { answers[it.id] != null }
        4 -> SelfReportSurvey.amplitudeQuestions.all { answers[it.id] != null }
        else -> true
    }

    /** 문항이 하나뿐인 장 — 선택이 곧 그 장의 답. 1장 = 캘리브레이션 단문항. */
    fun isSingleQuestionStep(step: Int): Boolean = step == 1

    fun whitelist(answers: Map<String, String>): Map<String, String> {
        val allowed = SelfReportSurvey.allQuestionIDs
        return answers.filterKeys { it in allowed }
    }
}
