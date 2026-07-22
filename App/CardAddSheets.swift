// 템포루틴 — 3카드 추가 시트 (MASTER §8.2.4)
// Input 제목 예시 = 카테고리×현재 계절 매트릭스(§8.1 정정 노트 — 허락 톤 예시, 처방 아님).
// 미저장 내용이 있으면 dismiss 확인(§8.2.4). one-shot엔 skip 미노출 — overflow는 P0 기본 clamp(§5.5.3).

import SwiftUI
import SwiftData
import TempoCore

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
                Picker("반복", selection: $repeatRule) {
                    Text("없음").tag(ScheduleRepeat.none)
                    Text("매년").tag(ScheduleRepeat.yearly)
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
    @State private var anchor: SeasonAnchor = .winter
    @State private var offset = 0
    @State private var everyCycle = true

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
                    Picker("반복", selection: $cycleBased) {
                        Text("매일").tag(false)
                        Text("주기 기준").tag(true)
                    }
                    .pickerStyle(.segmented)
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
                        let schedule: InputSchedule = cycleBased
                            ? .cycleAnchored(CycleRecurrence(anchor: .phase(anchor.phase), dayOffset: offset,
                                                             repeatsEveryCycle: everyCycle, overflowRule: .clamp))
                            : .daily
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
    @State private var anchor: SeasonAnchor = .winter
    @State private var offset = 0
    @State private var everyCycle = true
    @State private var kind: OutputProgressKind = .percent
    @State private var targetSessions = 3
    @State private var subtaskDraft = ""
    @State private var subtasks: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                TextField("예: 자격증 공부", text: $title)
                Section {
                    Picker("시작 계절", selection: $anchor) {
                        ForEach(SeasonAnchor.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Stepper("계절 시작 +\(offset)일", value: $offset, in: 0...13)
                    Toggle("매 주기 반복", isOn: $everyCycle)
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
                        let recurrence = CycleRecurrence(anchor: .phase(anchor.phase), dayOffset: offset,
                                                         repeatsEveryCycle: everyCycle, overflowRule: .clamp)
                        let item = OutputItem(title: title, recurrence: recurrence, progressKind: kind)
                        if kind == .sessions { item.targetSessions = targetSessions }
                        if kind == .subtasks {
                            item.subtasks = subtasks.enumerated().map { OutputSubtask(title: $0.element, order: $0.offset) }
                        }
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
