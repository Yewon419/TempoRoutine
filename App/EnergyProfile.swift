// 템포루틴 — 단계별 에너지 프로필 (2026-07-23 사용자 지시: 데이터가 쌓이면 계절 문구·Input 예시 개인화)
// §5.6.3 집계 계약의 (단계×energy) 부분 선행 실장: 비투영(projected 제외) 체크인만, MIN_SAMPLES=3.
// 카피 가드레일 준수: 과거형·"기록상" hedge·허락 톤 — 명령형 금지(§8.1 MoodLine)·운세/고정관념 금지(§5.6.3).
// 데이터 미달 단계는 nil → 기존 계절 기본 문구/계절 예시로 폴백(§3.5 콜드스타트 하이브리드).

import Foundation
import TempoCore

enum EnergyLevel {
    case low, mid, high
}

struct EnergyProfile {
    /// 단계별 energy 표본 — 비투영 일자의 체크인(energy 1...5)만 집계
    private let stats: [CyclePhase: (sum: Int, count: Int)]

    static let minSamples = 3

    init(checkIns: [DailyCheckIn], snapshot: CycleSnapshot) {
        var acc: [CyclePhase: (sum: Int, count: Int)] = [:]
        for record in checkIns where (1...5).contains(record.energy) {
            guard let info = snapshot.phaseInfo(on: record.day), !info.projected,
                  let phase = snapshot.phase(on: record.day) else { continue }
            let cur = acc[phase] ?? (0, 0)
            acc[phase] = (cur.sum + record.energy, cur.count + 1)
        }
        stats = acc
    }

    /// 해당 단계의 비투영 energy 표본 수 — 콜드 카드 진행 표시용(2026-07-23)
    func sampleCount(for phase: CyclePhase) -> Int {
        stats[phase]?.count ?? 0
    }

    /// 표본 3개 미만이면 nil(기본 문구 유지). 경계: 평균 ≤2.5 low / ≥3.5 high / 그 외 mid.
    func level(for phase: CyclePhase) -> EnergyLevel? {
        guard let s = stats[phase], s.count >= Self.minSamples else { return nil }
        let mean = Double(s.sum) / Double(s.count)
        if mean <= 2.5 { return .low }
        if mean >= 3.5 { return .high }
        return .mid
    }

    // ── 개인화 무드라인 (계절 × 기록상 에너지 — 12종) ──
    static func moodline(for phase: CyclePhase, level: EnergyLevel) -> String {
        switch (phase, level) {
        case (.menstrual, .low):   Loc.str("겨울이에요. 기록상 이맘때는 에너지가 낮았어요. 조금은 쉬어가도 좋아요.")
        case (.menstrual, .mid):   Loc.str("겨울이에요. 기록상 이맘때의 당신은 잔잔했어요. 천천히 가도 좋아요.")
        case (.menstrual, .high):  Loc.str("겨울이에요. 기록상 이맘때도 에너지가 꽤 있었어요. 원하는 만큼 해보아도, 이번엔 쉬어가도 좋아요.")
        case (.follicular, .low):  Loc.str("봄이에요. 기록상 이맘때는 아직 잔잔했어요. 서두르지 않아도 좋아요.")
        case (.follicular, .mid):  Loc.str("봄이에요. 기록상 조금씩 기지개를 켜던 때예요. 가볍게 시작해도 좋아요.")
        case (.follicular, .high): Loc.str("봄이에요. 기록상 이맘때 에너지가 생긴대요. 슬슬 시동을 걸어볼까요!")
        case (.ovulation, .low):   Loc.str("여름이에요. 기록상 이맘때는 쉼이 필요했어요. 쉬어가도 좋아요.")
        case (.ovulation, .mid):   Loc.str("여름이에요. 기록상 이맘때의 당신은 밝았어요. 하고 싶은 만큼 해봐요!")
        case (.ovulation, .high):  Loc.str("여름이에요. 기록상 이맘때 가장 빛났어요. 마음껏 몰입해도 좋아요!")
        case (.luteal, .low):      Loc.str("가을이에요. 기록상 이맘때는 쉽게 지치곤 했어요. 짐을 좀 덜어내도 괜찮아요.")
        case (.luteal, .mid):      Loc.str("가을이에요. 기록상 하나씩 정리하던 때예요. 스스로를 돌아보는 시간을 가져봐요.")
        case (.luteal, .high):     Loc.str("가을이에요. 기록상 이맘때 에너지가 충분했어요. 오늘은 어떤 것에 몰입해볼까요?")
        }
    }

    // ── Input 제목 예시 (카테고리 × 기록상 에너지 — §3.3 편집 가능 기본값, 처방 아님) ──
    static func inputExample(category: InputCategory, level: EnergyLevel) -> String {
        switch (category, level) {
        case (.food, .low):      Loc.str("소화 편한 죽 한 그릇")
        case (.food, .mid):      Loc.str("제철 재료로 한 끼")
        case (.food, .high):     Loc.str("새 레시피 도전")
        case (.exercise, .low):  Loc.str("가볍게 스트레칭 10분")
        case (.exercise, .mid):  Loc.str("동네 산책 30분")
        case (.exercise, .high): Loc.str("달리기 5km")
        case (.media, .low):     Loc.str("포근한 영화 한 편")
        case (.media, .mid):     Loc.str("팟캐스트 한 편")
        case (.media, .high):    Loc.str("미뤄둔 다큐 정주행")
        case (.other, .low):     Loc.str("오늘은 일찍 잠들기")
        case (.other, .mid):     Loc.str("물 자주 마시기")
        case (.other, .high):    Loc.str("책상 정리")
        }
    }
}
