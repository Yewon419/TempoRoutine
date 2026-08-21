// 템포루틴 — 로컬라이제이션 도구 (2026-08-20, en·ja 이관 개시)
// 계약 SSOT = `..\로컬라이제이션.md`. 여기는 그 규칙의 코드 쪽 한 조각.
// **Shared 소속** — 위젯 익스텐션도 같은 규칙을 쓴다. 각 타깃이 제 번들 카탈로그를 본다
// (앱 = App/Localizable.xcstrings, 위젯 = Widgets/Localizable.xcstrings).
//
// 규칙 ① **보간 없는 화면 문자열은 한글 리터럴을 그대로 키로 쓴다.** SwiftUI가 `Text`·`Button`·
//   `Label` 등에서 리터럴을 `LocalizedStringKey`로 받으므로 소스를 고칠 필요가 없다.
//   번역은 `Localizable.xcstrings`에 그 한글을 키로 넣는다.
//
// 규칙 ② **보간이 있으면 이 헬퍼로 명시 포맷을 쓴다.** 이유는 환경이다 — Windows라 Xcode의
//   문자열 추출(빌드 시 카탈로그 자동 갱신)을 돌릴 수 없어 카탈로그를 손으로 쓴다. 그런데
//   보간 리터럴의 런타임 키는 보간부를 포맷 지정자로 바꾼 문자열(Int → %lld, String → %@)이라
//   소스만 보고 단정할 수 없다. 포맷을 소스에 직접 적으면 키가 소스와 글자 그대로 같아지고,
//   `tools/loc_audit.py`가 카탈로그와 1:1로 대조할 수 있다.
//
// ⚠ `String` 값을 받는 API(`Text(변수)`·`accessibilityLabel(String)`)는 로컬라이즈되지 않는다.
//   변수로 넘길 문구는 만드는 자리에서 `Loc.str`로 뽑아 둘 것 — 앱 언어 선택까지 함께 탄다.

import Foundation
import SwiftUI

/// 앱 언어 선택(2026-08-21 대표님 요청 — 온보딩 첫 화면). 기본값은 **기기 설정 따름**이다.
/// 시스템 언어를 그대로 쓰는 게 애플 표준이고(설정 > 앱 > 언어), 여기서 고르는 건 그 위의 덮개다.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, ko, en, ja

    var id: String { rawValue }

    /// 선택지 이름은 **그 언어로** 적는다 — 지금 화면이 무슨 언어든 읽을 수 있어야 한다.
    var nativeName: String {
        switch self {
        case .system: "시스템"      // 표시 시 로컬라이즈(키 = 이 문자열)
        case .ko: "한국어"
        case .en: "English"
        case .ja: "日本語"
        }
    }

    static let storageKey = "appLanguage"

    /// 다음 실행부터 시스템도 이 언어로 앱을 띄우도록 표준 키에 적는다(설정 > 앱 > 언어와 같은 자리).
    static let systemOverrideKey = "AppleLanguages"
}

enum Loc {
    // ── 언어 선택 상태 — 쓰기는 메인(설정 탭·온보딩), 읽기는 뷰 body와 헬퍼뿐 ──
    nonisolated(unsafe) private(set) static var language: AppLanguage = .system
    /// 조회에 쓸 번들 — `.system`이면 메인, 아니면 그 언어의 `.lproj`.
    /// 번들을 명시해야 조회 언어가 확정된다(로케일만 바꾸면 서식만 바뀔 수 있다).
    nonisolated(unsafe) private(set) static var bundle: Bundle = .main
    /// SwiftUI `Text` 리터럴용 — 루트에 `.environment(\.locale, Loc.locale)`로 걸면 즉시 전환된다.
    nonisolated(unsafe) private(set) static var locale: Locale = .current

    /// 앱 시작 1회 + 사용자가 고를 때. 저장까지 한다.
    static func apply(_ new: AppLanguage, persist: Bool = true) {
        language = new
        switch new {
        case .system:
            bundle = .main
            locale = .current
        default:
            bundle = Bundle.main.path(forResource: new.rawValue, ofType: "lproj")
                .flatMap(Bundle.init(path:)) ?? .main
            locale = Locale(identifier: new.rawValue)
        }
        guard persist else { return }
        let defaults = UserDefaults.standard
        defaults.set(new.rawValue, forKey: AppLanguage.storageKey)
        if new == .system {
            defaults.removeObject(forKey: AppLanguage.systemOverrideKey)
        } else {
            defaults.set([new.rawValue], forKey: AppLanguage.systemOverrideKey)
        }
    }

    /// 앱 시작 복원 — 저장값이 없으면 시스템 따름.
    static func restore() {
        let saved = UserDefaults.standard.string(forKey: AppLanguage.storageKey)
        apply(saved.flatMap(AppLanguage.init(rawValue:)) ?? .system, persist: false)
    }

    /// 로컬라이즈 문자열 — **선택된 언어로** 뽑는다. 리터럴이 아닌 자리(String 반환)는 전부 이걸 쓴다.
    static func str(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: bundle, locale: locale)
    }

    /// **앱이 만든 한국어 문구를 담은 String**을 다시 번역 키로 되돌린다.
    /// 쓰는 자리: TempoCore가 돌려주는 문구(설문 문항·선택지·공휴일 이름·표시명)처럼
    /// 리터럴이 아니라 값으로 흘러오는 앱 카피. 키가 앱 카탈로그에 있으면 런타임에 조회된다
    /// — TempoCore를 순수 모듈로 두고(패키지 로컬라이제이션·번들 리소스 불요) 번역만 앱에서 한다.
    ///
    /// ⚠ **사용자가 입력한 내용에는 절대 쓰지 않는다.** 사용자가 적은 「완료」라는 제목이
    /// 영어에서 「Done」으로 둔갑한다. 대상은 앱이 쓴 문구뿐이다.
    static func key(_ appCopy: String) -> LocalizedStringKey { LocalizedStringKey(appCopy) }

    /// 뷰 밖(알림 본문·위젯 스냅샷 합성 등)에서 같은 일을 한다.
    static func text(_ appCopy: String) -> String {
        str(String.LocalizationValue(appCopy))
    }

    /// 공휴일 이름 — TempoCore는 순수 모듈이라 대체공휴일을 「대체공휴일(설날)」로 **합성해서**
    /// 돌려준다. 합성된 문자열은 카탈로그 키가 아니므로 앱에서 풀어 다시 합성한다.
    /// (합성을 TempoCore에서 걷어내려면 반환 타입을 구조체로 바꿔야 한다 — 로컬라이제이션.md §5)
    static func holidayName(_ raw: String) -> String {
        let prefix = "대체공휴일("
        guard raw.hasPrefix(prefix), raw.hasSuffix(")") else { return text(raw) }
        let base = String(raw.dropFirst(prefix.count).dropLast())
        return fmt("대체공휴일(%1$@)", text(base))
    }

    /// 포맷 인자가 있는 로컬라이즈 문자열.
    /// - Parameter key: 포맷 지정자를 포함한 **한글 키**(예: `"%lld일차"`). 카탈로그 키와 글자 그대로 같아야 한다.
    /// - Note: 번역에서 어순이 바뀌면 `%1$@`·`%2$lld` 위치 지정자를 쓴다. 리터럴 퍼센트는 `%%`.
    static func fmt(_ key: String.LocalizationValue, _ args: CVarArg...) -> String {
        String(format: str(key), arguments: args)
    }
}
