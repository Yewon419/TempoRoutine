// 템포루틴 — 오늘·내일 2열 일정 위젯 (2026-08-18 사용자 지시, 레퍼런스: Planit 2열 카드)
// 한 화면에 이틀을 나란히 놓는다. 「오늘」만 포인트색으로 세우고 내일은 잉크 — 어느 열이
// 지금인지 색 하나로 갈린다.
//
// 데이터 = 기존 스냅샷 그대로(WidgetDay.schedules). 새 필드를 안 만든 이유:
// 발행부가 이미 -35~+34일치를 싣고 있어 내일 치가 들어 있다(WidgetBridge).

import WidgetKit
import SwiftUI

struct TwoDayEntry: TimelineEntry {
    let date: Date
    let today: WidgetDay?
    let tomorrow: WidgetDay?
}

struct TwoDayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TwoDayEntry {
        TwoDayEntry(date: .now, today: nil, tomorrow: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TwoDayEntry) -> Void) {
        completion(entry(for: .now, snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TwoDayEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        // 자정마다 하루씩 밀린다 — 앱을 안 열어도 스냅샷 범위(+34일)만큼 버틴다
        var entries: [TwoDayEntry] = []
        for offset in 0...6 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            entries.append(entry(for: day, snapshot: snapshot))
        }
        let next = cal.date(byAdding: .day, value: 7, to: today) ?? today
        completion(Timeline(entries: entries, policy: .after(next)))
    }

    private func entry(for date: Date, snapshot: WidgetSnapshot?) -> TwoDayEntry {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let next = cal.date(byAdding: .day, value: 1, to: day) ?? day
        return TwoDayEntry(date: day,
                           today: snapshot?.entry(for: day),
                           tomorrow: snapshot?.entry(for: next))
    }
}

struct TwoDayScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TwoDaySchedule", provider: TwoDayProvider()) { entry in
            TwoDayScheduleView(entry: entry)
                .containerBackground(for: .widget) { WWidgetGround(date: entry.date) }
                .environment(\.locale, Loc.locale)   // 앱의 언어 선택 추종(App Group 경유, 2026-08-21)
        }
        .configurationDisplayName("오늘·내일")
        .description("이틀치 일정을 나란히 보여줘요.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TwoDayScheduleView: View {
    let entry: TwoDayEntry
    @Environment(\.widgetFamily) private var family

    private var rowLimit: Int { family == .systemLarge ? 8 : 3 }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            column(title: "오늘", date: entry.date, day: entry.today, isToday: true)
            column(title: "내일", date: nextDate, day: entry.tomorrow, isToday: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var nextDate: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: entry.date) ?? entry.date
    }

    private func column(title: String, date: Date, day: WidgetDay?, isToday: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(WFont.almanac(19, weight: .bold))
                    // 「오늘」만 포인트색 — 계절색(winter)이 곧 이 테마의 포인트다
                    .foregroundStyle(isToday ? WInk.winter : WInk.text)
                Text(dateLabel(date))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(WInk.text.opacity(0.55))
            }
            rows(for: day)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(dateLabel(date)), \(scheduleSummary(day))")
    }

    @ViewBuilder
    private func rows(for day: WidgetDay?) -> some View {
        let lines = day?.schedules ?? []
        if lines.isEmpty {
            Text("일정 없음")
                .font(.system(size: 12))
                .foregroundStyle(WInk.text.opacity(0.4))
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(lines.prefix(rowLimit).enumerated()), id: \.offset) { _, line in
                    row(line)
                }
                if lines.count > rowLimit {
                    Text("+\(lines.count - rowLimit)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(WInk.text.opacity(0.45))
                }
            }
        }
    }

    private func row(_ line: WidgetScheduleLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // 점 = 레퍼런스의 불릿. 시각은 제목 아래가 아니라 점을 대신하지 않는다 —
            // 좁은 열에서 "18:30 제주 여행 2/3일차"는 두 줄로 접힌다.
            Circle()
                .fill(WInk.winter.opacity(0.85))
                .frame(width: 7, height: 7)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: 1) {
                Text(line.title)
                    .font(.system(size: 13))
                    .foregroundStyle(WInk.text)
                    .lineLimit(1)
                if line.time != "종일" {
                    Text(line.time)
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(WInk.text.opacity(0.5))
                }
            }
        }
    }

    private func dateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let weekday = ["일", "월", "화", "수", "목", "금", "토"][cal.component(.weekday, from: date) - 1]
        return Loc.fmt("%1$@월 %2$@일 (%3$@)", "\(cal.component(.month, from: date))", "\(cal.component(.day, from: date))", "\(weekday)")
    }

    private func scheduleSummary(_ day: WidgetDay?) -> String {
        let lines = day?.schedules ?? []
        guard !lines.isEmpty else { return "일정 없음" }
        return lines.prefix(rowLimit).map(\.title).joined(separator: ", ")
    }
}
