// 템포루틴 — 테마 시스템 (§8.2.6, 시안 SSOT: ui-mockup/theme/DESIGN.md)
// 테마 = 팔레트(색 토큰 세트) 교체. 구조·치수는 테마가 건드리지 않는다(시안 §0 원칙).
// Ink의 정적 API는 유지하고 백킹만 위임 — 콜사이트 ~280곳(15파일) 무수정.
// 반응성: 정적 캐시(palette) + 루트 `.id(테마)` 리빌드. 뷰별 UserDefaults 읽기 금지
// (드래그 프레임 성능 함정 — repo CLAUDE.md). 제공 방식 = 무료 설정 스위치(테스트 중,
// 2026-07-29 사용자 결정 — IAP 설계 확정 시 §8.2.6 개정과 함께 재검토).

import SwiftUI
import TempoCore
import UIKit

enum AppTheme: String, CaseIterable, Identifiable {
    /// 기본(2026-08-12) — Apple 기본 UI 계열. 장식을 벗고 정보만 남긴 지면.
    /// ⚠ `allCases` 순서 = 테마 탭 카드 순서. 기본이 맨 위다.
    case plain
    /// 은필 — 종전 기본. 2026-08-12부터 씨앗 구매 테마로 내려왔다(MASTER §3.8.1 트랙 분리).
    /// rawValue는 `standard` 그대로 둔다 — 바꾸면 기존 설치의 저장값이 깨진다.
    case standard
    case modern
    /// 티켓(2026-08-14, 시안 SSOT §3) — 색면 위에 놓인 발권물. 경계를 선이 아니라 절단으로 쓴다.
    case ticket

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plain: "기본"
        case .standard: "은필"
        case .modern: "모던"
        case .ticket: "티켓"
        }
    }
}

private extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
    /// 모던 = 항상 다크 단일 외관 — 라이트/다크 동값
    static func flat(_ r: Int, _ g: Int, _ b: Int) -> Color { .rgb(r, g, b) }
}

/// 색 토큰 세트 — Ink가 위임하는 전 항목. 이름·의미는 종전 Ink와 1:1.
struct ThemePalette {
    let winter: Color
    let spring: Color
    let summer: Color
    let autumn: Color
    let text: Color
    let paper: Color
    let coral: Color
    let record: Color
    let danger: Color
    let dim: Color
    let oxide: Color
    let holiday: Color
    let saturday: Color
    let frost: Color
    let glowWinter: Color
    let glowSpring: Color
    let glowSummer: Color
    let glowAutumn: Color
    let surface: Color
    /// 구조 악센트(오늘 원·괘선·요일·카드 테두리) — 시안에서 신설된 토큰.
    /// 기본 테마는 은필 흑청(winter 동값) — 종전 렌더와 동일.
    let accent: Color
}

