// 템포루틴 — 일정 제목에서 시각 읽기 (빠른 일정 §8.2.3, 2026-07-25 사용자 지시)
// 순수 Foundation 문자 스캐너 — 정규식 미사용(언어 모드·플랫폼 편차 회피). 명세는 Linux swift test로 고정.
// 다루는 것은 "시각"뿐이다: 날짜(내일·모레)·반복(매주)은 읽지 않는다 — 날짜는 누른 칸, 반복은 칩으로 정한다.
// 원문은 고치지 않는다(한글 조합 중 텍스트 치환 금지) — 제목 정제본은 저장 시점에만 쓴다.

import Foundation

public struct ParsedTime: Equatable, Sendable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public var minutesOfDay: Int { hour * 60 + minute }
}

public struct ParsedScheduleText: Equatable, Sendable {
    /// 인식한 시각 표현을 걷어낸 제목. 인식 실패면 원문 trim 그대로.
    public let title: String
    public let start: ParsedTime?
    public let end: ParsedTime?
    /// 인식한 원문 조각 — UI가 "'3시'를 오후 3:00으로 읽었어요"로 근거를 보여준다.
    public let matchedText: String?
    /// 오전·오후를 안 쓴 "N시"라 두 읽기가 다 성립하는가 — UI가 두 칩을 띄워 고르게 한다(2026-07-26).
    public let ambiguousMeridiem: Bool

    public init(title: String, start: ParsedTime?, end: ParsedTime?, matchedText: String?,
                ambiguousMeridiem: Bool = false) {
        self.title = title
        self.start = start
        self.end = end
        self.matchedText = matchedText
        self.ambiguousMeridiem = ambiguousMeridiem
    }
}

public enum ScheduleTextParser {

    public static func parse(_ raw: String) -> ParsedScheduleText {
        let chars = Array(raw)
        let plain = raw.trimmingCharacters(in: .whitespaces)
        guard let first = firstMatch(in: chars) else {
            return ParsedScheduleText(title: plain, start: nil, end: nil, matchedText: nil)
        }

        var consumedEnd = first.range.upperBound
        var end: ParsedTime?

        // 범위 표현 — "3시~5시", "3시-5시", "3시부터 5시까지"
        var i = skipSpaces(chars, from: consumedEnd)
        if let separatorEnd = matchRangeSeparator(chars, from: i) {
            i = skipSpaces(chars, from: separatorEnd)
            if let second = scanTime(chars, at: i) {
                var closing = second.time
                // "오후 3시~5시" — 뒤쪽에 수식어가 없으면 앞 시각 이후로 당겨 읽는다
                if !second.hadMeridiem && !second.explicit24
                    && closing.minutesOfDay <= first.time.minutesOfDay && closing.hour + 12 <= 23 {
                    closing = ParsedTime(hour: closing.hour + 12, minute: closing.minute)
                }
                end = closing
                consumedEnd = second.range.upperBound
                consumedEnd = consume(chars, from: skipSpaces(chars, from: consumedEnd), word: "까지") ?? consumedEnd
            } else {
                // "3시부터 청소" — 뒤 시각이 없어도 "부터"는 제목에 남기지 않는다
                consumedEnd = separatorEnd
            }
        }

        // 시각 뒤 조사 — "3시에 회의"의 "에"가 제목에 남지 않게
        for particle in ["에는", "에"] {
            if let after = consume(chars, from: consumedEnd, word: particle) {
                consumedEnd = after
                break
            }
        }

        let matchRange = first.range.lowerBound..<consumedEnd
        return ParsedScheduleText(title: strip(chars, removing: matchRange),
                                  start: first.time,
                                  end: end,
                                  matchedText: String(chars[matchRange]).trimmingCharacters(in: .whitespaces),
                                  ambiguousMeridiem: first.isAmbiguous)
    }

    // ── 스캔 ──

    private enum Modifier {
        case am      // 오전·아침
        case pm      // 오후·점심
        case night   // 밤 — 12시는 자정
        case dawn    // 새벽 — 12시는 자정, 그 외 그대로
    }

    private struct TimeMatch {
        let time: ParsedTime
        let range: Range<Int>
        let hadMeridiem: Bool
        let explicit24: Bool
        /// 수식어 없는 1~12시 = 오전·오후 둘 다 성립(휴리스틱으로 하나를 고른 상태)
        let isAmbiguous: Bool
    }

    private static let modifierWords: [(word: [Character], modifier: Modifier)] = [
        (Array("오전"), .am), (Array("아침"), .am),
        (Array("오후"), .pm), (Array("점심"), .pm), (Array("저녁"), .pm),
        (Array("새벽"), .dawn), (Array("밤"), .night),
    ]

    private static func firstMatch(in chars: [Character]) -> TimeMatch? {
        var i = 0
        while i < chars.count {
            // 숫자 한가운데서 다시 시작하지 않는다 — "25시"가 "5시"로 읽히면 안 된다
            let insideNumber = i > 0 && isDigit(chars[i - 1])
            if !insideNumber, let match = scanTime(chars, at: i) { return match }
            i += 1
        }
        return nil
    }

