// 템포루틴 — 테마 7일 무료 체험 (2026-08-19 사용자 결정, MASTER §3.8.1 개정)
// 시작 = 신규는 온보딩 완료, 기존 설치는 업데이트 후 첫 실행(RootTabView가 기록).
// 체험 중엔 씨앗 테마 포함 전 테마 적용 가능. 종료 후 첫 실행에 기본·은필 중 하나를
// 골라 영구 보유한다(종료 시트 = RootTabView 한 곳 — 2026-08-12 시트 원칙).
// 시작 시각은 기기별 UserDefaults — 원장(SeedLedgerDTO)에 섞지 않는다. 체험은 기간 상태지
// 재화가 아니고, 병합 맵에 넣으면 "늘기만 하는 맵" 법칙(교환·결합·멱등)에 안 맞는다.
// 종료 시트의 은필 선택만 grandfather(0원)로 원장에 적혀 기기 간 전파된다.

import Foundation

enum ThemeTrial {
    static let startKey = "themeTrialStart"
    /// 종료 시트에서 테마를 골랐는가 — 시트 1회 보장(기기별)
    static let resolvedKey = "themeTrialResolved"
    /// 온보딩 테마 선택(rawValue) — 종료 시트의 기본 선택값으로 잇는다("이전 거랑 연결")
    static let choiceKey = "onboardingThemeChoice"
    static let lengthDays = 7

    /// 시작 기록 — 최초 1회만. 이미 기록돼 있으면 무해(멱등).
    static func beginIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: startKey) == nil else { return }
        defaults.set(Date.now, forKey: startKey)
    }

    static var start: Date? { UserDefaults.standard.object(forKey: startKey) as? Date }

    private static var end: Date? {
        start.flatMap { Calendar.current.date(byAdding: .day, value: lengthDays, to: $0) }
    }

    /// 체험 중인가 — 시작 기록이 없으면(온보딩 전) false.
    static var isActive: Bool {
        guard let end else { return false }
        return Date.now < end
    }

    /// 남은 일수(올림, 표기용). 마지막 날도 「1일 남음」으로 읽힌다.
    static var daysLeft: Int {
        guard let end else { return 0 }
        let seconds = end.timeIntervalSince(.now)
        guard seconds > 0 else { return 0 }
        return max(1, Int((seconds / 86_400).rounded(.up)))
    }

    static var isResolved: Bool { UserDefaults.standard.bool(forKey: resolvedKey) }
    static func resolve() { UserDefaults.standard.set(true, forKey: resolvedKey) }

    /// 종료 시트를 띄울 조건 — 체험이 실제로 있었고, 끝났고, 아직 안 골랐을 때.
    /// 은필 기보유(구매·승계) 생략 판정은 호출부(RootTabView)가 Seeds와 조합한다.
    static var needsResolution: Bool {
        start != nil && !isActive && !isResolved
    }
}
