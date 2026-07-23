// 템포루틴 — 3카드 추가 시트 (MASTER §8.2.4)
// Input 제목 예시 = 카테고리×현재 계절 매트릭스(§8.1 정정 노트 — 허락 톤 예시, 처방 아님).
// 미저장 내용이 있으면 dismiss 확인(§8.2.4). one-shot엔 skip 미노출 — overflow는 P0 기본 clamp(§5.5.3).

import SwiftUI
import SwiftData
import TempoCore

/// 반복 빈도 칩(매일/매주/매달/매년) — 일정·Input 추가 시트 공용(프로토 opt-chips 문법, 2026-07-22)
private struct FreqChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? Ink.paper : Ink.text.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(selected ? AnyShapeStyle(Ink.text) : AnyShapeStyle(Ink.text.opacity(0.08)),
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// 계절 앵커 선택 (프로토 v77 Output 시트 문법: 시작 계절 4칩)
enum SeasonAnchor: String, CaseIterable, Identifiable {
    case winter = "겨울", spring = "봄", summer = "여름", autumn = "가을"
    var id: String { rawValue }
    var phase: CyclePhase {
        switch self {
        case .winter: .menstrual
        case .spring: .follicular
        case .summer: .ovulation
        case .autumn: .luteal
        }
    }
}

// ── ① 일정 추가·수정 (2026-07-22 캘린더 이벤트 문법 / 2026-07-23 수정·삭제 추가 — 행 탭 = 이 시트) ──
struct ScheduleAddSheet: View {
    let defaultDate: Date
    var editing: ScheduleItem? = nil   // nil = 추가 / 값 = 수정(삭제 버튼 노출)

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool
    @State private var title = ""
    @State private var allDay = true
    @State private var start: Date
    @State private var end: Date
    @State private var repeatRule: ScheduleRepeat = .none
    @State private var reminderMinutes = -1
    @State private var showDeleteConfirm = false

    private static let repeatChoices: [ScheduleRepeat] = [.daily, .weekly, .monthly, .yearly]
    /// 시간 지정 일정 — 시작 기준 N분 전
    private static let timedReminders: [(label: String, minutes: Int)] =
        [("없음", -1), ("정시", 0), ("10분 전", 10), ("30분 전", 30), ("1시간 전", 60), ("1일 전", 1440)]
    /// 하루종일 일정 — 기준 시각 오전 9시(ScheduleReminder.allDayHour)
    private static let allDayReminders: [(label: String, minutes: Int)] =
        [("없음", -1), ("당일 아침", 0), ("전날 아침", 1440)]

    init(defaultDate: Date, editing: ScheduleItem? = nil) {
        self.defaultDate = defaultDate
        self.editing = editing
        if let item = editing {
            _title = State(initialValue: item.title)
            _allDay = State(initialValue: item.isAllDay)
            _start = State(initialValue: item.date)
            _end = State(initialValue: item.endDate ?? item.date.addingTimeInterval(3600))
            _repeatRule = State(initialValue: item.repeatRule)
            _reminderMinutes = State(initialValue: item.reminderMinutes)
        } else {
            // 시간 지정 전환 시의 기본 시각 — 선택 날짜 + (지금 시각의 다음 정시), 1시간짜리
            let cal = Calendar.current
            var comps = cal.dateComponents([.year, .month, .day], from: defaultDate)
            comps.hour = min(23, cal.component(.hour, from: .now) + 1)
            let base = cal.date(from: comps) ?? defaultDate
            _start = State(initialValue: base)
            _end = State(initialValue: base.addingTimeInterval(3600))
        }
    }

    private var reminderChoices: [(label: String, minutes: Int)] {
        allDay ? Self.allDayReminders : Self.timedReminders
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("제목", text: $title)
                        .font(.title3.weight(.semibold))
                        .focused($titleFocused)
                }
                Section {
                    Toggle("하루종일", isOn: $allDay)
                        .tint(Ink.text)
                    DatePicker("시작", selection: $start,
                               displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                    if !allDay {
                        DatePicker("종료", selection: $end, in: start...,
                                   displayedComponents: [.date, .hourAndMinute])
                    }
                }
                Section {
                    Toggle("반복", isOn: Binding(
                        get: { repeatRule != .none },
                        set: { on in repeatRule = on ? .daily : .none }
                    ))
                    .tint(Ink.text)
                    if repeatRule != .none {
                        HStack(spacing: 6) {
                            ForEach(Self.repeatChoices, id: \.self) { freq in
                                FreqChip(label: freq.shortLabel ?? "", selected: repeatRule == freq) {
                                    repeatRule = freq
                                }
                            }
                        }
                    }
                }
                Section {
                    Picker("알림", selection: $reminderMinutes) {
                        ForEach(reminderChoices, id: \.minutes) { choice in
                            Text(choice.label).tag(choice.minutes)
                        }
                    }
                }
                if editing != nil {
                    // 파괴 액션 분리 배치 + 확인(§8.2.6 문법)
                    Section {
                        Button("일정 삭제", role: .destructive) { showDeleteConfirm = true }
                            .foregroundStyle(Ink.danger)
                    }
                }
            }
            .confirmationDialog("이 일정을 삭제할까요?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    if let item = editing {
                        ScheduleReminder.cancel(id: item.id)
                        modelContext.delete(item)
                    }
                    dismiss()
                }
                Button("취소", role: .cancel) {}
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: start) {
                if end <= start { end = start.addingTimeInterval(3600) }
            }
            .onChange(of: allDay) {
                // 하루종일 전환 시 알림 선택지가 달라짐 — 유효하지 않은 값은 없음으로
                if !reminderChoices.contains(where: { $0.minutes == reminderMinutes }) { reminderMinutes = -1 }
            }
            .navigationTitle(editing == nil ? "일정 추가" : "일정 수정")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!title.isEmpty)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }.foregroundStyle(Ink.text)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        if let item = editing {
                            item.title = title
                            item.date = start
                            item.isAllDay = allDay
                            item.repeatRule = repeatRule
                            item.endDate = allDay ? nil : end
                            item.reminderMinutes = reminderMinutes
                            ScheduleReminder.cancel(id: item.id)   // 알림 재예약 — 시간·반복이 바뀌었을 수 있음
                            ScheduleReminder.schedule(id: item.id, title: title, date: start,
                                                      isAllDay: allDay, repeatRule: repeatRule,
                                                      reminderMinutes: reminderMinutes)
                        } else {
                            let item = ScheduleItem(title: title, date: start, isAllDay: allDay,
                                                    repeatRule: repeatRule,
                                                    endDate: allDay ? nil : end,
                                                    reminderMinutes: reminderMinutes)
                            modelContext.insert(item)
                            ScheduleReminder.schedule(id: item.id, title: item.title, date: start,
                                                      isAllDay: allDay, repeatRule: repeatRule,
                                                      reminderMinutes: reminderMinutes)
                        }
                        dismiss()
                    }
                    .foregroundStyle(Ink.text)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") { titleFocused = false }.foregroundStyle(Ink.text)
                }
            }
        }
    }
}

