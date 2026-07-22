// 템포루틴 — 3카드 SwiftData 모델 (MASTER §5.5 / §5.5.2 / §5.5.3)
// §5.5 CloudKit 호환 P0 규칙: 프로퍼티 전부 기본값, 관계는 optional, unique 제약 금지.
// 값 타입(CycleRecurrence·InputSchedule 등)은 TempoCore 소유 — 참조 방향은 앱→Core만(§5.10).

import Foundation
import SwiftData
import TempoCore

// [공통] 발생 완료 — 상대 저장이라 완료는 절대 날짜로. P0에서 Input 전용(§5.5.2).
@Model
final class ItemCompletion {
    var id: UUID = UUID()
    var itemID: UUID = UUID()
    var occurredOn: Date = Date()
    var completedAt: Date = Date()

    init(itemID: UUID, occurredOn: Date) {
        self.id = UUID()
        self.itemID = itemID
        self.occurredOn = Calendar.current.startOfDay(for: occurredOn)
        self.completedAt = .now
    }
}

// ① 일정 카드 — 외부·고정. 절대 날짜 / 연 반복. 계절 레버 X.
@Model
final class ScheduleItem {
    var id: UUID = UUID()
    var title: String = ""
    var date: Date = Date()                  // 절대 날짜. 연반복은 month/day만 의미
    var isAllDay: Bool = true                // false = 시간 지정(프로모드)
    var repeatRule: ScheduleRepeat = ScheduleRepeat.none
    var createdAt: Date = Date()

    init(title: String, date: Date, isAllDay: Bool = true, repeatRule: ScheduleRepeat = .none) {
        self.id = UUID()
        self.title = title
        self.date = date
        self.isAllDay = isAllDay
        self.repeatRule = repeatRule
        self.createdAt = .now
    }

    /// 이 날짜에 표시되는가. 연반복 윤년 규칙: 2/29는 비윤년에 2/28로(§5.6.4).
    /// 매일·매주·매달 반복은 시작일(date) 이전에는 표시하지 않는다.
    func occurs(on day: Date) -> Bool {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let target = cal.startOfDay(for: day)
        switch repeatRule {
        case .none:
            return cal.isDate(date, inSameDayAs: day)
        case .daily:
            return target >= start
        case .weekly:
            guard target >= start else { return false }
            return cal.component(.weekday, from: date) == cal.component(.weekday, from: day)
        case .monthly:
            guard target >= start else { return false }
            let startDayOfMonth = cal.component(.day, from: date)
            let targetDayOfMonth = cal.component(.day, from: day)
            if startDayOfMonth == targetDayOfMonth { return true }
            // 시작일이 그 달엔 없는 날짜(예: 31일)면 그 달의 마지막 날에 표시
            let daysInTargetMonth = cal.range(of: .day, in: .month, for: day)?.count ?? 31
            return startDayOfMonth > daysInTargetMonth && targetDayOfMonth == daysInTargetMonth
        case .yearly:
            let d = cal.dateComponents([.month, .day], from: date)
            let t = cal.dateComponents([.month, .day], from: day)
            if d.month == t.month && d.day == t.day { return true }
            // 2/29 → 비윤년 2/28
            if d.month == 2 && d.day == 29 && t.month == 2 && t.day == 28 {
                return cal.range(of: .day, in: .month,
                                 for: cal.date(from: DateComponents(year: cal.component(.year, from: day), month: 2, day: 1)) ?? day)?.count == 28
            }
            return false
        }
    }
}

extension ScheduleRepeat {
    /// 반복 배지·칩 라벨. .none은 표시할 게 없어 nil.
    var shortLabel: String? {
        switch self {
        case .none: nil
        case .daily: "매일"
        case .weekly: "매주"
        case .monthly: "매달"
        case .yearly: "매년"
        }
    }
}

// ② Input 카드 — 채움. 일일 체크리스트. 완료 = ItemCompletion 존재 여부.
@Model
final class InputItem {
    var id: UUID = UUID()
    var title: String = ""
    var category: InputCategory = InputCategory.other
    // 연관값 enum을 SwiftData 속성으로 직접 저장하면 실기기 크래시(§5.5.1 실측 계열)
    // → Data 인코딩 저장 + computed 노출. 빈 Data = .daily 폴백.
    var scheduleData: Data = Data()
    var createdAt: Date = Date()

    var schedule: InputSchedule {
        get { (try? JSONDecoder().decode(InputSchedule.self, from: scheduleData)) ?? .daily }
        set { scheduleData = (try? JSONEncoder().encode(newValue)) ?? scheduleData }
    }

    init(title: String, category: InputCategory = .other, schedule: InputSchedule = .daily) {
        self.id = UUID()
        self.title = title
        self.category = category
        self.scheduleData = (try? JSONEncoder().encode(schedule)) ?? Data()
        self.createdAt = .now
    }
}

// ③ Output 카드 — 내보냄. 진행도는 아이템 수명 누적, 완료는 파생(§5.5.2).
@Model
final class OutputSubtask {
    var id: UUID = UUID()
    var title: String = ""
    var isDone: Bool = false
    var order: Int = 0
    var owner: OutputItem?   // inverse — CloudKit 호환(관계 optional + 양방향)

    init(title: String, order: Int) {
        self.id = UUID()
        self.title = title
        self.isDone = false
        self.order = order
    }
}

@Model
final class OutputItem {
    var id: UUID = UUID()
    var title: String = ""
    // CycleRecurrence(내부에 연관값 enum CycleAnchor) 직접 저장 금지 — InputItem.scheduleData와 동일 근거
    var recurrenceData: Data = Data()
    var progressKind: OutputProgressKind = OutputProgressKind.percent
    @Relationship(deleteRule: .cascade, inverse: \OutputSubtask.owner)
    var subtasks: [OutputSubtask]? = []   // CloudKit 규칙: optional
    var targetSessions: Int = 0
    var loggedSessions: Int = 0
    var percent: Double = 0
    var createdAt: Date = Date()

    var recurrence: CycleRecurrence {
        get {
            (try? JSONDecoder().decode(CycleRecurrence.self, from: recurrenceData))
                ?? CycleRecurrence(anchor: .cycleStart, dayOffset: 0, repeatsEveryCycle: true, overflowRule: .clamp)
        }
        set { recurrenceData = (try? JSONEncoder().encode(newValue)) ?? recurrenceData }
    }

    init(title: String, recurrence: CycleRecurrence, progressKind: OutputProgressKind = .percent) {
        self.id = UUID()
        self.title = title
        self.recurrenceData = (try? JSONEncoder().encode(recurrence)) ?? Data()
        self.progressKind = progressKind
        self.subtasks = []
        self.targetSessions = 0
        self.loggedSessions = 0
        self.percent = 0
        self.createdAt = .now
    }

    /// 완료 = 파생 상태(§5.5.2). 저장 필드 아님.
    var isComplete: Bool {
        switch progressKind {
        case .subtasks:
            let list = subtasks ?? []
            return !list.isEmpty && list.allSatisfy(\.isDone)
        case .sessions:
            return targetSessions > 0 && loggedSessions >= targetSessions
        case .percent:
            return percent >= 1.0
        }
    }
}
