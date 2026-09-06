// 템포루틴 Android — 설정 저장(DataStore Preferences). iOS UserDefaults/AppSettings 대응.
// 키 규약 승계: prior는 0 = 없음. 씨앗 원장은 SeedLedgerDTO JSON 한 덩어리.

package app.temporoutine.android.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import app.temporoutine.core.ExportCodec
import app.temporoutine.core.SeedLedgerDTO
import app.temporoutine.core.TrackedSignals
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.SerializationException

private val Context.settingsStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

data class SettingsSnapshot(
    val trackedSignals: TrackedSignals,
    val cycleLengthPrior: Int?,
    val periodLengthPrior: Int?,
    val seedLedger: SeedLedgerDTO,
    val onboardingDone: Boolean,
    /** 캘린더 탭에서 「생리 기록」 진입을 숨긴다(iOS 2026-09-02 스위치). */
    val hideCalendarPeriodEntry: Boolean = false,
    /** 설정 「온보딩 다시 보기」로 들어왔는가 — 좌상단 X(즉시 나가기) 노출 조건. */
    val onboardingRevisit: Boolean = false,
) {
    companion object {
        /** iOS AppSettings.trackedSignals 기본값 */
        val defaultSignals = TrackedSignals(sleep = true, pain = false, appetite = true, note = true, irritability = false)
        val default = SettingsSnapshot(defaultSignals, null, null, SeedLedgerDTO(), false)
    }
}

class Settings(context: Context) {
    private val store = context.applicationContext.settingsStore

    private object Keys {
        val trackedSignals = stringPreferencesKey("trackedSignals")
        val cycleLengthPrior = intPreferencesKey("cycleLengthPrior")
        val periodLengthPrior = intPreferencesKey("periodLengthPrior")
        val seedLedger = stringPreferencesKey("seedLedger")
        val onboardingDone = booleanPreferencesKey("onboardingDone")
        val hideCalendarPeriodEntry = booleanPreferencesKey("hideCalendarPeriodEntry")
        val onboardingRevisit = booleanPreferencesKey("onboardingRevisit")
    }

    val snapshot: Flow<SettingsSnapshot> = store.data.map { p ->
        SettingsSnapshot(
            trackedSignals = p[Keys.trackedSignals]?.let { decode(it, TrackedSignals.serializer()) } ?: SettingsSnapshot.defaultSignals,
            cycleLengthPrior = p[Keys.cycleLengthPrior]?.takeIf { it > 0 },
            periodLengthPrior = p[Keys.periodLengthPrior]?.takeIf { it > 0 },
            seedLedger = p[Keys.seedLedger]?.let { decode(it, SeedLedgerDTO.serializer()) } ?: SeedLedgerDTO(),
            onboardingDone = p[Keys.onboardingDone] ?: false,
            hideCalendarPeriodEntry = p[Keys.hideCalendarPeriodEntry] ?: false,
            onboardingRevisit = p[Keys.onboardingRevisit] ?: false,
        )
    }

    suspend fun current(): SettingsSnapshot = snapshot.first()

    suspend fun setTrackedSignals(value: TrackedSignals) {
        store.edit { it[Keys.trackedSignals] = ExportCodec.json.encodeToString(TrackedSignals.serializer(), value) }
    }

    suspend fun setCycleLengthPrior(value: Int?) {
        store.edit { it[Keys.cycleLengthPrior] = value ?: 0 }
    }

    suspend fun setPeriodLengthPrior(value: Int?) {
        store.edit { it[Keys.periodLengthPrior] = value ?: 0 }
    }

    suspend fun setSeedLedger(value: SeedLedgerDTO) {
        store.edit { it[Keys.seedLedger] = ExportCodec.json.encodeToString(SeedLedgerDTO.serializer(), value) }
    }

    suspend fun setOnboardingDone(value: Boolean) {
        store.edit { it[Keys.onboardingDone] = value }
    }

    suspend fun setHideCalendarPeriodEntry(value: Boolean) {
        store.edit { it[Keys.hideCalendarPeriodEntry] = value }
    }

    /** 온보딩 다시 보기 — 재진입 표식과 게이트를 한 번에 연다(따로 쓰면 그 사이 프레임이 첫 실행처럼 보인다). */
    suspend fun beginOnboardingRevisit() {
        store.edit { it[Keys.onboardingRevisit] = true; it[Keys.onboardingDone] = false }
    }

    /** 온보딩 종료 — 재진입 표식도 여기서 내린다(다음 첫 실행과 혼동 방지). */
    suspend fun finishOnboarding() {
        store.edit { it[Keys.onboardingDone] = true; it[Keys.onboardingRevisit] = false }
    }

    private fun <T> decode(json: String, serializer: kotlinx.serialization.KSerializer<T>): T? = try {
        ExportCodec.json.decodeFromString(serializer, json)
    } catch (e: SerializationException) {
        null
    } catch (e: IllegalArgumentException) {
        null
    }
}
