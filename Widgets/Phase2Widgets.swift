// 템포루틴 — 위젯 Phase 2 (2026-07-27, MASTER §8.2.8)
// 주간 스트립 = 캘린더 문법의 축소판: 계절 = 숫자 잉크색 / 오늘 = 은필 채운 원 /
// 코랄 = 기록·회색 = 예상 형광펜(§8.2.3과 동일 어휘). 오늘 일정 = 일정 구획의 축소판.
// 데이터는 WidgetSnapshot뿐 — 로컬 일정만(EventKit 오버레이는 런타임 전용이라 미포함).

import WidgetKit
import SwiftUI

// ══ 주간 스트립 (systemMedium) ══

struct WeekEntry: TimelineEntry {
    let date: Date
    let days: [WidgetDay?]   // 이번 주 7칸 — 스냅샷에 없으면 nil
}

struct WeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekEntry {
        weekEntry(for: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekEntry) -> Void) {
        completion(weekEntry(for: .now, snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var entries: [WeekEntry] = []
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let base = weekEntry(for: day, snapshot: snapshot)
            entries.append(WeekEntry(date: offset == 0 ? Date() : day, days: base.days))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func weekEntry(for date: Date, snapshot: WidgetSnapshot?) -> WeekEntry {
        let cal = Calendar.current
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: date)?.start else {
            return WeekEntry(date: date, days: Array(repeating: nil, count: 7))
        }
        let days = (0..<7).map { offset -> WidgetDay? in
            guard let d = cal.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            return snapshot?.entry(for: d)
        }
        return WeekEntry(date: date, days: days)
    }
}

struct WeekStripWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekStrip", provider: WeekProvider()) { entry in
            WeekStripView(entry: entry)
                .containerBackground(for: .widget) { WWidgetGround(date: entry.date, grid: true) }
                .environment(\.locale, Loc.locale)   // 앱의 언어 선택 추종(App Group 경유, 2026-08-21)
        }
        .configurationDisplayName("이번 주")
        .description("일주일의 계절과 기록을 한 줄로 보여줘요.")
        .supportedFamilies([.systemMedium])
    }
}

struct WeekStripView: View {
    let entry: WeekEntry

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: entry.date) }

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortWeekdaySymbols
        let shift = cal.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                column(index: index)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func column(index: Int) -> some View {
        let day = entry.days[index]
        let isToday = day.map { cal.isDate($0.day, inSameDayAs: today) } ?? false
        let weekday = (cal.firstWeekday - 1 + index) % 7 + 1
        return VStack(spacing: 8) {
            Text(weekdaySymbols[index])
                .font(.system(size: 11))
                .foregroundStyle(WInk.weekdayAccent(weekday) ?? WInk.accent.opacity(0.8))   // 구조색(기본=winter 동값)
            ZStack {
                // 계절 = 숫자 아래 얇은 밑줄 띠(2026-07-28 4차 — 앱 캘린더와 동일)
                if let season = day?.season {
                    SeasonGlowBand(seasonKey: season,
                                   projected: day?.projected == true,
                                   roundLeft: index == 0 || entry.days[index - 1]?.season != season,
                                   roundRight: index == 6 || entry.days[index + 1]?.season != season,
                                   height: 4)
                        .offset(y: 17)   // 숫자 프레임(30pt) 바로 밑
                }
                dayNumber(day, isToday: isToday, weekday: weekday)
            }
        }
    }

    private func dayNumber(_ day: WidgetDay?, isToday: Bool, weekday: Int) -> some View {
        let number = day.map { String(cal.component(.day, from: $0.day)) } ?? "·"
        let ink = WInk.weekdayAccent(weekday) ?? WInk.text   // 계절은 띠가 담당 — 숫자는 먹색(새 문법)
        return Text(number)
            .font(.system(size: 16, weight: isToday ? .bold : .semibold))
            .monospacedDigit()
            .foregroundStyle(isToday ? WInk.paper : ink)
            .frame(width: 30, height: 30)
            .background { numberBackground(day, isToday: isToday) }
    }

    @ViewBuilder
    private func numberBackground(_ day: WidgetDay?, isToday: Bool) -> some View {
        if isToday {
            Circle().fill(WInk.accent)   // 오늘 = 구조색 원(기본=은필 동값 / 모던=흰색, §8.1)
        } else if day?.recorded == true && day?.season != "winter" {
            // 겨울 띠와 어긋난 기록만 코랄 — 회색 예상 폐기(앱 캘린더와 동일 규칙, 2026-07-28)
            Capsule().fill(WInk.record.opacity(0.25))
        }
    }

}

