// 템포루틴 — 외부 에이전트 연동 (MASTER §5.14, 개정 Q 2026-11-13)
//
// 아이폰 안의 에이전트(단축어·Siri, 이후 열리는 호출 주체)가 일정·루틴·목표를 넣고 하루·한 주를 읽는다.
// Phase 1 = 추가·조회. Phase 2 = 수정·순서·삭제. **삭제만 실행 전 확인**(2026-11-13 사용자 결정 —
// 수정은 결과 문장으로 알린다). 완료 체크는 앱에서 한다(같은 날 사용자 결정, 인텐트 없음).
//
// **노출 경계(§5.14 계약)**: 주기 기준 아이템(.cycleAnchored)·계절·체크인·생리 기록은 여기서 읽지도
// 쓰지도 않는다. 날짜로 풀어 보여 줘도 단계 시점이 역산되기 때문이다. 존재 자체가 안 보여야 하므로
// 개수에도 넣지 않는다. 판정은 `AgentBoundary` 한 곳이고, 조회 경로는 전부 `AgentAgenda`를 거친다.
//
// **실행 위치 = 앱 프로세스**(앱 타깃). 화면이 떠 있지 않을 수 있어 뷰 대신 스토어를 직접 연다
// (TimerIntentHandler와 같은 구조). 그래서 뷰 쪽 위젯 발행(WidgetRefresher)도 안 돌 수 있다 —
// 쓰기 뒤 발행·동기화는 `AgentStore.commit`이 직접 한다.
//
// **잠금 해제 필수**: 일정·루틴 열람·추가 경로라, 타이머 인텐트의 `.alwaysAllowed` 근거
// ("기록 열람·수정 경로 없음")에 해당하지 않는다.

import AppIntents
import Foundation
import SwiftData
import TempoCore

// MARK: - 스토어·경계

@MainActor
enum AgentStore {
    /// 앱이 지금 보여 주는 스토어 — 개발자 모드면 dev 스토어(TempoRoutineApp.body와 같은 분기).
    static var context: ModelContext {
        (DevMode.active ? TempoRoutineApp.devContainer : TempoRoutineApp.container).mainContext
    }

    static func fetch<T: PersistentModel>(_ context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    /// 쓰기 뒤 — 저장 → 위젯 재발행 → 동기화 왕복. 개발자 모드 게이트는 각 함수 안에 있다(repo CLAUDE.md).
    static func commit(_ context: ModelContext) throws {
        try context.save()
        let periodDays: [PeriodDay] = try fetch(context)
        let schedules: [ScheduleItem] = try fetch(context)
        let inputs: [InputItem] = try fetch(context)
        let outputs: [OutputItem] = try fetch(context)
        let completions: [ItemCompletion] = try fetch(context)
        let progresses: [InputProgress] = try fetch(context)
        WidgetBridge.publish(periodDays: periodDays, schedules: schedules, inputs: inputs,
                             outputs: outputs, completions: completions, inputProgresses: progresses)
        PlannerSync.shared.kick()
    }
}

/// §5.14 노출 경계 — 주기 기준 아이템은 에이전트에게 존재하지 않는다.
enum AgentBoundary {
    static func exposes(_ item: InputItem) -> Bool {
        if case .cycleAnchored = item.schedule { return false }
        return true
    }

    static func exposes(_ item: OutputItem) -> Bool {
        if case .cycleAnchored = item.schedule { return false }
        return true
    }
}

// MARK: - 조회 (경계 적용본)

@MainActor
struct AgentAgenda {
    let schedules: [ScheduleItem]
    let inputs: [InputItem]
    let outputs: [OutputItem]
    let completions: [ItemCompletion]

    static func load(_ context: ModelContext) throws -> AgentAgenda {
        let schedules: [ScheduleItem] = try AgentStore.fetch(context)
        let inputs: [InputItem] = try AgentStore.fetch(context)
        let outputs: [OutputItem] = try AgentStore.fetch(context)
        let completions: [ItemCompletion] = try AgentStore.fetch(context)
        return AgentAgenda(schedules: schedules,
                           inputs: inputs.filter { AgentBoundary.exposes($0) },
                           outputs: outputs.filter { AgentBoundary.exposes($0) },
                           completions: completions)
    }

