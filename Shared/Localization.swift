// 템포루틴 — 로컬라이제이션 도구 (2026-08-20 en·ja 이관 개시 → 08-22 단일 경로로 재설계)
// 계약 SSOT = `..\로컬라이제이션.md`. 여기는 그 규칙의 코드 쪽 한 조각.
// **Shared 소속** — 위젯 익스텐션도 같은 규칙을 쓴다. 각 타깃이 제 번들 카탈로그를 본다
// (앱 = App/Localizable.xcstrings, 위젯 = Widgets/Localizable.xcstrings).
//
// ── 왜 「번들 덮어쓰기」인가 (2026-08-22 베타 "3개국어" 혼재 사고) ──
// 화면 문자열이 번역을 타는 경로가 **셋**이다: ① SwiftUI `Text("리터럴")` ② `String(localized:)`
// ③ 우리 `Loc.str`. 처음엔 ①은 환경 로케일, ③은 명시 번들로 따로 잡았는데, 둘이 서로 다른
// 언어를 보는 순간이 생겼다(리빌드 타이밍·시트 환경 상속·AppleLanguages 캐시). 그래서 한
// 화면에 영어·일본어·한국어가 같이 떴다.
// 해법: **세 경로가 전부 `Bundle.main.localizedString(forKey:)`로 모인다**는 점을 쓴다.
// `Bundle.main`의 클래스를 `LocalizedBundle`로 바꿔(object_setClass) 그 메서드 하나를 가로채면,
// 어느 경로로 들어오든 선택 언어의 `.lproj`를 본다. 런타임 언어 전환의 표준 기법이다.
//
// 규칙은 그대로다: 보간 없는 화면 문자열은 한글 리터럴이 곧 키. 값으로 흐르는 문구(switch·배열·
// 튜플·알림 본문)는 만드는 자리에서 `Loc.str`. 보간은 `Loc.fmt` + 명시 포맷 키.

import Foundation
import ObjectiveC
import SwiftUI

/// 앱 언어 선택(2026-08-21 — 온보딩 0단계·설정). 기본값은 **기기 설정 따름**이다.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case ko
    case en
    case ja
    /// 간체 중국어 — rawValue가 곧 `.lproj` 폴더 이름이자 로케일 식별자라 `zh-Hans` 표기를 쓴다.
    /// 번체(zh-Hant)는 이번 범위가 아니다(글자 변환이 아니라 어휘가 달라 별도 번역이 필요하다).
    case zhHans = "zh-Hans"

    var id: String { rawValue }

    /// 선택지 이름은 **그 언어로** 적는다(endonym) — 지금 화면이 무슨 언어든 읽을 수 있어야 한다.
    var nativeName: String {
        switch self {
        case .system: "시스템"      // 표시 시 로컬라이즈(키 = 이 문자열) — 현재 피커는 별도 키를 쓴다
        case .ko: "한국어"
        case .en: "English"
        case .ja: "日本語"
        case .zhHans: "简体中文"
        }
    }

    static let storageKey = "appLanguage"
    /// 다음 실행부터 시스템도 이 언어로 앱을 띄우도록 표준 키에 적는다(설정 > 앱 > 언어와 같은 자리).
    static let systemOverrideKey = "AppleLanguages"
}

