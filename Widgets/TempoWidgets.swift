// 템포루틴 — 오늘의 계절 위젯 (Phase 1: 소형 + 잠금화면, 2026-07-27 / MASTER §8.2.8)
// 데이터 = App Group 스냅샷만(WidgetSnapshot — 주기 로직·SwiftData 없음).
// 프라이버시 = 계절 은유 그 자체: 홈에 떠도 제3자에겐 계절 위젯으로 보인다. 명시 용어 없음.
// 잉크 토큰·글리프는 앱 Almanac.swift와 동값 사본 — 위젯 타깃을 앱 소스와 얽지 않는다(의도적 중복).
// 서체: Gowun Batang 번들 + 런타임 등록(2026-07-27 — 앱 표제 서체와 통일, 실패 시 세리프 폴백).

import WidgetKit
import SwiftUI
import CoreText

// ── 책력 서체 (App/Almanac.swift AlmanacFont와 동형 — 위젯은 별도 프로세스라 자체 등록) ──
enum WFont {
    static let available: Bool = {
        ["GowunBatang-Regular", "GowunBatang-Bold"].allSatisfy { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { return false }
            return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    /// 모던 표제 서체 — 앱 ThemeFont와 동형(Pretendard otf는 App/Fonts 리소스로 위젯 번들에도 포함)
    static let pretendardAvailable: Bool = {
        ["Pretendard-Regular", "Pretendard-Medium", "Pretendard-SemiBold"].allSatisfy { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "otf") else { return false }
            return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    static func almanac(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if WThemeStore.isModern {
            guard pretendardAvailable else {
                return .system(size: size, weight: weight == .bold ? .semibold : .medium)
            }
            return .custom(weight == .bold ? "Pretendard-SemiBold" : "Pretendard-Medium", size: size)
        }
        guard available else { return .system(size: size, weight: weight, design: .serif) }
        return .custom(weight == .bold ? "GowunBatang-Bold" : "GowunBatang-Regular", size: size)
    }
}

@main
struct TempoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SeasonTodayWidget()
        SeasonLockWidget()     // 잠금화면 직사각형(2026-07-27 개편)
        WeekStripWidget()      // Phase 2 (2026-07-27)
        TodayScheduleWidget()  // Phase 2 (2026-07-27) → 오늘 카드(일정·Input·Output)
        MonthGridWidget()      // 월 캘린더(2026-07-27 개편)
        InputTodayWidget()     // A단계 (2026-08-02) — Input 전폭
        OutputTodayWidget()    // A단계 (2026-08-02) — Output 전폭 + D-day
        CardLockWidget()       // A단계 (2026-08-02) — 잠금화면 Input 요약 + Output 1건
    }
}

// ── 잉크 토큰 — 테마 팔레트 위임(앱 Theme.swift와 동형 사본, Phase 5 2026-07-29) ──
// 테마 키는 스냅샷(theme 필드)으로 전달 — 위젯 프로세스는 렌더 단명이라 첫 접근 1회 읽기,
// 앱이 테마 변경 시 재발행 + reloadAllTimelines로 갱신된다.
struct WPalette {
    let winter, spring, summer, autumn, text, paper, coral, record: Color
    let predictGray, holidayRed, saturday, frost: Color
    let glowWinter, glowSpring, glowSummer, glowAutumn, accent: Color

