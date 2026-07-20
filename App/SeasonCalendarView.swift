// 템포루틴 — 계절 캘린더 (Phase 0 ③, MASTER §5.9-3 / §8.2.3 / §4 보강 I 책력 조판)
// 계절 = 숫자 잉크색(글리프 정식 이식은 §5.9-8 미학 패스), 오늘 = 은필 채운 원,
// 생리 = 코랄 형광펜(기록) / 회색 형광펜(예상, 미래만 — 과거 소급 투영 금지 §5.6.2).
// 캘린더 탭은 조회 전용(2026-07-20 사용자 결정 — 드래그·길게 누르기 편집 폐기, MASTER I-2b 개정 대기).
// 기록 편집 = 상단 "생리 기록" 버튼 → PeriodTrackerSheet(건강 앱 문법) + 하루 상세 토글(접근성 유지).
// 탭 = 하루 상세 push.

import SwiftUI
import SwiftData
import TempoCore
import UIKit

struct SeasonCalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PeriodDay.day) private var periodDays: [PeriodDay]
    @Query(sort: \ScheduleItem.date) private var schedules: [ScheduleItem]
    @Query(sort: \InputItem.createdAt) private var inputs: [InputItem]
    @Query(sort: \OutputItem.createdAt) private var outputs: [OutputItem]

    @State private var monthAnchor = Calendar.current.startOfDay(for: .now)
    @State private var showLogSheet = false
    @State private var pushedDay: Date?

    // v16 확정: 개방형·풀하이트 — 그리드가 남은 세로를 균등 분할(grid-auto-rows: 1fr).
    // 고정 셀 높이 폐기, 최소 높이만 보장(일정 글줄 노출 여지 — 프로토 min-height 54px).
    private let minCellHeight: CGFloat = 54
    /// 예측 형광펜 회색 — 다크에선 한 단계 밝게 (기준 대응 팔레트)
    private let highlightGray = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x9B / 255, green: 0xA2 / 255, blue: 0xA8 / 255, alpha: 1)
            : UIColor(red: 0x87 / 255, green: 0x8E / 255, blue: 0x94 / 255, alpha: 1)
    })

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: .now) }
    private var recordedDays: Set<Date> { Set(periodDays.map(\.day)) }
    private var starts: [Date] { PeriodMath.episodeStarts(days: periodDays.map(\.day)) }
    private var avgLength: Int { CyclePredictor.averageLength(startDates: starts) }

    /// §5.6.2 투영 지평 — low=1 / medium=2 / high=3 주기까지만 예측 렌더.
    private var horizonCycles: Int {
        switch CyclePredictor.confidence(periodStarts: starts) {
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }

    // ── 월 그리드 파라미터 ──
    private var monthStart: Date {
        cal.date(from: cal.dateComponents([.year, .month], from: monthAnchor)) ?? monthAnchor
    }
    private var daysInMonth: Int {
        cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
    }
    private var leadingBlanks: Int {
        (cal.component(.weekday, from: monthStart) - cal.firstWeekday + 7) % 7
    }
    private var rowCount: Int { (leadingBlanks + daysInMonth + 6) / 7 }

    var body: some View {
        let marks = monthMarks
        ZStack {
            Ink.paper.ignoresSafeArea()
            SeasonLight(phase: CycleSnapshot(periodDays: periodDays).phase(on: today))
            VStack(alignment: .leading, spacing: 12) {
                monthHeader
                HStack(alignment: .firstTextBaseline) {
                    Text(seasonLine)
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Ink.text.opacity(0.65))
                    Spacer()
                    // 기록 편집 진입 — 캘린더 탭 자체는 조회 전용
                    Button {
                        showLogSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(Ink.coral).frame(width: 7, height: 7)
                            Text("생리 기록")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Ink.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay(Capsule().stroke(Ink.text.opacity(0.3), lineWidth: 1))
                    }
                }
                weekdayRow
                grid(marks: marks)
                legend
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .sheet(isPresented: $showLogSheet) {
            PeriodTrackerSheet()
        }
        .navigationDestination(isPresented: Binding(
            get: { pushedDay != nil },
            set: { if !$0 { pushedDay = nil } }
        )) {
            if let pushedDay {
                DayDetailView(day: pushedDay)
            }
        }
    }

    /// 이 달의 잉크 글줄(§5.9-4: resolve가 캘린더에 뜨는지) — 일정 + cycle-anchored occurrence.
    /// 매일 Input은 셀에 그리지 않음(전 셀 노이즈). projected는 faded.
    private var monthMarks: [Date: [(title: String, projected: Bool)]] {
        var marks: [Date: [(title: String, projected: Bool)]] = [:]
        let snap = CycleSnapshot(periodDays: periodDays)
        for dayNumber in 1...daysInMonth {
            guard let d = cal.date(byAdding: .day, value: dayNumber - 1, to: monthStart) else { continue }
            let day = cal.startOfDay(for: d)
            for s in schedules where s.occurs(on: day) {
                marks[day, default: []].append((s.title, false))
            }
        }
        guard let monthEnd = cal.date(byAdding: .day, value: daysInMonth, to: monthStart) else { return marks }
        for item in inputs {
            if case .cycleAnchored(let r) = item.schedule {
                for occ in snap.occurrences(of: r, createdAt: cal.startOfDay(for: item.createdAt))
                where occ.date >= monthStart && occ.date < monthEnd {
                    marks[cal.startOfDay(for: occ.date), default: []].append((item.title, occ.projected))
                }
            }
        }
        for item in outputs {
            for occ in snap.occurrences(of: item.recurrence, createdAt: cal.startOfDay(for: item.createdAt))
            where occ.date >= monthStart && occ.date < monthEnd {
                if item.isComplete && occ.projected { continue }   // §5.5.2 완료된 Output 미래 미표시
                marks[cal.startOfDay(for: occ.date), default: []].append((item.title, occ.projected))
            }
        }
        return marks
    }

    // ── 표제 (책력 조판: 거대 월 + 연도, 월 이동) ──
    private var monthHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(cal.component(.month, from: monthStart))월")
                .font(.almanac(size: 58, weight: .bold))   // v6 거대 표제부 확정 치수
                .foregroundStyle(Ink.text)
            Text(String(cal.component(.year, from: monthStart)))
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.5))
            Spacer()
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(Ink.text)
    }

    private func shiftMonth(_ delta: Int) {
        if let next = cal.date(byAdding: .month, value: delta, to: monthStart) {
            monthAnchor = next
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortWeekdaySymbols
        let shift = cal.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { s in
                Text(s)
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.winter)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 4)
        .almanacRule(opacity: 0.28)   // 은필 괘선
    }

    // ── 그리드 ──
    private func grid(marks: [Date: [(title: String, projected: Bool)]]) -> some View {
        VStack(spacing: 4) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        cell(index: row * 7 + col, marks: marks)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(minHeight: minCellHeight, maxHeight: .infinity)   // 풀하이트 균등 분할
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func date(at index: Int) -> Date? {
        let dayNumber = index - leadingBlanks + 1
        guard dayNumber >= 1 && dayNumber <= daysInMonth else { return nil }
        return cal.date(byAdding: .day, value: dayNumber - 1, to: monthStart).map { cal.startOfDay(for: $0) }
    }

    @ViewBuilder
    private func cell(index: Int, marks: [Date: [(title: String, projected: Bool)]]) -> some View {
        if let date = date(at: index) {
            let style = cellStyle(for: date)
            let recorded = recordedDays.contains(date)
            let predicted = !recorded && isPredictedPeriod(date)
            let isToday = date == today
            let cellMarks = marks[date] ?? []
            VStack(spacing: 0) {
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 14, weight: isToday ? .bold : .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Ink.paper : style.color)
                    .frame(width: 27, height: 27)
                    .background {
                        if isToday {
                            Circle().fill(Ink.winter)   // 오늘 = 은필 흑청 채운 원 (먹색은 기각 이력, §8.1)
                        }
                    }
                // 일정·occurrence = 날짜 밑 작은 잉크 글줄(책력 문법, 프로토 v15)
                // 잉크 글줄(v16): 먹색 78% / 과거는 산화색 75% / 예상은 옅게
                ForEach(Array(cellMarks.prefix(2).enumerated()), id: \.offset) { _, mark in
                    Text(mark.title)
                        .font(.system(size: 8.5, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(mark.projected ? Ink.text.opacity(0.45)
                                         : (date < today ? Ink.oxide.opacity(0.75) : Ink.text.opacity(0.78)))
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 3)
            .padding(.horizontal, 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if recorded || predicted {
                    highlightBand(for: date, index: index, recorded: recorded)
                        .transaction { $0.animation = nil }   // 형광펜 on/off 즉시 전환
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { pushedDay = date }   // 탭 → 하루 상세 push(§8.2.3). 기록 편집은 트래커·하루 상세만
            .accessibilityElement()
            .accessibilityLabel(accessibilityText(for: date, style: style, recorded: recorded, predicted: predicted))
            .accessibilityAddTraits(.isButton)
        } else {
            Color.clear
        }
    }

    /// 형광펜 밴드 — 연속 구간은 이어지고 양 끝만 둥글게 (행 경계 포함).
    private func highlightBand(for date: Date, index: Int, recorded: Bool) -> some View {
        let prev = cal.date(byAdding: .day, value: -1, to: date).map { sameKind($0, recorded: recorded) } ?? false
        let next = cal.date(byAdding: .day, value: 1, to: date).map { sameKind($0, recorded: recorded) } ?? false
        let col = index % 7
        let roundLeft = !prev || col == 0
        let roundRight = !next || col == 6
        return UnevenRoundedRectangle(
            topLeadingRadius: roundLeft ? 9 : 0,
            bottomLeadingRadius: roundLeft ? 9 : 0,
            bottomTrailingRadius: roundRight ? 9 : 0,
            topTrailingRadius: roundRight ? 9 : 0
        )
        .fill((recorded ? Ink.coral : highlightGray).opacity(0.22))
        .frame(height: 20)
        .padding(.leading, roundLeft ? 4 : 0)
        .padding(.trailing, roundRight ? 4 : 0)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 6)   // 숫자(상단 27pt 원역) 뒤를 지나는 마커 — 프로토 z-계층과 동일
    }

    private func sameKind(_ date: Date, recorded: Bool) -> Bool {
        recorded ? recordedDays.contains(date)
                 : (!recordedDays.contains(date) && isPredictedPeriod(date))
    }

    // ── 단계 → 렌더 규칙 ──
    private func cellStyle(for date: Date) -> (color: Color, meta: SeasonMeta?, projected: Bool) {
        guard let last = starts.max() else { return (Ink.text, nil, false) }   // S0 = 전부 먹색
        // 투영 지평 밖 미래 = 먹색 (예측 렌더 중단)
        if let horizon = cal.date(byAdding: .day, value: horizonCycles * avgLength, to: last), date > horizon {
            return (Ink.text, nil, false)
        }
        guard let r = CyclePredictor.cycleDay(of: date, periodStarts: starts, averageLength: avgLength) else {
            return (Ink.text, nil, false)
        }
        let meta = seasonMeta(for: CyclePredictor.phaseForDay(r.day, cycleLength: avgLength))
        return (meta.color.opacity(r.projected ? 0.55 : 1.0), meta, r.projected)   // 미래/역투영 = faded
    }

    /// 회색 형광펜 = 예상 생리일 (I-2b). 미래·투영 구간의 월경기만, 오늘 이전 소급 금지.
    private func isPredictedPeriod(_ date: Date) -> Bool {
        guard date >= today, let last = starts.max() else { return false }
        if let horizon = cal.date(byAdding: .day, value: horizonCycles * avgLength, to: last), date > horizon {
            return false
        }
        guard let r = CyclePredictor.cycleDay(of: date, periodStarts: starts, averageLength: avgLength),
              r.projected else { return false }
        return CyclePredictor.phaseForDay(r.day, cycleLength: avgLength) == .menstrual
    }

    // ── 계절 라인 (S0/S1/S2/S4 — §5.6.2) ──
    private var seasonLine: String {
        guard let last = starts.max() else { return "첫 생리일을 기록하면 계절이 채워져요" }
        let diff = cal.dateComponents([.day], from: last, to: today).day ?? 0
        if diff >= avgLength + TodayView.overdueGraceDays {
            return "겨울 예상 · 예정일 \(diff - avgLength)일 지남"
        }
        guard let r = CyclePredictor.cycleDay(of: today, periodStarts: starts, averageLength: avgLength) else {
            return "첫 생리일을 기록하면 계절이 채워져요"
        }
        let meta = seasonMeta(for: CyclePredictor.phaseForDay(r.day, cycleLength: avgLength))
        let hedge = starts.count == 1 ? "아마 " : ""
        let projected = r.projected ? " · 예상" : ""
        return "\(hedge)\(meta.name) · \(meta.phaseName) \(r.day)일차\(projected)"
    }

    // ── 범례 (색맹 담보: 글리프+계절명 병행 — §8.1 SeasonGlyph) ──
    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(.menstrual)
            legendItem(.follicular)
            legendItem(.ovulation)
            legendItem(.luteal)
            Spacer()
            legendSwatch(Ink.coral, "기록")
            legendSwatch(highlightGray, "예상")
        }
        .padding(.top, 6)
    }

    private func legendItem(_ phase: CyclePhase) -> some View {
        let meta = seasonMeta(for: phase)
        return HStack(spacing: 4) {
            SeasonGlyph(phase: phase, size: 12)
            Text(meta.name)
                .font(.system(size: 12, weight: .semibold, design: .serif))
                .foregroundStyle(meta.color)
        }
    }

    private func legendSwatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(color.opacity(0.3)).frame(width: 16, height: 8)
            Text(label).font(.system(size: 11)).foregroundStyle(Ink.text.opacity(0.6))
        }
    }

    private func accessibilityText(for date: Date, style: (color: Color, meta: SeasonMeta?, projected: Bool),
                                   recorded: Bool, predicted: Bool) -> String {
        var parts = [date.formatted(.dateTime.month().day())]
        if let meta = style.meta {
            parts.append(meta.phaseName)
            parts.append(style.projected ? "\(meta.name) 예상" : meta.name)
        }
        if recorded { parts.append("생리 기록") }
        if predicted { parts.append("생리 예상") }
        return parts.joined(separator: ", ")
    }

}