    /// 하루종일 먼저, 그다음 시작 시각순
    func schedules(on day: Date) -> [ScheduleItem] {
        schedules.filter { $0.occurs(on: day) }.sorted { a, b in
            if a.isAllDay != b.isAllDay { return a.isAllDay }
            return Self.minutes(of: a.date) < Self.minutes(of: b.date)
        }
    }

    /// 하루 상세(DayDetailView.inputRowsUnsorted)와 같은 판정 — .once는 적은 날 또는 완료한 날
    func inputs(on day: Date) -> [InputItem] {
        let shown = inputs.filter { item in
            switch item.schedule {
            case .once: return isDone(item.id, on: day) || item.onceShows(on: day)
            case .daily, .weekly, .monthly: return item.occursByCalendar(on: day) || isDone(item.id, on: day)
            case .cycleAnchored: return false
            }
        }
        return orderedInputs(shown) { $0 }
    }

    func outputs(on day: Date) -> [OutputItem] {
        outputs.filter { $0.occursByCalendar(on: day) }
    }

    func isDone(_ itemID: UUID, on day: Date) -> Bool {
        let cal = Calendar.current
        return completions.contains { $0.itemID == itemID && cal.isDate($0.occurredOn, inSameDayAs: day) }
    }

    /// 하루를 몇 줄로 — 에이전트가 그대로 읽어 줄 수 있는 문장. 계절 이름은 쓰지 않는다(§5.14).
    func describe(_ day: Date) -> String {
        let done = Loc.str("(완료)")
        var lines: [String] = [day.formatted(Loc.dateTime.month().day().weekday(.abbreviated))]

        let scheduleTexts: [String] = schedules(on: day).map { item in
            item.isAllDay ? item.title : "\(item.title) \(item.date.formatted(Loc.shortTime))"
        }
        lines.append(scheduleTexts.isEmpty
                     ? Loc.str("일정 없음")
                     : Loc.fmt("일정: %1$@", scheduleTexts.joined(separator: ", ")))

        let routineTexts: [String] = inputs(on: day).map { item in
            var text = item.title
            if let minutes = item.timeMinutes { text += " \(timeOfDayLabel(minutes))" }
            if isDone(item.id, on: day) { text += " \(done)" }
            return text
        }
        lines.append(routineTexts.isEmpty
                     ? Loc.str("루틴 없음")
                     : Loc.fmt("루틴: %1$@", routineTexts.joined(separator: ", ")))

        let goalTexts: [String] = outputs(on: day).map { item in
            item.isComplete ? "\(item.title) \(done)" : item.title
        }
        if !goalTexts.isEmpty {
            lines.append(Loc.fmt("목표: %1$@", goalTexts.joined(separator: ", ")))
        }
        return lines.joined(separator: "\n")
    }

    static func minutes(of date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}

// MARK: - 오류

enum AgentIntentError: Error, CustomLocalizedStringResourceConvertible {
    case emptyTitle
    case endBeforeStart
    case notFound
    case missingAnchor
    case sameRoutine

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .emptyTitle: "제목이 비어 있어요."
        case .endBeforeStart: "종료가 시작보다 앞서요."
        case .notFound: "찾을 수 없어요. 이미 지워졌을 수 있어요."
        case .missingAnchor: "어느 루틴 앞에 둘지 알려 주세요."
        case .sameRoutine: "같은 루틴이에요."
        }
    }
}

// MARK: - 쓰기 공용 (Phase 2)

