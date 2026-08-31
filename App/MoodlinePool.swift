// 템포루틴 — 무드라인 풀 (2026-08-31 대표님 승인 A4)
// 계절당 고정 1문구는 사흘이면 외운다 — 풀을 넓히되 **하루 안에서는 고정**(대표님 단서).
// 선택 = 날짜 시드(PlaylistSpec 커버 해시 전례: day × 2654435761). ⚠ String.hashValue는
// 프로세스마다 달라 재실행에 문구가 바뀐다 — 기준일로부터의 일수(안정값)를 시드로 쓴다.
//
// 층은 종전 그대로 둘: 개인화(계절×기록상 에너지, 표본 있으면 우선) → 기본(계절).
// 톤 = §7 허락 톤(재촉·처방 금지), 기존 문구는 각 풀의 첫 항목으로 보존.

import Foundation
import TempoCore

enum MoodlinePool {
    /// 하루 고정 시드 — start-of-day 기준 일수(재실행·기기 재부팅에도 안정)
    private static func pick(_ pool: [String], on day: Date) -> String {
        guard !pool.isEmpty else { return "" }
        let dayNumber = UInt32(truncatingIfNeeded: Int(day.timeIntervalSinceReferenceDate / 86400))
        let seed = dayNumber &* 2654435761
        return pool[Int(seed % UInt32(pool.count))]
    }

    // ── 기본(계절당 4) — 소비처: 오늘 탭 폴백 + 위젯 스냅샷 ──
    static func base(for phase: CyclePhase, on day: Date) -> String {
        pick(basePool(phase), on: day)
    }

    private static func basePool(_ phase: CyclePhase) -> [String] {
        switch phase {
        case .menstrual: [
            Loc.str("이번 주는 겨울이에요. 조금은 쉬어가도 괜찮아요."),
            Loc.str("겨울이에요. 몸이 하는 말을 먼저 들어봐요."),
            Loc.str("겨울이에요. 따뜻한 것 하나면 충분한 날도 있어요."),
            Loc.str("겨울이에요. 오늘은 나에게 너그러워도 좋아요."),
        ]
        case .follicular: [
            Loc.str("봄이에요. 가볍게 시작해보기 좋은 때예요."),
            Loc.str("봄이에요. 작은 것부터 하나씩 깨워봐요."),
            Loc.str("봄이에요. 새로 하고 싶은 게 생겼다면 그게 신호예요."),
            Loc.str("봄이에요. 서두르지 않아도 어느새 자라 있을 거예요."),
        ]
        case .ovulation: [
            Loc.str("여름이에요. 하고 싶은 만큼 빛나도 좋아요."),
            Loc.str("여름이에요. 오늘의 에너지를 마음껏 써봐요."),
            Loc.str("여름이에요. 미뤄둔 일을 꺼내기 좋은 날이에요."),
            Loc.str("여름이에요. 사람을 만나기에도 좋은 때예요."),
        ]
        case .luteal: [
            Loc.str("가을이에요. 스스로를 돌아보는 시간을 가져봐요."),
            Loc.str("가을이에요. 하나씩 매듭지어도 좋은 때예요."),
            Loc.str("가을이에요. 속도를 줄이는 것도 실력이에요."),
            Loc.str("가을이에요. 오늘은 정리 하나면 충분해요."),
        ]
        }
    }

    // ── 개인화(계절×레벨당 2) — 표본이 쌓인 사람의 문구도 하루마다 결이 갈린다 ──
    static func personalized(for phase: CyclePhase, level: EnergyLevel, on day: Date) -> String {
        pick(personalizedPool(phase, level), on: day)
    }

    private static func personalizedPool(_ phase: CyclePhase, _ level: EnergyLevel) -> [String] {
        switch (phase, level) {
        case (.menstrual, .low): [
            Loc.str("겨울이에요. 기록상 이맘때는 에너지가 낮았어요. 조금은 쉬어가도 좋아요."),
            Loc.str("겨울이에요. 기록상 이맘때는 쉼이 먼저였어요. 오늘도 그래도 돼요."),
        ]
        case (.menstrual, .mid): [
            Loc.str("겨울이에요. 기록상 이맘때의 당신은 잔잔했어요. 천천히 가도 좋아요."),
            Loc.str("겨울이에요. 기록상 무리하지 않는 날이 많았어요. 그 감각을 믿어봐요."),
        ]
        case (.menstrual, .high): [
            Loc.str("겨울이에요. 기록상 이맘때도 에너지가 꽤 있었어요. 원하는 만큼 해보아도, 이번엔 쉬어가도 좋아요."),
            Loc.str("겨울이에요. 기록상 이맘때도 힘이 남아 있었어요. 다만 무리는 말아요."),
        ]
        case (.follicular, .low): [
            Loc.str("봄이에요. 기록상 이맘때는 아직 잔잔했어요. 서두르지 않아도 좋아요."),
            Loc.str("봄이에요. 기록상 천천히 깨어나던 때예요. 몸을 먼저 풀어봐요."),
        ]
        case (.follicular, .mid): [
            Loc.str("봄이에요. 기록상 조금씩 기지개를 켜던 때예요. 가볍게 시작해도 좋아요."),
            Loc.str("봄이에요. 기록상 리듬이 올라오던 때예요. 작은 일부터 얹어봐요."),
        ]
        case (.follicular, .high): [
            Loc.str("봄이에요. 기록상 이맘때 에너지가 생긴대요. 슬슬 시동을 걸어볼까요!"),
            Loc.str("봄이에요. 기록상 출발이 좋던 때예요. 오늘 하나 시작해봐요."),
        ]
        case (.ovulation, .low): [
            Loc.str("여름이에요. 기록상 이맘때는 쉼이 필요했어요. 쉬어가도 좋아요."),
            Loc.str("여름이에요. 기록상 이맘때는 의외로 지치곤 했어요. 오늘은 가볍게 가요."),
        ]
        case (.ovulation, .mid): [
            Loc.str("여름이에요. 기록상 이맘때의 당신은 밝았어요. 하고 싶은 만큼 해봐요!"),
            Loc.str("여름이에요. 기록상 컨디션이 안정적이던 때예요. 꾸준히 가기 좋아요."),
        ]
        case (.ovulation, .high): [
            Loc.str("여름이에요. 기록상 이맘때 가장 빛났어요. 마음껏 몰입해도 좋아요!"),
            Loc.str("여름이에요. 기록상 절정이던 때예요. 큰 일을 두기 좋은 날이에요."),
        ]
        case (.luteal, .low): [
            Loc.str("가을이에요. 기록상 이맘때는 쉽게 지치곤 했어요. 짐을 좀 덜어내도 괜찮아요."),
            Loc.str("가을이에요. 기록상 기운이 내려가던 때예요. 일정을 가볍게 둬도 좋아요."),
        ]
        case (.luteal, .mid): [
            Loc.str("가을이에요. 기록상 하나씩 정리하던 때예요. 스스로를 돌아보는 시간을 가져봐요."),
            Loc.str("가을이에요. 기록상 차분히 마무리하던 때예요. 매듭 하나면 충분해요."),
        ]
        case (.luteal, .high): [
            Loc.str("가을이에요. 기록상 이맘때 에너지가 충분했어요. 오늘은 어떤 것에 몰입해볼까요?"),
            Loc.str("가을이에요. 기록상 끝심이 좋던 때예요. 미뤄둔 마무리를 해봐요."),
        ]
        }
    }
}
