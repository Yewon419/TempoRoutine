// 템포루틴 — 오늘의 계절 위젯 (Phase 1: 소형 + 잠금화면, 2026-07-27 / MASTER §8.2.8)
// 데이터 = App Group 스냅샷만(WidgetSnapshot — 주기 로직·SwiftData 없음).
// 프라이버시 = 계절 은유 그 자체: 홈에 떠도 제3자에겐 계절 위젯으로 보인다. 명시 용어 없음.
// 잉크 토큰·글리프는 앱 Almanac.swift와 동값 사본 — 위젯 타깃을 앱 소스와 얽지 않는다(의도적 중복).
// 서체: Gowun Batang 번들 미포함(Phase 1) — 시스템 세리프 폴백(.almanac 폴백 경로와 동일 판단).

import WidgetKit
import SwiftUI

@main
struct TempoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SeasonTodayWidget()
        SeasonLockWidget()     // 잠금화면 직사각형(2026-07-27 개편)
        WeekStripWidget()      // Phase 2 (2026-07-27)
        TodayScheduleWidget()  // Phase 2 (2026-07-27) → 오늘 카드(일정·Input·Output)
        MonthGridWidget()      // 월 캘린더(2026-07-27 개편)
    }
}

// ── 잉크 토큰 (App/TodayView.swift Ink와 동값) ──
enum WInk {   // 위젯 타깃 내부 공용(Phase2Widgets가 함께 씀)
    private static func dyn(_ light: (Int, Int, Int), _ dark: (Int, Int, Int)) -> Color {
        Color(uiColor: UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255,
                           blue: CGFloat(c.2) / 255, alpha: 1)
        })
    }
    static let winter = dyn((0x55, 0x60, 0x6C), (0x98, 0xA6, 0xB4))
    static let spring = dyn((0x8F, 0x7C, 0x2E), (0xC2, 0xAC, 0x52))
    static let summer = dyn((0x6E, 0x7C, 0x46), (0xA3, 0xB3, 0x78))
    static let autumn = dyn((0xA8, 0x4B, 0x38), (0xD6, 0x82, 0x6B))
    static let text = dyn((0x2C, 0x2B, 0x27), (0xE8, 0xE6, 0xE1))
    static let paper = dyn((0xF1, 0xEE, 0xE6), (0x1C, 0x1B, 0x19))
    static let coral = dyn((0xD6, 0x64, 0x4C), (0xE0, 0x7A, 0x63))          // 기록 형광펜
    static let predictGray = dyn((0x87, 0x8E, 0x94), (0x9B, 0xA2, 0xA8))   // 예상 형광펜

    static func season(_ key: String?) -> Color {
        switch key {
        case "winter": winter
        case "spring": spring
        case "summer": summer
        case "autumn": autumn
        default: text
        }
    }
}

// ── 계절 글리프 (App/Almanac.swift SeasonGlyphShape와 동일 path — 키만 String) ──
struct GlyphShape: Shape {   // 위젯 타깃 내부 공용
    let season: String

    func path(in rect: CGRect) -> Path {
        let s = rect.width / 16
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }
        var path = Path()
        switch season {
        case "winter":        // 눈결정 3획
            path.move(to: p(8, 2)); path.addLine(to: p(8, 14))
            path.move(to: p(2.8, 5)); path.addLine(to: p(13.2, 11))
            path.move(to: p(13.2, 5)); path.addLine(to: p(2.8, 11))
        case "spring":        // 새싹
            path.move(to: p(8, 14)); path.addLine(to: p(8, 6))
            path.move(to: p(8, 8))
            path.addCurve(to: p(4, 4), control1: p(8, 5.4), control2: p(6, 4))
            path.addCurve(to: p(8, 8), control1: p(4, 6.6), control2: p(6, 8))
            path.move(to: p(8, 6.6))
            path.addCurve(to: p(12, 3), control1: p(8, 4.2), control2: p(10, 3))
            path.addCurve(to: p(8, 6.6), control1: p(12, 5.4), control2: p(10, 6.6))
        case "summer":        // 해
            path.addEllipse(in: CGRect(x: rect.minX + 4.8 * s, y: rect.minY + 4.8 * s,
                                       width: 6.4 * s, height: 6.4 * s))
            path.move(to: p(8, 1.5)); path.addLine(to: p(8, 3.2))
            path.move(to: p(8, 12.8)); path.addLine(to: p(8, 14.5))
            path.move(to: p(1.5, 8)); path.addLine(to: p(3.2, 8))
            path.move(to: p(12.8, 8)); path.addLine(to: p(14.5, 8))
        default:              // 가을 = 잎
            path.move(to: p(13, 3))
            path.addCurve(to: p(3, 12), control1: p(8, 3), control2: p(4, 6))
            path.addCurve(to: p(13, 3), control1: p(9, 11), control2: p(12, 8))
            path.closeSubpath()
            path.move(to: p(3, 12)); path.addLine(to: p(9, 6))
        }
        return path
    }
}

