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
        switch WThemeStore.key {
        // 티켓 = Pretendard 계열. 시안은 IBM Plex Sans KR이지만 번들에 없어, 발권물
        // 그로테스크에 가장 가까운 번들 서체로 대체한다(시안 §3.3-① 대체).
        // ⚠ 포인트컬러(key "modern")는 2026-08-16부터 여기 없다 — 서체도 기본(시스템)이다.
        case "ticket":
            guard pretendardAvailable else {
                return .system(size: size, weight: weight == .bold ? .semibold : .medium)
            }
            return .custom(weight == .bold ? "Pretendard-SemiBold" : "Pretendard-Medium", size: size)
        case "standard":
            guard available else { return .system(size: size, weight: weight, design: .serif) }
            return .custom(weight == .bold ? "GowunBatang-Bold" : "GowunBatang-Regular", size: size)
        default:
            return .system(size: size, weight: weight)   // 기본 = 시스템 서체
        }
    }
}

@main
struct TempoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SeasonTodayWidget()    // 홈 소형만(잠금 원형·인라인은 2026-08-18 은퇴)
        WeekStripWidget()      // Phase 2 (2026-07-27)
        TodayScheduleWidget()  // Phase 2 (2026-07-27) → 오늘 카드(일정·Input·Output)
        TwoDayScheduleWidget() // 오늘·내일 2열 일정(2026-08-18 사용자 지시)
        MonthGridWidget()      // 월 캘린더(2026-07-27 개편)
        InputTodayWidget()     // A단계 (2026-08-02) — Input 전폭
        OutputTodayWidget()    // A단계 (2026-08-02) — Output 전폭 + D-day
        CardLockWidget()       // A단계 (2026-08-02) — 잠금화면 Input 요약 + Output 1건
        TimerActivityWidget()  // 타이머·스톱워치 Live Activity (2026-08-09)
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

    /// 기본 — Apple 기본 UI 계열(앱 ThemePalette.plain 사본, 2026-08-12).
    /// 지면 하나(paper == frost) + 흰 카드 + systemGray 악센트.
    /// ⚠ glow*는 계절광이 아니라 캘린더 계절 밴드 색이다 — 끄면 계절 구분이 사라진다.
    static let plain = WPalette(
        winter: dyn((0x6E, 0x7A, 0x8A), (0x9A, 0xA6, 0xB6)),
        spring: dyn((0x7B, 0x9E, 0x6B), (0xA3, 0xC4, 0x94)),
        summer: dyn((0xC9, 0x97, 0x4B), (0xE0, 0xB4, 0x74)),
        autumn: dyn((0xB5, 0x70, 0x5A), (0xD1, 0x93, 0x7E)),
        text: dyn((0x1C, 0x1C, 0x1E), (0xF2, 0xF2, 0xF7)),
        paper: dyn((0xF2, 0xF2, 0xF7), (0x00, 0x00, 0x00)),
        coral: dyn((0x63, 0x63, 0x66), (0xAE, 0xAE, 0xB2)),
        record: dyn((0x63, 0x63, 0x66), (0xAE, 0xAE, 0xB2)),
        predictGray: dyn((0x8E, 0x8E, 0x93), (0x8E, 0x8E, 0x93)),
        holidayRed: dyn((0xD6, 0x45, 0x3C), (0xFF, 0x6B, 0x60)),
        saturday: dyn((0x3D, 0x6B, 0xC4), (0x7F, 0xA4, 0xE8)),
        frost: dyn((0xF2, 0xF2, 0xF7), (0x00, 0x00, 0x00)),
        // ⚠ 다크 밴드는 검정 지면 위라 밝아야 읽힌다(앱 ThemePalette.plain 주석 참조)
        glowWinter: dyn((0xA8, 0xB4, 0xC2), (0x7A, 0x86, 0x94)),
        glowSpring: dyn((0xA9, 0xC4, 0x9A), (0x7E, 0x9B, 0x70)),
        glowSummer: dyn((0xE0, 0xC4, 0x89), (0xB0, 0x8F, 0x52)),
        glowAutumn: dyn((0xD4, 0xA1, 0x92), (0xA5, 0x70, 0x5F)),
        accent: dyn((0x8E, 0x8E, 0x93), (0x8E, 0x8E, 0x93))
    )

    /// 포인트컬러 — 기본에서 색만 덜어낸 판(앱 ThemePalette.modern 사본, 2026-08-16 개편).
    /// 지면·카드는 plain과 동값이고 계절 3색만 무채 램프다 — 포인트색이 유일한 유채색.
    /// ⚠ 공휴일은 로즈, 토요일은 무채. 유채가 둘이면 포인트가 성립하지 않는다.
    /// ⚠ 포인트색은 스냅샷에서 온다(2026-08-17). 위젯 타깃은 앱의 `PointColor`를 못 보므로
    ///    같은 표를 여기 사본으로 둔다 — 앱 Theme.swift와 값이 갈리면 홈 화면만 색이 어긋난다.
    static func modern(point: String?) -> WPalette {
        let ink: ((Int, Int, Int), (Int, Int, Int))
        let glow: ((Int, Int, Int), (Int, Int, Int))
        switch point {
        case "skyBlue": ink = ((0x2A, 0x8C, 0xC4), (0x62, 0xB8, 0xE8)); glow = ((0x45, 0x9E, 0xD0), (0x52, 0xA8, 0xDC))
        case "green":   ink = ((0x2F, 0x8B, 0x57), (0x5C, 0xB8, 0x82)); glow = ((0x45, 0x9B, 0x68), (0x4E, 0xA5, 0x72))
        case "yellow":  ink = ((0xB0, 0x86, 0x11), (0xE8, 0xBE, 0x4E)); glow = ((0xC2, 0x98, 0x22), (0xD6, 0xAC, 0x3A))
        case "purple":  ink = ((0x7B, 0x52, 0xC4), (0xA8, 0x8A, 0xE8)); glow = ((0x8C, 0x66, 0xD0), (0x96, 0x74, 0xD8))
        case "cobalt":  ink = ((0x2B, 0x52, 0xB8), (0x6D, 0x8F, 0xE8)); glow = ((0x40, 0x66, 0xC6), (0x52, 0x78, 0xD4))
        case "orange":  ink = ((0xD1, 0x6A, 0x1E), (0xF0, 0x94, 0x4A)); glow = ((0xDD, 0x7B, 0x33), (0xE6, 0x86, 0x3E))
        default:        ink = ((0xC9, 0x43, 0x2C), (0xE0, 0x70, 0x5C)); glow = ((0xD4, 0x55, 0x3E), (0xE2, 0x60, 0x4A))
        }
        let inkColor = dyn(ink.0, ink.1)
        return WPalette(
            winter: inkColor,
            spring: dyn((0x9A, 0xA0, 0xA8), (0xC8, 0xCD, 0xD5)),
            summer: dyn((0x71, 0x77, 0x7F), (0x9A, 0xA0, 0xA8)),
            autumn: dyn((0x4A, 0x4F, 0x56), (0x70, 0x75, 0x7C)),
            text: dyn((0x1C, 0x1C, 0x1E), (0xF2, 0xF2, 0xF7)),
            paper: dyn((0xF2, 0xF2, 0xF7), (0x00, 0x00, 0x00)),
            coral: inkColor,
            record: inkColor,
            predictGray: flat((0x8E, 0x8E, 0x93)),
            holidayRed: dyn((0xC2, 0x45, 0x6A), (0xEC, 0x8A, 0xA0)),
            saturday: flat((0x8E, 0x8E, 0x93)),
            frost: dyn((0xF2, 0xF2, 0xF7), (0x00, 0x00, 0x00)),
            glowWinter: dyn(glow.0, glow.1),
            glowSpring: dyn((0xA3, 0xA9, 0xB1), (0xA8, 0xAD, 0xB5)),
            glowSummer: dyn((0x7B, 0x81, 0x8A), (0x84, 0x8A, 0x92)),
            glowAutumn: dyn((0x56, 0x5B, 0x62), (0x62, 0x67, 0x6E)),
            accent: flat((0x8E, 0x8E, 0x93))
        )
    }

    /// 티켓 — 시안 SSOT §3.2 (앱 ThemePalette.ticket 사본).
    /// ⚠ 라이트/다크 동값이다. 발권물은 인쇄물이라 지면이 뒤집히지 않는다.
    static let ticket = WPalette(
        winter: flat((0xA9, 0x32, 0x26)),
        spring: flat((0x3F, 0x7A, 0x44)),
        summer: flat((0x1C, 0x7A, 0x94)),
        autumn: flat((0xB8, 0x86, 0x1F)),
        text: flat((0x22, 0x38, 0x4F)),
        paper: flat((0xFA, 0xFA, 0xF8)),   // 흰 지면 전환(2026-08-18) — 앱 팔레트 동조
        coral: flat((0xA9, 0x32, 0x26)),
        record: flat((0xA9, 0x32, 0x26)),
        predictGray: flat((0x7E, 0x8F, 0xA0)),
        holidayRed: flat((0xA9, 0x32, 0x26)),
        saturday: flat((0x2E, 0x5C, 0x8A)),
        frost: flat((0xFA, 0xFA, 0xF8)),
        glowWinter: flat((0xA9, 0x32, 0x26)),
        glowSpring: flat((0x3F, 0x7A, 0x44)),
        glowSummer: flat((0x1C, 0x7A, 0x94)),
        glowAutumn: flat((0xB8, 0x86, 0x1F)),
        accent: flat((0x22, 0x38, 0x4F))
    )
}

