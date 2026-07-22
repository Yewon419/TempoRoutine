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

// ── ① 일정 추가 ──
struct ScheduleAddSheet: View {
    let defaultDate: Date

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date: Date
    @State private var timed = false
    @State private var repeatRule: ScheduleRepeat = .none

    private static let repeatChoices: [ScheduleRepeat] = [.daily, .weekly, .monthly, .yearly]

    init(defaultDate: Date) {
        self.defaultDate = defaultDate
        _date = State(initialValue: defaultDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("예: 병원 예약", text: $title)
                DatePicker("날짜", selection: $date, displayedComponents: timed ? [.date, .hourAndMinute] : [.date])
                Toggle("시간 지정", isOn: $timed)
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
            .navigationTitle("일정 추가")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!title.isEmpty)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }.foregroundStyle(Ink.text)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        modelContext.insert(ScheduleItem(title: title, date: date,
                                                         isAllDay: !timed, repeatRule: repeatRule))
                        dismiss()
                    }
                    .foregroundStyle(Ink.text)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// ── ② Input 추가 ──
struct InputAddSheet: View {
    let currentSeason: SeasonMeta?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var category: InputCategory = .other
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
                    // 상호 배타(프로토 data-excl="rep") — 한 불리언의 두 얼굴이라 항상 정확히 하나만 켜짐
                    Toggle("반복", isOn: Binding(
                        get: { !cycleBased },
                        set: { on in cycleBased = !on }
                    ))
                    .tint(Ink.text)
                    if !cycleBased {
                        HStack(spacing: 6) {
                            ForEach(Self.calendarChoices, id: \.self) { freq in
                                FreqChip(label: freq.shortLabel ?? "", selected: calendarFreq == freq) {
                                    calendarFreq = freq
                                }
                            }
                        }
                    }
                    Toggle("주기 기준", isOn: $cycleBased)
                        .tint(Ink.text)
                    if cycleBased {
                        Picker("시작 계절", selection: $anchor) {
                            ForEach(SeasonAnchor.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Stepper("계절 시작 +\(offset)일", value: $offset, in: 0...13)
                        Toggle("매 주기 반복", isOn: $everyCycle)
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
                        } else {
                            switch calendarFreq {
                            case .weekly:  schedule = .weekly
                            case .monthly: schedule = .monthly
                            default:       schedule = .daily
                            }
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
                    // 상호 배타 — Input 추가 시트와 동일 문법(2026-07-22, 주기 데이터 없어도 동작)
                    Toggle("반복", isOn: Binding(
                        get: { !cycleBased },
                        set: { on in cycleBased = !on }
                    ))
                    .tint(Ink.text)
                    if !cycleBased {
                        HStack(spacing: 6) {
                            ForEach(Self.calendarChoices, id: \.self) { freq in
                                FreqChip(label: freq.shortLabel ?? "", selected: calendarFreq == freq) {
                                    calendarFreq = freq
                                }
                            }
                        }
                    }
                    Toggle("주기 기준", isOn: $cycleBased)
                        .tint(Ink.text)
                    if cycleBased {
                        Picker("시작 계절", selection: $anchor) {
                            ForEach(SeasonAnchor.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Stepper("계절 시작 +\(offset)일", value: $offset, in: 0...13)
                        Toggle("매 주기 반복", isOn: $everyCycle)
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
                        } else {
                            switch calendarFreq {
                            case .weekly:  schedule = .weekly
                            case .monthly: schedule = .monthly
                            default:       schedule = .daily
                            }
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