@MainActor
enum AgentEdit {
    nonisolated static func title(_ raw: String) throws -> String {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw AgentIntentError.emptyTitle }
        return title
    }

    static func schedule(_ id: UUID, in context: ModelContext) throws -> ScheduleItem {
        let all: [ScheduleItem] = try AgentStore.fetch(context)
        guard let item = all.first(where: { $0.id == id }) else { throw AgentIntentError.notFound }
        return item
    }

    /// 경계 밖(.cycleAnchored)은 없는 것과 같다 — 수정·삭제·순서 대상이 될 수 없다
    static func routine(_ id: UUID, in context: ModelContext) throws -> InputItem {
        let all: [InputItem] = try AgentStore.fetch(context)
        guard let item = all.first(where: { $0.id == id && AgentBoundary.exposes($0) }) else {
            throw AgentIntentError.notFound
        }
        return item
    }

    static func goal(_ id: UUID, in context: ModelContext) throws -> OutputItem {
        let all: [OutputItem] = try AgentStore.fetch(context)
        guard let item = all.first(where: { $0.id == id && AgentBoundary.exposes($0) }) else {
            throw AgentIntentError.notFound
        }
        return item
    }

    /// 시작일 옮기기 — 생성 경로(insertInputItem)와 같은 createdAt·backfilled 규칙.
    /// 이미 완료한 날은 완료 기록 우선 표시라 그날에 남는다(2026-11-13 사용자 결정 "해낸 걸 없애면 안 되지").
    static func moveStart(_ item: InputItem, to day: Date) {
        let cal = Calendar.current
        item.createdAt = anchorDate(for: day)
        item.backfilled = cal.startOfDay(for: day) < AppDay.today(calendar: cal)
    }

    static func moveStart(_ item: OutputItem, to day: Date) {
        item.createdAt = anchorDate(for: day)
    }

    /// 삭제 확인 버튼 — 빨간 「삭제」
    nonisolated static var deleteAction: ConfirmationActionName {
        .custom(acceptLabel: "삭제", acceptAlternatives: [], denyLabel: "취소", denyAlternatives: [],
                destructive: true)
    }

    nonisolated static func dialog(_ text: String) -> IntentDialog {
        IntentDialog(LocalizedStringResource(stringLiteral: text))
    }
}

// MARK: - 선택지

enum ScheduleRepeatOption: String, AppEnum {
    case never, daily, weekly, monthly, yearly

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "반복"
    static let caseDisplayRepresentations: [ScheduleRepeatOption: DisplayRepresentation] = [
        .never: "반복 없음",
        .daily: "매일",
        .weekly: "매주",
        .monthly: "매달",
        .yearly: "매년",
    ]

    var model: ScheduleRepeat {
        switch self {
        case .never: ScheduleRepeat.none
        case .daily: ScheduleRepeat.daily
        case .weekly: ScheduleRepeat.weekly
        case .monthly: ScheduleRepeat.monthly
        case .yearly: ScheduleRepeat.yearly
        }
    }
}

/// 루틴 반복 — 주기 기준(.cycleAnchored)은 선택지에 없다(§5.14 생성 금지).
/// 매주·매달은 시작일의 요일·날짜 하나로 반복한다(현행 InputSchedule 의미론, 여러 요일은 미결).
enum RoutineRepeatOption: String, AppEnum {
    case once, daily, weekly, monthly

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "반복"
    static let caseDisplayRepresentations: [RoutineRepeatOption: DisplayRepresentation] = [
        .once: "한 번",
        .daily: "매일",
        .weekly: "매주",
        .monthly: "매달",
    ]

    var model: InputSchedule {
        switch self {
        case .once: InputSchedule.once
        case .daily: InputSchedule.daily
        case .weekly: InputSchedule.weekly
        case .monthly: InputSchedule.monthly
        }
    }

    /// 목표(Output)도 같은 네 갈래 — 반복 의미론이 Input과 동형(CardModels occursByCalendar)
    var goalModel: OutputSchedule {
        switch self {
        case .once: OutputSchedule.once
        case .daily: OutputSchedule.daily
        case .weekly: OutputSchedule.weekly
        case .monthly: OutputSchedule.monthly
        }
    }
}

/// 루틴 순서 — 전체 순서 기준이라 어느 날 화면에서든 같은 자리로 보인다
enum RoutinePlacement: String, AppEnum {
    case top, bottom, before

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "위치"
    static let caseDisplayRepresentations: [RoutinePlacement: DisplayRepresentation] = [
        .top: "맨 위",
        .bottom: "맨 아래",
        .before: "다른 루틴 앞",
    ]
}

