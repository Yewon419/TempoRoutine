// 활판 인용문 = 계절 고전 문장 카탈로그 (시안 §2.3-5, 2026-08-24)
// 외국 문장 = 자체 번역(원문 전부 퍼블릭 도메인 — 저작권 규칙은 시안 SSOT §2.3-5).
// ⚠ 계절 = 주기 은유(겨울=월경기…)라 실제 달력과 무관 — 달력 이벤트·월 이름·날씨 서술 금지.
//    계절어는 주기 은유로 읽힐 때만("겨울 지나면 봄" = 회복 예감). 새 문구도 이 규칙을 따른다.
// 다국어 카탈로그는 미결(시안 §2.3-5) — 현재는 전 언어에서 한국어 문장이 나간다.

import Foundation
import TempoCore

enum LetterpressQuotes {
    struct Quote {
        let line1: String
        let line2: String
        let source: String
    }

    /// 오늘의 문구 — 선택은 날짜 시드(§4.5 커버 랜덤과 같은 곱셈 해시, 리렌더 불변)
    static func quote(for phase: CyclePhase, day: Int) -> Quote {
        let list = catalog(for: phase)
        let idx = Int((UInt32(truncatingIfNeeded: day) &* 2654435761) % UInt32(list.count))
        return list[idx]
    }

    private static func catalog(for phase: CyclePhase) -> [Quote] {
        switch phase {
        case .menstrual:   // 겨울 — 쉼·여백·회복 예감
            [Quote(line1: Loc.str("겨울이 왔다면"), line2: Loc.str("봄도 머지않으리"),
                   source: Loc.str("셸리, 「서풍에 부치는 노래」")),
             Quote(line1: Loc.str("내 삶에 넓은 여백이"), line2: Loc.str("있기를 바란다"),
                   source: Loc.str("소로, 『월든』")),
             Quote(line1: Loc.str("겨울이 지나고"), line2: Loc.str("나의 별에도 봄이 오면"),
                   source: Loc.str("윤동주, 「별 헤는 밤」"))]
        case .follicular:  // 봄 — 시작·생동
            [Quote(line1: Loc.str("골짜기와 언덕 위를 떠도는"), line2: Loc.str("구름처럼 홀로 거닐었네"),
                   source: Loc.str("워즈워스, 「수선화」")),
             Quote(line1: Loc.str("제대로 바라보면 온 세상이"), line2: Loc.str("하나의 정원인 걸 알게 돼"),
                   source: Loc.str("버넷, 『비밀의 화원』")),
             Quote(line1: Loc.str("산에는 꽃 피네 꽃이 피네"), line2: Loc.str("갈 봄 여름 없이 꽃이 피네"),
                   source: Loc.str("김소월, 「산유화」"))]
        case .ovulation:   // 여름 — 절정 예찬
            [Quote(line1: Loc.str("그대를 여름날에"), line2: Loc.str("견주어 볼까요"),
                   source: Loc.str("셰익스피어, 소네트 18")),
             Quote(line1: Loc.str("여름 오후, 여름 오후."), line2: Loc.str("언제나 가장 아름다운 말이었다"),
                   source: Loc.str("헨리 제임스")),
             Quote(line1: Loc.str("옛이야기 지줄대는 실개천이"), line2: Loc.str("휘돌아 나가고"),
                   source: Loc.str("정지용, 「향수」"))]
        case .luteal:      // 가을 — 결실·마무리
            [Quote(line1: Loc.str("안개와 무르익은"), line2: Loc.str("결실의 계절"),
                   source: Loc.str("키츠, 「가을에게」")),
             Quote(line1: Loc.str("주여, 때가 왔습니다."), line2: Loc.str("지난여름은 참으로 위대했습니다"),
                   source: Loc.str("릴케, 「가을날」")),
             Quote(line1: Loc.str("꽃이 소금을 뿌린 듯이"), line2: Loc.str("흐뭇한 달빛에 숨이 막힐 지경이다"),
                   source: Loc.str("이효석, 「메밀꽃 필 무렵」"))]
        }
    }
}
