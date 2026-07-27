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
    @State private var endDay: Date       // 하루종일 일정의 종료 "날짜" — 시작일과 같으면 하루짜리(§8.2.3)
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
            _endDay = State(initialValue: item.isAllDay ? (item.endDate ?? item.date) : item.date)
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
            _endDay = State(initialValue: defaultDate)
        }
    }

    private var reminderChoices: [(label: String, minutes: Int)] {
        allDay ? Self.allDayReminders : Self.timedReminders
    }

    /// 하루종일 일정의 종료 날짜 — 시작일과 같으면 nil(하루짜리)
    private var allDayEndDate: Date? {
        let cal = Calendar.current
        let s = cal.startOfDay(for: start)
        let e = cal.startOfDay(for: endDay)
        return e > s ? e : nil
    }

    private var multiDaySpanLabel: String? {
        guard allDay, allDayEndDate != nil else { return nil }
        let days = ScheduleSpan.dayCount(start: start, end: endDay, calendar: Calendar.current)
        return "\(days)일에 걸친 일정이에요"
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
                    if allDay {
                        // 종료일을 시작일보다 뒤로 잡으면 여러 날 일정(§8.2.3 — 캘린더에 띠로)
                        DatePicker("종료", selection: $endDay, in: start...,
                                   displayedComponents: [.date])
                        if let span = multiDaySpanLabel {
                            Text(span)
                                .font(.footnote)
                                .foregroundStyle(Ink.text.opacity(0.5))
                        }
                    } else {
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
                if Calendar.current.startOfDay(for: endDay) < Calendar.current.startOfDay(for: start) {
                    endDay = start
                }
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
                            item.endDate = allDay ? allDayEndDate : end
                            item.reminderMinutes = reminderMinutes
                            ScheduleReminder.cancel(id: item.id)   // 알림 재예약 — 시간·반복이 바뀌었을 수 있음
                            ScheduleReminder.schedule(id: item.id, title: title, date: start,
                                                      isAllDay: allDay, repeatRule: repeatRule,
                                                      reminderMinutes: reminderMinutes)
                        } else {
                            let item = ScheduleItem(title: title, date: start, isAllDay: allDay,
                                                    repeatRule: repeatRule,
                                                    endDate: allDay ? allDayEndDate : end,
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

// ── ①-b 빠른 일정 (2026-07-25 사용자 지시: 캘린더 날짜 길게 누르기 → 제목 한 줄로 저장) ──
// 시각은 제목에서 읽는다(`ScheduleTextParser`, TempoCore) — "회의 3시" → 오후 3:00 + 제목 "회의".
// 입력 중엔 원문을 고치지 않는다(한글 조합 깨짐 방지): 읽은 결과는 칩·근거 줄로만 보여주고,
// 실제 적용은 저장 시점. 시각만 칩으로 덮어쓸 수 있다 — **반복 없음·알림 없음은 고정**
// (2026-07-25 사용자 결정), 둘 다 저장 후 일정 행 탭 → 수정 시트에서 정한다.
// 시트 크기는 기본(large) 고정 — 작은 detent는 키보드가 입력칸을 덮는 사례가 보고돼 있어 쓰지 않는다.
struct QuickScheduleSheet: View {
    let day: Date
    /// 드래그 기간 선택의 끝 날짜(2026-07-27) — 있으면 하루종일 여러 날 모드(시각 파서·시간 칩 미적용)
    var endDay: Date? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool
    @State private var title = ""
    @State private var pickedTime: Date?           // 칩으로 직접 정한 시각 — 있으면 파싱값보다 우선
    @State private var ignoreParsed = false        // 읽은 시각을 물린 상태(하루종일로 되돌림)
    @State private var pmOverride: Bool?           // 오전·오후 직접 선택(nil = 관례 해석 그대로, 2026-07-26)
    @State private var showTimePicker = false

    private var cal: Calendar { Calendar.current }
    private var parsed: ParsedScheduleText { ScheduleTextParser.parse(title) }

    /// 제목에서 읽은 시작 시각 — 오전·오후를 직접 고른 경우 그쪽으로 뒤집는다
    private var parsedStart: ParsedTime? {
        guard !ignoreParsed, let start = parsed.start else { return nil }
        guard parsed.ambiguousMeridiem, let pm = pmOverride else { return start }
        return variant(start, pm: pm)
    }

    /// 같은 시각의 오전·오후 짝 — 12시는 정오↔자정
    private func variant(_ time: ParsedTime, pm: Bool) -> ParsedTime {
        let base = time.hour % 12
        return ParsedTime(hour: pm ? base + 12 : base, minute: time.minute)
    }

    /// 저장에 쓰는 시각 — 칩 지정이 우선, 없으면 제목에서 읽은 값
    private var startTime: ParsedTime? {
        if let pickedTime {
            let c = cal.dateComponents([.hour, .minute], from: pickedTime)
            return ParsedTime(hour: c.hour ?? 0, minute: c.minute ?? 0)
        }
        return parsedStart
    }

    /// 종료 시각은 제목에서 범위를 읽었을 때만("3시~5시"). 칩으로 정했으면 1시간.
    private var endTime: ParsedTime? {
        guard pickedTime == nil, !ignoreParsed, let end = parsed.end else { return nil }
        guard parsed.ambiguousMeridiem, let pm = pmOverride, let start = parsed.start,
              let shown = parsedStart else { return end }
        // 시작을 뒤집었으면 종료도 같은 폭으로 — "3시~5시"를 오전으로 고르면 05:00
        _ = pm   // 방향은 delta가 이미 반영 — 플래그는 가드 용도만
        let delta = shown.minutesOfDay - start.minutesOfDay
        let moved = ((end.minutesOfDay + delta) % 1440 + 1440) % 1440
        return ParsedTime(hour: moved / 60, minute: moved % 60)
    }

    /// 시각 표현을 실제로 쓸 때만 제목을 정제한다 — 기간 모드는 파서 미적용(원문 그대로)
    private var effectiveTitle: String {
        if endDay != nil { return title.trimmingCharacters(in: .whitespaces) }
        return parsedStart != nil ? parsed.title : title.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.paper.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    // 하루 상세와 같은 책력 표제(§4 조판) — 어느 날짜에 적는지가 먼저 보이게
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let endDay {
                            // 드래그 기간 — 같은 달 안에서만 선택되므로 일(day)만 잇는다
                            Text("\(cal.component(.day, from: day))~\(cal.component(.day, from: endDay))")
                                .font(.almanac(size: 56, weight: .bold))
                                .foregroundStyle(Ink.text)
                            Text("\(day.formatted(.dateTime.month())) · \(ScheduleSpan.dayCount(start: day, end: endDay, calendar: cal))일")
                                .font(.system(.subheadline, design: .serif))
                                .foregroundStyle(Ink.text.opacity(0.6))
                        } else {
                            Text("\(cal.component(.day, from: day))")
                                .font(.almanac(size: 56, weight: .bold))
                                .foregroundStyle(Ink.text)
                            Text(day.formatted(.dateTime.month().weekday(.wide)))
                                .font(.system(.subheadline, design: .serif))
                                .foregroundStyle(Ink.text.opacity(0.6))
                        }
                    }
                    TextField("무엇을 적어둘까요?", text: $title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Ink.text)
                        .focused($titleFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .padding(.bottom, 8)
                        .almanacRule(opacity: 0.28)
                    if endDay == nil {
                        chips
                        if showsMeridiemChoice { meridiemChips }
                        if showTimePicker { timePicker }
                        if let hint { readingHint(hint) }
                    } else {
                        Text("하루종일 일정으로 적어둬요. 시간·반복·알림은 저장한 뒤 일정을 탭해서 정할 수 있어요.")
                            .font(.footnote)
                            .foregroundStyle(Ink.text.opacity(0.5))
                    }
                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .navigationTitle("빠른 일정")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!title.trimmingCharacters(in: .whitespaces).isEmpty)   // 적던 내용 날리지 않기(§8.2.4)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }.foregroundStyle(Ink.text)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("추가", action: save)
                        .foregroundStyle(Ink.text)
                        .disabled(effectiveTitle.isEmpty)
                }
            }
        }
        .task {
            // 시트 전환이 끝난 뒤 포커스 — 즉시 지정은 키보드가 올라오지 않는 사례가 있다
            try? await Task.sleep(nanoseconds: 300_000_000)
            titleFocused = true
        }
    }

    // ── 칩 행: 시간 (반복은 여기서 다루지 않는다 — 2026-07-25 사용자 결정: 반복 없음 고정 유지) ──
    private var chips: some View {
        HStack(spacing: 8) {
            chipButton(icon: "clock", label: timeLabel, filled: startTime != nil) {
                showTimePicker.toggle()
                // 제목에서 읽은 시각이 있으면 그걸 이어받고, 없으면 다음 정시
                if showTimePicker, pickedTime == nil {
                    pickedTime = parsedStart.flatMap(date(at:)) ?? defaultPickerTime
                }
            }
            Spacer()
        }
    }

    /// 오전·오후를 안 쓴 "N시"는 두 읽기가 다 성립 — 고르게 한다(2026-07-26 사용자 지시)
    private var showsMeridiemChoice: Bool {
        pickedTime == nil && !ignoreParsed && parsed.ambiguousMeridiem && parsed.start != nil
    }

    private var meridiemChips: some View {
        HStack(spacing: 6) {
            if let base = parsed.start {
                let selectedPM = (parsedStart?.hour ?? 0) >= 12
                FreqChip(label: clockText(variant(base, pm: false)), selected: !selectedPM) {
                    pmOverride = false
                }
                FreqChip(label: clockText(variant(base, pm: true)), selected: selectedPM) {
                    pmOverride = true
                }
            }
            Spacer()
        }
    }

    private var timeLabel: String {
        guard let start = startTime else { return "하루종일" }
        let startText = clockText(start)
        guard let end = endTime else { return startText }
        return "\(startText) – \(clockText(end))"
    }

    private func chipButton(icon: String, label: String, filled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption2)
                Text(label).font(.caption.weight(.semibold))
            }
            .foregroundStyle(filled ? Ink.paper : Ink.text.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(filled ? AnyShapeStyle(Ink.text) : AnyShapeStyle(Ink.text.opacity(0.08)),
                        in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var timePicker: some View {
        HStack {
            DatePicker("시각", selection: Binding(
                get: { pickedTime ?? defaultPickerTime },
                set: { pickedTime = $0; ignoreParsed = false }
            ), displayedComponents: [.hourAndMinute])
            .labelsHidden()
            Spacer()
            Button("하루종일로") {
                pickedTime = nil
                ignoreParsed = true          // 제목에서 읽은 시각도 함께 물린다
                showTimePicker = false
            }
            .font(.caption)
            .foregroundStyle(Ink.text.opacity(0.6))
        }
    }

    /// 제목에서 읽은 근거 — 무엇을 어떻게 읽었고 제목이 뭐가 되는지 미리 보여준다
    private var hint: String? {
        guard pickedTime == nil, !ignoreParsed,
              let matched = parsed.matchedText, let start = parsed.start else { return nil }
        var text: String
        if parsed.ambiguousMeridiem {
            text = "「\(matched)」를 시각으로 읽었어요"
        } else {
            text = "「\(matched)」를 \(clockText(start))"
            if let end = parsed.end { text += "–\(clockText(end))" }
            text += "으로 읽었어요"
        }
        if !parsed.title.isEmpty { text += " · 제목은 「\(parsed.title)」" }
        return text
    }

    private func readingHint(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(Ink.text.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Button("아니요") { ignoreParsed = true }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Ink.text.opacity(0.75))
        }
    }

    private var defaultPickerTime: Date {
        let base = cal.startOfDay(for: day)
        return date(at: ParsedTime(hour: min(23, cal.component(.hour, from: .now) + 1), minute: 0)) ?? base
    }

    private func clockText(_ time: ParsedTime) -> String {
        guard let d = date(at: time) else { return "" }
        return d.formatted(date: .omitted, time: .shortened)
    }

    /// 누른 날짜 + 시:분 — DateComponents로 직접 조립(bySettingHour의 전진 탐색 회피)
    private func date(at time: ParsedTime) -> Date? {
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        comps.hour = time.hour
        comps.minute = time.minute
        return cal.date(from: comps)
    }

    private func save() {
        let name = effectiveTitle
        guard !name.isEmpty else { return }
        if let endDay {
            // 드래그 기간 — 하루종일 여러 날(§8.2.3). 시각 파서는 단일 날짜 전용이라 미적용.
            modelContext.insert(ScheduleItem(title: name, date: cal.startOfDay(for: day),
                                             endDate: cal.startOfDay(for: endDay)))
        } else if let start = startTime, let startDate = date(at: start) {
            var endDate = startDate.addingTimeInterval(3600)
            if let end = endTime, let d = date(at: end), d > startDate { endDate = d }
            // 반복은 빠른 일정에서 다루지 않는다 — 기본 .none 유지(2026-07-25 사용자 결정)
            modelContext.insert(ScheduleItem(title: name, date: startDate, isAllDay: false,
                                             endDate: endDate))
        } else {
            modelContext.insert(ScheduleItem(title: name, date: cal.startOfDay(for: day)))
        }
        dismiss()
    }
}