enum AgendaRange: String, AppEnum {
    case today, week

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "범위"
    static let caseDisplayRepresentations: [AgendaRange: DisplayRepresentation] = [
        .today: "오늘",
        .week: "앞으로 7일",
    ]
}

// MARK: - 엔티티

struct ScheduleEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "일정"
    static let defaultQuery = ScheduleEntityQuery()

    let id: UUID
    let title: String
    let whenLabel: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(whenLabel)")
    }

    init(_ item: ScheduleItem) {
        id = item.id
        title = item.title
        let day = item.date.formatted(Loc.dateTime.month().day().weekday(.abbreviated))
        let allDay = Loc.str("하루 종일")
        whenLabel = item.isAllDay
            ? "\(day) \(allDay)"
            : "\(day) \(item.date.formatted(Loc.shortTime))"
    }
}

struct ScheduleEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ScheduleEntity] {
        let all: [ScheduleItem] = try AgentStore.fetch(AgentStore.context)
        return all.filter { identifiers.contains($0.id) }.map { ScheduleEntity($0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ScheduleEntity] {
        let all: [ScheduleItem] = try AgentStore.fetch(AgentStore.context)
        return all.map { ScheduleEntity($0) }
    }
}

struct RoutineEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "루틴"
    static let defaultQuery = RoutineEntityQuery()

    let id: UUID
    let title: String
    let repeatLabel: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(repeatLabel)")
    }

    /// 경계 밖(.cycleAnchored) 아이템으로는 만들지 않는다 — 쿼리가 먼저 거른다
    init(_ item: InputItem) {
        id = item.id
        title = item.title
        let label: String = switch item.schedule {
        case .once: Loc.str("한 번")
        case .daily: Loc.str("매일")
        case .weekly: Loc.str("매주")
        case .monthly: Loc.str("매달")
        case .cycleAnchored: ""
        }
        repeatLabel = item.timeMinutes.map { "\(label) \(timeOfDayLabel($0))" } ?? label
    }
}

struct GoalEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "목표"
    static let defaultQuery = GoalEntityQuery()

    let id: UUID
    let title: String
    let repeatLabel: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(repeatLabel)")
    }

    /// RoutineEntity와 같은 라벨 — 경계 밖 아이템은 쿼리가 먼저 거른다
    init(_ item: OutputItem) {
        id = item.id
        title = item.title
        let label: String = switch item.schedule {
        case .once: Loc.str("한 번")
        case .daily: Loc.str("매일")
        case .weekly: Loc.str("매주")
        case .monthly: Loc.str("매달")
        case .cycleAnchored: ""
        }
        repeatLabel = item.timeMinutes.map { "\(label) \(timeOfDayLabel($0))" } ?? label
    }
}