// ── ② Input 추가 ──
struct InputAddSheet: View {
    let currentSeason: SeasonMeta?
    /// 기록상 에너지 수준(2026-07-23) — 있으면 제목 예시를 에너지별로, 없으면 계절 매트릭스 폴백
    var energyLevel: EnergyLevel? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var category: InputCategory = .other
    @State private var repeats = true      // 기본 = 매일(체크리스트가 본질). 반복+주기 둘 다 끔 = .once(2026-07-23)
    @State private var cycleBased = false
    @State private var calendarFreq: ScheduleRepeat = .daily   // 반복(달력 기준) 칩 선택 — daily/weekly/monthly만 사용
    @State private var anchor: SeasonAnchor = .winter
    @State private var offset = 0
    @State private var everyCycle = true

    private static let calendarChoices: [ScheduleRepeat] = [.daily, .weekly, .monthly]

    private static let examples: [InputCategory: [String: String]] = [
        .food:     ["겨울": "따뜻한 국 한 그릇", "봄": "가벼운 아침 식사", "여름": "시원한 과일 한 접시", "가을": "든든한 저녁 챙기기"],
        .exercise: ["겨울": "가볍게 걷기 20분", "봄": "아침 러닝", "여름": "수영 30분", "가을": "저녁 요가"],
        .media:    ["겨울": "포근한 영화 한 편", "봄": "새 플레이리스트 찾기", "여름": "팟캐스트 한 편", "가을": "책 한 챕터"],
        .other:    ["겨울": "철분 챙기기", "봄": "새 노트 펴기", "여름": "물 자주 마시기", "가을": "반신욕"],
    ]