extension ThemePalette {
    /// 기본 — 종전 Ink 리터럴과 동값 (기본 테마 픽셀 변화 0 원칙)
    static let standard = ThemePalette(
        winter: Color(light: .rgb(0x55, 0x60, 0x6C), dark: .rgb(0x98, 0xA6, 0xB4)),
        spring: Color(light: .rgb(0x8F, 0x7C, 0x2E), dark: .rgb(0xC2, 0xAC, 0x52)),
        summer: Color(light: .rgb(0x6E, 0x7C, 0x46), dark: .rgb(0xA3, 0xB3, 0x78)),
        autumn: Color(light: .rgb(0xA8, 0x4B, 0x38), dark: .rgb(0xD6, 0x82, 0x6B)),
        text: Color(light: .rgb(0x2C, 0x2B, 0x27), dark: .rgb(0xE8, 0xE6, 0xE1)),
        paper: Color(light: .rgb(0xF1, 0xEE, 0xE6), dark: .rgb(0x1C, 0x1B, 0x19)),
        coral: Color(light: .rgb(0xD6, 0x64, 0x4C), dark: .rgb(0xE0, 0x7A, 0x63)),
        record: Color(light: .rgb(0x5B, 0x62, 0x6B), dark: .rgb(0xA9, 0xB0, 0xB8)),
        danger: Color(light: .rgb(0xB2, 0x3A, 0x30), dark: .rgb(0xD0, 0x68, 0x5E)),
        dim: Color(light: Color(red: 44 / 255, green: 43 / 255, blue: 39 / 255).opacity(0.55),
                   dark: Color(red: 232 / 255, green: 230 / 255, blue: 225 / 255).opacity(0.5)),
        oxide: Color(light: .rgb(0x8B, 0x6F, 0x55), dark: .rgb(0xB2, 0x94, 0x77)),
        holiday: Color(light: .rgb(0xC2, 0x45, 0x3C), dark: .rgb(0xE0, 0x7A, 0x70)),
        saturday: Color(light: .rgb(0x3D, 0x6B, 0xC4), dark: .rgb(0x7F, 0xA4, 0xE8)),
        frost: Color(light: .rgb(0xF2, 0xF3, 0xF0), dark: .rgb(0x1A, 0x1B, 0x1B)),
        glowWinter: Color(light: .rgb(0x96, 0xAE, 0xCA), dark: .rgb(0xA6, 0xBA, 0xD2)),
        glowSpring: Color(light: .rgb(0xF4, 0xDC, 0xA9), dark: .rgb(0xF6, 0xE1, 0xB6)),
        glowSummer: Color(light: .rgb(0xBD, 0xD0, 0x85), dark: .rgb(0xC7, 0xD7, 0x97)),
        glowAutumn: Color(light: .rgb(0xD0, 0x8C, 0x86), dark: .rgb(0xD7, 0x9D, 0x98)),
        surface: Color(light: Color.white.opacity(0.55), dark: Color.white.opacity(0.07)),
        accent: Color(light: .rgb(0x55, 0x60, 0x6C), dark: .rgb(0x98, 0xA6, 0xB4))
    )

    /// 모던 (시안 SSOT §1.2) — 도트 그리드 + 무채 램프 + 다홍 단일 시그널.
    /// ⚠ **2026-08-12부터 시스템 라이트/다크를 따라간다**(사용자 지시). 종전 「항상 다크 단일
    /// 외관」 확정을 뒤집는 것 — 라이트는 같은 문법을 밝은 지면으로 뒤집어 옮겼다.
    /// ⚠ 여름·가을 명도차 확대(사용자 지적: 구분이 거의 안 됨). **다크에선 가을을 내리는 게
    /// 아니라 여름을 올려서 벌린다** — 가을을 더 내리면 니어블랙 지면에 묻힌다(시안 실측).
    /// 라이트는 반대로 가을을 내려서 벌린다(흰 지면).
    static let modern = ThemePalette(
        winter: Color(light: .rgb(0xC9, 0x43, 0x2C), dark: .rgb(0xE0, 0x70, 0x5C)),  // 생리 = 다홍
        spring: Color(light: .rgb(0x9E, 0xA4, 0xAE), dark: .rgb(0xED, 0xEF, 0xF3)),
        summer: Color(light: .rgb(0x6F, 0x76, 0x81), dark: .rgb(0xC2, 0xC8, 0xD2)),
        autumn: Color(light: .rgb(0x3D, 0x43, 0x4D), dark: .rgb(0x7C, 0x81, 0x8C)),
        text: Color(light: .rgb(0x10, 0x10, 0x14), dark: .rgb(0xE9, 0xE7, 0xF0)),
        paper: Color(light: .rgb(0xFA, 0xFA, 0xFC), dark: .rgb(0x0A, 0x0A, 0x0C)),
        coral: Color(light: .rgb(0xC9, 0x43, 0x2C), dark: .rgb(0xE0, 0x70, 0x5C)),   // 은퇴 색
        record: Color(light: .rgb(0x5B, 0x62, 0x70), dark: .rgb(0xA9, 0xAF, 0xC0)),
        danger: Color(light: .rgb(0xC2, 0x45, 0x3C), dark: .rgb(0xE0, 0x6D, 0x62)),
        dim: Color(light: Color(red: 0x10 / 255, green: 0x10 / 255, blue: 0x14 / 255).opacity(0.5),
                   dark: Color(red: 0xE9 / 255, green: 0xE7 / 255, blue: 0xF0 / 255).opacity(0.5)),
        oxide: Color(light: .rgb(0x8A, 0x90, 0x99), dark: .rgb(0x9A, 0xA0, 0xAA)),
        holiday: Color(light: .rgb(0xC2, 0x45, 0x6A), dark: .rgb(0xEC, 0x8A, 0xA0)),  // 로즈
        saturday: .flat(0x7F, 0xA4, 0xE8),
        frost: Color(light: .rgb(0xF4, 0xF4, 0xF7), dark: .rgb(0x06, 0x06, 0x07)),
        glowWinter: Color(light: .rgb(0xD4, 0x55, 0x3E), dark: .rgb(0xE2, 0x5B, 0x45)),
        glowSpring: Color(light: .rgb(0xB4, 0xBA, 0xC4), dark: .rgb(0xF5, 0xF6, 0xF8)),
        glowSummer: Color(light: .rgb(0x84, 0x8B, 0x96), dark: .rgb(0xC6, 0xCC, 0xD6)),
        glowAutumn: Color(light: .rgb(0x54, 0x5A, 0x64), dark: .rgb(0x70, 0x75, 0x7F)),
        surface: Color(light: Color.white.opacity(0.72), dark: Color.white.opacity(0.05)),
        accent: Color(light: .rgb(0x10, 0x10, 0x14), dark: .rgb(0xF2, 0xF3, 0xF6))
    )