struct GoalEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [GoalEntity] {
        let all: [OutputItem] = try AgentStore.fetch(AgentStore.context)
        return all.filter { identifiers.contains($0.id) && AgentBoundary.exposes($0) }
            .map { GoalEntity($0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [GoalEntity] {
        let all: [OutputItem] = try AgentStore.fetch(AgentStore.context)
        return all.filter { AgentBoundary.exposes($0) }.map { GoalEntity($0) }
    }
}

struct RoutineEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [RoutineEntity] {
        let all: [InputItem] = try AgentStore.fetch(AgentStore.context)
        return all.filter { identifiers.contains($0.id) && AgentBoundary.exposes($0) }
            .map { RoutineEntity($0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [RoutineEntity] {
        let all: [InputItem] = try AgentStore.fetch(AgentStore.context)
        return all.filter { AgentBoundary.exposes($0) }.map { RoutineEntity($0) }
    }
}

// MARK: - 인텐트

struct AddScheduleIntent: AppIntent {
    static let title: LocalizedStringResource = "일정 추가"
    static let description: IntentDescription? = IntentDescription("템포루틴 캘린더에 일정을 추가해요.", resultValueName: nil)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "제목") var itemTitle: String
    @Parameter(title: "시작") var start: Date
    @Parameter(title: "하루 종일", default: false) var isAllDay: Bool
    @Parameter(title: "종료") var end: Date?
    @Parameter(title: "반복", default: .never) var repeatRule: ScheduleRepeatOption

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<ScheduleEntity> & ProvidesDialog {
        let title = itemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw AgentIntentError.emptyTitle }
        let cal = Calendar.current
        let begin = isAllDay ? cal.startOfDay(for: start) : start
        var finish: Date? = nil
        if let end {
            let endBase = isAllDay ? cal.startOfDay(for: end) : end
            guard endBase >= begin else { throw AgentIntentError.endBeforeStart }
            // 하루종일 = 종료 날짜(같은 날이면 하루짜리 nil — 추가 시트 allDayEndDate와 같은 규칙)
            finish = isAllDay ? (endBase > begin ? endBase : nil) : endBase
        }
        let context = AgentStore.context
        // 알림 없음(-1) 고정 — 빠른 일정 바와 같은 기본값(§5.14)
        let item = insertScheduleItem(into: context, title: title, start: begin, isAllDay: isAllDay,
                                      repeatRule: repeatRule.model, endDate: finish, reminderMinutes: -1)
        try AgentStore.commit(context)
        let entity = ScheduleEntity(item)
        let text = Loc.fmt("「%1$@」 일정을 넣었어요. %2$@", title, entity.whenLabel)
        return .result(value: entity, dialog: IntentDialog(LocalizedStringResource(stringLiteral: text)))
    }
}

struct AddRoutineIntent: AppIntent {
    static let title: LocalizedStringResource = "루틴 추가"
    static let description: IntentDescription? = IntentDescription("템포루틴에 루틴을 추가해요. 매주·매달은 시작일의 요일·날짜로 반복해요.", resultValueName: nil)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "제목") var itemTitle: String
    @Parameter(title: "반복", default: .daily) var repeatRule: RoutineRepeatOption
    @Parameter(title: "시작일") var startDay: Date?
    @Parameter(title: "시각") var time: Date?

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<RoutineEntity> & ProvidesDialog {
        let title = itemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw AgentIntentError.emptyTitle }
        let day = startDay.map { Calendar.current.startOfDay(for: $0) } ?? AppDay.today()
        let context = AgentStore.context
        let item = insertInputItem(into: context, title: title, category: .other,
                                   schedule: repeatRule.model, day: day,
                                   timeMinutes: time.map { AgentAgenda.minutes(of: $0) })
        try AgentStore.commit(context)
        let entity = RoutineEntity(item)
        let text = Loc.fmt("「%1$@」 루틴을 넣었어요. %2$@", title, entity.repeatLabel)
        return .result(value: entity, dialog: IntentDialog(LocalizedStringResource(stringLiteral: text)))
    }
}

struct SummarizeAgendaIntent: AppIntent {
    static let title: LocalizedStringResource = "일정·루틴 요약"
    static let description: IntentDescription? = IntentDescription("템포루틴의 일정·루틴·목표와 완료 여부를 날짜별로 알려 줘요.", resultValueName: nil)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "범위", default: .today) var range: AgendaRange

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let agenda = try AgentAgenda.load(AgentStore.context)
        let cal = Calendar.current
        let today = AppDay.today()
        let count = range == .today ? 1 : 7
        let days: [Date] = (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
        let text = days.map { agenda.describe($0) }.joined(separator: "\n\n")
        return .result(value: text, dialog: IntentDialog(LocalizedStringResource(stringLiteral: text)))
    }
}

struct DayAgendaIntent: AppIntent {
    static let title: LocalizedStringResource = "하루 일정 보기"
    static let description: IntentDescription? = IntentDescription("지정한 날짜의 일정·루틴·목표를 알려 줘요.", resultValueName: nil)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "날짜") var day: Date

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let agenda = try AgentAgenda.load(AgentStore.context)
        let text = agenda.describe(Calendar.current.startOfDay(for: day))
        return .result(value: text, dialog: IntentDialog(LocalizedStringResource(stringLiteral: text)))
    }
}

