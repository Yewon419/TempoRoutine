// 템포루틴 — 데일리 체크인 (MASTER §3.4 / §5.5)
// 단계는 저장하지 않는다 — 집계 시 cycleDay로 도출(§5.5, stale 방지). day 기준 upsert(하루 1개).
// §5.5 CloudKit 호환 규칙: 프로퍼티 전부 기본값, unique 제약 금지(dedup=쓰기 경로).

import Foundation
import SwiftData

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
    }
}
