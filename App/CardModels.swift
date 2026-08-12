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
    var date: Date = Date()                  // 절대 날짜(시작). 연반복은 month/day만 의미
    // 종료 시점. 시간 지정이면 종료 시각, 하루종일이면 종료 날짜(여러 날 일정, 2026-07-25). nil = 하루짜리.
    var endDate: Date? = nil
    var isAllDay: Bool = true                // false = 시간 지정(프로모드)
    var repeatRule: ScheduleRepeat = ScheduleRepeat.none
    var reminderMinutes: Int = -1            // -1 = 알림 없음 / 0 = 정시(하루종일=당일 9시) / N = N분 전
    var createdAt: Date = Date()

    init(title: String, date: Date, isAllDay: Bool = true, repeatRule: ScheduleRepeat = .none,
         endDate: Date? = nil, reminderMinutes: Int = -1) {
        self.id = UUID()
        self.title = title
        self.date = date
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.repeatRule = repeatRule
        self.reminderMinutes = reminderMinutes
        self.createdAt = .now
    }

    /// 걸치는 날 수 — 하루짜리는 1 (§8.2.3 여러 날 일정)
    var spanDays: Int {
        ScheduleSpan.dayCount(start: date, end: endDate, calendar: Calendar.current)
    }

    var isMultiDay: Bool { spanDays > 1 }

    /// 여러 날 일정에서 그날이 몇 일차인가(1부터). 하루짜리거나 해당 없으면 nil.
    func dayIndex(on day: Date) -> Int? {
        guard isMultiDay else { return nil }
        let cal = Calendar.current
        let target = cal.startOfDay(for: day)
        for offset in 0..<spanDays {
            guard let candidate = cal.date(byAdding: .day, value: -offset, to: target) else { continue }
            if startsOn(candidate) { return offset + 1 }
        }
        return nil
    }

    /// 이 날짜에 표시되는가 — 발생 시작일(`startsOn`) + 기간(`spanDays`) 확장.
    /// 반복 일정도 회차마다 같은 길이를 갖는다(2026-07-25 사용자 결정).
    func occurs(on day: Date) -> Bool {
        let cal = Calendar.current
        let target = cal.startOfDay(for: day)
        let span = spanDays
        if span == 1 { return startsOn(target) }
        switch repeatRule {
        case .none:
            let start = cal.startOfDay(for: date)
            guard let last = cal.date(byAdding: .day, value: span - 1, to: start) else { return false }
            return target >= start && target <= last
        case .daily:
            return startsOn(target)   // 매일 시작하므로 기간은 의미 없다
        case .weekly, .monthly, .yearly:
            // 회차 주기보다 긴 기간은 어차피 연속 — 주기 길이까지만 되짚는다(그리드 렌더 비용 상한)
            let limit = min(span, repeatRule.periodDayCap)
            for offset in 0..<limit {
                guard let candidate = cal.date(byAdding: .day, value: -offset, to: target) else { continue }
                if startsOn(candidate) { return true }
            }
            return false
        }
    }

    /// 발생(회차)의 시작일인가. 연반복 윤년 규칙: 2/29는 비윤년에 2/28로(§5.6.4).
    /// 매일·매주·매달 반복은 시작일(date) 이전에는 표시하지 않는다.
    func startsOn(_ day: Date) -> Bool {
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
    /// 회차 간격의 상한(일) — 기간이 이보다 길면 발생이 이어지므로 되짚기를 여기서 끊는다.
    var periodDayCap: Int {
        switch self {
        case .none, .daily: 1
        case .weekly: 7
        case .monthly: 31
        case .yearly: 366
        }
    }

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
// 진행 방식(2026-08-12 사용자 지시)은 **정의만** 여기 둔다 — 그날의 값은 InputProgress.
// Output처럼 아이템에 값을 두면 매일 반복에서 이틀째부터 목표 도달 상태가 된다(§5.5.2 개정).
@Model
final class InputItem {
    var id: UUID = UUID()
    var title: String = ""
    var category: InputCategory = InputCategory.other
    /// 진행 방식 — 빈 문자열 = 종전 단순 체크. raw String 저장 + computed 노출은
    /// optional enum 저장 동작을 추측하지 않기 위한 선택이다(repo CLAUDE.md).
    var progressKindRaw: String = ""
    /// 서브태스크 **이름·순서만** — 완료 여부는 날짜별이라 InputProgress가 갖는다
    /// (OutputSubtask.isDone과 다른 점). CloudKit 규칙: optional + inverse.
    @Relationship(deleteRule: .cascade, inverse: \InputSubtask.owner)
    var subtasks: [InputSubtask]? = []
    var targetSessions: Int = 0
    var targetSeconds: Int?
    // 연관값 enum을 SwiftData 속성으로 직접 저장하면 실기기 크래시(§5.5.1 실측 계열)
    // → Data 인코딩 저장 + computed 노출. 빈 Data = .daily 폴백.
    var scheduleData: Data = Data()
    var createdAt: Date = Date()
    /// 지난 날짜에 소급해 적은 기록인가(2026-07-27) — .once의 "완료 전까지 이어짐"을 끄고
    /// 적어 넣은 그날에만 둔다. 오늘 적은 단발 할 일은 종전대로 완료할 때까지 따라온다.
    var backfilled: Bool = false
    /// 하루 중 시각(자정 기준 분, 2026-08-09 사용자 결정) — 제목 시각 파서가 채운다.
    /// 정렬(시각 있는 것 시간순, 없으면 맨 뒤)과 행 표시에만 쓰고 발생 판정엔 관여하지 않는다.
    var timeMinutes: Int?

    var schedule: InputSchedule {
        get { (try? JSONDecoder().decode(InputSchedule.self, from: scheduleData)) ?? .daily }
        set { scheduleData = (try? JSONEncoder().encode(newValue)) ?? scheduleData }
    }

    /// nil = 단순 체크(종전 Input 전부가 여기 해당 — 저장분 무변경으로 그대로 산다)
    var progressKind: OutputProgressKind? {
        get { OutputProgressKind(rawValue: progressKindRaw) }
        set { progressKindRaw = newValue?.rawValue ?? "" }
    }

    /// 목표 정의 — 판정은 TempoCore의 순수 규칙이 한다(ProgressRule)
    var progressGoal: ProgressGoal? {
        guard let kind = progressKind else { return nil }
        return ProgressGoal(kind: kind, targetSessions: targetSessions,
                                 targetSeconds: targetSeconds,
                                 subtaskCount: subtasks?.count ?? 0)
    }

    /// createdAt = 이 아이템이 시작되는 날(발생 판정의 기준선). 하루 상세에서 추가하면 그날이어야
    /// 한다 — 기본값 .now로 두면 지난 날짜에 추가해도 오늘부터 뜬다(2026-07-26 실기기 결함).
    init(title: String, category: InputCategory = .other, schedule: InputSchedule = .daily,
         createdAt: Date = .now, backfilled: Bool = false) {
        self.id = UUID()
        self.title = title
        self.category = category
        self.scheduleData = (try? JSONEncoder().encode(schedule)) ?? Data()
        self.createdAt = createdAt
        self.backfilled = backfilled
        self.timeMinutes = nil
        self.progressKindRaw = ""   // 기본 = 단순 체크(진행 방식은 시트에서 고른다)
        self.subtasks = []
        self.targetSessions = 0
        self.targetSeconds = nil
    }

    /// .once가 이 날짜에 뜨는가 — 소급 기록은 적어 넣은 그날에만. 완료 판정은 호출부(뷰) 책임.
    func onceShows(on day: Date) -> Bool {
        guard backfilled else { return occursByCalendar(on: day) }
        return Calendar.current.isDate(createdAt, inSameDayAs: day)
    }

    /// .once·.daily·.weekly·.monthly 판정(달력 기준 — 주기 기준은 CycleSnapshot 필요라 호출부에서 별도 처리).
    /// 생성일(createdAt) 이전은 발생 안 함. .cycleAnchored는 항상 false(호출부 분기 전용 가드).
    /// .once의 "완료 후 다른 날 숨김"은 completions가 필요해 호출부(뷰) 책임.
    func occursByCalendar(on day: Date) -> Bool {
        let cal = Calendar.current
        let start = cal.startOfDay(for: createdAt)
        let target = cal.startOfDay(for: day)
        guard target >= start else { return false }
        switch schedule {
        case .once:
            return true
        case .daily:
            return true
        case .weekly:
            return cal.component(.weekday, from: createdAt) == cal.component(.weekday, from: day)
        case .monthly:
            let startDay = cal.component(.day, from: createdAt)
            let targetDay = cal.component(.day, from: day)
            if startDay == targetDay { return true }
            let daysInTargetMonth = cal.range(of: .day, in: .month, for: day)?.count ?? 31
            return startDay > daysInTargetMonth && targetDay == daysInTargetMonth
        case .cycleAnchored:
            return false
        }
    }
}

/// Input 서브태스크 — **이름·순서만.** 완료 여부는 날짜마다 달라서 InputProgress가 갖는다.
/// OutputSubtask와 형태가 닮았지만 isDone이 없다는 게 결정적 차이다(2026-08-12).
@Model
final class InputSubtask {
    var id: UUID = UUID()
    var title: String = ""
    var order: Int = 0
    var owner: InputItem?   // inverse — CloudKit 호환(관계 optional + 양방향)

    init(title: String, order: Int) {
        self.id = UUID()
        self.title = title
        self.order = order
    }
}

/// Input의 **그날치** 진행 상태(2026-08-12). 완료는 여기가 아니라 ItemCompletion이 맡는다 —
/// "레코드 존재 = 완료"에 씨앗 판정·위젯·내보내기가 의존해서 미완료 상태를 섞을 수 없다.
/// 한 아이템 × 한 날짜에 하나. 진행이 0으로 되돌아가면 레코드는 남아도 무해하다.
@Model
final class InputProgress {
    var id: UUID = UUID()
    var itemID: UUID = UUID()
    var occurredOn: Date = Date()
    var loggedSessions: Int = 0
    /// 0~1 스케일 — OutputItem.percent와 같은 단위(2026-08-12 통일)
    var percent: Double = 0
    var elapsedAccumSeconds: Double = 0
    /// 진행 중 시작 앵커 — nil = 멈춤. 앱이 죽어도 경과가 이어진다(OutputItem 타이머와 같은 계약)
    var timerStartedAt: Date?
    /// 완료된 서브태스크 id 목록(JSON). 배열 직접 저장은 SwiftData 처리를 추측하지 않는다는
    /// repo 규칙에 따라 Data 인코딩 + computed 노출로 간다.
    var doneSubtaskData: Data = Data()

    init(itemID: UUID, occurredOn: Date) {
        self.id = UUID()
        self.itemID = itemID
        self.occurredOn = Calendar.current.startOfDay(for: occurredOn)
        self.loggedSessions = 0
        self.percent = 0
        self.elapsedAccumSeconds = 0
        self.timerStartedAt = nil
        self.doneSubtaskData = Data()
    }

    var doneSubtaskIDs: Set<UUID> {
        get { Set((try? JSONDecoder().decode([UUID].self, from: doneSubtaskData)) ?? []) }
        set { doneSubtaskData = (try? JSONEncoder().encode(Array(newValue))) ?? doneSubtaskData }
    }

    var isTimerRunning: Bool { timerStartedAt != nil }

    /// 현재 경과(초) — 누적 + 진행 중 델타
    func elapsedSeconds(at now: Date = .now) -> Double {
        elapsedAccumSeconds + (timerStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    /// 판정용 값 타입 — 뷰는 이걸 TempoCore 규칙에 넘긴다
    func state(at now: Date = .now) -> ProgressState {
        ProgressState(loggedSessions: loggedSessions, percent: percent,
                           elapsedSeconds: elapsedSeconds(at: now),
                           doneSubtasks: doneSubtaskIDs.count)
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
    // 연관값 enum(OutputSchedule) 직접 저장 금지 — InputItem.scheduleData와 동일 근거
    var scheduleData: Data = Data()
    var progressKind: OutputProgressKind = OutputProgressKind.percent
    @Relationship(deleteRule: .cascade, inverse: \OutputSubtask.owner)
    var subtasks: [OutputSubtask]? = []   // CloudKit 규칙: optional
    var targetSessions: Int = 0
    var loggedSessions: Int = 0
    var percent: Double = 0
    var createdAt: Date = Date()
    /// 목표일(디데이, 2026-08-01 베타 피드백). optional = CloudKit 규칙 + 기존 저장분 경량 마이그레이션.
    var targetDate: Date?
    // 타이머·스톱워치(2026-08-09 사용자 결정) — 시간도 수명 누적(§5.5.2).
    // 실행 상태는 timerStartedAt 앵커 하나로 영속 — 앱이 죽어도 경과가 이어진다.
    var targetSeconds: Int?                 // 타이머 목표(초). 스톱워치·타 진행 방식 = nil
    var elapsedAccumSeconds: Double = 0     // 일시정지까지 누적된 초
    var timerStartedAt: Date?               // 진행 중 시작 앵커 — nil = 멈춤
    /// 하루 중 시각(자정 기준 분, 2026-08-09) — InputItem.timeMinutes와 동일 계약
    var timeMinutes: Int?

    var schedule: OutputSchedule {
        get { (try? JSONDecoder().decode(OutputSchedule.self, from: scheduleData)) ?? .daily }
        set { scheduleData = (try? JSONEncoder().encode(newValue)) ?? scheduleData }
    }

    var isTimerRunning: Bool { timerStartedAt != nil }

    /// 현재 경과(초) — 누적 + 진행 중 델타
    func elapsedSeconds(at now: Date = .now) -> Double {
        elapsedAccumSeconds + (timerStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    /// createdAt = 시작되는 날 — InputItem과 같은 근거(2026-07-26).
    init(title: String, schedule: OutputSchedule, progressKind: OutputProgressKind = .percent,
         createdAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.scheduleData = (try? JSONEncoder().encode(schedule)) ?? Data()
        self.progressKind = progressKind
        self.subtasks = []
        self.targetSessions = 0
        self.loggedSessions = 0
        self.percent = 0
        self.createdAt = createdAt
        self.targetSeconds = nil
        self.elapsedAccumSeconds = 0
        self.timerStartedAt = nil
        self.timeMinutes = nil
    }

    /// .once·.daily·.weekly·.monthly 판정(달력 기준) — InputItem.occursByCalendar와 동형(§ 반복 통일).
    func occursByCalendar(on day: Date) -> Bool {
        let cal = Calendar.current
        let start = cal.startOfDay(for: createdAt)
        let target = cal.startOfDay(for: day)
        guard target >= start else { return false }
        switch schedule {
        case .once:     // 반복 없음 — 완료까지 계속 표시(완료 후 미래 미표시는 렌더 규칙 §5.5.2)
            return true
        case .daily:
            return true
        case .weekly:
            return cal.component(.weekday, from: createdAt) == cal.component(.weekday, from: day)
        case .monthly:
            let startDay = cal.component(.day, from: createdAt)
            let targetDay = cal.component(.day, from: day)
            if startDay == targetDay { return true }
            let daysInTargetMonth = cal.range(of: .day, in: .month, for: day)?.count ?? 31
            return startDay > daysInTargetMonth && targetDay == daysInTargetMonth
        case .cycleAnchored:
            return false
        }
    }

    /// 목표 정의 — Input과 같은 값 타입을 쓴다(2026-08-13 규칙 통일)
    var progressGoal: ProgressGoal {
        ProgressGoal(kind: progressKind, targetSessions: targetSessions,
                     targetSeconds: targetSeconds, subtaskCount: (subtasks ?? []).count)
    }

    /// 지금 진행 상태 — Output은 값이 아이템에 누적된다(Input은 그날 레코드)
    var progressState: ProgressState {
        ProgressState(loggedSessions: loggedSessions, percent: percent,
                      elapsedSeconds: elapsedSeconds(),
                      doneSubtasks: (subtasks ?? []).filter(\.isDone).count)
    }

    /// 완료 = 파생 상태(§5.5.2). 저장 필드 아님.
    /// 판정은 ProgressRule 한 곳 — 종전엔 같은 규칙이 여기와 TempoCore 두 벌이었다(2026-08-13).
    /// 스톱워치가 완료 개념 없음도 그 규칙이 갖는다(§5.5.2 파생 완료의 명시적 예외).
    var isComplete: Bool {
        ProgressRule.isFulfilled(goal: progressGoal, state: progressState)
    }
}

// 타이머 저장처 통일(2026-08-13) — 두 모델이 이미 같은 이름·같은 뜻으로 갖고 있어
// 선언만으로 충족된다. 컨트롤은 이 프로토콜만 알고 어느 카드인지 모른다.
extension OutputItem: TimerBacking {}
extension InputProgress: TimerBacking {}

// ── 하루 중 시각 공용 (2026-08-09 사용자 결정 — Input·Output 시각 인식) ──

/// 자정 기준 분 → 로케일 시각 표기(오전 8:00). 일정 행의 time .shortened와 같은 문법.
func timeOfDayLabel(_ minutes: Int) -> String {
    var comps = Calendar.current.dateComponents([.year, .month, .day], from: .now)
    comps.hour = minutes / 60
    comps.minute = minutes % 60
    guard let date = Calendar.current.date(from: comps) else { return "" }
    return date.formatted(date: .omitted, time: .shortened)
}

/// 하루 안 정렬(2026-08-09): 시각 있는 항목 = 시간순, 없는 항목 = 맨 뒤. 동률·무시각은
/// 원래 순서 유지(안정 정렬 — enumerated 인덱스 대조).
func sortedByTimeOfDay<T>(_ items: [T], time: (T) -> Int?) -> [T] {
    items.enumerated().sorted { a, b in
        switch (time(a.element), time(b.element)) {
        case let (t1?, t2?): t1 == t2 ? a.offset < b.offset : t1 < t2
        case (.some, .none): true
        case (.none, .some): false
        case (.none, .none): a.offset < b.offset
        }
    }.map(\.element)
}
