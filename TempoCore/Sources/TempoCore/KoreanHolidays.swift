// 템포루틴 — 한국 공휴일·기념일 (§8.2.3 캘린더 표기, 2026-07-28 사용자 지시)
// 고정일 공휴일 + 규칙 기반 대체공휴일(2023 개정 규칙: 삼일절·어린이날·광복절·개천절·한글날·
// 성탄절이 토·일과 겹치면 다음 평일. 신정·현충일은 미적용. 설·추석·석탄일은 음력이라 규칙 계산
// 대신 실측 테이블 — 2024~2028 웹 검증 완료(2026-07-28), 이후 연도는 데이터 연장 필요).
// 순수 Foundation — 렌더는 앱, 여기는 판정만.

import Foundation

public struct KoreanHoliday: Equatable, Sendable {
    public let name: String
    public let isPublic: Bool   // true = 법정공휴일(빨간날), false = 기념일(표기만)

    public init(name: String, isPublic: Bool) {
        self.name = name
        self.isPublic = isPublic
    }
}

public enum KoreanHolidays {

    // ── 고정일 공휴일(매년 같은 양력 날짜) ──
    private static let fixedPublic: [(month: Int, day: Int, name: String)] = [
        (1, 1, "신정"), (3, 1, "삼일절"), (5, 5, "어린이날"), (6, 6, "현충일"),
        (8, 15, "광복절"), (10, 3, "개천절"), (10, 9, "한글날"), (12, 25, "성탄절"),
    ]

    /// 대체공휴일 적용 대상(토·일 → 다음 평일). 신정·현충일 제외.
    private static let substituteEligible: Set<String> =
        ["삼일절", "어린이날", "광복절", "개천절", "한글날", "성탄절"]

    // ── 기념일(공휴일 아님 — 달력 표기 관례) ──
    private static let commemorations: [(month: Int, day: Int, name: String)] = [
        (5, 1, "근로자의 날"), (5, 8, "어버이날"), (5, 15, "스승의 날"),
        (7, 17, "제헌절"), (10, 1, "국군의 날"),
    ]

    // ── 음력 명절(설·추석·석가탄신일) — 대체공휴일까지 실측 그대로 ──
    private static let lunarTable: [Int: [(month: Int, day: Int, name: String)]] = [
        2024: [(2, 9, "설 연휴"), (2, 10, "설날"), (2, 11, "설 연휴"), (2, 12, "대체공휴일"),
               (5, 15, "석가탄신일"),
               (9, 16, "추석 연휴"), (9, 17, "추석"), (9, 18, "추석 연휴")],
        2025: [(1, 28, "설 연휴"), (1, 29, "설날"), (1, 30, "설 연휴"),
               (5, 5, "석가탄신일"), (5, 6, "대체공휴일"),
               (10, 5, "추석 연휴"), (10, 6, "추석"), (10, 7, "추석 연휴"), (10, 8, "대체공휴일")],
        2026: [(2, 16, "설 연휴"), (2, 17, "설날"), (2, 18, "설 연휴"),
               (5, 24, "석가탄신일"), (5, 25, "대체공휴일"),
               (9, 24, "추석 연휴"), (9, 25, "추석"), (9, 26, "추석 연휴")],
        2027: [(2, 6, "설 연휴"), (2, 7, "설날"), (2, 8, "설 연휴"), (2, 9, "대체공휴일"),
               (5, 13, "석가탄신일"),
               (9, 14, "추석 연휴"), (9, 15, "추석"), (9, 16, "추석 연휴")],
        2028: [(1, 26, "설 연휴"), (1, 27, "설날"), (1, 28, "설 연휴"),
               (5, 2, "석가탄신일"),
               (10, 2, "추석 연휴"), (10, 4, "추석 연휴"), (10, 5, "대체공휴일")],
        // 2028 추석 당일(10/3)은 개천절과 겹침 — 고정일(개천절)이 우선 표기, 연휴·대체는 위에.
    ]

    /// 외부 소스(애플 캘린더) 이름의 기념일 판별 — 빨간날/회색 표기 분기용(2026-07-28)
    public static func isCommemorationName(_ name: String) -> Bool {
        commemorations.contains { name.contains($0.name.replacingOccurrences(of: " ", with: ""))
            || name.contains($0.name) }
    }

    /// 그날의 공휴일·기념일 전부(없으면 빈 배열). 공휴일이 앞에 온다.
    public static func holidays(on date: Date, calendar: Calendar = .current) -> [KoreanHoliday] {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day else { return [] }

        var result: [KoreanHoliday] = []
        for entry in fixedPublic where entry.month == month && entry.day == day {
            result.append(KoreanHoliday(name: entry.name, isPublic: true))
        }
        for entry in lunarTable[year] ?? [] where entry.month == month && entry.day == day {
            result.append(KoreanHoliday(name: entry.name, isPublic: true))
        }
        if let substitute = substituteName(year: year, month: month, day: day, calendar: calendar) {
            result.append(KoreanHoliday(name: substitute, isPublic: true))
        }
        for entry in commemorations where entry.month == month && entry.day == day {
            result.append(KoreanHoliday(name: entry.name, isPublic: false))
        }
        return result
    }

    /// 고정일 공휴일의 규칙 기반 대체공휴일 — 이 날짜가 어느 공휴일의 대체일이면 그 이름을 돌려준다.
    private static func substituteName(year: Int, month: Int, day: Int, calendar: Calendar) -> String? {
        for entry in fixedPublic where substituteEligible.contains(entry.name) {
            guard let holiday = calendar.date(from: DateComponents(year: year, month: entry.month, day: entry.day))
            else { continue }
            let weekday = calendar.component(.weekday, from: holiday)
            guard weekday == 7 || weekday == 1 else { continue }   // 토(7)·일(1)만
            var candidate = calendar.date(byAdding: .day, value: weekday == 7 ? 2 : 1, to: holiday)
            var hops = 0
            while let c = candidate, hops < 7, isPublicHoliday(c, calendar: calendar) {
                candidate = calendar.date(byAdding: .day, value: 1, to: c)
                hops += 1
            }
            guard let c = candidate else { continue }
            let comps = calendar.dateComponents([.month, .day], from: c)
            if comps.month == month && comps.day == day {
                return "대체공휴일(\(entry.name))"
            }
        }
        return nil
    }

    /// 대체일 충돌 회피용 — 그날이 이미 법정공휴일인가(대체일 재귀는 안 본다: 규칙상 발생 불가 조합)
    private static func isPublicHoliday(_ date: Date, calendar: Calendar) -> Bool {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day else { return false }
        if fixedPublic.contains(where: { $0.month == month && $0.day == day }) { return true }
        return (lunarTable[year] ?? []).contains { $0.month == month && $0.day == day }
    }
}
