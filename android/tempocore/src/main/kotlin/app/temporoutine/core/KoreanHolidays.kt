// 템포루틴 — 한국 공휴일·기념일 (§8.2.3 캘린더 표기)
// iOS TempoCore/KoreanHolidays.swift 1:1 이식. 고정일 + 규칙 기반 대체공휴일(2023 개정) + 음력 실측 테이블(2024~2028).

package app.temporoutine.core

import java.time.DayOfWeek
import java.time.LocalDate

data class KoreanHoliday(
    val name: String,
    val isPublic: Boolean,   // true = 법정공휴일(빨간날), false = 기념일(표기만)
)

object KoreanHolidays {

    private data class Entry(val month: Int, val day: Int, val name: String)

    // ── 고정일 공휴일(매년 같은 양력 날짜) ──
    private val fixedPublic = listOf(
        Entry(1, 1, "신정"), Entry(3, 1, "삼일절"), Entry(5, 5, "어린이날"), Entry(6, 6, "현충일"),
        Entry(8, 15, "광복절"), Entry(10, 3, "개천절"), Entry(10, 9, "한글날"), Entry(12, 25, "성탄절"),
    )

    /** 대체공휴일 적용 대상(토·일 → 다음 평일). 신정·현충일 제외. */
    private val substituteEligible = setOf("삼일절", "어린이날", "광복절", "개천절", "한글날", "성탄절")

    // ── 기념일(공휴일 아님 — 달력 표기 관례) ──
    private val commemorations = listOf(
        Entry(5, 1, "근로자의 날"), Entry(5, 8, "어버이날"), Entry(5, 15, "스승의 날"),
        Entry(7, 17, "제헌절"), Entry(10, 1, "국군의 날"),
    )

    // ── 음력 명절(설·추석·석가탄신일) — 대체공휴일까지 실측 그대로 ──
    private val lunarTable: Map<Int, List<Entry>> = mapOf(
        2024 to listOf(
            Entry(2, 9, "설 연휴"), Entry(2, 10, "설날"), Entry(2, 11, "설 연휴"), Entry(2, 12, "대체공휴일"),
            Entry(5, 15, "석가탄신일"),
            Entry(9, 16, "추석 연휴"), Entry(9, 17, "추석"), Entry(9, 18, "추석 연휴"),
        ),
        2025 to listOf(
            Entry(1, 28, "설 연휴"), Entry(1, 29, "설날"), Entry(1, 30, "설 연휴"),
            Entry(5, 5, "석가탄신일"), Entry(5, 6, "대체공휴일"),
            Entry(10, 5, "추석 연휴"), Entry(10, 6, "추석"), Entry(10, 7, "추석 연휴"), Entry(10, 8, "대체공휴일"),
        ),
        2026 to listOf(
            Entry(2, 16, "설 연휴"), Entry(2, 17, "설날"), Entry(2, 18, "설 연휴"),
            Entry(5, 24, "석가탄신일"), Entry(5, 25, "대체공휴일"),
            Entry(9, 24, "추석 연휴"), Entry(9, 25, "추석"), Entry(9, 26, "추석 연휴"),
        ),
        2027 to listOf(
            Entry(2, 6, "설 연휴"), Entry(2, 7, "설날"), Entry(2, 8, "설 연휴"), Entry(2, 9, "대체공휴일"),
            Entry(5, 13, "석가탄신일"),
            Entry(9, 14, "추석 연휴"), Entry(9, 15, "추석"), Entry(9, 16, "추석 연휴"),
        ),
        2028 to listOf(
            Entry(1, 26, "설 연휴"), Entry(1, 27, "설날"), Entry(1, 28, "설 연휴"),
            Entry(5, 2, "석가탄신일"),
            Entry(10, 2, "추석 연휴"), Entry(10, 4, "추석 연휴"), Entry(10, 5, "대체공휴일"),
        ),
        // 2028 추석 당일(10/3)은 개천절과 겹침 — 고정일(개천절)이 우선 표기, 연휴·대체는 위에.
    )

    /** 외부 소스(기기 캘린더) 이름의 기념일 판별 — 빨간날/회색 표기 분기용 */
    fun isCommemorationName(name: String): Boolean =
        commemorations.any { name.contains(it.name.replace(" ", "")) || name.contains(it.name) }

    /** 그날의 공휴일·기념일 전부(없으면 빈 배열). 공휴일이 앞에 온다. */
    fun holidays(on: LocalDate): List<KoreanHoliday> {
        val year = on.year
        val month = on.monthValue
        val day = on.dayOfMonth

        val result = mutableListOf<KoreanHoliday>()
        for (entry in fixedPublic) if (entry.month == month && entry.day == day) result.add(KoreanHoliday(entry.name, true))
        for (entry in lunarTable[year].orEmpty()) if (entry.month == month && entry.day == day) result.add(KoreanHoliday(entry.name, true))
        substituteName(year, month, day)?.let { result.add(KoreanHoliday(it, true)) }
        for (entry in commemorations) if (entry.month == month && entry.day == day) result.add(KoreanHoliday(entry.name, false))
        return result
    }

    /** 고정일 공휴일의 규칙 기반 대체공휴일 — 이 날짜가 어느 공휴일의 대체일이면 그 이름을 돌려준다. */
    private fun substituteName(year: Int, month: Int, day: Int): String? {
        for (entry in fixedPublic) {
            if (entry.name !in substituteEligible) continue
            val holiday = LocalDate.of(year, entry.month, entry.day)
            val weekday = holiday.dayOfWeek
            if (weekday != DayOfWeek.SATURDAY && weekday != DayOfWeek.SUNDAY) continue
            var candidate = holiday.plusDays(if (weekday == DayOfWeek.SATURDAY) 2 else 1)
            var hops = 0
            while (hops < 7 && isPublicHoliday(candidate)) {
                candidate = candidate.plusDays(1)
                hops += 1
            }
            if (candidate.monthValue == month && candidate.dayOfMonth == day) return "대체공휴일(${entry.name})"
        }
        return null
    }

    /** 대체일 충돌 회피용 — 그날이 이미 법정공휴일인가 */
    private fun isPublicHoliday(date: LocalDate): Boolean {
        val month = date.monthValue
        val day = date.dayOfMonth
        if (fixedPublic.any { it.month == month && it.day == day }) return true
        return lunarTable[date.year].orEmpty().any { it.month == month && it.day == day }
    }
}