/// `Bundle.main`에 덧씌우는 클래스 — 선택 언어가 있으면 그 `.lproj`에서 찾는다.
/// `@unchecked Sendable`: Bundle 자체가 Sendable이고 우리는 상태를 더하지 않는다.
private final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let override = Loc.overrideBundle {
            return override.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

enum Loc {
    // ── 상태 — 진실은 UserDefaults(appLanguage)다. 캐시는 그 raw 값으로 무효화된다. ──
    // 읽을 때마다 defaults를 보는 이유: 언어를 고른 뷰의 onChange가 루트 리빌드에 쓸려 안 불릴 수
    // 있었다(2026-08-22). 정적 캐시가 defaults와 어긋나는 창을 없앤다.
    nonisolated(unsafe) private static var cachedRaw: String?
    nonisolated(unsafe) private static var cachedLanguage: AppLanguage = .system
    nonisolated(unsafe) private static var cachedOverride: Bundle?
    nonisolated(unsafe) private static var cachedLocale: Locale = .current
    nonisolated(unsafe) private static var installed = false

    /// App Group 기본값 — **한 번만 만든다.** 문자열 조회마다 `UserDefaults(suiteName:)`을 새로
    /// 생성하던 것이 "적용이 느리다"(2026-08-22 베타)의 한 축이었다(화면당 수백 회 조회).
    private static let sharedDefaults = UserDefaults(suiteName: WidgetShared.appGroupID)

    private static var storedRaw: String? {
        // 위젯 프로세스에는 기본 도메인 값이 없다 — App Group을 먼저 본다(스냅샷과 같은 그룹)
        sharedDefaults?.string(forKey: AppLanguage.storageKey)
            ?? UserDefaults.standard.string(forKey: AppLanguage.storageKey)
    }

    private static func sync() {
        if !installed {
            installed = true
            // Bundle.main의 클래스를 바꾼다 — 프로세스당 1회. 앱·위젯 각자 자기 Bundle.main.
            object_setClass(Bundle.main, LocalizedBundle.self)
        }
        let raw = storedRaw
        guard raw != cachedRaw || cachedRaw == nil else { return }
        cachedRaw = raw
        let lang = raw.flatMap(AppLanguage.init(rawValue:)) ?? .system
        cachedLanguage = lang
        switch lang {
        case .system:
            cachedOverride = nil
            cachedLocale = .current
        default:
            cachedOverride = Bundle.main.path(forResource: lang.rawValue, ofType: "lproj")
                .flatMap(Bundle.init(path:))
            cachedLocale = Locale(identifier: lang.rawValue)
        }
    }

    static var language: AppLanguage { sync(); return cachedLanguage }
    /// 선택 언어의 `.lproj` 번들. `.system`이면 nil = 기본 경로(기기 언어).
    static var overrideBundle: Bundle? { sync(); return cachedOverride }
    /// SwiftUI 트리에 `.environment(\.locale, Loc.locale)` — **서식**(날짜·숫자)이 이걸 따른다.
    /// 문자열 조회는 위 번들 덮어쓰기가 담당하므로 이 값에 의존하지 않는다.
    static var locale: Locale { sync(); return cachedLocale }

    /// 사용자가 고를 때. 저장까지 한다(캐시는 다음 읽기에서 defaults로 맞춰진다).
    static func apply(_ new: AppLanguage, persist: Bool = true) {
        guard persist else { sync(); return }
        let defaults = UserDefaults.standard
        defaults.set(new.rawValue, forKey: AppLanguage.storageKey)
        if new == .system {
            defaults.removeObject(forKey: AppLanguage.systemOverrideKey)
        } else {
            defaults.set([new.rawValue], forKey: AppLanguage.systemOverrideKey)
        }
        // 위젯은 **별도 프로세스**라 앱의 기본 도메인을 못 본다 — App Group에도 적는다
        sharedDefaults?.set(new.rawValue, forKey: AppLanguage.storageKey)
        sync()
    }

    /// 앱 시작 1회 — 번들 덮어쓰기 설치 + 캐시 준비. 위젯은 첫 읽기에서 같은 일을 한다.
    static func restore() { sync() }

    /// 로컬라이즈 문자열 — 값으로 흐르는 문구(switch·배열·튜플·알림 본문)는 만드는 자리에서 이걸 쓴다.
    /// `Bundle.main` 경로를 타므로 SwiftUI 리터럴과 **같은 언어**가 보장된다.
    static func str(_ key: String) -> String {
        sync()
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    /// **앱이 만든 한국어 문구를 담은 String**을 다시 번역 키로 되돌린다(TempoCore 산출 등).
    /// ⚠ 사용자가 입력한 내용에는 절대 쓰지 않는다 — 사용자가 적은 「완료」가 「Done」으로 둔갑한다.
    static func key(_ appCopy: String) -> LocalizedStringKey { LocalizedStringKey(appCopy) }

    /// 뷰 밖(알림 본문·위젯 스냅샷 합성 등)에서 같은 일을 한다.
    static func text(_ appCopy: String) -> String { str(appCopy) }

    /// 포맷 인자가 있는 로컬라이즈 문자열. `key`는 포맷 지정자를 포함한 **한글 키**(예: `"%lld일차"`).
    /// 어순이 바뀌면 `%1$@`·`%2$lld` 위치 지정자. 리터럴 퍼센트는 `%%`.
    static func fmt(_ key: String, _ args: CVarArg...) -> String {
        String(format: str(key), arguments: args)
    }

    /// 공휴일 이름 — TempoCore는 순수 모듈이라 대체공휴일을 「대체공휴일(설날)」로 **합성해서**
    /// 돌려준다. 합성된 문자열은 카탈로그 키가 아니므로 앱에서 풀어 다시 합성한다.
    static func holidayName(_ raw: String) -> String {
        let prefix = "대체공휴일("
        guard raw.hasPrefix(prefix), raw.hasSuffix(")") else { return text(raw) }
        let base = String(raw.dropFirst(prefix.count).dropLast())
        return fmt("대체공휴일(%1$@)", text(base))
    }

    // ── 날짜 서식도 선택 언어를 따른다(2026-08-22 베타 피드백 — 영어 앱에 날짜만 기기 언어) ──
    /// `.formatted(.dateTime…)`는 Locale.current(기기)를 본다 — 이걸로 바꿔 쓴다.
    static var dateTime: Date.FormatStyle { Date.FormatStyle.dateTime.locale(locale) }
    /// `.formatted(date: .omitted, time: .shortened)` 대체
    static var shortTime: Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
    }
    /// 월 이름 — ko 「8월」· en 「Aug」· ja·zh 「8月」. 종전 「%@월」 키는 영어에서 「Month 8」이 되어
    /// 표제가 「Mon / th 8」로 꺾였다. 달력 심볼은 언어가 제 형식을 안다.
    static func monthName(_ month: Int) -> String {
        var cal = Calendar.current
        cal.locale = locale
        return cal.shortStandaloneMonthSymbols[max(0, min(11, month - 1))]
    }
    /// 요일 한 글자 — 일요일부터(인덱스 0 = 일). 종전 「일 월 화…」 리터럴 배열 대체.
    static func veryShortWeekdaySymbols(_ calendar: Calendar) -> [String] {
        var cal = calendar
        cal.locale = locale
        return cal.veryShortStandaloneWeekdaySymbols
    }
}
