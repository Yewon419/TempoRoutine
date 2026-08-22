// 템포루틴 — 온보딩 ② 기준일 재구성 부품 (개정 M 2026-08-08, 프로토 onboarding-m 확정)
// DrumPicker: 상시 노출 세로 스피너(이웃 값 흐림 + 가운데 선택값 + 사이 화살표).
// OnboardingCalendar: 월 그리드 — 시작일 탭 = 지속일만큼 자동 채움, 칸 탭 = 개별 토글,
// 이전 달 이동 가능·미래 차단. 쓰기는 전부 PeriodStore(중앙 쓰기 경로) 경유.

import SwiftUI
import SwiftData
import TempoCore

// ── 세로 스피너 ──────────────────────────────────────────
struct DrumPicker: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    var body: some View {
        VStack(spacing: 10) {
            adjacent(value - 1, visible: value > range.lowerBound) { step(-1) }
            arrow("chevron.up", enabled: value > range.lowerBound) { step(-1) }
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(value)")
                    .font(.system(size: 54, weight: .bold, design: .serif))
                    .foregroundStyle(Ink.text)
                    .contentTransition(.numericText(value: Double(value)))
                Text(unit)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Ink.text.opacity(0.5))
            }
            arrow("chevron.down", enabled: value < range.upperBound) { step(1) }
            adjacent(value + 1, visible: value < range.upperBound) { step(1) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityRepresentation {
            Stepper(value: $value, in: range) { Text("\(value)\(unit)") }
        }
    }

    private func step(_ d: Int) {
        let next = min(range.upperBound, max(range.lowerBound, value + d))
        guard next != value else { return }
        withAnimation(.easeOut(duration: 0.22)) { value = next }
    }

    /// 이웃 값 — 끝값에선 투명하게만(자리 유지 = 가운데 숫자 고정, 프로토 확정 동작)
    private func adjacent(_ n: Int, visible: Bool, action: @escaping () -> Void) -> some View {
        Text(visible ? "\(n)" : " ")
            .font(.system(size: 22, design: .serif))
            .foregroundStyle(Ink.text.opacity(0.25))
            .frame(minHeight: 30)
            .opacity(visible ? 1 : 0)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Ink.text.opacity(0.55))
                .frame(width: 96, height: 36)
                .contentShape(Rectangle())
        }
        .opacity(enabled ? 1 : 0)
        .disabled(!enabled)
    }
}

// ── 온보딩 월 캘린더 ─────────────────────────────────────
struct OnboardingCalendar: View {
    let periodDays: [PeriodDay]
    let fillLength: Int                 // ②-2 지속일 답 — 시작일 탭 시 채울 일수
    let onChanged: () -> Void           // 햅틱 등 부모 피드백

    @Environment(\.modelContext) private var modelContext
    @State private var monthAnchor: Date = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var busy = false     // PeriodStore 비동기 쓰기 중 중복 탭 방지

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: .now) }
    private var markedDays: Set<Date> { Set(periodDays.map(\.day)) }

    var body: some View {
        VStack(spacing: 8) {
            header
            weekdayRow
            grid
            Text("대략이어도 괜찮아요.")
                .font(.system(.caption, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.5))
                .padding(.top, 4)
        }
    }

    private var header: some View {
        HStack {
            Button { move(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            Spacer()
            Text(monthAnchor.formatted(Loc.dateTime.year().month(.wide)))
                .font(.system(.subheadline, design: .serif).weight(.semibold))
                .foregroundStyle(Ink.text)
            Spacer()
            Button { move(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .opacity(canGoForward ? 1 : 0)
            .disabled(!canGoForward)
        }
        .foregroundStyle(Ink.text.opacity(0.6))
    }

    private var canGoForward: Bool {
        guard let next = cal.date(byAdding: .month, value: 1, to: monthAnchor) else { return false }
        return next <= today
    }

    private func move(_ d: Int) {
        guard let next = cal.date(byAdding: .month, value: d, to: monthAnchor) else { return }
        monthAnchor = next
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Loc.veryShortWeekdaySymbols(Calendar.current), id: \.self) { w in
                Text(w)
                    .font(.caption2)
                    .foregroundStyle(Ink.text.opacity(0.4))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let days = monthDays()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                         spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let marked = markedDays.contains(day)
        let future = day > today
        return Text("\(cal.component(.day, from: day))")
            .font(.system(.subheadline, design: .serif))
            .foregroundStyle(future ? Ink.text.opacity(0.2) : (marked ? Ink.paper : Ink.text))
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(marked ? Ink.text : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .onTapGesture { guard !future, !busy else { return }; tap(day) }
    }

    /// 빈 칸 패딩 포함한 이 달의 날짜들
    private func monthDays() -> [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: monthAnchor) else { return [] }
        let first = interval.start
        let count = cal.range(of: .day, in: .month, for: monthAnchor)?.count ?? 30
        let pad = cal.component(.weekday, from: first) - 1
        var result: [Date?] = Array(repeating: nil, count: pad)
        for i in 0..<count {
            result.append(cal.date(byAdding: .day, value: i, to: first))
        }
        return result
    }

    /// 미기록 날 탭 = 시작일로 보고 지속일만큼 채움(오늘 이후 캡) / 기록 날 탭 = 그 하루만 해제
    private func tap(_ day: Date) {
        busy = true
        onChanged()
        let snapshot = Array(periodDays)
        Task { @MainActor in
            if markedDays.contains(day) {
                let records = snapshot.filter { $0.day == day }
                await PeriodStore.remove(records: records, context: modelContext, all: snapshot)
            } else {
                let fill = (0..<fillLength).compactMap { cal.date(byAdding: .day, value: $0, to: day) }
                    .filter { $0 <= today }
                await PeriodStore.add(days: fill, context: modelContext, existing: snapshot)
            }
            busy = false
        }
    }
}
