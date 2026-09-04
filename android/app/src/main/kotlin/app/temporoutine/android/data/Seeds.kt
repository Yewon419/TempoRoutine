// 템포루틴 Android — 씨앗 재화 판정 (iOS Seeds.swift 이식 — 순수 규칙만. 원장 저장은 Settings)
// 획득 원장(earnedDays)에도 적는다 — 체크인 행이 지워져도 획득이 남는다(도장 불변 원칙).

package app.temporoutine.android.data

import app.temporoutine.core.ExportCodec
import app.temporoutine.core.SeedLedgerDTO
import app.temporoutine.core.TrackedSignals
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

object Seeds {

    /** 완성 판정 — 켜 둔 옵션 신호까지 채워야 한다. 노트는 제외, pain·irritability는 안 본다. */
    fun isComplete(energy: Int, mood: Int, sleep: Int?, appetite: Int?, signals: TrackedSignals): Boolean =
        energy > 0 && mood > 0 &&
            !(signals.sleep && (sleep ?: 0) == 0) &&
            !(signals.appetite && (appetite ?: 0) == 0)

    /** 지급 판정 — 그날 또는 다음 날 안에 완성했을 때만(completedAt < day + 2일). */
    fun isAwarded(day: LocalDate, completedAt: Instant?, zone: ZoneId = ZoneId.systemDefault()): Boolean {
        completedAt ?: return false
        val deadline = day.plusDays(2).atStartOfDay(zone).toInstant()
        return completedAt < deadline
    }

    fun isAwarded(record: DailyCheckInEntity, zone: ZoneId = ZoneId.systemDefault()): Boolean =
        isAwarded(record.day, record.completedAt, zone)

    /** 도장 — 미완성이거나 이미 찍혀 있으면 null. 반환 = 도장 찍힌 레코드와 지급 여부. */
    fun stamp(record: DailyCheckInEntity, signals: TrackedSignals, now: Instant = Instant.now(),
              zone: ZoneId = ZoneId.systemDefault()): Pair<DailyCheckInEntity, Boolean>? {
        if (record.completedAt != null) return null
        if (!isComplete(record.energy, record.mood, record.sleep, record.appetite, signals)) return null
        val stamped = record.copy(completedAt = now)
        return stamped to isAwarded(stamped, zone)
    }

    private fun earnedDayKeys(checkIns: List<DailyCheckInEntity>, ledger: SeedLedgerDTO, zone: ZoneId): Set<String> =
        checkIns.filter { isAwarded(it, zone) }.map { ExportCodec.dayString(it.day) }.toSet() + ledger.earnedDays.orEmpty()

    /** 잔액 = 획득 일수 + 보너스 − 소비. Phase 1(상점 없음)엔 획득 일수 그대로. */
    fun available(checkIns: List<DailyCheckInEntity>, ledger: SeedLedgerDTO, zone: ZoneId = ZoneId.systemDefault()): Int =
        maxOf(0, earnedDayKeys(checkIns, ledger, zone).size + ledger.bonus - ledger.spent)

    /** 원장에 획득일 추가(멱등). */
    fun recordEarned(ledger: SeedLedgerDTO, day: LocalDate): SeedLedgerDTO {
        val days = (ledger.earnedDays.orEmpty().toSet() + ExportCodec.dayString(day)).sorted()
        return ledger.copy(earnedDays = days)
    }
}