// ── 타임라인 ──
struct SeasonEntry: TimelineEntry {
    let date: Date
    let day: WidgetDay?
}

struct SeasonProvider: TimelineProvider {
    func placeholder(in context: Context) -> SeasonEntry {
        SeasonEntry(date: .now, day: sampleDay)
    }

    func getSnapshot(in context: Context, completion: @escaping (SeasonEntry) -> Void) {
        if context.isPreview {
            completion(SeasonEntry(date: .now, day: sampleDay))
        } else {
            completion(SeasonEntry(date: .now, day: WidgetSnapshot.load()?.entry(for: .now)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SeasonEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var entries: [SeasonEntry] = []
        // 오늘은 지금 시각으로, 이후 6일은 자정마다 — 앱을 안 열어도 일차가 굴러간다
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            entries.append(SeasonEntry(date: offset == 0 ? Date() : day,
                                       day: snapshot?.entry(for: day)))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private var sampleDay: WidgetDay {
        WidgetDay(day: .now, season: "winter", title: "겨울", sub: "월경기 3일차",
                  inline: "겨울 3일차", mood: "이번 주는 겨울이에요. 쉬어가도 괜찮아요.",
                  projected: false)
    }
}

// ── 위젯 ──
struct SeasonTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SeasonToday", provider: SeasonProvider()) { entry in
            SeasonWidgetView(entry: entry)
                .containerBackground(WInk.paper, for: .widget)
        }
        .configurationDisplayName("오늘의 계절")
        .description("지금 계절과 일차를 보여줘요.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

struct SeasonWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SeasonEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: small
        }
    }

    // 소형 홈 위젯 — 글리프 + 계절명 + 일차 + 무드라인(책력 조판 축소)
    private var small: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                if let season = entry.day?.season {
                    GlyphShape(season: season)
                        .stroke(WInk.season(season), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .frame(width: 16, height: 16)
                }
                Text(entry.day?.title ?? "템포루틴")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(WInk.season(entry.day?.season))
            }
            Text(entry.day?.sub ?? "앱을 한 번 열면 채워져요")
                .font(.footnote)
                .foregroundStyle(WInk.text.opacity(entry.day?.projected == true ? 0.55 : 0.75))
            Spacer(minLength: 0)
            // 오늘 일정 2줄(2026-07-27 사용자 지시) — 없으면 무드라인 폴백
            if let lines = entry.day?.schedules, !lines.isEmpty {
                ForEach(Array(lines.prefix(2).enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 5) {
                        Text(line.time)
                            .font(.system(size: 10))
                            .foregroundStyle(WInk.text.opacity(0.5))
                        Text(line.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WInk.text.opacity(0.85))
                            .lineLimit(1)
                    }
                }
            } else if let mood = entry.day?.mood {
                Text(mood)
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(WInk.text.opacity(0.6))
                    .lineLimit(3)
                    .minimumScaleFactor(0.9)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    // 잠금화면 원형 — 글리프만(최소 정보·은유 유지)
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            GlyphShape(season: entry.day?.season ?? "winter")
                .stroke(.primary, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .frame(width: 24, height: 24)
                .opacity(entry.day?.season == nil ? 0.45 : 1)
        }
        .accessibilityLabel(entry.day?.inline ?? "템포루틴")
    }

    // 잠금화면 인라인 — "겨울 3일차"
    private var inline: some View {
        Text(entry.day?.inline ?? "템포루틴")
    }
}

// ── 잠금화면 직사각형 — 계절 한 줄 (2026-07-27 사용자 지시: "예쁘장한" 잠금 위젯) ──
// 글리프 + 계절·일차 + 무드라인. 잠금화면은 시스템이 모노크롬 틴트 — widgetAccentable로 강조 위계만.

struct SeasonLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SeasonLock", provider: SeasonProvider()) { entry in
            SeasonLockView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("계절 한 줄")
        .description("잠금화면에서 계절과 오늘의 결을 보여줘요.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct SeasonLockView: View {
    let entry: SeasonEntry

    var body: some View {
        HStack(spacing: 8) {
            GlyphShape(season: entry.day?.season ?? "winter")
                .stroke(.primary, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                .frame(width: 20, height: 20)
                .widgetAccentable()
                .opacity(entry.day?.season == nil ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.day?.inline ?? "템포루틴")
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .widgetAccentable()
                Text(entry.day?.mood ?? entry.day?.sub ?? "앱을 한 번 열면 채워져요")
                    .font(.system(size: 11))
                    .opacity(0.8)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