// ── ② Input 추가 ──
struct InputAddSheet: View {
    /// 어느 날에 추가하는가 — 하루 상세에서 지난 날짜에 추가하면 그날부터 시작해야 한다(2026-07-26)
    let day: Date
    let currentSeason: SeasonMeta?
    /// 기록상 에너지 수준(2026-07-23) — 있으면 제목 예시를 에너지별로, 없으면 계절 매트릭스 폴백
    let energyLevel: EnergyLevel?

    /// 지난 날짜에 추가하는 건 대개 "그날 한 번 했다"는 기록이다 — 매일로 잡히면 오늘까지 따라온다.
    /// 오늘·미래는 종전대로 매일 기본(체크리스트가 본질). 2026-07-27 사용자 결정.
    init(day: Date = .now, currentSeason: SeasonMeta?, energyLevel: EnergyLevel? = nil) {
        self.day = day
        self.currentSeason = currentSeason
        self.energyLevel = energyLevel
        let cal = Calendar.current
        _repeats = State(initialValue: cal.startOfDay(for: day) >= cal.startOfDay(for: .now))
    }

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
                        let cal = Calendar.current
                        modelContext.insert(InputItem(title: title, category: category, schedule: schedule,
                                                      createdAt: anchorDate(for: day),
                                                      backfilled: cal.startOfDay(for: day) < cal.startOfDay(for: .now)))
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
    /// 어느 날에 추가하는가 — InputAddSheet와 같은 근거(2026-07-26)
    var day: Date = .now

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
                        let item = OutputItem(title: title, schedule: schedule, progressKind: kind,
                                              createdAt: anchorDate(for: day))
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

/// 아이템 시작 기준선 — 오늘이면 지금 시각 그대로, 다른 날이면 그날의 같은 시각.
/// 날짜만 startOfDay로 뭉개면 같은 날 추가한 아이템들의 정렬(createdAt)이 동률이 돼 순서가 흔들린다.
func anchorDate(for day: Date) -> Date {
    let cal = Calendar.current
    let now = Date()
    if cal.isDate(day, inSameDayAs: now) { return now }
    var comps = cal.dateComponents([.year, .month, .day], from: day)
    let time = cal.dateComponents([.hour, .minute, .second], from: now)
    comps.hour = time.hour
    comps.minute = time.minute
    comps.second = time.second
    return cal.date(from: comps) ?? day
}
