// 템포루틴 — 논리적 「오늘」 (2026-09-15 대표님 결정 "생리 기록 시트만 자정 기준")
// 새벽 2:56에 생리 기록 시트가 「9월 14일, 오늘」로 떠서 "13일인데 왜 오늘이래"(베타 09-14). 사람은 자기 전까지를
// 같은 날로 산다. 그래서 앱의 하루(오늘 탭·컨디션 기록·한 줄·루틴 완료·위젯 「오늘」)는 새벽 4시 전을 전날로 본다.
// **생리 기록만 예외** — 시작일은 달력상의 사실이라 PeriodTrackerSheet·PeriodStore·예측(CycleSnapshot)은 자정 기준 그대로.
// 알림(아침 브리핑·예정일)도 달력 날짜 기준 유지. 저장된 day 값은 안 바뀐다 — 판정만 바뀐다.
// 앱·위젯 공용(Shared) — 위젯 타임라인 경계도 이 시각.

import Foundation

enum AppDay {
    /// 하루 경계 시각(시). 습관 앱 관례 = 4시.
    static let boundaryHour = 4

    /// 논리적 오늘의 자정(달력 날짜) — `now`가 04:00 전이면 전날.
    static func today(now: Date = .now, calendar: Calendar = .current) -> Date {
        let shifted = calendar.date(byAdding: .hour, value: -boundaryHour, to: now) ?? now
        return calendar.startOfDay(for: shifted)
    }

    static func isToday(_ day: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.isDate(day, inSameDayAs: today(now: now, calendar: calendar))
    }

    /// 그 날의 경계 시각(그 날 04:00) — 위젯 타임라인 엔트리가 그 날로 넘어가는 순간.
    static func boundary(of day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: boundaryHour, minute: 0, second: 0, of: start) ?? start
    }

    /// 위젯 타임라인 엔트리 시각 — 그 날이 지금의 달력 날짜면 지금(시간대·날씨 낮밤이 맞게), 아니면 그 날 04:00.
    /// 새벽 2시엔 논리적 오늘이 전날이라 엔트리 시각도 전날 04:00(과거)이 된다 — WidgetKit은 now 이하 최신 엔트리를 그린다.
    static func entryTime(for day: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.isDate(now, inSameDayAs: day) ? now : boundary(of: day, calendar: calendar)
    }

    /// 다음 경계 시각(다음 04:00).
    static func nextBoundary(after now: Date = .now, calendar: Calendar = .current) -> Date {
        let day = today(now: now, calendar: calendar)
        let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        return boundary(of: next, calendar: calendar)
    }
}