/// 목표는 「체크만」으로만 만든다(2026-11-13 사용자 결정) — 진행 방식 파라미터를 열지 않는다
struct AddGoalIntent: AppIntent {
    static let title: LocalizedStringResource = "목표 추가"
    static let description: IntentDescription? = IntentDescription("템포루틴에 체크 하나로 끝나는 목표를 추가해요.", resultValueName: nil)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "제목") var itemTitle: String
    @Parameter(title: "반복", default: .once) var repeatRule: RoutineRepeatOption
    @Parameter(title: "시작일") var startDay: Date?
    @Parameter(title: "시각") var time: Date?

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<GoalEntity> & ProvidesDialog {
        let title = try AgentEdit.title(itemTitle)
        let day = startDay.map { Calendar.current.startOfDay(for: $0) } ?? AppDay.today()
        let context = AgentStore.context
        let item = OutputItem(title: title, schedule: repeatRule.goalModel, progressKind: .checkOnly,
                              createdAt: anchorDate(for: day))
        item.timeMinutes = time.map { AgentAgenda.minutes(of: $0) }
        context.insert(item)
        try AgentStore.commit(context)
        let entity = GoalEntity(item)
        let text = Loc.fmt("「%1$@」 목표를 넣었어요. %2$@", title, entity.repeatLabel)
        return .result(value: entity, dialog: AgentEdit.dialog(text))
    }
}

// MARK: - Phase 2 수정 — 비워 둔 파라미터는 그대로 둔다

struct EditScheduleIntent: AppIntent {
    static let title: LocalizedStringResource = "일정 수정"
    static let description: IntentDescription? = IntentDescription("템포루틴 일정의 제목·시간·반복을 고쳐요. 비워 둔 항목은 그대로 둬요.", resultValueName: nil)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "일정") var schedule: ScheduleEntity
    @Parameter(title: "새 제목") var newTitle: String?
    @Parameter(title: "시작") var start: Date?
    @Parameter(title: "하루 종일") var isAllDay: Bool?
    @Parameter(title: "종료") var end: Date?
    @Parameter(title: "반복") var repeatRule: ScheduleRepeatOption?

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<ScheduleEntity> & ProvidesDialog {
        let context = AgentStore.context
        let item = try AgentEdit.schedule(schedule.id, in: context)
        let title = try newTitle.map { try AgentEdit.title($0) } ?? item.title
        let cal = Calendar.current
        let allDay = isAllDay ?? item.isAllDay
        let rawStart = start ?? item.date
        let begin = allDay ? cal.startOfDay(for: rawStart) : rawStart
        let finish: Date?
        if let end {
            let endBase = allDay ? cal.startOfDay(for: end) : end
            guard endBase >= begin else { throw AgentIntentError.endBeforeStart }
            finish = allDay ? (endBase > begin ? endBase : nil) : endBase
        } else if let oldEnd = item.endDate, allDay == item.isAllDay {
            // 시작만 옮기면 길이를 유지한다
            finish = oldEnd.addingTimeInterval(begin.timeIntervalSince(item.date))
        } else {
            finish = nil
        }
        updateScheduleItem(item, title: title, start: begin, isAllDay: allDay,
                           repeatRule: repeatRule?.model ?? item.repeatRule, endDate: finish,
                           reminderMinutes: item.reminderMinutes)
        try AgentStore.commit(context)
        let entity = ScheduleEntity(item)
        let text = Loc.fmt("「%1$@」 일정을 고쳤어요. %2$@", title, entity.whenLabel)
        return .result(value: entity, dialog: AgentEdit.dialog(text))
    }
}