    /// 티켓 (시안 SSOT §3.2) — 딥 네이비 잉크 · 블루그레이 색면 지면 · 웜 화이트 발권물.
    /// ⚠ 라이트/다크 동값(`.flat`)이다. 발권물은 인쇄물이라 지면이 뒤집히지 않는다 —
    /// 다크에서 흰 티켓을 검게 만들면 이 테마의 앵커가 통째로 사라진다.
    /// ⚠ 계절 4색은 **흰 티켓 위에서 읽히는 값**이다. 유화 지면 위(설정·하루 상세)에서는
    /// 성립하지 않으므로 그 자리 활자는 뷰에서 흰 계열로 덮는다(시안 §3.2 주석).
    static let ticket = ThemePalette(
        winter: .flat(0xA9, 0x32, 0x26),      // 검표 스탬프 레드 = 생리 시그널
        spring: .flat(0x3F, 0x7A, 0x44),      // 잎 그린
        summer: .flat(0x1C, 0x7A, 0x94),      // 시안
        autumn: .flat(0xB8, 0x86, 0x1F),      // 골드
        text: .flat(0x22, 0x38, 0x4F),        // 딥 네이비 잉크
        paper: .flat(0x6E, 0x8A, 0xAC),       // 지면 = 블루그레이 색면
        coral: .flat(0xA9, 0x32, 0x26),       // 은퇴 토큰
        record: .flat(0xA9, 0x32, 0x26),
        danger: .flat(0xA9, 0x32, 0x26),
        dim: Color(red: 0x22 / 255, green: 0x38 / 255, blue: 0x4F / 255).opacity(0.55),
        oxide: .flat(0x7E, 0x8F, 0xA0),       // 과거 = 바랜 블루그레이
        holiday: .flat(0xA9, 0x32, 0x26),
        saturday: .flat(0x2E, 0x5C, 0x8A),
        frost: .flat(0x6E, 0x8A, 0xAC),
        glowWinter: .flat(0xA9, 0x32, 0x26),
        glowSpring: .flat(0x3F, 0x7A, 0x44),
        glowSummer: .flat(0x1C, 0x7A, 0x94),
        glowAutumn: .flat(0xB8, 0x86, 0x1F),
        surface: .flat(0xFA, 0xFA, 0xF8),     // 발권물 = 웜 화이트
        accent: .flat(0x22, 0x38, 0x4F)
    )
}

