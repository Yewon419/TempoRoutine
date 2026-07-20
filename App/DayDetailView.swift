// 템포루틴 — 하루 상세 3카드 (Phase 0 ④, MASTER §8.2.4 / §3.6 — 제품의 심장)
// 일정=절대날짜·연반복 / Input=일일 체크(ItemCompletion) / Output=진행도(수명 누적, 완료=파생 §5.5.2).
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

    @State private var selectedCard: CardKind = .schedule
    @State private var addSheet: CardKind?

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: .now) }
    private var isFuture: Bool { day > today }
    private var snapshot: CycleSnapshot { CycleSnapshot(periodDays: periodDays) }

    var body: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()
            SeasonLight(phase: snapshot.phase(on: day))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    periodToggle
                    Picker("카드", selection: $selectedCard) {
                        ForEach(CardKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    cardBody
                }
                .padding(20)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $addSheet) { kind in
            switch kind {
            case .schedule: ScheduleAddSheet(defaultDate: day)
            case .input:    InputAddSheet(currentSeason: snapshot.phaseInfo(on: today)?.meta)
            case .output:   OutputAddSheet()
            }
        }
    }

    // ── 상단: 날짜 표제 + 계절·단계 칩 ──
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(cal.component(.day, from: day))")
                    .font(.almanac(size: 48, weight: .bold))
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

    // ── 카드 본문 ──
    @ViewBuilder
    private var cardBody: some View {
        switch selectedCard {
        case .schedule: scheduleCard
        case .input:    inputCard
        case .output:   outputCard
        }
    }

    private func cardShell(_ empty: Bool, addLabel: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if empty {
                Text("아직 없어요")
                    .font(.footnote)
                    .foregroundStyle(Ink.text.opacity(0.45))
                    .padding(.vertical, 8)
            } else {
                rows()
            }
            Button {
                addSheet = selectedCard
            } label: {
                Label(addLabel, systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Ink.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    // ① 일정
    private var scheduleRows: [ScheduleItem] { schedules.filter { $0.occurs(on: day) } }

    private var scheduleCard: some View {
        cardShell(false, addLabel: "일정 추가") {
            VStack(alignment: .leading, spacing: 10) {
                if scheduleRows.isEmpty && EventOverlay.shared.events(on: day).isEmpty {
                    Text("아직 없어요")
                        .font(.footnote)
                        .foregroundStyle(Ink.text.opacity(0.45))
                        .padding(.vertical, 8)
                }
                ForEach(scheduleRows) { item in
                    HStack {
                        Text(item.title).foregroundStyle(Ink.text)
                        Spacer()
                        if !item.isAllDay {
                            Text(item.date.formatted(date: .omitted, time: .shortened))
                                .font(.footnote).foregroundStyle(Ink.text.opacity(0.55))
                        }
                        if item.repeatRule == .yearly {
                            Text("매년").font(.caption2).foregroundStyle(Ink.text.opacity(0.45))
                        }
                    }
                    .font(.subheadline)
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
            case .daily:
                return InputRow(item: item, projected: false)
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

    private func toggleCompletion(_ itemID: UUID) {
        if let existing = completions.first(where: { $0.itemID == itemID && cal.isDate($0.occurredOn, inSameDayAs: day) }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(ItemCompletion(itemID: itemID, occurredOn: day))
        }
    }

    private var inputCard: some View {
        cardShell(inputRows.isEmpty, addLabel: "Input 추가") {
            ForEach(inputRows) { row in
                let checked = isCompleted(row.item.id)
                Button {
                    toggleCompletion(row.item.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(checked ? Ink.text : Ink.text.opacity(0.35))
                        Text(row.item.title)
                            .foregroundStyle(Ink.text.opacity(row.projected ? 0.55 : 1.0))
                            .strikethrough(checked, color: Ink.text.opacity(0.5))
                        if row.projected {
                            Text("예상").font(.caption2).foregroundStyle(Ink.text.opacity(0.45))
                        }
                        Spacer()
                    }
                    .font(.subheadline)
                }
                .disabled(isFuture)   // 미래 완료 금지(원칙 4)
                .accessibilityValue(checked ? "완료" : "미완료")
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
            guard let occ = snapshot.occurrence(of: item.recurrence,
                                                createdAt: cal.startOfDay(for: item.createdAt), on: day) else {
                return nil
            }
            if item.isComplete && occ.projected { return nil }
            return OutputRow(item: item, projected: occ.projected)
        }
    }

    private var outputCard: some View {
        cardShell(outputRows.isEmpty, addLabel: "Output 추가") {
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
                    sub.isDone.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: sub.isDone ? "checkmark.square.fill" : "square")
                            .foregroundStyle(sub.isDone ? Ink.text : Ink.text.opacity(0.35))
                        Text(sub.title)
                            .font(.footnote)
                            .foregroundStyle(Ink.text)
                            .strikethrough(sub.isDone, color: Ink.text.opacity(0.5))
                        Spacer()
                    }
                }
                .accessibilityValue(sub.isDone ? "완료" : "미완료")
            }
        case .sessions:
            HStack(spacing: 12) {
                Text(item.targetSessions > 0 ? "\(item.loggedSessions) / \(item.targetSessions) 세션"
                                             : "\(item.loggedSessions) 세션")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Ink.text.opacity(0.7))
                Button {
                    if item.loggedSessions > 0 { item.loggedSessions -= 1 }
                } label: { Image(systemName: "minus.circle") }
                Button {
                    item.loggedSessions += 1
                } label: { Image(systemName: "plus.circle") }
            }
            .foregroundStyle(Ink.text)
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