    /// 정확히 위치 i에서 시작하는 시각 표현만 인정한다.
    private static func scanTime(_ chars: [Character], at start: Int) -> TimeMatch? {
        guard start < chars.count else { return nil }

        // 숫자 없이 성립하는 표현
        if let after = consume(chars, from: start, word: "정오") {
            return TimeMatch(time: ParsedTime(hour: 12, minute: 0),
                             range: start..<after, hadMeridiem: true, explicit24: false, isAmbiguous: false)
        }
        if let after = consume(chars, from: start, word: "자정") {
            return TimeMatch(time: ParsedTime(hour: 0, minute: 0),
                             range: start..<after, hadMeridiem: true, explicit24: false, isAmbiguous: false)
        }

        var i = start
        var modifier: Modifier?
        for entry in modifierWords {
            if let after = consume(chars, from: i, word: String(entry.word)) {
                modifier = entry.modifier
                i = skipSpaces(chars, from: after)
                break
            }
        }

        guard let hourScan = scanNumber(chars, from: i), hourScan.value <= 23 else { return nil }
        i = hourScan.end

        var minute = 0
        var explicit24 = false

        if let after = consume(chars, from: i, word: "시") {
            // "3시간"은 기간이지 시각이 아니다
            if after < chars.count && chars[after] == "간" { return nil }
            i = after
            if let afterHalf = consume(chars, from: i, word: "반") {
                minute = 30
                i = afterHalf
            } else {
                let j = skipSpaces(chars, from: i)
                if let minuteScan = scanNumber(chars, from: j), minuteScan.value <= 59,
                   let afterUnit = consume(chars, from: minuteScan.end, word: "분") {
                    minute = minuteScan.value
                    i = afterUnit
                }
            }
        } else if i < chars.count && chars[i] == ":" {
            guard let minuteScan = scanNumber(chars, from: i + 1), minuteScan.value <= 59 else { return nil }
            minute = minuteScan.value
            i = minuteScan.end
            explicit24 = true
        } else {
            return nil   // 단위 없는 숫자는 시각이 아니다
        }

        // 얼버무림 어미 — 제목에 남지 않게 같이 먹는다
        for hedge in ["쯤", "경", "께"] {
            if let after = consume(chars, from: i, word: hedge) { i = after; break }
        }

        guard let hour = normalize(hour: hourScan.value, modifier: modifier, explicit24: explicit24) else {
            return nil
        }
        return TimeMatch(time: ParsedTime(hour: hour, minute: minute),
                         range: start..<i,
                         hadMeridiem: modifier != nil,
                         explicit24: explicit24,
                         isAmbiguous: modifier == nil && !explicit24 && (1...12).contains(hourScan.value))
    }

    /// 12시간제 해석 — 수식어가 없으면 1~6시는 오후, 7~12시는 오전으로 읽는다(일상 관례).
    private static func normalize(hour raw: Int, modifier: Modifier?, explicit24: Bool) -> Int? {
        guard raw >= 0 && raw <= 23 else { return nil }
        switch modifier {
        case .am:
            return raw == 12 ? 0 : raw
        case .pm:
            return raw < 12 ? raw + 12 : raw
        case .night:
            if raw == 12 { return 0 }
            return raw < 12 ? raw + 12 : raw
        case .dawn:
            return raw == 12 ? 0 : raw
        case nil:
            if explicit24 { return raw }
            if raw >= 1 && raw <= 6 { return raw + 12 }
            return raw
        }
    }

    // ── 문자 유틸 ──

    private static func isDigit(_ c: Character) -> Bool {
        c.isASCII && c.wholeNumberValue != nil
    }

    private static func scanNumber(_ chars: [Character], from start: Int) -> (value: Int, end: Int)? {
        var i = start
        var value = 0
        var digits = 0
        while i < chars.count, digits < 2, isDigit(chars[i]) {
            value = value * 10 + (chars[i].wholeNumberValue ?? 0)
            digits += 1
            i += 1
        }
        guard digits > 0 else { return nil }
        // 3자리 이상 숫자는 시각으로 읽지 않는다(전화번호·수량)
        if i < chars.count, isDigit(chars[i]) { return nil }
        return (value, i)
    }

    private static func consume(_ chars: [Character], from start: Int, word: String) -> Int? {
        let target = Array(word)
        guard start >= 0, start + target.count <= chars.count else { return nil }
        for (offset, c) in target.enumerated() {
            if chars[start + offset] != c { return nil }
        }
        return start + target.count
    }

    private static func matchRangeSeparator(_ chars: [Character], from start: Int) -> Int? {
        guard start < chars.count else { return nil }
        if chars[start] == "~" || chars[start] == "-" || chars[start] == "–" { return start + 1 }
        return consume(chars, from: start, word: "부터")
    }

    private static func skipSpaces(_ chars: [Character], from start: Int) -> Int {
        var i = start
        while i < chars.count && chars[i] == " " { i += 1 }
        return i
    }

    /// 인식 구간을 걷어낸 제목 — 남은 공백은 한 칸으로 정리한다.
    private static func strip(_ chars: [Character], removing range: Range<Int>) -> String {
        var rest = Array(chars[chars.startIndex..<range.lowerBound])
        rest.append(contentsOf: chars[range.upperBound..<chars.endIndex])
        var out = ""
        var lastWasSpace = false
        for c in rest {
            if c == " " {
                if !lastWasSpace && !out.isEmpty { out.append(c) }
                lastWasSpace = true
            } else {
                out.append(c)
                lastWasSpace = false
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
