// 템포루틴 — 로컬라이제이션 도구 (2026-08-20, en·ja 이관 개시)
// 계약 SSOT = `..\로컬라이제이션.md`. 여기는 그 규칙의 코드 쪽 한 조각.
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
//   변수로 넘길 문구는 만드는 자리에서 `String(localized:)`로 뽑아 둘 것.

import Foundation
import SwiftUI

enum Loc {
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
        String(localized: String.LocalizationValue(appCopy))
    }

    /// 포맷 인자가 있는 로컬라이즈 문자열.
    /// - Parameter key: 포맷 지정자를 포함한 **한글 키**(예: `"%lld일차"`). 카탈로그 키와 글자 그대로 같아야 한다.
    /// - Note: 번역에서 어순이 바뀌면 `%1$@`·`%2$lld` 위치 지정자를 쓴다. 리터럴 퍼센트는 `%%`.
    static func fmt(_ key: String.LocalizationValue, _ args: CVarArg...) -> String {
        String(format: String(localized: key), arguments: args)
    }
}
