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
    /// 표시는 번역을 거친다 — rawValue는 저장·식별 키(2026-08-22). Input/Output은 키 그대로 나온다.
    var title: String { Loc.text(rawValue) }

    /// 구획 ⓘ 설명(2026-08-06 베타 피드백 — 체크인 행이 아니라 구획 제목 뒤).
    /// 문안 = 코치마크(§3.6 카드 정의의 사용자 언어)와 같은 계열.
    var info: String {
        switch self {
        case .schedule: Loc.str("약속이나 생일같은 일정을 적어봐요. 텍스트에서 시간을 자동으로 읽어올수도 있어요.")
        // 「각」 앞에서 줄바꿈(2026-08-16 베타 피드백) — 온보딩 장에서 "각"만 첫 줄 끝에 걸렸다
        case .input: Loc.str("식단이나 운동처럼 나를 채우는 일들이에요.\n각 계절에 맞는 인풋으로 당신을 채워봐요.")
        case .output: Loc.str("프로젝트나 공부처럼 내보내는 일들이에요. 계절에 따라 분량을 조절해보면 어떨까요?")
        }
    }
}

/// 회색 물음표 뱃지 — 탭 = 설명 알럿. 구획 제목·온보딩 항목 공용(2026-08-06 베타 피드백).
/// 알럿을 자체 보유해 부모 뷰에 상태를 요구하지 않는다.
struct InfoBadge: View {
    let title: String
    let message: String
    @State private var show = false

    var body: some View {
        Button {
            show = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(Ink.text.opacity(0.35))
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Loc.fmt("%1$@ 설명", "\(title)"))
        .alert(title, isPresented: $show) {
            Button("확인") {}
        } message: {
            Text(message)
        }
    }
}

struct DayDetailView: View {
    /// 진입한 날짜 — 화면 안에서 전날·다음날로 옮기면 offset만 움직인다(2026-08-01 베타 피드백).
    /// 화면을 새로 push하지 않으므로 뒤로가기 스택이 쌓이지 않는다.
    private let anchorDay: Date
    /// 주기 지도 경유(2026-08-18) — 이 화면에서 추가하는 Input·Output에 그날의 계절·일차를
    /// 주기 반복 프리셋으로 얹는다("이 탭에서 추가되는 건 기본 주기 반복" — 사용자 지시).
    private let presetsCycleAnchor: Bool
    @State private var dayOffset = 0

    init(day: Date, presetsCycleAnchor: Bool = false) {
        self.anchorDay = day
        self.presetsCycleAnchor = presetsCycleAnchor
    }

