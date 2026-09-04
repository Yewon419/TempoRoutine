// 템포루틴 Android — 체크인 upsert (iOS CheckInEditor.persist / CheckInCard 저장 규칙 이식)
// day 기준 하루 1개. 전부 비면 삭제(기록 철회). 도장(completedAt)은 Seeds가 한 번만 찍고 원장에 적는다.

package app.temporoutine.android.data

import java.time.Instant
import java.time.LocalDate

/** 편집기 드래프트 — 0 = 미기록. 증상은 카드 편집기만 만진다(시트 편집기는 기존 값 보존). */
data class CheckInDraft(
    val energy: Int = 0,
    val mood: Int = 0,
    val sleep: Int = 0,
    val appetite: Int = 0,
    val note: String = "",
    /** null = 건드리지 않음(시트 편집기) / 값 = 그대로 저장(카드) */
    val symptoms: Set<CheckInSymptom>? = null,
) {
    val hasSignals: Boolean get() = energy > 0 && mood > 0
    val hasNote: Boolean get() = note.trim().isNotEmpty()
    val hasSymptoms: Boolean get() = !symptoms.isNullOrEmpty()
}

class CheckInStore(private val dao: DailyCheckInDao, private val settings: Settings) {

    /** 저장 결과 — awarded = 씨앗 연출 트리거. */
    data class Result(val record: DailyCheckInEntity?, val awarded: Boolean)

    /** iOS persist(): 값이 있으면 upsert, 전부 비면 삭제. 미래 날짜는 무시. */
    suspend fun persist(day: LocalDate, draft: CheckInDraft, today: LocalDate = LocalDate.now(),
                        now: Instant = Instant.now()): Result {
        if (day > today) return Result(null, false)
        val existing = dao.forDay(day)
        val keep = draft.hasSignals || draft.hasNote || draft.hasSymptoms
        if (!keep) {
            if (existing != null) dao.delete(existing)
            return Result(null, false)
        }
        val base = existing ?: DailyCheckInEntity(day = day, createdAt = now, isBackfilled = day != today)
        var next = base.copy(
            energy = draft.energy,
            mood = draft.mood,
            sleep = draft.sleep.takeIf { it > 0 },
            appetite = draft.appetite.takeIf { it > 0 },
            note = draft.note.takeIf { draft.hasNote },
            symptoms = draft.symptoms?.let { DailyCheckInEntity.joinSymptoms(it) } ?: base.symptoms,
        )
        var awarded = false
        val signals = settings.current().trackedSignals
        Seeds.stamp(next, signals, now)?.let { (stamped, isAwarded) ->
            next = stamped
            awarded = isAwarded
            if (isAwarded) settings.setSeedLedger(Seeds.recordEarned(settings.current().seedLedger, day))
        }
        if (existing == null) dao.insert(next) else dao.update(next)
        return Result(next, awarded)
    }

    fun draftOf(record: DailyCheckInEntity?): CheckInDraft =
        if (record == null) CheckInDraft()
        else CheckInDraft(record.energy, record.mood, record.sleep ?: 0, record.appetite ?: 0, record.note ?: "", record.symptomSet)
}
