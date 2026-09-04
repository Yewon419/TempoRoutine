// 템포루틴 — 일정 제목에서 시각 읽기 (빠른 일정 §8.2.3)
// iOS TempoCore/ScheduleTextParser.swift 1:1 이식 — 정규식 미사용 문자 스캐너. 명세는 테스트로 고정.
// 다루는 것은 "시각"뿐이다: 날짜(내일·모레)·반복(매주)은 읽지 않는다. 원문은 고치지 않는다.

package app.temporoutine.core

data class ParsedTime(val hour: Int, val minute: Int) {
    val minutesOfDay: Int get() = hour * 60 + minute
}

data class ParsedScheduleText(
    /** 인식한 시각 표현을 걷어낸 제목. 인식 실패면 원문 trim 그대로. */
    val title: String,
    val start: ParsedTime?,
    val end: ParsedTime?,
    /** 인식한 원문 조각 — UI가 근거를 보여준다. */
    val matchedText: String?,
    /** 오전·오후를 안 쓴 "N시"라 두 읽기가 다 성립하는가. */
    val ambiguousMeridiem: Boolean = false,
)

object ScheduleTextParser {

    fun parse(raw: String): ParsedScheduleText {
        val chars = raw.toCharArray()
        val plain = raw.trimSpaces()
        val first = firstMatch(chars) ?: return ParsedScheduleText(plain, null, null, null)

        var consumedEnd = first.range.last + 1
        var end: ParsedTime? = null

        // 범위 표현 — "3시~5시", "3시-5시", "3시부터 5시까지"
        var i = skipSpaces(chars, consumedEnd)
        val separatorEnd = matchRangeSeparator(chars, i)
        if (separatorEnd != null) {
            i = skipSpaces(chars, separatorEnd)
            val second = scanTime(chars, i)
            if (second != null) {
                var closing = second.time
                // "오후 3시~5시" — 뒤쪽에 수식어가 없으면 앞 시각 이후로 당겨 읽는다
                if (!second.hadMeridiem && !second.explicit24
                    && closing.minutesOfDay <= first.time.minutesOfDay && closing.hour + 12 <= 23
                ) {
                    closing = ParsedTime(closing.hour + 12, closing.minute)
                }
                end = closing
                consumedEnd = second.range.last + 1
                consumedEnd = consume(chars, skipSpaces(chars, consumedEnd), "까지") ?: consumedEnd
            } else {
                // "3시부터 청소" — 뒤 시각이 없어도 "부터"는 제목에 남기지 않는다
                consumedEnd = separatorEnd
            }
        }

        // 시각 뒤 조사 — "3시에 회의"의 "에"가 제목에 남지 않게
        for (particle in listOf("에는", "에")) {
            val after = consume(chars, consumedEnd, particle)
            if (after != null) { consumedEnd = after; break }
        }

        val matchRange = first.range.first until consumedEnd
        return ParsedScheduleText(
            title = strip(chars, matchRange),
            start = first.time,
            end = end,
            matchedText = String(chars, matchRange.first, matchRange.last - matchRange.first + 1).trimSpaces(),
            ambiguousMeridiem = first.isAmbiguous,
        )
    }

    // ── 스캔 ──

    private enum class Modifier { AM, PM, NIGHT, DAWN }

    private class TimeMatch(
        val time: ParsedTime,
        val range: IntRange,
        val hadMeridiem: Boolean,
        val explicit24: Boolean,
        /** 수식어 없는 1~12시 = 오전·오후 둘 다 성립(휴리스틱으로 하나를 고른 상태) */
        val isAmbiguous: Boolean,
    )

    private val modifierWords: List<Pair<String, Modifier>> = listOf(
        "오전" to Modifier.AM, "아침" to Modifier.AM,
        "오후" to Modifier.PM, "점심" to Modifier.PM, "저녁" to Modifier.PM,
        "새벽" to Modifier.DAWN, "밤" to Modifier.NIGHT,
    )

    private fun firstMatch(chars: CharArray): TimeMatch? {
        var i = 0
        while (i < chars.size) {
            // 숫자 한가운데서 다시 시작하지 않는다 — "25시"가 "5시"로 읽히면 안 된다
            val insideNumber = i > 0 && isDigit(chars[i - 1])
            if (!insideNumber) scanTime(chars, i)?.let { return it }
            i += 1
        }
        return null
    }