// ══ 오늘 일정 (systemMedium) ══

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let day: WidgetDay?
}

struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(date: .now, day: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        completion(ScheduleEntry(date: .now, day: WidgetSnapshot.load()?.entry(for: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var entries: [ScheduleEntry] = []
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            entries.append(ScheduleEntry(date: offset == 0 ? Date() : day,
                                         day: snapshot?.entry(for: day)))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct TodayScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodaySchedule", provider: ScheduleProvider()) { entry in
            TodayScheduleView(entry: entry)
                .containerBackground(for: .widget) { WWidgetGround(date: entry.date) }
                .environment(\.locale, Loc.locale)   // 앱의 언어 선택 추종(App Group 경유, 2026-08-21)
        }
        .configurationDisplayName("오늘")
        .description("오늘의 일정·Input·Output을 한눈에 보여줘요.")
        .supportedFamilies([.systemMedium])
    }
}

struct TodayScheduleView: View {
    let entry: ScheduleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            HStack(alignment: .top, spacing: 10) {
                scheduleColumn
                inputColumn
                outputColumn
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let season = entry.day?.season {
                GlyphShape(season: season)
                    .stroke(WInk.season(season), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .frame(width: 12, height: 12)
            }
            Text(entry.date.formatted(.dateTime.month().day().weekday(.wide)))
                .font(WFont.almanac(14, weight: .bold))
                .foregroundStyle(WInk.text)
            Spacer()
            Text(entry.day?.inline ?? "")
                .font(WFont.almanac(11, weight: .bold))
                .foregroundStyle(WInk.season(entry.day?.season).opacity(0.9))
        }
    }

    // ── 3열 — 오늘 탭 3구획의 축소판(2026-07-27) ──
    private func column(_ title: String, empty: Bool,
                        @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WInk.text.opacity(0.45))
            if empty {
                Text("없어요")
                    .font(.system(size: 10))
                    .foregroundStyle(WInk.text.opacity(0.3))
            } else {
                rows()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scheduleColumn: some View {
        let lines = entry.day?.schedules ?? []
        return column("일정", empty: lines.isEmpty) {
            ForEach(Array(lines.prefix(3).enumerated()), id: \.offset) { _, line in
                VStack(alignment: .leading, spacing: 0) {
                    Text(line.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WInk.text)
                        .lineLimit(1)
                    Text(line.time)
                        .font(.system(size: 9))
                        .foregroundStyle(WInk.text.opacity(0.5))
                }
            }
        }
    }

    private var inputColumn: some View {
        let lines = entry.day?.inputs ?? []
        return column("Input", empty: lines.isEmpty) {
            ForEach(Array(lines.prefix(3).enumerated()), id: \.offset) { _, line in
                HStack(spacing: 4) {
                    Image(systemName: line.done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 9))
                        .foregroundStyle(line.done ? WInk.text : WInk.text.opacity(0.35))
                    Text(line.title)
                        .font(.system(size: 11))
                        .foregroundStyle(WInk.text.opacity(line.done ? 0.5 : 0.9))
                        .strikethrough(line.done, color: WInk.text.opacity(0.4))
                        .lineLimit(1)
                    // 그날 진행 라벨(2026-08-20) — 오늘 카드 위젯과 동일 문법
                    if let label = line.progressLabel {
                        Text(label)
                            .font(.system(size: 9))
                            .monospacedDigit()
                            .foregroundStyle(WInk.text.opacity(0.5))
                    }
                }
            }
        }
    }

    private var outputColumn: some View {
        let lines = entry.day?.outputs ?? []
        return column("Output", empty: lines.isEmpty) {
            ForEach(Array(lines.prefix(3).enumerated()), id: \.offset) { _, line in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(line.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WInk.text)
                            .lineLimit(1)
                        Text(line.label)
                            .font(.system(size: 9))
                            .foregroundStyle(WInk.text.opacity(0.5))
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(WInk.text.opacity(0.12))
                            Capsule().fill(WInk.text.opacity(0.75))
                                .frame(width: max(3, proxy.size.width * line.fraction))
                        }
                    }
                    .frame(height: 3)
                }
            }
        }
    }
}