enum WThemeStore {
    /// 스냅샷 테마 키 1회 읽기 — 위젯 프로세스 수명 = 렌더 1회.
    /// ⚠ 종전엔 `isModern: Bool`이었다. 테마가 셋이 되면서 「모던이 아닌 것」이 전부 은필로
    /// 떨어져 새 기본 테마가 은필 지면으로 그려졌다(2026-08-12). 키를 그대로 들고 간다.
    /// ⚠ 스냅샷을 두 번 읽지 않는다 — 파일 I/O라 렌더마다 반복하면 비싸다.
    /// 테마 키와 포인트색을 한 번에 꺼내 둘 다 캐시한다.
    nonisolated(unsafe) private static let snapshot: WidgetSnapshot? = WidgetSnapshot.load()
    nonisolated(unsafe) static let key: String = snapshot?.theme ?? "plain"
    /// 포인트컬러의 선택 색(2026-08-17). nil = 다홍(기존 설치의 스냅샷엔 이 필드가 없다).
    nonisolated(unsafe) static let point: String? = snapshot?.pointColor

    static var palette: WPalette {
        switch key {
        case "modern":   .modern(point: point)
        case "standard": .standard
        case "ticket":   .ticket
        default:         .plain     // 저장값 없음 = 새 설치 = 기본
        }
    }
}

