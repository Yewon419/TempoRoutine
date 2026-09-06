// 템포루틴 Android — 설정 상태 (iOS SettingsView의 @AppStorage·@Query·액션을 한 곳에)
// 파일 입출력 자체는 화면(SAF 런처)이 맡고, 여기선 문자열 ↔ DB만 오간다.

package app.temporoutine.android.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.temporoutine.android.TempoApp
import app.temporoutine.android.data.BackupStore
import app.temporoutine.android.data.SelfReportEntity
import app.temporoutine.android.data.SettingsSnapshot
import app.temporoutine.android.onboarding.SurveyLogic
import app.temporoutine.core.ExportCodec
import app.temporoutine.core.ExportEnvelopeV1
import app.temporoutine.core.TrackedSignals
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate

data class SettingsUiState(
    val loaded: Boolean = false,
    val signals: TrackedSignals = SettingsSnapshot.defaultSignals,
    val hidePeriodEntry: Boolean = false,
    val hasSelfReport: Boolean = false,
    val lastAnswers: Map<String, String> = emptyMap(),
    /** 저장 실측 — 「지금 저장된 기록」 문구에 쓰는 실제 개수. */
    val periodDayCount: Int = 0,
    val checkInCount: Int = 0,
)

/** 화면에 띄울 결과 — 문구는 화면이 고른다(여긴 문자열 리소스를 모른다). */
sealed interface SettingsEvent {
    data class Imported(val added: Int) : SettingsEvent
    data object ImportNewerVersion : SettingsEvent
    data object ImportCorrupt : SettingsEvent
    data object ExportFailed : SettingsEvent
    /** 되돌리기용 봉투를 든 채 8초간 토스트. */
    data class Wiped(val undo: ExportEnvelopeV1) : SettingsEvent
    data object UndoDone : SettingsEvent
}

class SettingsViewModel(private val app: TempoApp) : ViewModel() {

    private val backup = BackupStore(app.db, app.settings)

    val state: StateFlow<SettingsUiState> = combine(
        app.settings.snapshot, app.db.selfReports().observeAll(), app.db.periodDays().observeAll(), app.db.checkIns().observeAll(),
    ) { settings, reports, periodDays, checkIns ->
        SettingsUiState(
            loaded = true,
            signals = settings.trackedSignals,
            hidePeriodEntry = settings.hideCalendarPeriodEntry,
            hasSelfReport = reports.isNotEmpty(),
            lastAnswers = reports.maxByOrNull { it.completedAt }?.answers.orEmpty(),
            periodDayCount = periodDays.size,
            checkInCount = checkIns.size,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SettingsUiState())

    private val _events = MutableStateFlow<SettingsEvent?>(null)
    val events: StateFlow<SettingsEvent?> = _events
    fun consumeEvent() { _events.value = null }

    fun setSignals(value: TrackedSignals) {
        viewModelScope.launch { app.settings.setTrackedSignals(value) }
    }

    fun setHidePeriodEntry(value: Boolean) {
        viewModelScope.launch { app.settings.setHideCalendarPeriodEntry(value) }
    }

    fun beginOnboardingRevisit() {
        viewModelScope.launch { app.settings.beginOnboardingRevisit() }
    }

    fun submitSelfReport(answers: Map<String, String>) {
        viewModelScope.launch {
            val cleaned = SurveyLogic.whitelist(answers)
            app.db.selfReports().insert(SelfReportEntity(answersJson = SelfReportEntity.encodeAnswers(cleaned)))
        }
    }

    /** 내보내기 — 봉투 문자열을 콜백으로 넘긴다(파일 쓰기는 화면의 SAF 런처). */
    fun exportJson(onReady: (String) -> Unit) {
        viewModelScope.launch {
            val text = runCatching { backup.exportJson(Instant.now()) }.getOrNull()
            if (text == null) _events.value = SettingsEvent.ExportFailed else onReady(text)
        }
    }

    fun importJson(text: String) {
        viewModelScope.launch {
            val envelope = try {
                ExportCodec.decode(text)
            } catch (e: ExportCodec.CodecError.NewerVersion) {
                _events.value = SettingsEvent.ImportNewerVersion
                return@launch
            } catch (e: ExportCodec.CodecError) {
                _events.value = SettingsEvent.ImportCorrupt
                return@launch
            }
            _events.value = SettingsEvent.Imported(backup.importEnvelope(envelope))
        }
    }

    fun wipeAll() {
        viewModelScope.launch { _events.value = SettingsEvent.Wiped(backup.wipeAll()) }
    }

    fun undoWipe(envelope: ExportEnvelopeV1) {
        viewModelScope.launch {
            backup.importEnvelope(envelope)
            _events.value = SettingsEvent.UndoDone
        }
    }

    /** 내보내기 파일명 — iOS와 같은 모양. */
    fun exportFileName(today: LocalDate = LocalDate.now()): String = "TempoRoutine-백업-${ExportCodec.dayString(today)}.json"
}