    private var placeholder: String {
        if let level = energyLevel {
            return "예: \(EnergyProfile.inputExample(category: category, level: level))"
        }
        let byCat = Self.examples[category] ?? [:]
        let ex = currentSeason.flatMap { byCat[$0.name] } ?? "스트레칭 10분"
        return "예: \(ex)"
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(placeholder, text: $title)
                Picker("카테고리", selection: $category) {
                    Text("식단").tag(InputCategory.food)
                    Text("운동").tag(InputCategory.exercise)
                    Text("미디어").tag(InputCategory.media)
                    Text("기타").tag(InputCategory.other)
                }
                Section {
                    // 상호 배타(둘 다 끔 = 단발 체크 — Output과 동일 문법, 2026-07-23)
                    Toggle("반복", isOn: Binding(
                        get: { repeats },
                        set: { on in repeats = on; if on { cycleBased = false } }
                    ))
                    .tint(Ink.text)
                    if repeats {
                        HStack(spacing: 6) {
                            ForEach(Self.calendarChoices, id: \.self) { freq in
                                FreqChip(label: freq.shortLabel ?? "", selected: calendarFreq == freq) {
                                    calendarFreq = freq
                                }
                            }
                        }
                    }
                    Toggle("주기 기준", isOn: Binding(
                        get: { cycleBased },
                        set: { on in cycleBased = on; if on { repeats = false } }
                    ))
                    .tint(Ink.text)
                    if cycleBased {
                        Picker("시작 계절", selection: $anchor) {
                            ForEach(SeasonAnchor.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Stepper("계절 시작 +\(offset)일", value: $offset, in: 0...13)
                        Toggle("매 주기 반복", isOn: $everyCycle)
                    }
                    if !repeats && !cycleBased {
                        Text("반복 없이, 체크할 때까지 계속 보여요.")
                            .font(.footnote)
                            .foregroundStyle(Ink.text.opacity(0.5))
                    }
                }
            }
            .navigationTitle("Input 추가")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!title.isEmpty)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }.foregroundStyle(Ink.text)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        let schedule: InputSchedule
                        if cycleBased {
                            schedule = .cycleAnchored(CycleRecurrence(anchor: .phase(anchor.phase), dayOffset: offset,
                                                                      repeatsEveryCycle: everyCycle, overflowRule: .clamp))
                        } else if repeats {
                            switch calendarFreq {
                            case .weekly:  schedule = .weekly
                            case .monthly: schedule = .monthly
                            default:       schedule = .daily
                            }
                        } else {
                            schedule = .once
                        }
                        modelContext.insert(InputItem(title: title, category: category, schedule: schedule))
                        dismiss()
                    }
                    .foregroundStyle(Ink.text)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// ── ③ Output 추가 ──