    private static func dyn(_ light: (Int, Int, Int), _ dark: (Int, Int, Int)) -> Color {
        Color(uiColor: UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255,
                           blue: CGFloat(c.2) / 255, alpha: 1)
        })
    }
    private static func flat(_ c: (Int, Int, Int)) -> Color { dyn(c, c) }   // 모던 = 항상 다크 단일

    /// 기본 — 종전 WInk 리터럴 동값(앱 ThemePalette.standard 사본)
    static let standard = WPalette(
        winter: dyn((0x55, 0x60, 0x6C), (0x98, 0xA6, 0xB4)),
        spring: dyn((0x8F, 0x7C, 0x2E), (0xC2, 0xAC, 0x52)),
        summer: dyn((0x6E, 0x7C, 0x46), (0xA3, 0xB3, 0x78)),
        autumn: dyn((0xA8, 0x4B, 0x38), (0xD6, 0x82, 0x6B)),
        text: dyn((0x2C, 0x2B, 0x27), (0xE8, 0xE6, 0xE1)),
        paper: dyn((0xF1, 0xEE, 0xE6), (0x1C, 0x1B, 0x19)),
        coral: dyn((0xD6, 0x64, 0x4C), (0xE0, 0x7A, 0x63)),
        record: dyn((0x5B, 0x62, 0x6B), (0xA9, 0xB0, 0xB8)),
        predictGray: dyn((0x87, 0x8E, 0x94), (0x9B, 0xA2, 0xA8)),
        holidayRed: dyn((0xC2, 0x45, 0x3C), (0xE0, 0x7A, 0x70)),
        saturday: dyn((0x3D, 0x6B, 0xC4), (0x7F, 0xA4, 0xE8)),
        frost: dyn((0xF2, 0xF3, 0xF0), (0x1A, 0x1B, 0x1B)),
        glowWinter: dyn((0x96, 0xAE, 0xCA), (0xA6, 0xBA, 0xD2)),
        glowSpring: dyn((0xF4, 0xDC, 0xA9), (0xF6, 0xE1, 0xB6)),
        glowSummer: dyn((0xBD, 0xD0, 0x85), (0xC7, 0xD7, 0x97)),
        glowAutumn: dyn((0xD0, 0x8C, 0x86), (0xD7, 0x9D, 0x98)),
        accent: dyn((0x55, 0x60, 0x6C), (0x98, 0xA6, 0xB4))
    )

    /// 모던 — 시안 SSOT §1.2(니어블랙 + 무채 램프 + 다홍 시그널 + 로즈 관례색)
    static let modern = WPalette(
        winter: flat((0xE0, 0x70, 0x5C)),
        spring: flat((0xED, 0xEF, 0xF3)),
        summer: flat((0xA5, 0xAA, 0xB4)),
        autumn: flat((0x87, 0x8C, 0x97)),
        text: flat((0xE9, 0xE7, 0xF0)),
        paper: flat((0x0A, 0x0A, 0x0C)),
        coral: flat((0xE0, 0x70, 0x5C)),
        record: flat((0xA9, 0xAF, 0xC0)),
        predictGray: flat((0xA9, 0xAF, 0xC0)),
        holidayRed: flat((0xEC, 0x8A, 0xA0)),
        saturday: flat((0x7F, 0xA4, 0xE8)),
        frost: flat((0x06, 0x06, 0x07)),
        glowWinter: flat((0xE2, 0x5B, 0x45)),
        glowSpring: flat((0xF5, 0xF6, 0xF8)),
        glowSummer: flat((0xA9, 0xAE, 0xB8)),
        glowAutumn: flat((0x7C, 0x81, 0x8C)),
        accent: flat((0xF2, 0xF3, 0xF6))
    )
}

enum WThemeStore {
    /// 스냅샷 테마 키 1회 읽기 — 위젯 프로세스 수명 = 렌더 1회
    nonisolated(unsafe) static let isModern: Bool = WidgetSnapshot.load()?.theme == "modern"
    static var palette: WPalette { isModern ? .modern : .standard }
}

enum WInk {   // 위젯 타깃 내부 공용(Phase2Widgets가 함께 씀) — 정적 API 유지, 백킹만 위임
    static var winter: Color { WThemeStore.palette.winter }
    static var spring: Color { WThemeStore.palette.spring }
    static var summer: Color { WThemeStore.palette.summer }
    static var autumn: Color { WThemeStore.palette.autumn }
    static var text: Color { WThemeStore.palette.text }
    static var paper: Color { WThemeStore.palette.paper }
    static var coral: Color { WThemeStore.palette.coral }          // ⚠ 기록 표기서 은퇴(2026-07-28)
    static var record: Color { WThemeStore.palette.record }
    static var predictGray: Color { WThemeStore.palette.predictGray }
    static var holidayRed: Color { WThemeStore.palette.holidayRed }
    static var saturday: Color { WThemeStore.palette.saturday }
    static var frost: Color { WThemeStore.palette.frost }
    static var glowWinter: Color { WThemeStore.palette.glowWinter }
    static var glowSpring: Color { WThemeStore.palette.glowSpring }
    static var glowSummer: Color { WThemeStore.palette.glowSummer }
    static var glowAutumn: Color { WThemeStore.palette.glowAutumn }
    /// 구조 악센트(오늘 원·요일 잉크) — 기본 = winter 동값, 모던 = 흰색
    static var accent: Color { WThemeStore.palette.accent }

    static func glow(_ key: String?) -> Color {
        switch key {
        case "winter": glowWinter
        case "spring": glowSpring
        case "summer": glowSummer
        case "autumn": glowAutumn
        default: text
        }
    }

    /// 주말은 숫자색 관례 양보(2026-07-28 사용자 결정) — 공휴일은 스냅샷에 없어 위젯은 요일만
    static func weekdayAccent(_ weekday: Int) -> Color? {
        switch weekday {
        case 1: holidayRed
        case 7: saturday
        default: nil
        }
    }

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

// ── 계절 빛 띠 조각 (앱 seasonBand 문법 — 구간 양 끝만 둥글게, 세로 사그라드는 그래디언트) ──
struct SeasonGlowBand: View {
    let seasonKey: String
    let projected: Bool
    let roundLeft: Bool
    let roundRight: Bool
    let height: CGFloat

    var body: some View {
        // 밑줄형 플랫 — 직각 사각(2026-07-28 5차: 라운드 제거, 사용자 지시)
        Rectangle()
            .fill(WInk.glow(seasonKey).opacity(projected ? 0.25 : 0.5))
        .frame(height: height)
        .padding(.leading, roundLeft ? 2 : 0)
        .padding(.trailing, roundRight ? 2 : 0)
        .allowsHitTesting(false)
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
                    .font(WFont.almanac(24, weight: .bold))
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
                    .font(WFont.almanac(12))
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
                    .font(WFont.almanac(15, weight: .bold))
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