/// 티켓 전용 상수 — 팔레트 토큰으로 표현되지 않는 값들(시안 §3.2·§3.4).
enum TicketSpec {
    /// 발권물 지면. `surface`와 동값이지만 의미가 달라 이름을 따로 둔다.
    static let ticketPaper = Color.flatRGB(0xFA, 0xFA, 0xF8)
    /// 극소 캡션 라벨 잉크
    static let label = Color.flatRGB(0x7B, 0x8C, 0xA0)
    /// 노치 안쪽 = 다른 탭 지면색 근사. **고정값** — 계절 유화가 교체돼도 흔들리면 안 된다.
    static let notch = Color.flatRGB(0x45, 0x59, 0x6F)
    /// 발권 정보 블록 높이. 이 값이 고정이라 절취선 y가 콘텐츠와 무관해지고,
    /// 그래서 노치를 뚫을 수 있다(시안 §3.4 "노치가 왜 이제 가능한가").
    static let headerHeight: CGFloat = 150
    /// 도판
    static let plateSize = CGSize(width: 94, height: 118)
    /// 세로 스텁 폭
    static let stubWidth: CGFloat = 50

    /// 계절 유화 에셋 이름. 매핑은 `Almanac`의 모티프 규칙과 같다 —
    /// 콜드(nil)는 겨울 그림으로 떨어진다.
    static func plateAsset(for phase: CyclePhase?) -> String {
        switch phase {
        case .follicular: "TicketSpring"
        case .ovulation:  "TicketSummer"
        case .luteal:     "TicketAutumn"
        default:          "TicketWinter"    // menstrual · 콜드(nil)
        }
    }
}

