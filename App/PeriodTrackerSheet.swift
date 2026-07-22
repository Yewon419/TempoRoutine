// 템포루틴 — 생리 기록 트래커 (2026-07-20 사용자 결정 2차: 애플 건강 주기 추적 문법 정합)
// - 날짜 선택 = 스크롤 중앙(▼ 마커) / 날짜 칸 탭 = 그 날짜 기록 즉시 토글 (건강 앱과 동일)
// - 기록 섹션 = 생리 행 + 컨디션(체크인 §3.4 — 선택 날짜의 에너지·기분·잠·한 줄)
// 데이터 계약 불변: PeriodStore 경유(dedup=day·미래 금지·HK 미러), DailyCheckIn day 키 upsert.

import SwiftUI
import SwiftData
import TempoCore

struct PeriodTrackerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PeriodDay.day) private var periodDays: [PeriodDay]

    @State private var centeredDay: Date? = Calendar.current.startOfDay(for: .now)
    @State private var recordFeedback = 0
    @State private var seasonFeedback = 0   // 계절 전환 확정 순간(§4 — 생리 기록·아이템 완료와 구분되는 특별한 순간)
    @State private var lightFeedback = 0    // 작은 햅틱(§4 — 연동 토글 등, 확정 아님)

    // 지연 제거(사용자 결정): 시트 안은 로컬 드래프트로 즉시 토글,
    // 저장·에피소드 재계산·HK 미러는 완료/닫기 때 일괄 커밋
    @State private var draftRecorded: Set<Date> = []
    @State private var draftLoaded = false
    @State private var committed = false
    @State private var showDatePicker = false   // 날짜 제목 탭 → 날짜 피커 점프(2026-07-22 베타 피드백)
    private let mirror = HealthMirror.shared

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: .now) }
    private var recordedDays: Set<Date> { Set(periodDays.map(\.day)) }
    private var selectedDay: Date { centeredDay ?? today }
    private var isSelectedFuture: Bool { selectedDay > today }

    /// 스트립 범위: 과거 90일 ~ 미래 6일(미래는 표시만, 기록 불가)
    private var stripDays: [Date] {
        (-90...6).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
            .map { cal.startOfDay(for: $0) }
    }

    var body: some View {
        // 렌더 소스 = 로컬 드래프트 (즉시 반영, 저장은 커밋 때)
        let recorded = draftRecorded
        NavigationStack {
            ZStack {
                Ink.paper.ignoresSafeArea()
                SeasonLight(phase: CycleSnapshot(periodDays: periodDays).phase(on: selectedDay))
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Button {
                            lightFeedback += 1
                            showDatePicker = true
                        } label: {
                            Text(dayTitle)
                                .font(.almanac(size: 22, weight: .bold))
                                .foregroundStyle(Ink.text)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                        .popover(isPresented: $showDatePicker) {
                            DatePicker(
                                "날짜 선택",
                                selection: Binding(
                                    get: { selectedDay },
                                    set: { newDay in
                                        centeredDay = cal.startOfDay(for: newDay)
                                        showDatePicker = false
                                    }
                                ),
                                in: (stripDays.first ?? today)...(stripDays.last ?? today),
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                            .tint(Ink.text)
                            .padding()
                            .presentationCompactAdaptation(.popover)
                        }
                        dayStrip(recorded: recorded)
                        recordSection(recorded: recorded)
                    }
                    .padding(.vertical, 10)
                }
            }
            .navigationTitle("생리 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        commit()
                        dismiss()
                    }
                    .foregroundStyle(Ink.text)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: recordFeedback)
        .sensoryFeedback(.success, trigger: seasonFeedback)
        .sensoryFeedback(.impact(weight: .light), trigger: lightFeedback)
        .onAppear {
            if !draftLoaded {
                draftLoaded = true
                draftRecorded = recordedDays
            }
        }
        .onDisappear { commit() }   // 스와이프로 닫아도 커밋 보장
    }

    /// 드래프트 ↔ 실제 차이만 일괄 반영 — PeriodStore가 dedup·미래 금지·HK 미러 담당
    private func commit() {
        guard !committed else { return }
        committed = true
        let actual = recordedDays
        let adds = draftRecorded.subtracting(actual).filter { $0 <= today }
        let removeDays = actual.subtracting(draftRecorded)
        guard !adds.isEmpty || !removeDays.isEmpty else { return }
        let records = periodDays.filter { removeDays.contains($0.day) }
        let all = periodDays
        let phaseBefore = CycleSnapshot(periodDays: all).phase(on: today)
        let projectedDays = all.map(\.day).filter { !removeDays.contains($0) } + adds
        let phaseAfter = CycleSnapshot(days: projectedDays).phase(on: today)
        if phaseAfter != phaseBefore {
            seasonFeedback += 1   // 오늘의 계절이 이 편집으로 바뀜 — 확정 순간(§4)
        }
        Task {
            if !records.isEmpty {
                await PeriodStore.remove(records: records, context: modelContext, all: all)
            }
            if !adds.isEmpty {
                await PeriodStore.add(days: Array(adds), context: modelContext, existing: all.filter { !removeDays.contains($0.day) })
            }
        }
    }

    private var dayTitle: String {
        let base = selectedDay.formatted(.dateTime.month().day())
        return selectedDay == today ? "\(base), 오늘" : base
    }

    // ── 날짜 스트립: 스크롤 중앙 = 선택(▼), 칸 탭 = 기록 토글 ──
    private func dayStrip(recorded: Set<Date>) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 10))
                .foregroundStyle(Ink.text)
                .frame(maxWidth: .infinity)
            GeometryReader { geo in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(stripDays, id: \.self) { day in
                            dayPill(day, recorded: recorded.contains(day))
                                .id(day)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, max(0, (geo.size.width - 38) / 2), for: .scrollContent)
                .scrollPosition(id: $centeredDay, anchor: .center)
                .scrollTargetBehavior(.viewAligned)
            }
            .frame(height: 86)
        }
    }

    private func dayPill(_ day: Date, recorded: Bool) -> some View {
        let selected = day == selectedDay
        let future = day > today
        return Button {
            togglePeriod(on: day)   // 건강 앱 문법: 칸 탭 = 그 날짜 기록 토글
        } label: {
            VStack(spacing: 6) {
                Text(weekdayLetter(day))
                    .font(.system(size: 11, weight: selected ? .bold : .regular))
                    .foregroundStyle(selected ? Ink.paper : Ink.text.opacity(0.55))
                    .frame(width: 22, height: 22)
                    .background {
                        if selected { Circle().fill(Ink.text) }
                    }
                RoundedRectangle(cornerRadius: 19)
                    .fill(recorded ? Ink.coral.opacity(0.38) : Ink.text.opacity(0.06))
                    .frame(width: 38, height: 52)
                    .overlay(alignment: .bottom) {
                        Text("\(cal.component(.day, from: day))")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Ink.text.opacity(0.55))
                            .padding(.bottom, 6)
                    }
            }
            .opacity(future ? 0.4 : 1.0)
            .transaction { $0.animation = nil }   // 기록 on/off는 즉시 전환(페이드 금지 — 사용자 결정)
        }
        .disabled(future)
        .accessibilityLabel("\(day.formatted(.dateTime.month().day()))\(recorded ? ", 생리 기록됨" : "")\(future ? ", 미래" : "")")
        .accessibilityHint(future ? "" : "이중 탭으로 생리 기록 전환")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func weekdayLetter(_ day: Date) -> String {
        cal.veryShortWeekdaySymbols[cal.component(.weekday, from: day) - 1]
    }

    // ── 기록 섹션: 생리 + 컨디션(체크인) ──
    private func recordSection(recorded: Set<Date>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("기록")
                .font(.almanac(size: 17, weight: .bold))
                .foregroundStyle(Ink.text)
            periodRow(recorded: recorded.contains(selectedDay))
            CheckInEditor(day: selectedDay)
            healthLinkRow
        }
        .padding(.horizontal, 20)
    }

    // ── 건강 앱 연동 진입 (설정과 동일 동작 — 기록 맥락에서 바로 접근) ──
    @ViewBuilder
    private var healthLinkRow: some View {
        if mirror.available {
            let on = mirror.linked && mirror.writeAuthorized
            Button {
                lightFeedback += 1
                if on {
                    mirror.linked = false
                } else {
                    let current = periodDays
                    Task {
                        if await mirror.requestAccess() {
                            await mirror.sync(context: modelContext, periodDays: current)
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "heart")
                        .font(.footnote)
                        .foregroundStyle(Ink.text.opacity(0.6))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("건강 앱과 연동")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Ink.text)
                        Text(on ? "생리 기록이 건강 앱에도 저장돼요." : "건강 앱의 기록을 함께 보고, 이 앱의 기록도 저장해요.")
                            .font(.caption)
                            .foregroundStyle(Ink.text.opacity(0.55))
                    }
                    Spacer()
                    Text(on ? "켜짐" : "연동")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(on ? Ink.paper : Ink.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if on { Capsule().fill(Ink.text) }
                            else { Capsule().stroke(Ink.text.opacity(0.3), lineWidth: 1) }
                        }
                }
                .padding(16)
                .milkGlass(radius: 14)
                .transaction { $0.animation = nil }
            }
            .accessibilityValue(on ? "켜짐" : "꺼짐")
        }
    }

    private func periodRow(recorded: Bool) -> some View {
        Button {
            togglePeriod(on: selectedDay)
        } label: {
            HStack(spacing: 10) {
                Circle().fill(Ink.coral).frame(width: 8, height: 8)
                Text("생리")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Ink.text)
                Spacer()
                Image(systemName: recorded ? "checkmark.circle.fill" : "plus")
                    .foregroundStyle(recorded ? Ink.coral : Ink.text.opacity(0.5))
            }
            .padding(16)
            .background(Ink.coral.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            .transaction { $0.animation = nil }
        }
        .disabled(isSelectedFuture)
        .accessibilityValue(recorded ? "기록됨" : "기록 없음")
    }

    private func togglePeriod(on day: Date) {
        guard day <= today else { return }
        recordFeedback += 1
        if draftRecorded.contains(day) {
            draftRecorded.remove(day)   // 로컬 즉시 — 저장은 commit()
        } else {
            draftRecorded.insert(day)
        }
    }
}

