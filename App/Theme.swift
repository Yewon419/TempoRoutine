// 템포루틴 — 테마 시스템 (§8.2.6, 시안 SSOT: ui-mockup/theme/DESIGN.md)
// 테마 = 팔레트(색 토큰 세트) 교체. 구조·치수는 테마가 건드리지 않는다(시안 §0 원칙).
// Ink의 정적 API는 유지하고 백킹만 위임 — 콜사이트 ~280곳(15파일) 무수정.
// 반응성: 정적 캐시(palette) + 루트 `.id(테마)` 리빌드. 뷰별 UserDefaults 읽기 금지
// (드래그 프레임 성능 함정 — repo CLAUDE.md). 제공 방식 = 무료 설정 스위치(테스트 중,
// 2026-07-29 사용자 결정 — IAP 설계 확정 시 §8.2.6 개정과 함께 재검토).

import SwiftUI
import UIKit

enum AppTheme: String, CaseIterable, Identifiable {
    case standard
    case modern

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: "기본"
        case .modern: "모던"
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

    /// 모던 (시안 SSOT §1.2) — 니어블랙 + 무채 램프 + 다홍 단일 시그널. 항상 다크 단일 외관.
    static let modern = ThemePalette(
        winter: .flat(0xE0, 0x70, 0x5C),          // 겨울(생리) = 다홍 시그널
        spring: .flat(0xED, 0xEF, 0xF3),          // 봄 흰 → 여름 회 → 가을 짙은 회 무채 램프
        summer: .flat(0xA5, 0xAA, 0xB4),
        autumn: .flat(0x87, 0x8C, 0x97),
        text: .flat(0xE9, 0xE7, 0xF0),
        paper: .flat(0x0A, 0x0A, 0x0C),
        coral: .flat(0xE0, 0x70, 0x5C),           // 은퇴 색 — 사용처 0, 다홍 동값 보관
        record: .flat(0xA9, 0xAF, 0xC0),          // 기록 = 달빛 회색
        danger: .flat(0xE0, 0x6D, 0x62),
        dim: Color(red: 0xE9 / 255, green: 0xE7 / 255, blue: 0xF0 / 255).opacity(0.5),
        oxide: .flat(0x9A, 0xA0, 0xAA),           // 과거 일정도 회색 통일(산화 갈색 은퇴)
        holiday: .flat(0xEC, 0x8A, 0xA0),         // 관례 빨강 → 로즈(다홍 = 생리 전용 사수)
        saturday: .flat(0x7F, 0xA4, 0xE8),
        frost: .flat(0x06, 0x06, 0x07),
        glowWinter: .flat(0xE2, 0x5B, 0x45),
        glowSpring: .flat(0xF5, 0xF6, 0xF8),
        glowSummer: .flat(0xA9, 0xAE, 0xB8),
        glowAutumn: .flat(0x7C, 0x81, 0x8C),
        surface: Color.white.opacity(0.05),
        accent: .flat(0xF2, 0xF3, 0xF6)           // 구조 악센트 = 흰색
    )
}

/// 현재 팔레트의 정적 캐시. 변경 경로는 둘뿐 — 앱 시작(TempoRoutineApp.init)과
/// 설정의 테마 선택(쓰기 전 apply → AppStorage 갱신 → 루트 .id 리빌드).
enum ThemeStore {
    static let storageKey = "appTheme"

    // 쓰기는 메인 스레드 한정(앱 init·설정 선apply·루트 onChange — 전부 MainActor 문맥),
    // 읽기는 뷰 body뿐 — Swift 6 strict의 전역 가변 상태 경고를 명시 해제한다.
    // @MainActor 격리는 Ink 정적 API까지 전파돼 콜사이트 무수정 원칙과 충돌(기각).
    nonisolated(unsafe) private(set) static var current: AppTheme = .standard
    nonisolated(unsafe) private(set) static var palette: ThemePalette = .standard

    static func apply(_ rawValue: String?) {
        let theme = rawValue.flatMap(AppTheme.init(rawValue:)) ?? .standard
        current = theme
        palette = theme == .modern ? .modern : .standard
    }
}