extension Color {
    /// 라이트/다크 동값 RGB — TicketSpec처럼 팔레트 밖에서 쓰는 고정색용
    static func flatRGB(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

// ── 팔레트 밖의 테마 결정 (2026-08-12) ──
// 색으로 표현되지 않는 것들: 서체·질감·계절광 유무·조판 순서 같은 판단.
// **왜 생겼나**: 종전엔 `ThemeStore.current == .modern` 분기가 19곳에 흩어져 있었고, 전부
// 「모던인가 아닌가」 형태였다. 테마가 셋이 되는 순간 새 테마가 전부 「모던이 아닌 것」 =
// 은필 취급을 받아 배경 선화와 계절광이 딸려온다. 조건을 「이 테마가 무엇을 켜는가」로
// 뒤집어 각 테마가 스스로 답하게 한다.
struct ThemeChrome {
    /// 표제·책력 표기 서체 계열. `.system`은 번들 서체를 쓰지 않는다.
    enum TypeFace { case gowun, pretendard, system }
    /// 지면 질감. `.none`은 아무것도 얹지 않는다.
    enum Texture { case motif, dotGrid, none }

    let typeFace: TypeFace
    let texture: Texture
    /// 거대 표제를 아웃라인 타이포로(솔리드 대신)
    let outlineDisplay: Bool
    /// 계절광을 그리는가. false면 지면만 남는다.
    let showsSeasonLight: Bool
    /// 계절광을 계절 불문 무채로
    let neutralSeasonLight: Bool
    /// 시스템 다크에서 배경 레이어를 감쇠하는가. 단일 외관 테마는 감쇠하지 않는다.
    let dimsInDarkMode: Bool
    /// 항상 다크 외관으로 고정하는가
    let forcesDarkAppearance: Bool
    /// 캘린더 상단에서 계절 라인을 거대 표제보다 위에
    let seasonRowFirst: Bool
    /// 오늘 원을 accent로 채우는가(아니면 먹색)
    let todayCircleUsesAccent: Bool
    /// 기록일을 회색 원으로 표시하는가(형광펜 대신). 오늘·기록일 원 뒤 지면색 링도 함께 따라간다.
    let circlesRecordedDays: Bool
    /// 어두운 지면 대비 보정 — 진행 막대·부인공 텍스트 불투명도를 올린다
    let boostsContrast: Bool
    /// 캘린더를 한 장의 발권물로 조판하는가(티켓, 시안 §3.4).
    /// 표제·계절 라인·도판·스텁이 150pt 고정 블록으로 묶이고, 그 아래 절취선에 노치가 뚫린다.
    /// 기존 축(seasonRowFirst 등)으로는 표현할 수 없어 신설했다.
    let ticketChrome: Bool
    /// 지면이 사진(계절 유화)인가. true면 지면 위 보조 활자를 흰 계열로 올린다 —
    /// 기본 규칙(`Ink.text` 50~60%)은 사진 위에서 묻힌다(시안 §3.3-⑥).
    let photographicGround: Bool
}

extension ThemeChrome {
    /// 은필 — 종전 「모던이 아닌」 경로와 동값(픽셀 변화 0 원칙)
    static let silverpoint = ThemeChrome(
        typeFace: .gowun, texture: .motif, outlineDisplay: false,
        showsSeasonLight: true, neutralSeasonLight: false,
        dimsInDarkMode: true, forcesDarkAppearance: false,
        seasonRowFirst: false, todayCircleUsesAccent: false,
        circlesRecordedDays: false, boostsContrast: false,
        ticketChrome: false, photographicGround: false
    )

    /// 기본 — 장식을 전부 끈다(2026-08-12). 계절 정보(글리프·밴드 색)는 팔레트가 담당하므로
    /// 여기서 끄는 건 배경 선화·계절광·책력 서체뿐이다.
    static let plain = ThemeChrome(
        typeFace: .system, texture: .none, outlineDisplay: false,
        showsSeasonLight: false, neutralSeasonLight: false,
        dimsInDarkMode: false, forcesDarkAppearance: false,
        seasonRowFirst: false, todayCircleUsesAccent: false,
        circlesRecordedDays: false, boostsContrast: false,
        ticketChrome: false, photographicGround: false
    )

    /// 모던 — 2026-08-12부터 시스템 라이트/다크를 따라간다(종전 다크 고정 해제).
    /// `dimsInDarkMode`는 계속 false — 계절광이 무채라 다크에서 감쇠할 이유가 없다.
    static let modern = ThemeChrome(
        typeFace: .pretendard, texture: .dotGrid, outlineDisplay: true,
        showsSeasonLight: true, neutralSeasonLight: true,
        dimsInDarkMode: false, forcesDarkAppearance: false,
        seasonRowFirst: true, todayCircleUsesAccent: true,
        circlesRecordedDays: true, boostsContrast: true,
        ticketChrome: false, photographicGround: false
    )

    /// 티켓 — 지면이 계절 유화라 대비 보정을 켜고, 계절광은 얹지 않는다(레퍼런스 지면은 평면).
    /// `seasonRowFirst`는 false: 티켓 조판에서는 표제가 위, 계절 라인이 아래다.
    static let ticket = ThemeChrome(
        typeFace: .pretendard, texture: .none, outlineDisplay: false,
        showsSeasonLight: false, neutralSeasonLight: false,
        dimsInDarkMode: false, forcesDarkAppearance: false,
        seasonRowFirst: false, todayCircleUsesAccent: true,
        circlesRecordedDays: false, boostsContrast: true,
        ticketChrome: true, photographicGround: true
    )
}

extension AppTheme {
    /// ⚠ 새 테마를 추가하면 여기와 `chrome` 양쪽에 케이스를 더해야 한다. switch라 빠뜨리면
    /// 컴파일이 막는다 — 종전 삼항 연산자(`== .modern ? :`)는 조용히 은필로 떨어뜨렸다.
    var palette: ThemePalette {
        switch self {
        case .plain: .plain
        case .standard: .standard
        case .modern: .modern
        case .ticket: .ticket
        }
    }

    var chrome: ThemeChrome {
        switch self {
        case .plain: .plain
        case .standard: .silverpoint
        case .modern: .modern
        case .ticket: .ticket
        }
    }
}

extension ThemePalette {
    /// 기본 — Apple 기본 UI 계열 (2026-08-12, 시안 `ui-mockup/theme/app-plain.html`).
    /// 지면을 하나로 둔다(paper == frost) — 캘린더만 다른 색이면 탭을 옮길 때 배경이 튄다.
    /// 라이트 = systemGroupedBackground 위 흰 카드, 다크 = 검정 위 #1C1C1E 카드(iOS 관례).
    static let plain = ThemePalette(
        winter: Color(light: .rgb(0x6E, 0x7A, 0x8A), dark: .rgb(0x9A, 0xA6, 0xB6)),
        spring: Color(light: .rgb(0x7B, 0x9E, 0x6B), dark: .rgb(0xA3, 0xC4, 0x94)),
        summer: Color(light: .rgb(0xC9, 0x97, 0x4B), dark: .rgb(0xE0, 0xB4, 0x74)),
        autumn: Color(light: .rgb(0xB5, 0x70, 0x5A), dark: .rgb(0xD1, 0x93, 0x7E)),
        text: Color(light: .rgb(0x1C, 0x1C, 0x1E), dark: .rgb(0xF2, 0xF2, 0xF7)),
        paper: Color(light: .rgb(0xF2, 0xF2, 0xF7), dark: .rgb(0x00, 0x00, 0x00)),
        coral: Color(light: .rgb(0x63, 0x63, 0x66), dark: .rgb(0xAE, 0xAE, 0xB2)),   // 은퇴 토큰
        record: Color(light: .rgb(0x63, 0x63, 0x66), dark: .rgb(0xAE, 0xAE, 0xB2)),
        danger: Color(light: .rgb(0xD6, 0x45, 0x3C), dark: .rgb(0xFF, 0x6B, 0x60)),
        dim: Color(light: .rgb(0xAE, 0xAE, 0xB2), dark: .rgb(0x8E, 0x8E, 0x93)),
        oxide: Color(light: .rgb(0x8E, 0x8E, 0x93), dark: .rgb(0x8E, 0x8E, 0x93)),
        holiday: Color(light: .rgb(0xD6, 0x45, 0x3C), dark: .rgb(0xFF, 0x6B, 0x60)),
        saturday: Color(light: .rgb(0x3D, 0x6B, 0xC4), dark: .rgb(0x7F, 0xA4, 0xE8)),
        frost: Color(light: .rgb(0xF2, 0xF2, 0xF7), dark: .rgb(0x00, 0x00, 0x00)),
        // ⚠ glow*는 계절광(장식)이 아니라 **캘린더 계절 밑줄 색**이다. 정보 구조라 끄면
        // 계절 구분이 통째로 사라진다(2026-08-12 시안 1차 결함). 장식인 계절광은 SeasonLight
        // 자체를 chrome.showsSeasonLight로 끈다.
        // ⚠⚠ 밴드는 **지면 대비**로 읽힌다. 라이트는 흰 지면 위라 「옅게」가 맞지만, 다크는
        // 검정 위라 같은 방향으로 어둡게 잡으면 밴드가 사라진다(2026-08-12 다크 시안에서 실측).
        // 다크 값은 계절색보다 조금 어두운 정도까지만 내린다.
        glowWinter: Color(light: .rgb(0xA8, 0xB4, 0xC2), dark: .rgb(0x7A, 0x86, 0x94)),
        glowSpring: Color(light: .rgb(0xA9, 0xC4, 0x9A), dark: .rgb(0x7E, 0x9B, 0x70)),
        glowSummer: Color(light: .rgb(0xE0, 0xC4, 0x89), dark: .rgb(0xB0, 0x8F, 0x52)),
        glowAutumn: Color(light: .rgb(0xD4, 0xA1, 0x92), dark: .rgb(0xA5, 0x70, 0x5F)),
        surface: Color(light: .rgb(0xFF, 0xFF, 0xFF), dark: .rgb(0x1C, 0x1C, 0x1E)),
        accent: .flat(0x8E, 0x8E, 0x93)          // systemGray — 괘선·요일·테두리를 배경으로 물린다
    )
}

/// 현재 팔레트의 정적 캐시. 변경 경로는 둘뿐 — 앱 시작(TempoRoutineApp.init)과
/// 설정의 테마 선택(쓰기 전 apply → AppStorage 갱신 → 루트 .id 리빌드).
enum ThemeStore {
    static let storageKey = "appTheme"

    // 쓰기는 메인 스레드 한정(앱 init·설정 선apply·루트 onChange — 전부 MainActor 문맥),
    // 읽기는 뷰 body뿐 — Swift 6 strict의 전역 가변 상태 경고를 명시 해제한다.
    // @MainActor 격리는 Ink 정적 API까지 전파돼 콜사이트 무수정 원칙과 충돌(기각).
    nonisolated(unsafe) private(set) static var current: AppTheme = .plain
    nonisolated(unsafe) private(set) static var palette: ThemePalette = .plain
    nonisolated(unsafe) private(set) static var chrome: ThemeChrome = .plain

    static func apply(_ rawValue: String?) {
        let theme = rawValue.flatMap(AppTheme.init(rawValue:)) ?? .plain
        current = theme
        palette = theme.palette
        chrome = theme.chrome
    }
}
