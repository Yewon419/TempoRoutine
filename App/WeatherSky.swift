// 템포루틴 — 날씨 테마 하늘 코어 (시안 SSOT: ui-mockup/theme/DESIGN.md §5, 2026-08-19 이식)
// 지면 = 오늘의 하늘: 조건 4(맑음/구름/비/눈) × 시간대 3(낮/노을/밤) = 12상태 3스톱
// 그라데이션. 값은 시안 app-base.html [data-wx][data-dp]와 동값(§5.2 — 시안이 SSOT).
// Phase ①은 그라데이션 하늘만 — 글로우·구름·파티클은 Phase ③, WeatherKit·위치는 Phase ②.

import SwiftUI

/// 날씨 조건 4분류 — WeatherKit의 세분 조건은 Phase ②에서 이 4개로 접는다(§5.7).
enum WxCondition: String, CaseIterable, Identifiable {
    case clear, cloud, rain, snow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clear: "맑음"
        case .cloud: "구름"
        case .rain: "비"
        case .snow: "눈"
        }
    }
}

/// 시간대 3분류 — **시간대가 모드 역할**을 한다(밤 하늘이 곧 다크, §5.1).
enum Daypart: String, CaseIterable {
    case day, dusk, night

    /// 기기 시계 근사(§5.5) — Phase ②에서 WeatherKit 일출·일몰로 경계를 교체한다.
    static func now(_ date: Date = .now) -> Daypart {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 7..<17: return .day
        case 17..<20: return .dusk
        default: return .night
        }
    }
}

/// 하늘 12상태 — 위→아래(천정→지평선) 3스톱. 하단 명도 캡: 화이트 잉크 담보를 위해
/// 가장 밝은 상태(눈×낮)도 하단 #AEBEC9까지만(§5.2).
enum SkySpec {
    static func stops(_ condition: WxCondition, _ daypart: Daypart) -> (a: Color, b: Color, c: Color) {
        func rgb(_ v: (Int, Int, Int)) -> Color {
            Color(red: Double(v.0) / 255, green: Double(v.1) / 255, blue: Double(v.2) / 255)
        }
        let hex: ((Int, Int, Int), (Int, Int, Int), (Int, Int, Int))
        switch (condition, daypart) {
        case (.clear, .day):   hex = ((0x3D, 0x7B, 0xBF), (0x6F, 0xA8, 0xDC), (0x8F, 0xBC, 0xE0))
        case (.clear, .dusk):  hex = ((0x2E, 0x48, 0x78), (0x7A, 0x62, 0x88), (0xDE, 0x85, 0x58))
        case (.clear, .night): hex = ((0x0B, 0x12, 0x20), (0x1C, 0x2A, 0x44), (0x2E, 0x42, 0x60))
        case (.cloud, .day):   hex = ((0x5C, 0x6E, 0x80), (0x82, 0x96, 0xA8), (0x9D, 0xB0, 0xBE))
        case (.cloud, .dusk):  hex = ((0x3E, 0x44, 0x58), (0x5E, 0x5A, 0x70), (0x8A, 0x6E, 0x72))
        case (.cloud, .night): hex = ((0x10, 0x14, 0x1C), (0x22, 0x2A, 0x36), (0x32, 0x3C, 0x4A))
        case (.rain, .day):    hex = ((0x46, 0x58, 0x6A), (0x64, 0x76, 0x86), (0x7E, 0x90, 0x9E))
        case (.rain, .dusk):   hex = ((0x33, 0x38, 0x50), (0x4E, 0x4A, 0x62), (0x6A, 0x5A, 0x68))
        case (.rain, .night):  hex = ((0x0C, 0x11, 0x1A), (0x1C, 0x24, 0x2F), (0x2A, 0x34, 0x40))
        case (.snow, .day):    hex = ((0x6E, 0x82, 0x96), (0x93, 0xA6, 0xB6), (0xAE, 0xBE, 0xC9))
        case (.snow, .dusk):   hex = ((0x4A, 0x54, 0x68), (0x6E, 0x72, 0x84), (0x8E, 0x84, 0x94))
        case (.snow, .night):  hex = ((0x13, 0x1A, 0x26), (0x26, 0x30, 0x3E), (0x38, 0x44, 0x4F))
        }
        return (rgb(hex.0), rgb(hex.1), rgb(hex.2))
    }
}

/// 현재 하늘 상태 — Phase ①은 조건 = 확인용 스위처(기본 맑음), 시간대 = 기기 시계
/// (스위처로 고정 가능 — 12상태를 시각과 무관하게 확인하는 자리).
/// Phase ②에서 조건이 WeatherKit로 교체된다(실패 시 폴백: 마지막 값 → 맑음, §5.7).
/// ThemeStore와 같은 정적 캐시 규칙 — 쓰기는 메인(설정 스위처·앱 시작), 읽기는 뷰 body뿐.
enum WxState {
    static let conditionKey = "wxDebugCondition"
    static let daypartKey = "wxDebugDaypart"

    nonisolated(unsafe) private(set) static var condition: WxCondition = .clear
    nonisolated(unsafe) private(set) static var daypartOverride: Daypart?

    static var daypart: Daypart { daypartOverride ?? .now() }

    /// - Parameter daypartRaw: 빈 문자열·nil = 시계 따름
    static func apply(conditionRaw: String?, daypartRaw: String?) {
        condition = conditionRaw.flatMap(WxCondition.init(rawValue:)) ?? .clear
        daypartOverride = daypartRaw.flatMap(Daypart.init(rawValue:))
    }

    /// WeatherKit 실측이 조건만 갱신하는 경로(Phase ②) — 시간대 고정은 건드리지 않는다.
    /// 저장까지 해서 다음 실행의 「마지막 값」 폴백(§5.7)이 된다. 설정 스위처와 같은 키라
    /// 스위처에도 실측값이 비친다 — 마지막에 쓴 쪽이 이기는 단일 값.
    static func applyCondition(_ new: WxCondition) {
        condition = new
        UserDefaults.standard.set(new.rawValue, forKey: conditionKey)
    }
}

/// 하늘 지면 — 전 화면 ZStack 최하층(§5.3-1). 스크롤과 무관하게 고정.
/// `veil`(캘린더 14%)은 낮 하늘 위 격자 흰 숫자 대비를 되찾는 자리.
struct WeatherSky: View {
    var veil: Double = 0

    var body: some View {
        let condition = WxState.condition
        let daypart = WxState.daypart
        let s = SkySpec.stops(condition, daypart)
        LinearGradient(colors: [s.a, s.b, s.c], startPoint: .top, endPoint: .bottom)
            // 이펙트 순서 = 시안 DOM(§5.4): 글로우 → 구름 → 파티클, 베일은 맨 위(콘텐츠 아래)
            .overlay { WeatherGlow(condition: condition, daypart: daypart) }
            .overlay { WeatherClouds(condition: condition, daypart: daypart) }
            .overlay { WeatherParticles(condition: condition, daypart: daypart) }
            .overlay(Color.black.opacity(veil))
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            // 실날씨 갱신(Phase ②) — 하늘이 필요할 때만 위치·네트워크를 쓴다.
            // 갱신값은 다음 등장(탭 전환)부터 반영 — 지면이 눈앞에서 바뀌지 않는 게 오히려 낫다.
            .task { await WxProvider.shared.refreshIfNeeded() }
    }
}