struct OutputAddSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var repeats = false     // 반복 끔 + 주기 끔 = .once(2026-07-22 베타 피드백 — 단발 목표)
    @State private var cycleBased = false
    @State private var calendarFreq: ScheduleRepeat = .daily   // 반복(달력 기준) 칩 선택 — daily/weekly/monthly만 사용
    @State private var anchor: SeasonAnchor = .winter
    @State private var offset = 0
    @State private var everyCycle = true
    @State private var kind: OutputProgressKind = .percent
    @State private var targetSessions = 3
    @State private var subtaskDraft = ""
    @State private var subtasks: [String] = []
    @State private var initialPercent: Double = 0

    private static let calendarChoices: [ScheduleRepeat] = [.daily, .weekly, .monthly]

    var body: some View {
        NavigationStack {
            Form {
                TextField("예: 자격증 공부", text: $title)
                Section {
                    // 상호 배타(둘 다 끔 = 반복 없음 — 완료까지 계속 표시. 2026-07-22 베타 피드백)
                    Toggle("반복", isOn: Binding(
                        get: { repeats },
                        set: { on in repeats = on; if on { cycleBased = false } }
                    ))
                    .tint(Ink.text)
                    if repeats {
                        HStack(spacing: 6) {
                            ForEach(Self.calendarChoices, id: \.self) { freq in
                                FreqChip(label: freq.shortLabel ?? "", selected: calendarFreq == freq) {
                                    calendarFreq = freq
                                }
                            }
                        }
                    }
                    Toggle("주기 기준", isOn: Binding(
                        get: { cycleBased },
                        set: { on in cycleBased = on; if on { repeats = false } }
                    ))
                    .tint(Ink.text)
                    if cycleBased {
                        Picker("시작 계절", selection: $anchor) {
                            ForEach(SeasonAnchor.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Stepper("계절 시작 +\(offset)일", value: $offset, in: 0...13)
                        Toggle("매 주기 반복", isOn: $everyCycle)
                    }
                    if !repeats && !cycleBased {
                        Text("반복 없이, 완료할 때까지 계속 보여요.")
                            .font(.footnote)
                            .foregroundStyle(Ink.text.opacity(0.5))
                    }
                }
                Section("진행 방식") {
                    Picker("진행 방식", selection: $kind) {
                        Text("서브태스크").tag(OutputProgressKind.subtasks)
                        Text("세션").tag(OutputProgressKind.sessions)
                        Text("퍼센트").tag(OutputProgressKind.percent)
                    }
                    .pickerStyle(.segmented)
                    if kind == .sessions {
                        Stepper("목표 \(targetSessions)세션", value: $targetSessions, in: 1...50)
                    }
                    if kind == .subtasks {
                        ForEach(subtasks, id: \.self) { Text($0).font(.footnote) }
                        HStack {
                            TextField("서브태스크 추가", text: $subtaskDraft)
                            Button("추가") {
                                let t = subtaskDraft.trimmingCharacters(in: .whitespaces)
                                if !t.isEmpty { subtasks.append(t); subtaskDraft = "" }
                            }
                            .disabled(subtaskDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    if kind == .percent {
                        HStack(spacing: 10) {
                            Slider(value: $initialPercent, in: 0...1)
                                .tint(Ink.text)
                            Text(initialPercent.formatted(.percent.precision(.fractionLength(0))))
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(Ink.text.opacity(0.7))
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
            .navigationTitle("Output 추가")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!title.isEmpty)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }.foregroundStyle(Ink.text)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        let schedule: OutputSchedule
                        if cycleBased {
                            schedule = .cycleAnchored(CycleRecurrence(anchor: .phase(anchor.phase), dayOffset: offset,
                                                                      repeatsEveryCycle: everyCycle, overflowRule: .clamp))
                        } else if repeats {
                            switch calendarFreq {
                            case .weekly:  schedule = .weekly
                            case .monthly: schedule = .monthly
                            default:       schedule = .daily
                            }
                        } else {
                            schedule = .once
                        }
                        let item = OutputItem(title: title, schedule: schedule, progressKind: kind)
                        if kind == .sessions { item.targetSessions = targetSessions }
                        if kind == .subtasks {
                            item.subtasks = subtasks.enumerated().map { OutputSubtask(title: $0.element, order: $0.offset) }
                        }
                        if kind == .percent { item.percent = initialPercent }
                        modelContext.insert(item)
                        dismiss()
                    }
                    .foregroundStyle(Ink.text)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
