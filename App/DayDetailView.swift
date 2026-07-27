// 템포루틴 — 하루 상세 (Phase 0 ④, MASTER §8.2.4 / §3.6 — 제품의 심장)
// 조판 = 오늘 탭과 동일: 표제 → 생리 기록 토글 → 일정·Input·Output 3지면 → 체크인(과거·오늘만).
// 세그먼트 카드 전환은 2026-07-26 폐기 — 시안(프로토 data-view="day")은 처음부터 스택이었다.
// 일정=절대날짜·반복·기간 / Input=일일 체크(ItemCompletion) / Output=진행도(수명 누적, 완료=파생 §5.5.2).
// 상단 생리 기록 토글 = 긋기 접근성 대체(§5.5.4). projected 아이템 = faded + "예상"(§8.1 상태 어휘).

import SwiftUI
import SwiftData
import TempoCore

enum CardKind: String, CaseIterable, Identifiable {
    case schedule = "일정"
    case input = "Input"
    case output = "Output"
    var id: String { rawValue }
}

struct DayDetailView: View {
    let day: Date

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PeriodDay.day) private var periodDays: [PeriodDay]
    @Query(sort: \ScheduleItem.date) private var schedules: [ScheduleItem]
    @Query(sort: \InputItem.createdAt) private var inputs: [InputItem]
    @Query(sort: \OutputItem.createdAt) private var outputs: [OutputItem]
    @Query private var completions: [ItemCompletion]
    @Query private var checkIns: [DailyCheckIn]

    @State private var addSheet: CardKind?
    @State private var pendingDelete: DeleteTarget?   // 행 길게 누르기 = 빠른 삭제(2026-07-27)
    @State private var editingSchedule: ScheduleItem?   // 일정 행 탭 = 수정 시트(2026-07-23)
    @State private var confirmFeedback = 0   // 확정 순간 햅틱(§4 — 생리 기록·아이템 완료)
    @State private var lightFeedback = 0     // 작은 햅틱(§4 — 진행도 조정·월 이동 등, 확정 아님)

    /// 행 길게 누르기로 지울 대상 — 하단 액션 시트가 이걸 물고 뜬다(2026-07-27 사용자 지시)
    enum DeleteTarget: Identifiable {
        case schedule(ScheduleItem)
        case input(InputItem)
        case output(OutputItem)

        var id: UUID {
            switch self {
            case .schedule(let item): item.id
            case .input(let item): item.id
            case .output(let item): item.id
            }
        }

        var title: String {
            switch self {
            case .schedule(let item): item.title
            case .input(let item): item.title
            case .output(let item): item.title
            }
        }

        var kindLabel: String {
            switch self {
            case .schedule: "일정"
            case .input: "Input"
            case .output: "Output"
            }
        }
    }

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: .now) }
    private var isFuture: Bool { day > today }
    private var snapshot: CycleSnapshot { CycleSnapshot(periodDays: periodDays) }

    var body: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()
            SeasonLight(phase: snapshot.phase(on: day))
            ScrollView {
                // 오늘 탭과 같은 조판 — 3구획을 쌓는다(프로토 data-view="day" 문법, 2026-07-26 정정:
                // 세그먼트 전환은 MASTER §8.2.4 구문장을 따른 것이었고 시안과 어긋나 있었다)
                VStack(alignment: .leading, spacing: 18) {
                    header
                    periodToggle
                    scheduleCard
                    inputCard
                    outputCard
                    // 뒤늦은 기록·자정 넘긴 마무리 — 지난 날짜에도 체크인을 쓸 수 있어야 한다.
                    // 미래는 기록하지 않는다(생리 기록과 같은 원칙 §5.5.4).
                    if !isFuture {
                        CheckInCard(day: day)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.impact(weight: .medium), trigger: confirmFeedback)
        .sensoryFeedback(.impact(weight: .light), trigger: lightFeedback)
        .sheet(item: $addSheet) { kind in
            switch kind {
            case .schedule: ScheduleAddSheet(defaultDate: day)
            case .input:    InputAddSheet(day: day,
                                          currentSeason: snapshot.phaseInfo(on: today)?.meta,
                                          energyLevel: snapshot.phase(on: today).flatMap {
                                              EnergyProfile(checkIns: checkIns, snapshot: snapshot).level(for: $0)
                                          })
            case .output:   OutputAddSheet(day: day)
            }
        }
        .sheet(item: $editingSchedule) { item in
            ScheduleAddSheet(defaultDate: day, editing: item)
        }
        // 빠른 삭제 — 길게 누른 행을 하단에서 확인하고 지운다(§8.2.6 파괴 액션 확인 문법)
        .confirmationDialog(pendingDelete.map { "\($0.kindLabel) 「\($0.title)」" } ?? "",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                if let target = pendingDelete { delete(target) }
                pendingDelete = nil
            }
            Button("취소", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("이 항목과 기록이 함께 지워져요. 되돌릴 수 없어요.")
        }
    }

    /// 길게 누르기 = 삭제 확인 진입(2026-07-27). Button 위에 얹으므로 simultaneousGesture로 건다 —
    /// 탭(체크·수정)은 그대로 살아 있어야 한다.
    private func longPressDelete(_ target: DeleteTarget) -> some Gesture {
        LongPressGesture(minimumDuration: 0.45).onEnded { _ in
            confirmFeedback += 1
            pendingDelete = target
        }
    }

    private func delete(_ target: DeleteTarget) {
        switch target {
        case .schedule(let item):
            ScheduleReminder.cancel(id: item.id)
            modelContext.delete(item)
        case .input(let item):
            // 완료 기록은 itemID 참조라 관계 정리가 안 된다 — 고아가 남지 않게 같이 지운다
            for record in completions where record.itemID == item.id {
                modelContext.delete(record)
            }
            modelContext.delete(item)
        case .output(let item):
            modelContext.delete(item)   // 서브태스크는 cascade(§5.5)
        }
    }

    // ── 상단: 날짜 표제 + 계절·단계 칩 ──
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(cal.component(.day, from: day))")
                    .font(.almanac(size: 56, weight: .bold))   // v6 확정: 하루 상세 표제 56px
                    .foregroundStyle(Ink.text)
                Text(day.formatted(.dateTime.month().weekday(.wide)))
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(Ink.text.opacity(0.6))
            }
            if let info = snapshot.phaseInfo(on: day) {
                HStack(spacing: 6) {
                    Text("\(info.meta.name) · \(info.meta.phaseName) \(info.dayInCycle)일차")
                    if info.projected { Text("· 예상") }
                }
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(info.meta.color.opacity(info.projected ? 0.7 : 1.0))
            } else {
                Text("계절 기록 전")
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Ink.text.opacity(0.5))
            }
        }
    }

    // ── 생리 기록 토글 (§5.5.4 접근성 대체 — 미래 금지) ──
    private var periodToggle: some View {
        Toggle(isOn: Binding(
            get: { periodDays.contains { $0.day == day } },
            set: { on in
                confirmFeedback += 1
                let all = periodDays
                if on {
                    Task { await PeriodStore.add(days: [day], context: modelContext, existing: all) }
                } else {
                    let records = all.filter { $0.day == day }
                    Task { await PeriodStore.remove(records: records, context: modelContext, all: all) }
                }
            }
        )) {
            Text("생리 기록")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Ink.text)
        }
        .tint(Ink.text)
        .disabled(isFuture)
    }

    // ── 카드 껍데기 — 오늘 탭 section(kind:)과 같은 문법(표제 + 우상단 +) ──
    private func cardShell(_ kind: CardKind, empty: Bool, emptyMessage: String = "아직 없어요",
                            @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(kind.rawValue)
                    .font(.almanac(size: 17, weight: .bold))
                    .foregroundStyle(Ink.text)
                Spacer()
                Button {
                    lightFeedback += 1
                    addSheet = kind
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Ink.text.opacity(0.6))
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("\(kind.rawValue) 추가")
            }
            if empty {
                Text(emptyMessage)
                    .font(.footnote)
                    .foregroundStyle(Ink.text.opacity(0.45))
                    .padding(.vertical, 4)
            } else {
                rows()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .milkGlass()
    }

    // ① 일정
    private var scheduleRows: [ScheduleItem] { schedules.filter { $0.occurs(on: day) } }

    private var scheduleCard: some View {
        cardShell(.schedule, empty: false) {
            VStack(alignment: .leading, spacing: 10) {
                if scheduleRows.isEmpty && EventOverlay.shared.events(on: day).isEmpty {
                    Text("아직 없어요")
                        .font(.footnote)
                        .foregroundStyle(Ink.text.opacity(0.45))
                        .padding(.vertical, 8)
                }
                ForEach(scheduleRows) { item in
                    Button {
                        lightFeedback += 1
                        editingSchedule = item
                    } label: {
                        HStack {
                            Text(item.title).foregroundStyle(Ink.text)
                            // 여러 날 일정 — 그날이 몇 일차인지(§8.2.3)
                            if let index = item.dayIndex(on: day) {
                                Text("\(index)/\(item.spanDays)일차")
                                    .font(.caption2)
                                    .foregroundStyle(Ink.text.opacity(0.5))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .overlay(Capsule().stroke(Ink.text.opacity(0.2), lineWidth: 1))
                            }
                            Spacer()
                            if !item.isAllDay {
                                let startText = item.date.formatted(date: .omitted, time: .shortened)
                                Text(item.endDate.map { "\(startText)~\($0.formatted(date: .omitted, time: .shortened))" } ?? startText)
                                    .font(.footnote).foregroundStyle(Ink.text.opacity(0.55))
                            }
                            if let label = item.repeatRule.shortLabel {
                                Text(label).font(.caption2).foregroundStyle(Ink.text.opacity(0.45))
                            }
                        }
                        .font(.subheadline)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(longPressDelete(.schedule(item)))
                    .accessibilityHint("탭하면 수정, 길게 누르면 삭제할 수 있어요")
                    .accessibilityAction(named: "삭제") { pendingDelete = .schedule(item) }
                }
                OverlayEventRows(day: day)      // EventKit read-only 오버레이(§3.6.1 — 미저장)
                CalendarConnectRow()
            }
        }
    }

    // ② Input — 완료 우선(§5.6.4): occurrence가 없어도 그날 완료 기록이 있으면 표시(S3 보존)
    private struct InputRow: Identifiable {
        let item: InputItem
        let projected: Bool
        var id: UUID { item.id }
    }

    private var inputRows: [InputRow] {
        inputs.compactMap { item in
            switch item.schedule {
            case .once:
                // 단발 체크(2026-07-23): 완료된 날엔 기록으로, 미완료면 생성일 이후 모든 날에 대기로
                if isCompleted(item.id) { return InputRow(item: item, projected: false) }
                if !hasAnyCompletion(item.id) && item.occursByCalendar(on: day) {
                    return InputRow(item: item, projected: false)
                }
                return nil
            case .daily, .weekly, .monthly:
                return item.occursByCalendar(on: day) ? InputRow(item: item, projected: false) : nil
            case .cycleAnchored(let r):
                if let occ = snapshot.occurrence(of: r, createdAt: cal.startOfDay(for: item.createdAt), on: day) {
                    return InputRow(item: item, projected: occ.projected)
                }
                if isCompleted(item.id) {
                    return InputRow(item: item, projected: false)
                }
                return nil
            }
        }
    }

    private func isCompleted(_ itemID: UUID) -> Bool {
        completions.contains { $0.itemID == itemID && cal.isDate($0.occurredOn, inSameDayAs: day) }
    }

    private func hasAnyCompletion(_ itemID: UUID) -> Bool {
        completions.contains { $0.itemID == itemID }
    }

    private func toggleCompletion(_ itemID: UUID) {
        if let existing = completions.first(where: { $0.itemID == itemID && cal.isDate($0.occurredOn, inSameDayAs: day) }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(ItemCompletion(itemID: itemID, occurredOn: day))
        }
    }

    private var inputCard: some View {
        cardShell(.input, empty: inputRows.isEmpty) {
            ForEach(inputRows) { row in
                let checked = isCompleted(row.item.id)
                Button {
                    confirmFeedback += 1
                    toggleCompletion(row.item.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(checked ? Ink.text : Ink.text.opacity(0.35))
                        Text(row.item.title)
                            .foregroundStyle(Ink.text.opacity(row.projected ? 0.55 : 1.0))
                            .strikethrough(checked, color: Ink.dim)
                        if row.projected {
                            Text("예상").font(.caption2).foregroundStyle(Ink.text.opacity(0.45))
                        }
                        Spacer()
                    }
                    .font(.subheadline)
                }
                .disabled(isFuture)   // 미래 완료 금지(원칙 4)
                .simultaneousGesture(longPressDelete(.input(row.item)))
                .accessibilityValue(checked ? "완료" : "미완료")
                .accessibilityAction(named: "삭제") { pendingDelete = .input(row.item) }
            }
        }
    }

    // ③ Output — 완료된 아이템의 미래 occurrence 미표시(§5.5.2)
    private struct OutputRow: Identifiable {
        let item: OutputItem
        let projected: Bool
        var id: UUID { item.id }
    }

    private var outputRows: [OutputRow] {
        outputs.compactMap { item in
            switch item.schedule {
            case .once, .daily, .weekly, .monthly:
                guard item.occursByCalendar(on: day) else { return nil }
                let future = day > today
                if item.isComplete && future { return nil }
                return OutputRow(item: item, projected: future)
            case .cycleAnchored(let r):
                guard let occ = snapshot.occurrence(of: r, createdAt: cal.startOfDay(for: item.createdAt), on: day) else {
                    return nil
                }
                if item.isComplete && occ.projected { return nil }
                return OutputRow(item: item, projected: occ.projected)
            }
        }
    }

    /// 콜드스타트(생리 미기록)에서는 Output이 있어도 주기 앵커를 못 풀어 전부 안 보임 — 이유를 밝힌다.
    private var outputEmptyMessage: String {
        let hasColdBlocked = snapshot.isColdStart && outputs.contains {
            if case .cycleAnchored = $0.schedule { return true }
            return false
        }
        return hasColdBlocked ? "생리를 기록하면 계획이 보이기 시작해요." : "아직 없어요"
    }

    private var outputCard: some View {
        cardShell(.output, empty: outputRows.isEmpty, emptyMessage: outputEmptyMessage) {
            ForEach(outputRows) { row in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(row.item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Ink.text.opacity(row.projected ? 0.55 : 1.0))
                        if row.projected {
                            Text("예상").font(.caption2).foregroundStyle(Ink.text.opacity(0.45))
                        }
                        if row.item.isComplete {
                            Text("완료").font(.caption2.weight(.semibold)).foregroundStyle(Ink.text.opacity(0.6))
                        }
                        Spacer()
                    }
                    progressControl(row.item)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .simultaneousGesture(longPressDelete(.output(row.item)))
                .accessibilityAction(named: "삭제") { pendingDelete = .output(row.item) }
            }
        }
    }

    @ViewBuilder
    private func progressControl(_ item: OutputItem) -> some View {
        switch item.progressKind {
        case .subtasks:
            let list = (item.subtasks ?? []).sorted { $0.order < $1.order }
            ForEach(list) { sub in
                Button {
                    confirmFeedback += 1
                    sub.isDone.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: sub.isDone ? "checkmark.square.fill" : "square")
                            .foregroundStyle(sub.isDone ? Ink.text : Ink.text.opacity(0.35))
                        Text(sub.title)
                            .font(.footnote)
                            .foregroundStyle(Ink.text)
                            .strikethrough(sub.isDone, color: Ink.dim)
                        Spacer()
                    }
                }
                .accessibilityValue(sub.isDone ? "완료" : "미완료")
            }
        case .sessions:
            SessionProgressControl(item: item) { completed in
                if completed { confirmFeedback += 1 } else { lightFeedback += 1 }
            }
        case .percent:
            HStack(spacing: 10) {
                Slider(value: Binding(get: { item.percent }, set: { item.percent = $0 }), in: 0...1)
                    .tint(Ink.text)
                Text(item.percent.formatted(.percent.precision(.fractionLength(0))))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Ink.text.opacity(0.7))
                    .frame(width: 44, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(item.percent.formatted(.percent.precision(.fractionLength(0))))
        }
    }
}
