// 템포루틴 Android — 생리 기록 쓰기 단일 창구 (iOS PeriodStore.swift 이식, HealthKit 미러는 P1)
// dedup(day)·start-of-day·미래 금지가 여기 묶여 있다. UI에도 같은 가드가 있지만 일부러 중복.

package app.temporoutine.android.data

import java.time.LocalDate

class PeriodStore(private val dao: PeriodDayDao) {

    /** 기존 집합에 없는 오늘 이하 날짜만 삽입. */
    suspend fun add(days: Collection<LocalDate>, existing: List<PeriodDayEntity>, today: LocalDate = LocalDate.now()) {
        val existingDays = existing.map { it.day }.toSet()
        val newDays = days.filter { it <= today && it !in existingDays }.toSet().sorted()
        if (newDays.isEmpty()) return
        dao.insert(newDays.map { PeriodDayEntity(day = it) })
    }

    suspend fun remove(records: List<PeriodDayEntity>) {
        if (records.isEmpty()) return
        dao.delete(records)
    }

    /** 오늘 토글(오늘 화면 스위치) — 하루 단위 add/remove. */
    suspend fun toggle(day: LocalDate, existing: List<PeriodDayEntity>, today: LocalDate = LocalDate.now()) {
        val hits = existing.filter { it.day == day }
        if (hits.isNotEmpty()) remove(hits) else add(listOf(day), existing, today)
    }
}