enum WInk {   // 위젯 타깃 내부 공용(Phase2Widgets가 함께 씀) — 정적 API 유지, 백킹만 위임
    /// 위젯 지면(2026-08-18 사용자 지시) — **티켓만 발권물 흰색**으로 뒤집는다.
    /// 앱에서 티켓 지면은 블루그레이 색면이지만, 위젯은 남의 홈 화면 배경 위에 놓이는
    /// 작은 카드라 색면이면 혼자 무겁고 배경과 싸운다. 흰 발권물이 그대로 얹힌 모양이 맞다.
    /// `paper` 계열 자리에 쓴다.
    static var widgetGround: Color {
        WThemeStore.key == "ticket" ? Self.ticketPaper : WThemeStore.palette.paper
    }
    /// 위와 같은 규칙의 `frost` 계열 자리(격자 위젯 — 이번 주·이번 달)
    static var widgetGridGround: Color {
        WThemeStore.key == "ticket" ? Self.ticketPaper : WThemeStore.palette.frost
    }
    /// 발권물 웜 화이트 — 앱 `TicketSpec.ticketPaper`와 동값 사본(위젯 타깃은 앱 소스를 못 본다)
    private static let ticketPaper = Color(red: 0xFA / 255, green: 0xFA / 255, blue: 0xF8 / 255)

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
        WidgetDay(day: .now, season: "winter", title: "겨울", sub: "겨울 3일차",
                  inline: "겨울 3일차", mood: "이번 주는 겨울이에요. 조금은 쉬어가도 괜찮아요.",
                  projected: false)
    }
}

// ── 위젯 ──
struct SeasonTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SeasonToday", provider: SeasonProvider()) { entry in
            SeasonWidgetView(entry: entry)
                .containerBackground(WInk.widgetGround, for: .widget)
        }
        .configurationDisplayName("오늘의 계절")
        .description("지금 계절과 일차를 보여줘요.")
        // 잠금화면 패밀리(원형·인라인) 은퇴(2026-08-18 사용자 지시) — 홈 소형만 남긴다.
        .supportedFamilies([.systemSmall])
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

// 잠금화면 「계절 한 줄」(SeasonLockWidget)은 2026-08-18 사용자 지시로 은퇴.
// 잠금화면에 남는 주기 표면은 「오늘의 카드」 하나뿐이다 — 거기서도 계절명 + 일정만 보인다.
