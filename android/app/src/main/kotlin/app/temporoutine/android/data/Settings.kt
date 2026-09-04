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
    }

    val snapshot: Flow<SettingsSnapshot> = store.data.map { p ->
        SettingsSnapshot(
            trackedSignals = p[Keys.trackedSignals]?.let { decode(it, TrackedSignals.serializer()) } ?: SettingsSnapshot.defaultSignals,
            cycleLengthPrior = p[Keys.cycleLengthPrior]?.takeIf { it > 0 },
            periodLengthPrior = p[Keys.periodLengthPrior]?.takeIf { it > 0 },
            seedLedger = p[Keys.seedLedger]?.let { decode(it, SeedLedgerDTO.serializer()) } ?: SeedLedgerDTO(),
            onboardingDone = p[Keys.onboardingDone] ?: false,
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

    private fun <T> decode(json: String, serializer: kotlinx.serialization.KSerializer<T>): T? = try {
        ExportCodec.json.decodeFromString(serializer, json)
    } catch (e: SerializationException) {
        null
    } catch (e: IllegalArgumentException) {
        null
    }
}