// ── 컨디션 편집기 — 선택 날짜의 DailyCheckIn (§3.4: 3탭=1·3·5, 스킵 무벌점, 미래 금지) ──
struct CheckInEditor: View {
    let day: Date

    @Environment(\.modelContext) private var modelContext
    @Query private var checkIns: [DailyCheckIn]

    @State private var draftEnergy = 0
    @State private var draftMood = 0
    @State private var draftSleep = 0
    @State private var draftNote = ""
    @State private var lightFeedback = 0   // 작은 햅틱(§4 — 신호 선택, 확정 아님)

    private var today: Date { Calendar.current.startOfDay(for: .now) }
    private var isFuture: Bool { day > today }
    private var record: DailyCheckIn? { checkIns.first { $0.day == day } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle().fill(Ink.winter).frame(width: 8, height: 8)
                Text("컨디션")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Ink.text)
                Spacer()
            }
            signalRow(label: "에너지는", options: ["낮음", "보통", "높음"], value: $draftEnergy)
            signalRow(label: "기분은", options: ["흐림", "보통", "맑음"], value: $draftMood)
            signalRow(label: "지난밤 잠은", options: ["뒤척임", "보통", "푹 잤어요"], value: $draftSleep)
            TextField("남기고 싶은 만큼만, 짧게.", text: $draftNote, axis: .vertical)
                .font(.footnote)
                .foregroundStyle(Ink.text)
                .onChange(of: draftNote) { persist() }
        }
        .padding(16)
        .milkGlass(radius: 14)
        .opacity(isFuture ? 0.45 : 1.0)
        .disabled(isFuture)
        .sensoryFeedback(.impact(weight: .light), trigger: lightFeedback)
        .onAppear(perform: load)
        .onChange(of: day) { load() }
    }

    private func signalRow(label: String, options: [String], value: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Ink.text.opacity(0.7))
                .frame(width: 84, alignment: .leading)
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let mapped = index * 2 + 1   // 3탭 = 1·3·5
                let selected = value.wrappedValue == mapped
                Button {
                    lightFeedback += 1
                    value.wrappedValue = selected ? 0 : mapped
                    persist()
                } label: {
                    Text(option)
                        .font(.caption2)
                        .foregroundStyle(selected ? Ink.paper : Ink.text.opacity(0.7))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(selected ? AnyShapeStyle(Ink.text) : AnyShapeStyle(Ink.text.opacity(0.08)),
                                    in: Capsule())
                }
                .accessibilityLabel("\(label) \(option)")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
    }

    private func load() {
        draftEnergy = record?.energy ?? 0
        draftMood = record?.mood ?? 0
        draftSleep = record?.sleep ?? 0
        draftNote = record?.note ?? ""
    }

    /// energy·mood 둘 다 있으면 upsert — 저장 행은 항상 §5.5 계약(1...5). 해제 = 기록 철회.
    private func persist() {
        guard !isFuture else { return }
        if let existing = record {
            if draftEnergy > 0 && draftMood > 0 {
                existing.energy = draftEnergy
                existing.mood = draftMood
                existing.sleep = draftSleep > 0 ? draftSleep : nil
                existing.note = draftNote.isEmpty ? nil : draftNote
            } else {
                modelContext.delete(existing)
            }
        } else if draftEnergy > 0 && draftMood > 0 {
            let new = DailyCheckIn(day: day, energy: draftEnergy, mood: draftMood)
            new.sleep = draftSleep > 0 ? draftSleep : nil
            new.note = draftNote.isEmpty ? nil : draftNote
            modelContext.insert(new)
        }
    }
}
