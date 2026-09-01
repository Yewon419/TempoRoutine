// 템포루틴 — 데일리 체크인 (MASTER §3.4 / §5.5)
// 단계는 저장하지 않는다 — 집계 시 cycleDay로 도출(§5.5, stale 방지). day 기준 upsert(하루 1개).
// §5.5 CloudKit 호환 규칙: 프로퍼티 전부 기본값, unique 제약 금지(dedup=쓰기 경로).

import Foundation
import SwiftData

/// 아픈 날 증상(2026-09-01 대표님 지시 "질병 등으로 아픈 특수케이스를 따로") — 체크인 칩.
/// 질병(감기·몸살·배탈)의 낮은 신호는 주기와 무관한 오염이라 집계에서 **완전 제외**,
/// 통증(근육통·두통)은 주기 신호가 섞여 있을 수 있어 **절반 가중**(대표님 결정 — "감기나
/// 이런 질병은 제외하고, 근육통이라던가 그런건 가중치 반영").
enum CheckInSymptom: String, CaseIterable {
    case cold, fever, stomach, muscle, headache

    var title: String {
        switch self {
        case .cold: Loc.str("감기")
        case .fever: Loc.str("몸살·열")
        case .stomach: Loc.str("배탈")
        case .muscle: Loc.str("근육통")
        case .headache: Loc.str("두통")
        }
    }

    /// 질병(가중 0) 여부 — 나머지는 통증(가중 0.5)
    var isIllness: Bool {
        switch self {
        case .cold, .fever, .stomach: true
        case .muscle, .headache: false
        }
    }
}

@Model
final class DailyCheckIn {
    var id: UUID = UUID()
    var day: Date = Date()          // start-of-day 정규화, 하루 1개
    var energy: Int = 0             // 1...5 ordinal (UI 3탭 = 1·3·5 매핑), 0 = 미기록
    var mood: Int = 0               // 1...5 valence, 0 = 미기록
    var sleep: Int?                 // 옵션 1...5
    var pain: Int?                  // 신체 계열 — M축 분모(핸드오프 v1.5 §3-1)
    var appetite: Int?
    /// 예민함 1...5 — 정서 계열의 두 번째 문항. 기분 1문항만으로 정서를 구성하면
    /// 2문항 평균의 신뢰도 이득(Spearman-Brown)을 잃는다(v1.5 §3-1).
    var irritability: Int?
    var note: String?
    var createdAt: Date = Date()
    /// 소급 입력 여부(v1.5 §3-4) — 회상 기반이라 EMA(순간 자기보고)와 측정 시간 척도가 다르다.
    /// 적합에서 가중치를 낮추거나 제외하기 위한 플래그. CloudKit 규칙상 기본값 필수.
    var isBackfilled: Bool = false
    /// 체크인이 처음 완성된 시각(씨앗 재화 근거, 2026-08-09 — 판정·지급 규칙은 Seeds).
    /// optional 추가라 구 저장분 디코딩·CloudKit 규칙 모두 무영향. nil = 미완성.
    var completedAt: Date?
    /// 증상 raw 콤마 구분("cold,muscle" — CheckInSymptom, 2026-09-01). 복합 Codable을 저장
    /// 프로퍼티로 두지 않는 규칙(repo CLAUDE.md)이라 String 평탄화 + computed 노출. 기본값 필수.
    var symptoms: String = ""

    init(day: Date, energy: Int, mood: Int, isBackfilled: Bool = false) {
        self.id = UUID()
        self.day = Calendar.current.startOfDay(for: day)
        self.energy = energy
        self.mood = mood
        self.sleep = nil
        self.pain = nil
        self.appetite = nil
        self.irritability = nil
        self.note = nil
        self.createdAt = .now
        self.isBackfilled = isBackfilled
        self.completedAt = nil
        self.symptoms = ""
    }

    var symptomSet: Set<CheckInSymptom> {
        get { Set(symptoms.split(separator: ",").compactMap { CheckInSymptom(rawValue: String($0)) }) }
        set { symptoms = newValue.map(\.rawValue).sorted().joined(separator: ",") }
    }

    /// 집계 가중(2026-09-01) — 질병 0(완전 제외) / 통증 0.5 / 무증상 1.
    /// 소비처 = EnergyProfile·RhythmEngine 매핑·CycleRecap. AxisProfile은 이분법 유지
    /// (질병만 제외 — §5.12 백필 전례처럼 WindowStats는 가중 없이 포함/제외만 가른다).
    var aggregationWeight: Double {
        let set = symptomSet
        if set.contains(where: \.isIllness) { return 0 }
        return set.isEmpty ? 1 : 0.5
    }
}
