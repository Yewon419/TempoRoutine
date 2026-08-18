// 템포루틴 — 월 캘린더 위젯 (systemLarge, 2026-07-27 사용자 지시 / MASTER §8.2.8)
// 캘린더 탭의 축소판: 거대 월 표제(세리프) + 요일 행 + 계절 잉크 숫자 + 오늘 은필 원 +
// 코랄(기록)/회색(예상) 원 배경. 이번 달만 — 스냅샷 범위(-35~+34)가 월 전체를 덮는다.

import WidgetKit
import SwiftUI

struct MonthEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct MonthProvider: TimelineProvider {
    func placeholder(in context: Context) -> MonthEntry {
        MonthEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (MonthEntry) -> Void) {
        completion(MonthEntry(date: .now, snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MonthEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var entries: [MonthEntry] = []
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            entries.append(MonthEntry(date: offset == 0 ? Date() : day, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct MonthGridWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MonthGrid", provider: MonthProvider()) { entry in
            MonthGridView(entry: entry)
                .containerBackground(WInk.widgetGridGround, for: .widget)
        }
        .configurationDisplayName("이번 달")
        .description("한 달의 계절과 기록을 보여줘요.")
        .supportedFamilies([.systemLarge])
    }
}

struct MonthGridView: View {
    let entry: MonthEntry

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: entry.date) }

    private var monthStart: Date {
        cal.date(from: cal.dateComponents([.year, .month], from: entry.date)) ?? entry.date
    }
    private var daysInMonth: Int {
        cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
    }
    private var leadingBlanks: Int {
        (cal.component(.weekday, from: monthStart) - cal.firstWeekday + 7) % 7
    }
    private var rowCount: Int { (leadingBlanks + daysInMonth + 6) / 7 }

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortWeekdaySymbols
        let shift = cal.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            weekdayRow
            grid
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(cal.component(.month, from: monthStart))월")
                .font(WFont.almanac(22, weight: .bold))
                .foregroundStyle(WInk.text)
            Spacer()
            Text(entry.snapshot?.entry(for: today)?.inline ?? "")
                .font(WFont.almanac(11, weight: .bold))
                .foregroundStyle(WInk.season(entry.snapshot?.entry(for: today)?.season).opacity(0.9))
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                let weekday = (cal.firstWeekday - 1 + index) % 7 + 1
                Text(weekdaySymbols[index])
                    .font(.system(size: 10))
                    .foregroundStyle(WInk.weekdayAccent(weekday) ?? WInk.accent.opacity(0.75))   // 구조색(기본=winter 동값)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        VStack(spacing: 2) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        cell(index: row * 7 + col)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func date(at index: Int) -> Date? {
        let dayNumber = index - leadingBlanks + 1
        guard dayNumber >= 1 && dayNumber <= daysInMonth else { return nil }
        return cal.date(byAdding: .day, value: dayNumber - 1, to: monthStart)
            .map { cal.startOfDay(for: $0) }
    }

    /// 그 칸(달 안)의 계절 키 — 이웃 띠 연결 판정용. 달 밖·스냅샷 없음 = nil(끝 둥글게)
    private func seasonKey(at index: Int) -> String? {
        guard let d = date(at: index) else { return nil }
        return entry.snapshot?.entry(for: d)?.season
    }

    @ViewBuilder
    private func cell(index: Int) -> some View {
        if let date = date(at: index) {
            let day = entry.snapshot?.entry(for: date)
            let isToday = date == today
            ZStack {
                // 계절 = 숫자 아래 얇은 밑줄 띠(2026-07-28 4차 — 앱 캘린더와 동일 조판)
                if let season = day?.season {
                    let col = index % 7
                    SeasonGlowBand(seasonKey: season,
                                   projected: day?.projected == true,
                                   roundLeft: col == 0 || seasonKey(at: index - 1) != season,
                                   roundRight: col == 6 || seasonKey(at: index + 1) != season,
                                   height: 4)
                        .offset(y: 14)   // 숫자 프레임(24pt) 바로 밑
                }
                dayNumber(day, number: cal.component(.day, from: date), isToday: isToday,
                          weekday: cal.component(.weekday, from: date))
            }
        } else {
            Color.clear
        }
    }

    private func dayNumber(_ day: WidgetDay?, number: Int, isToday: Bool, weekday: Int) -> some View {
        let ink = WInk.weekdayAccent(weekday) ?? WInk.text   // 계절은 띠가 담당 — 숫자는 먹색(새 문법)
        return Text("\(number)")
            .font(.system(size: 12, weight: isToday ? .bold : .semibold))
            .monospacedDigit()
            .foregroundStyle(isToday ? WInk.paper : ink)
            .frame(width: 24, height: 24)
            .background { cellBackground(day, isToday: isToday) }
    }

    @ViewBuilder
    private func cellBackground(_ day: WidgetDay?, isToday: Bool) -> some View {
        if isToday {
            Circle().fill(WInk.accent)   // 오늘 = 구조색 원(기본=은필 동값 / 모던=흰색, §8.1)
        } else if day?.recorded == true && day?.season != "winter" {
            // 겨울 띠와 어긋난 기록만 코랄 — 회색 예상 폐기(앱 캘린더와 동일 규칙, 2026-07-28)
            Circle().fill(WInk.record.opacity(0.25))
        }
    }
}
