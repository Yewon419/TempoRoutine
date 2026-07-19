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
    var pain: Int?
    var appetite: Int?
    var note: String?
    var createdAt: Date = Date()

    init(day: Date, energy: Int, mood: Int) {
        self.id = UUID()
        self.day = Calendar.current.startOfDay(for: day)
        self.energy = energy
        self.mood = mood
        self.sleep = nil
        self.pain = nil
        self.appetite = nil
        self.note = nil
        self.createdAt = .now
    }
}