    /// 지금 보고 있는 날짜 — 내부 전 계산의 기준(종전 `day` 저장 프로퍼티 자리)
    private var day: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: anchorDay) ?? anchorDay
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PeriodDay.day) private var periodDays: [PeriodDay]
    @Query(sort: \ScheduleItem.date) private var schedules: [ScheduleItem]
    @Query(sort: \InputItem.createdAt) private var inputs: [InputItem]
    @Query private var inputProgresses: [InputProgress]   // Input 진행 방식(2026-08-12)
    @Query(sort: \OutputItem.createdAt) private var outputs: [OutputItem]
    @Query private var completions: [ItemCompletion]
    @Query private var checkIns: [DailyCheckIn]

    @State private var addSheet: CardKind?
    @State private var pendingDelete: QuickDeleteTarget?   // 행 길게 누르기 = 빠른 삭제(2026-07-27)
    @State private var editingSchedule: ScheduleItem?   // 일정 행 탭 = 수정 시트(2026-07-23)
    @State private var confirmFeedback = 0   // 확정 순간 햅틱(§4 — 생리 기록·아이템 완료)
    @State private var lightFeedback = 0     // 작은 햅틱(§4 — 진행도 조정·월 이동 등, 확정 아님)

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: .now) }
    private var isFuture: Bool { day > today }

    /// 활판 라틴 스탬프 `Tuesday, 28 July` — 캘린더 latinMonthFormatter와 같은 en_US 고정
    private static let latinStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter
    }()
    private static func latinStamp(_ date: Date) -> String {
        latinStampFormatter.string(from: date)
    }
    private var snapshot: CycleSnapshot { CycleSnapshot(periodDays: periodDays) }

    var body: some View {
        ZStack {
            // 티켓 = 흰 지면(2026-08-18 2차 — 유화는 오늘·나의 템포만)
            if ThemeStore.chrome.skyGround {
                WeatherSky()   // 날씨 = 오늘의 하늘(시안 §5.3-1 — 하루 상세도 하늘 지면)
            } else if ThemeStore.chrome.videoGround {
                PlaylistVideoGround()   // 플리 = 계절 배경 영상(§4.4 ⑪)
            } else {
                Ink.paper.ignoresSafeArea()
                SeasonLight(phase: snapshot.phase(on: day))
            }
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
                            .id(day)   // 날짜를 옮기면 카드 내부 입력 상태도 그날 것으로 새로 뜬다
                    }
                }
                .padding(20)
            }
            // 슬라이드로도 날짜 이동(2026-08-01) — 세로 스크롤을 막지 않게 동시 인식 + 수평 우세일 때만.
            // 좌측 엣지에서 시작한 드래그는 시스템 뒤로가기 몫이라 건드리지 않는다.
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        guard value.startLocation.x > 40 else { return }
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                        if value.translation.width < -50 { move(by: 1) }
                        else if value.translation.width > 50 { move(by: -1) }
                    }
            )
        }
        .safeAreaInset(edge: .bottom) { dayNavBar }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.impact(weight: .medium), trigger: confirmFeedback)
        .sensoryFeedback(.impact(weight: .light), trigger: lightFeedback)
        .sheet(item: $addSheet) { kind in
            Group {
            switch kind {
            case .schedule: ScheduleAddSheet(defaultDate: day)
            case .input:    InputAddSheet(day: day,
                                          currentSeason: snapshot.phaseInfo(on: today)?.meta,
                                          energyLevel: snapshot.phase(on: today).flatMap {
                                              EnergyProfile(checkIns: checkIns, snapshot: snapshot).level(for: $0)
                                          },
                                          presetSeason: cycleAnchorPreset?.season,
                                          presetDayOffset: cycleAnchorPreset?.dayOffset)
            case .output:   OutputAddSheet(day: day,
                                          presetSeason: cycleAnchorPreset?.season,
                                          presetDayOffset: cycleAnchorPreset?.dayOffset,
                                          energyLevel: snapshot.phase(on: today).flatMap {
                                              EnergyProfile(checkIns: checkIns, snapshot: snapshot).level(for: $0)
                                          })
            }
            }
            .themeColorScheme()
        }
        .sheet(item: $editingSchedule) { item in
            ScheduleAddSheet(defaultDate: day, editing: item).themeColorScheme()
        }
        .quickDeleteDialog($pendingDelete, completions: completions, context: modelContext)
    }

    /// 전날·다음날 이동 바(2026-08-01 베타 피드백) — 화살표 + 가운데에 지금 보는 날짜
    private var dayNavBar: some View {
        HStack {
            navArrow(systemName: "chevron.left", label: Loc.str("전날")) { move(by: -1) }
            Spacer()
            Text(day.formatted(Loc.dateTime.month().day().weekday(.abbreviated)))
                .font(.almanacBody(.footnote, size: 13))
                .foregroundStyle(Ink.text.opacity(0.6))
            Spacer()
            navArrow(systemName: "chevron.right", label: Loc.str("다음날")) { move(by: 1) }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Rectangle().fill(.ultraThinMaterial)
            .skyGlassScheme())   // 날씨 = 라이트 외관에서도 다크 글래스(2026-08-31)
    }

    private func navArrow(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Ink.text.opacity(0.8))
                .frame(width: 44, height: 44)   // §8.1 터치 44pt
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    /// 주기 지도 경유일 때만 — 보고 있는 날의 (계절, 계절 내 일차-1)을 추가 시트 프리셋으로.
    /// 날짜를 옮기면 옮긴 날 기준으로 따라간다.
    private var cycleAnchorPreset: (season: SeasonAnchor, dayOffset: Int)? {
        guard presetsCycleAnchor, let info = snapshot.phaseInfo(on: day),
              let season = SeasonAnchor.allCases.first(where: { $0.phase == info.meta.phase })   // 표시명 비교 금지
        else { return nil }
        return (season, info.dayInPhase - 1)
    }

    private func move(by days: Int) {
        lightFeedback += 1   // 월 이동과 같은 계층(§4 — 확정 아님)
        dayOffset += days
    }

    // ── 상단: 날짜 표제 + 계절·단계 칩 ──
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // 모던 = 아웃라인 표제(시안 §1.3-2), 그 외 = 종전 솔리드(v6 확정 56px)
                almanacDisplay("\(cal.component(.day, from: day))",
                               size: ThemeStore.chrome.debossDisplay ? 80 : 56,
                               color: Ink.text)
                if ThemeStore.chrome.latinCalendarHeader {
                    // 활판 = 라틴 이탤릭 스탬프(시안 §2.5.1 종결, 2026-08-24) — 캘린더 `July 2026`
                    // 라벨과 동형(같은 서체·버밀리언). 언어 무관 라틴 — 활판 조판 문법의 일부.
                    Text(Self.latinStamp(day))
                        .font(.system(size: 14, design: .serif).italic())
                        .foregroundStyle(Ink.autumn)
                } else {
                    Text(day.formatted(Loc.dateTime.month().weekday(.wide)))
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Ink.text.opacity(0.6))
                }
            }
            // 공휴일·기념일 표기(2026-07-28) — 소스는 캘린더 셀과 동일(애플 캘린더 우선, 내장 폴백)
            let holidays = dayHolidays()
            if !holidays.isEmpty {
                Text(holidays.map { Loc.holidayName($0.name) }.joined(separator: " · "))
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(holidays.contains(where: \.isPublic) ? Ink.holiday : Ink.text.opacity(0.55))
            }
            if let info = snapshot.phaseInfo(on: day) {
                HStack(spacing: 6) {
                    Text(Loc.fmt("%1$@ %2$@일차", "\(info.meta.name)", "\(info.dayInPhase)"))   // 계절 내 일차(2026-08-09 통일)
                    if info.projected { Text("· 예상") }
                }
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(info.meta.color.opacity(info.projected ? 0.7 : 1.0))
                if let line = selfCareLine {
                    Text(line)
                        .font(.system(.footnote, design: .serif))
                        .foregroundStyle(Ink.text.opacity(0.6))
                }
            } else {
                Text("계절 기록 전")
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Ink.text.opacity(0.5))
            }
        }
    }

    /// 가을 후반 자기돌봄 안내 — §5.3 `P` 소비처(개정 M). 카피 = §2.2 E+P 동반 하강 확정 문구.
    /// 침묵 조건(원칙 4): confidence low·S0·투영 지평 밖. P = 홀드아웃 채택 게이트 통과분(없으면 5).
    private var selfCareLine: String? {
        guard snapshot.horizonCycles > 1 else { return nil }   // low = 1 (§5.6.2)
        guard let r = snapshot.daysUntilNextStart(on: day) else { return nil }
        let axis = AxisProfile(checkIns: checkIns, snapshot: snapshot)
        guard r <= axis.adoptedPreWindow else { return nil }
        return Loc.str("두 호르몬이 함께 낮아지는 시기라 몸과 마음이 예민해질 수 있어요.")
    }

    /// 애플 공휴일 캘린더(연동 시) 우선, 내장 테이블 폴백 — SeasonCalendarView와 같은 규칙
    private func dayHolidays() -> [KoreanHoliday] {
        let start = cal.startOfDay(for: day)
        if let end = cal.date(byAdding: .day, value: 1, to: start),
           let names = EventOverlay.shared.holidayNames(from: start, to: end) {
            return (names[start] ?? []).map {
                KoreanHoliday(name: $0, isPublic: !KoreanHolidays.isCommemorationName($0))
            }
        }
        // 내장 표는 한국 지역 폴백 전용(2026-08-21) — 다른 나라 기기엔 아무것도 안 띄운다
        return EventOverlay.usesBuiltInKoreanHolidays ? KoreanHolidays.holidays(on: day) : []
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
    private func cardShell(_ kind: CardKind, empty: Bool, emptyMessage: String = Loc.str("아직 없어요"),
                            @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TicketFieldLabel(text: ticketFieldName(kind))   // 발권 필드명(시안 §3.3-④, 티켓만)
            HStack {
                Text(kind.title)
                    .font(.almanac(size: 17, weight: .bold))
                    .foregroundStyle(Ink.text)
                InfoBadge(title: kind.title, message: kind.info)   // 제목 뒤 ⓘ(2026-08-06 베타 피드백)
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
                .accessibilityLabel(Loc.fmt("%1$@ 추가", "\(kind.title)"))
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
        .milkGlass(stub: ticketStub(kind))
        .ticketCardGap()   // 티켓 간격 균일화(2026-08-25)
    }

    /// 티켓 스텁에 세울 «핵심 값 하나»(시안 §3.3-③) — 오늘 탭 ticketStub(for:)과 같은 규칙.
    private func ticketStub(_ kind: CardKind) -> String? {
        switch kind {
        case .schedule:
            guard let first = scheduleRows.first(where: { !$0.isAllDay }) else { return nil }
            return first.date.formatted(Loc.shortTime)
        case .input:
            let rows = inputRows
            guard !rows.isEmpty else { return nil }
            return "\(rows.filter { isCompleted($0.item.id) }.count) / \(rows.count)"
        case .output:
            let rows = outputRows
            guard !rows.isEmpty else { return nil }
            let mean = rows.map(\.item.percent).reduce(0, +) / Double(rows.count)
            return "\(Int((mean * 100).rounded()))%"
        }
    }

    // ① 일정 — 시각 있는 것 시간순, 종일(무시각)은 맨 뒤(2026-08-09 사용자 결정, 오늘 탭과 동형)
    private var scheduleRows: [ScheduleItem] {
        sortedByTimeOfDay(schedules.filter { $0.occurs(on: day) }) { item in
            item.isAllDay ? nil : cal.component(.hour, from: item.date) * 60
                + cal.component(.minute, from: item.date)
        }
    }

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
                                Text(Loc.fmt("%1$@/%2$@일차", "\(index)", "\(item.spanDays)"))
                                    .font(.caption2)
                                    .foregroundStyle(Ink.text.opacity(0.5))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .overlay(Capsule().stroke(Ink.text.opacity(0.2), lineWidth: 1))
                            }
                            Spacer()
                            if !item.isAllDay {
                                let startText = item.date.formatted(Loc.shortTime)
                                Text(item.endDate.map { "\(startText)~\($0.formatted(Loc.shortTime))" } ?? startText)
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
                    .simultaneousGesture(quickDeleteGesture(.schedule(item), into: $pendingDelete, feedback: $confirmFeedback))
                    .accessibilityHint("탭하면 수정, 길게 누르면 삭제할 수 있어요")
                    .accessibilityAction(named: Loc.str("삭제")) { pendingDelete = .schedule(item) }
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
        sortedByTimeOfDay(inputRowsUnsorted) { $0.item.timeMinutes }
    }

    private var inputRowsUnsorted: [InputRow] {
        inputs.compactMap { item in
            switch item.schedule {
            case .once:
                // 적어 넣은 그날에만(2026-08-20 개정 — Output과 통일, 종전 「완료 전까지
                // 모든 날 대기」 폐기). 완료된 날엔 기록으로 남는다
                if isCompleted(item.id) { return InputRow(item: item, projected: false) }
                if item.onceShows(on: day) {
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
                VStack(alignment: .leading, spacing: 4) {
                    inputCheckRow(row)
                    // 진행 방식이 붙은 Input만(2026-08-12) — 미래는 조작 금지(원칙 4).
                    // 타이머·스톱워치는 오늘만(2026-08-20 사용자 결정 — 잠금화면 인텐트가 날짜를
                    // 오늘로 고정해 과거 날짜 타이머는 버튼 무반응·오늘 레코드 오염. 지난날
                    // 실시간 측정은 의미도 없어 시작 자체를 막는다)
                    if let goal = row.item.progressGoal, !isFuture,
                       cal.isDateInToday(day) || (goal.kind != .timer && goal.kind != .stopwatch) {
                        InputProgressControl(
                            goal: goal,
                            itemID: row.item.id,
                            itemTitle: row.item.title,
                            subtasks: row.item.subtasks ?? [],
                            progress: progressRecord(row.item.id),
                            ensureProgress: { ensureProgress(row.item.id) },
                            onChange: { fulfilled in syncAutoCompletion(row.item, fulfilled: fulfilled) }
                        )
                        .padding(.leading, 26)   // 체크 아이콘 폭만큼 들여쓰기
                    }
                }
            }
        }
    }

    /// 그날의 진행 레코드 — 없으면 nil(안 만진 날은 레코드도 없다)
    private func progressRecord(_ itemID: UUID) -> InputProgress? {
        inputProgresses.first { $0.itemID == itemID && cal.isDate($0.occurredOn, inSameDayAs: day) }
    }

    private func ensureProgress(_ itemID: UUID) -> InputProgress {
        if let existing = progressRecord(itemID) { return existing }
        let created = InputProgress(itemID: itemID, occurredOn: day)
        modelContext.insert(created)
        return created
    }

    /// 목표 도달 = 그날 체크(2026-08-12 사용자 결정). 되돌리면 체크도 풀린다 —
    /// 진행 방식이 붙은 Input은 체크가 진행도에서 파생된다(§5.5.2 "진행도 갱신이 곧 기록"과 같은 정신).
    /// 스톱워치·목표 없음은 판정이 항상 false라 손 체크를 지우지 않도록 여기서 걸러낸다.
    private func syncAutoCompletion(_ item: InputItem, fulfilled: Bool) {
        guard item.progressKind != .stopwatch else { return }
        let checked = isCompleted(item.id)
        guard fulfilled != checked else { return }
        confirmFeedback += 1
        toggleCompletion(item.id)
    }

    private func inputCheckRow(_ row: InputRow) -> some View {
        let checked = isCompleted(row.item.id)
        return Group {
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
                        if let t = row.item.timeMinutes {   // 파서 시각 — trailing 문법(2026-08-09)
                            Text(timeOfDayLabel(t))
                                .font(.caption)
                                .foregroundStyle(Ink.text.opacity(0.5))
                        }
                    }
                    .font(.subheadline)
                }
                .disabled(isFuture)   // 미래 완료 금지(원칙 4)
                .simultaneousGesture(quickDeleteGesture(.input(row.item), into: $pendingDelete, feedback: $confirmFeedback))
                .accessibilityValue(checked ? Loc.str("완료") : Loc.str("미완료"))
                .accessibilityAction(named: Loc.str("삭제")) { pendingDelete = .input(row.item) }
        }
    }

    // ③ Output — 완료된 아이템의 미래 occurrence 미표시(§5.5.2)
    private struct OutputRow: Identifiable {
        let item: OutputItem
        let projected: Bool
        var id: UUID { item.id }
    }

    private var outputRows: [OutputRow] {
        sortedByTimeOfDay(outputRowsUnsorted) { $0.item.timeMinutes }
    }

    private var outputRowsUnsorted: [OutputRow] {
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
        return hasColdBlocked ? Loc.str("생리를 기록하면 계획이 보이기 시작해요.") : Loc.str("아직 없어요")
    }

    private var outputCard: some View {
        cardShell(.output, empty: outputRows.isEmpty, emptyMessage: outputEmptyMessage) {
            ForEach(outputRows) { row in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(row.item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Ink.text.opacity(row.projected ? 0.55 : 1.0))
                        if let target = row.item.targetDate {
                            DDayBadge(target: target, from: day)
                        }
                        if row.projected {
                            Text("예상").font(.caption2).foregroundStyle(Ink.text.opacity(0.45))
                        }
                        if row.item.isComplete {
                            Text("완료").font(.caption2.weight(.semibold)).foregroundStyle(Ink.text.opacity(0.6))
                        }
                        Spacer()
                        if let t = row.item.timeMinutes {   // 파서 시각 — trailing 문법(2026-08-09)
                            Text(timeOfDayLabel(t))
                                .font(.caption)
                                .foregroundStyle(Ink.text.opacity(0.5))
                        }
                    }
                    // 미래는 조작 금지(원칙 4 — Input 체크·진행과 동일 가드, 2026-08-20 감사:
                    // 미래 날짜에서 퍼센트·체크리스트를 만지면 아이템 누적에 즉시 반영되던 구멍)
                    if !isFuture {
                        progressControl(row.item)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .simultaneousGesture(quickDeleteGesture(.output(row.item), into: $pendingDelete, feedback: $confirmFeedback))
                .accessibilityAction(named: Loc.str("삭제")) { pendingDelete = .output(row.item) }
            }
        }
    }

    @ViewBuilder
    private func progressControl(_ item: OutputItem) -> some View {
        switch item.progressKind {
        case .checkOnly:
            // 체크만(2026-08-18) — 저장은 percent 0↔1. 완료는 종전대로 파생(isComplete).
            Button {
                item.percent = item.percent >= 1 ? 0 : 1
                if item.percent >= 1 { confirmFeedback += 1 } else { lightFeedback += 1 }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: item.percent >= 1 ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.percent >= 1 ? Ink.text : Ink.text.opacity(0.35))
                    Text(item.percent >= 1 ? Loc.str("완료") : Loc.str("체크"))
                        .font(.footnote)
                        .foregroundStyle(Ink.text.opacity(item.percent >= 1 ? 1 : 0.6))
                    Spacer()
                }
            }
            .accessibilityValue(item.percent >= 1 ? Loc.str("완료") : Loc.str("미완료"))
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
                .accessibilityValue(sub.isDone ? Loc.str("완료") : Loc.str("미완료"))
            }
        case .sessions:
            SessionProgressControl(logged: item.loggedSessions,
                                   target: item.targetSessions) { next, completed in
                item.loggedSessions = next
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
        case .timer, .stopwatch:
            TimerProgressControl(backing: item, activityID: item.id, activityTitle: item.title,
                                 isTimer: item.progressKind == .timer,
                                 targetSeconds: item.targetSeconds ?? 0,
                                 isInput: false) { completed in
                if completed { confirmFeedback += 1 } else { lightFeedback += 1 }
            }
        }
    }
}