struct EditRoutineIntent: AppIntent {
    static let title: LocalizedStringResource = "루틴 수정"
    static let description: IntentDescription? = IntentDescription("루틴의 제목·반복·시작일·시각을 고쳐요. 비워 둔 항목은 그대로 둬요. 이미 완료한 날의 기록은 남아요.", resultValueName: nil)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "루틴") var routine: RoutineEntity
    @Parameter(title: "새 제목") var newTitle: String?
    @Parameter(title: "반복") var repeatRule: RoutineRepeatOption?
    @Parameter(title: "시작일") var startDay: Date?
    @Parameter(title: "시각") var time: Date?

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<RoutineEntity> & ProvidesDialog {
        let context = AgentStore.context
        let item = try AgentEdit.routine(routine.id, in: context)
        let title = try newTitle.map { try AgentEdit.title($0) } ?? item.title
        item.title = title
        if let repeatRule { item.schedule = repeatRule.model }
        if let startDay { AgentEdit.moveStart(item, to: startDay) }
        if let time { item.timeMinutes = AgentAgenda.minutes(of: time) }
        try AgentStore.commit(context)
        let entity = RoutineEntity(item)
        let text = Loc.fmt("「%1$@」 루틴을 고쳤어요. %2$@", title, entity.repeatLabel)
        return .result(value: entity, dialog: AgentEdit.dialog(text))
    }
}

struct EditGoalIntent: AppIntent {
    static let title: LocalizedStringResource = "목표 수정"
    static let description: IntentDescription? = IntentDescription("목표의 제목·반복·시작일·시각을 고쳐요. 비워 둔 항목은 그대로 둬요.", resultValueName: nil)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "목표") var goal: GoalEntity
    @Parameter(title: "새 제목") var newTitle: String?
    @Parameter(title: "반복") var repeatRule: RoutineRepeatOption?
    @Parameter(title: "시작일") var startDay: Date?
    @Parameter(title: "시각") var time: Date?

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<GoalEntity> & ProvidesDialog {
        let context = AgentStore.context
        let item = try AgentEdit.goal(goal.id, in: context)
        let title = try newTitle.map { try AgentEdit.title($0) } ?? item.title
        item.title = title
        if let repeatRule { item.schedule = repeatRule.goalModel }
        if let startDay { AgentEdit.moveStart(item, to: startDay) }
        if let time { item.timeMinutes = AgentAgenda.minutes(of: time) }
        try AgentStore.commit(context)
        let entity = GoalEntity(item)
        let text = Loc.fmt("「%1$@」 목표를 고쳤어요. %2$@", title, entity.repeatLabel)
        return .result(value: entity, dialog: AgentEdit.dialog(text))
    }
}

struct MoveRoutineIntent: AppIntent {
    static let title: LocalizedStringResource = "루틴 순서 바꾸기"
    static let description: IntentDescription? = IntentDescription("루틴을 맨 위·맨 아래나 다른 루틴 앞으로 옮겨요.", resultValueName: nil)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "루틴") var routine: RoutineEntity
    @Parameter(title: "위치", default: .top) var placement: RoutinePlacement
    @Parameter(title: "기준 루틴") var anchor: RoutineEntity?

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = AgentStore.context
        let moving = try AgentEdit.routine(routine.id, in: context)
        let all: [InputItem] = try AgentStore.fetch(context)
        // 전체 순서를 「보이는 목록」으로 넘긴다 — 맨 위·맨 아래가 어느 날 화면에서든 같은 뜻이 된다
        let ordered = orderedInputs(all) { $0 }
        let others = ordered.filter { $0.id != moving.id }
        let index: Int
        switch placement {
        case .top:
            index = 0
        case .bottom:
            index = others.count
        case .before:
            guard let anchor else { throw AgentIntentError.missingAnchor }
            guard anchor.id != moving.id else { throw AgentIntentError.sameRoutine }
            guard let at = others.firstIndex(where: { $0.id == anchor.id && AgentBoundary.exposes($0) }) else {
                throw AgentIntentError.notFound
            }
            index = at
        }
        moveInput(moving, toVisibleIndex: index, visible: ordered, all: all)
        try AgentStore.commit(context)
        return .result(dialog: AgentEdit.dialog(Loc.fmt("「%1$@」 루틴을 옮겼어요.", moving.title)))
    }
}

// MARK: - Phase 2 삭제 — 실행 전 확인. 확인은 모델을 꺼내기 전에 받는다(await 너머로 모델을 들고 가지 않음)