    /** 정확히 위치 start에서 시작하는 시각 표현만 인정한다. */
    private fun scanTime(chars: CharArray, start: Int): TimeMatch? {
        if (start >= chars.size) return null

        // 숫자 없이 성립하는 표현
        consume(chars, start, "정오")?.let { after ->
            return TimeMatch(ParsedTime(12, 0), start until after, hadMeridiem = true, explicit24 = false, isAmbiguous = false)
        }
        consume(chars, start, "자정")?.let { after ->
            return TimeMatch(ParsedTime(0, 0), start until after, hadMeridiem = true, explicit24 = false, isAmbiguous = false)
        }

        var i = start
        var modifier: Modifier? = null
        for ((word, mod) in modifierWords) {
            val after = consume(chars, i, word)
            if (after != null) {
                modifier = mod
                i = skipSpaces(chars, after)
                break
            }
        }

        val hourScan = scanNumber(chars, i) ?: return null
        if (hourScan.first > 23) return null
        i = hourScan.second

        var minute = 0
        var explicit24 = false

        val afterHour = consume(chars, i, "시")
        if (afterHour != null) {
            // "3시간"은 기간이지 시각이 아니다
            if (afterHour < chars.size && chars[afterHour] == '간') return null
            i = afterHour
            val afterHalf = consume(chars, i, "반")
            if (afterHalf != null) {
                minute = 30
                i = afterHalf
            } else {
                val j = skipSpaces(chars, i)
                val minuteScan = scanNumber(chars, j)
                if (minuteScan != null && minuteScan.first <= 59) {
                    val afterUnit = consume(chars, minuteScan.second, "분")
                    if (afterUnit != null) {
                        minute = minuteScan.first
                        i = afterUnit
                    }
                }
            }
        } else if (i < chars.size && chars[i] == ':') {
            val minuteScan = scanNumber(chars, i + 1) ?: return null
            if (minuteScan.first > 59) return null
            minute = minuteScan.first
            i = minuteScan.second
            explicit24 = true
        } else {
            return null   // 단위 없는 숫자는 시각이 아니다
        }

        // 얼버무림 어미 — 제목에 남지 않게 같이 먹는다
        for (hedge in listOf("쯤", "경", "께")) {
            val after = consume(chars, i, hedge)
            if (after != null) { i = after; break }
        }

        val hour = normalize(hourScan.first, modifier, explicit24) ?: return null
        return TimeMatch(
            time = ParsedTime(hour, minute),
            range = start until i,
            hadMeridiem = modifier != null,
            explicit24 = explicit24,
            isAmbiguous = modifier == null && !explicit24 && hourScan.first in 1..12,
        )
    }

    /** 12시간제 해석 — 수식어가 없으면 1~6시는 오후, 7~12시는 오전으로 읽는다(일상 관례). */
    private fun normalize(raw: Int, modifier: Modifier?, explicit24: Boolean): Int? {
        if (raw < 0 || raw > 23) return null
        return when (modifier) {
            Modifier.AM -> if (raw == 12) 0 else raw
            Modifier.PM -> if (raw < 12) raw + 12 else raw
            Modifier.NIGHT -> if (raw == 12) 0 else if (raw < 12) raw + 12 else raw
            Modifier.DAWN -> if (raw == 12) 0 else raw
            null -> when {
                explicit24 -> raw
                raw in 1..6 -> raw + 12
                else -> raw
            }
        }
    }

    // ── 문자 유틸 ──

    private fun isDigit(c: Char): Boolean = c in '0'..'9'

    /** (값, 끝 인덱스) — 3자리 이상 숫자는 시각으로 읽지 않는다(전화번호·수량) */
    private fun scanNumber(chars: CharArray, start: Int): Pair<Int, Int>? {
        var i = start
        var value = 0
        var digits = 0
        while (i < chars.size && digits < 2 && isDigit(chars[i])) {
            value = value * 10 + (chars[i] - '0')
            digits += 1
            i += 1
        }
        if (digits == 0) return null
        if (i < chars.size && isDigit(chars[i])) return null
        return value to i
    }

    private fun consume(chars: CharArray, start: Int, word: String): Int? {
        if (start < 0 || start + word.length > chars.size) return null
        for ((offset, c) in word.withIndex()) {
            if (chars[start + offset] != c) return null
        }
        return start + word.length
    }

    private fun matchRangeSeparator(chars: CharArray, start: Int): Int? {
        if (start >= chars.size) return null
        if (chars[start] == '~' || chars[start] == '-' || chars[start] == '–') return start + 1
        return consume(chars, start, "부터")
    }

    private fun skipSpaces(chars: CharArray, start: Int): Int {
        var i = start
        while (i < chars.size && chars[i] == ' ') i += 1
        return i
    }

    /** 인식 구간을 걷어낸 제목 — 남은 공백은 한 칸으로 정리한다. */
    private fun strip(chars: CharArray, removing: IntRange): String {
        val rest = chars.slice(0 until removing.first) + chars.slice(removing.last + 1 until chars.size)
        val out = StringBuilder()
        var lastWasSpace = false
        for (c in rest) {
            if (c == ' ') {
                if (!lastWasSpace && out.isNotEmpty()) out.append(c)
                lastWasSpace = true
            } else {
                out.append(c)
                lastWasSpace = false
            }
        }
        return out.toString().trimSpaces()
    }

    /** Swift `.whitespaces`(줄바꿈 제외) 대응 */
    private fun String.trimSpaces(): String = trim { it == ' ' || it == '\t' || it == ' ' }
}
