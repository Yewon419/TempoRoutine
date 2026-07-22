// 템포루틴 — 3카드 값 타입 (MASTER §5.5)
// @Model(앱 타깃)이 참조하는 순수 Codable 값 — Core→SwiftData 의존 금지(§5.10), 참조 방향은 앱→Core만.

import Foundation

// ① 일정 카드 — 절대 날짜 / 연 반복 (cycle-anchored 모델 밖, resolveDate 안 씀)
public enum ScheduleRepeat: String, Codable, Sendable, CaseIterable { case none, daily, weekly, monthly, yearly }

// ② Input 카드
public enum InputCategory: String, Codable, CaseIterable, Sendable { case food, exercise, media, other }

public enum InputSchedule: Codable, Equatable, Sendable {
    case daily                          // 매일
    case cycleAnchored(CycleRecurrence) // 주기 기준 (resolveDate 사용)
}

// 연관값 enum auto-synthesis는 실기기서 불안정(§5.5.1 실측) → discriminator 커스텀 Codable.
extension InputSchedule {
    enum CodingKeys: String, CodingKey { case type, recurrence }
    enum Kind: String, Codable { case daily, cycleAnchored }
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        switch self {
        case .daily:
            try c.encode(Kind.daily, forKey: .type)
        case .cycleAnchored(let r):
            try c.encode(Kind.cycleAnchored, forKey: .type)
            try c.encode(r, forKey: .recurrence)
        }
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .daily:         self = .daily
        case .cycleAnchored: self = .cycleAnchored(try c.decode(CycleRecurrence.self, forKey: .recurrence))
        }
    }
}

// ③ Output 카드 — 진행도 종류 (§5.5.2: 진행은 아이템 수명 누적, 완료는 파생)
public enum OutputProgressKind: String, Codable, Sendable { case subtasks, sessions, percent }