struct DeleteScheduleIntent: AppIntent {
    static let title: LocalizedStringResource = "일정 삭제"
    static let description: IntentDescription? = IntentDescription("일정을 지워요. 지우기 전에 확인을 받아요.", resultValueName: nil)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "일정") var schedule: ScheduleEntity

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let title = schedule.title
        try await requestConfirmation(actionName: AgentEdit.deleteAction,
                                      dialog: AgentEdit.dialog(Loc.fmt("「%1$@」 일정을 지울까요?", title)))
        let context = AgentStore.context
        let item = try AgentEdit.schedule(schedule.id, in: context)
        let completions: [ItemCompletion] = try AgentStore.fetch(context)
        QuickDeleteTarget.schedule(item).delete(from: context, completions: completions)
        try AgentStore.commit(context)
        return .result(dialog: AgentEdit.dialog(Loc.fmt("「%1$@」 일정을 지웠어요.", title)))
    }
}

struct DeleteRoutineIntent: AppIntent {
    static let title: LocalizedStringResource = "루틴 삭제"
    static let description: IntentDescription? = IntentDescription("루틴과 그 완료 기록을 지워요. 지우기 전에 확인을 받아요.", resultValueName: nil)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "루틴") var routine: RoutineEntity

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let title = routine.title
        try await requestConfirmation(actionName: AgentEdit.deleteAction,
                                      dialog: AgentEdit.dialog(Loc.fmt("「%1$@」 루틴을 지울까요? 완료 기록도 함께 지워져요.", title)))
        let context = AgentStore.context
        let item = try AgentEdit.routine(routine.id, in: context)
        let completions: [ItemCompletion] = try AgentStore.fetch(context)
        QuickDeleteTarget.input(item).delete(from: context, completions: completions)
        try AgentStore.commit(context)
        return .result(dialog: AgentEdit.dialog(Loc.fmt("「%1$@」 루틴을 지웠어요.", title)))
    }
}

struct DeleteGoalIntent: AppIntent {
    static let title: LocalizedStringResource = "목표 삭제"
    static let description: IntentDescription? = IntentDescription("목표를 지워요. 지우기 전에 확인을 받아요.", resultValueName: nil)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "목표") var goal: GoalEntity

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let title = goal.title
        try await requestConfirmation(actionName: AgentEdit.deleteAction,
                                      dialog: AgentEdit.dialog(Loc.fmt("「%1$@」 목표를 지울까요?", title)))
        let context = AgentStore.context
        let item = try AgentEdit.goal(goal.id, in: context)
        let completions: [ItemCompletion] = try AgentStore.fetch(context)
        QuickDeleteTarget.output(item).delete(from: context, completions: completions)
        try AgentStore.commit(context)
        return .result(dialog: AgentEdit.dialog(Loc.fmt("「%1$@」 목표를 지웠어요.", title)))
    }
}

// MARK: - 호출 문구

/// 호출 문구는 원문(ko)만 — 다국어 문구는 AppShortcuts.xcstrings 형식 확인 뒤(PENDING).
struct TempoAgentShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddScheduleIntent(),
                    phrases: ["\(.applicationName)에 일정 추가", "\(.applicationName) 일정 추가"],
                    shortTitle: "일정 추가", systemImageName: "calendar.badge.plus")
        AppShortcut(intent: AddRoutineIntent(),
                    phrases: ["\(.applicationName)에 루틴 추가", "\(.applicationName) 루틴 추가"],
                    shortTitle: "루틴 추가", systemImageName: "checklist")
        AppShortcut(intent: AddGoalIntent(),
                    phrases: ["\(.applicationName)에 목표 추가", "\(.applicationName) 목표 추가"],
                    shortTitle: "목표 추가", systemImageName: "target")
        AppShortcut(intent: SummarizeAgendaIntent(),
                    phrases: ["\(.applicationName) 요약", "\(.applicationName) 오늘 루틴 알려줘"],
                    shortTitle: "일정·루틴 요약", systemImageName: "text.append")
        AppShortcut(intent: DayAgendaIntent(),
                    phrases: ["\(.applicationName) 하루 일정 보기"],
                    shortTitle: "하루 일정 보기", systemImageName: "calendar")
    }
}
