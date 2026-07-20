// 템포루틴 — 생리 기록 트래커 (2026-07-20 사용자 결정: 캘린더 탭은 조회 전용,
// 편집은 이 전용 화면 — 애플 건강 주기 추적 문법: 날짜 스트립 + 기록 행 토글)
// 데이터 계약은 불변: PeriodStore 경유(dedup=day·미래 금지·HK 미러·§5.5.4).
// 접근성 대체 경로 = 하루 상세 "생리 기록" 토글 유지.

import SwiftUI
import SwiftData
import TempoCore

struct PeriodTrackerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PeriodDay.day) private var periodDays: [PeriodDay]

    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var recordFeedback = 0

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: .now) }
    private var recordedDays: Set<Date> { Set(periodDays.map(\.day)) }
    private var isSelectedRecorded: Bool { recordedDays.contains(selectedDay) }

    /// 스트립 범위: 과거 90일 ~ 미래 6일(미래는 표시만, 기록 불가)
    private var stripDays: [Date] {
        (-90...6).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
            .map { cal.startOfDay(for: $0) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.paper.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 20) {
                    Text(dayTitle)
                        .font(.system(.title2, design: .serif).weight(.bold))
                        .foregroundStyle(Ink.text)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                    dayStrip
                    recordSection
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("생리 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: recordFeedback)
    }

    private var dayTitle: String {
        let base = selectedDay.formatted(.dateTime.month().day())
        return selectedDay == today ? "\(base), 오늘" : base
    }

    // ── 날짜 스트립 (가로 스크롤, 선택일 중앙) ──
    private var dayStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(stripDays, id: \.self) { day in
                        dayPill(day)
                            .id(day)
                    }
                }
                .padding(.horizontal, 20)
            }
            .onAppear {
                proxy.scrollTo(selectedDay, anchor: .center)
            }
            .onChange(of: selectedDay) { _, day in
                withAnimation { proxy.scrollTo(day, anchor: .center) }
            }
        }
        .frame(height: 96)
    }

    private func dayPill(_ day: Date) -> some View {
        let recorded = recordedDays.contains(day)
        let selected = day == selectedDay
        let future = day > today
        return Button {
            selectedDay = day
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
                    .fill(recorded ? Ink.coral.opacity(0.35) : Ink.text.opacity(0.06))
                    .frame(width: 38, height: 56)
                    .overlay {
                        RoundedRectangle(cornerRadius: 19)
                            .stroke(selected ? Ink.text.opacity(0.6) : .clear, lineWidth: 1.5)
                    }
                    .overlay(alignment: .bottom) {
                        Text("\(cal.component(.day, from: day))")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Ink.text.opacity(0.55))
                            .padding(.bottom, 6)
                    }
            }
            .opacity(future ? 0.4 : 1.0)
        }
        .accessibilityLabel("\(day.formatted(.dateTime.month().day()))\(recorded ? ", 생리 기록" : "")\(future ? ", 미래" : "")")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func weekdayLetter(_ day: Date) -> String {
        let symbols = cal.veryShortWeekdaySymbols
        return symbols[cal.component(.weekday, from: day) - 1]
    }

    // ── 기록 섹션 (건강 앱 문법: 행 탭 = 해당 날짜 기록 토글) ──
    private var recordSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("기록")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Ink.text)
            Button {
                togglePeriod()
            } label: {
                HStack(spacing: 10) {
                    Circle().fill(Ink.coral).frame(width: 8, height: 8)
                    Text("생리")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Ink.text)
                    Spacer()
                    Image(systemName: isSelectedRecorded ? "checkmark.circle.fill" : "plus")
                        .foregroundStyle(isSelectedRecorded ? Ink.coral : Ink.text.opacity(0.5))
                }
                .padding(16)
                .background(Ink.coral.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(selectedDay > today)   // 미래 기록 금지(원칙 4)
            .accessibilityValue(isSelectedRecorded ? "기록됨" : "기록 없음")
            if selectedDay > today {
                Text("미래 날짜는 기록할 수 없어요.")
                    .font(.caption)
                    .foregroundStyle(Ink.text.opacity(0.45))
            }
        }
        .padding(.horizontal, 20)
    }

    private func togglePeriod() {
        let all = periodDays
        let day = selectedDay
        recordFeedback += 1
        if recordedDays.contains(day) {
            let records = all.filter { $0.day == day }
            Task { await PeriodStore.remove(records: records, context: modelContext, all: all) }
        } else {
            Task { await PeriodStore.add(days: [day], context: modelContext, existing: all) }
        }
    }
}
