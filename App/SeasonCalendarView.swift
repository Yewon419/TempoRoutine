// 템포루틴 — 계절 캘린더 (Phase 0 ③, MASTER §5.9-3 / §8.2.3 / §4 보강 I 책력 조판)
// 계절 = 숫자 잉크색(글리프 정식 이식은 §5.9-8 미학 패스), 오늘 = 은필 채운 원,
// 생리 = 코랄 형광펜(기록) / 회색 형광펜(예상, 미래만 — 과거 소급 투영 금지 §5.6.2).
// 생리 기록은 조회 전용(2026-07-20 사용자 결정 — 드래그·길게 누르기 편집 폐기, MASTER I-2b 개정 대기).
// 기록 편집 = 상단 "생리 기록" 버튼 → PeriodTrackerSheet(건강 앱 문법) + 하루 상세 토글(접근성 유지).
// 탭 = 하루 상세 push / 길게 누르기 = 빠른 일정 추가(2026-07-25 사용자 지시 — 일정 한정, 생리 기록과 무관).

import SwiftUI
import SwiftData
import TempoCore
import UIKit

struct SeasonCalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSize   // 아이패드 분할 뷰(2026-07-23)
    @Query(sort: \PeriodDay.day) private var periodDays: [PeriodDay]
    @Query(sort: \ScheduleItem.date) private var schedules: [ScheduleItem]
    @Query(sort: \InputItem.createdAt) private var inputs: [InputItem]
    @Query(sort: \OutputItem.createdAt) private var outputs: [OutputItem]
    @Query private var checkIns: [DailyCheckIn]   // 씨앗 스티커 근거(2026-08-09)

    @State private var monthAnchor = Calendar.current.startOfDay(for: .now)
    @State private var showLogSheet = false
    @State private var pushedDay: Date?
    @State private var selectedDay: Date?       // regular 분할 뷰의 우측 하루 상세 선택(2026-07-23)
    @State private var quickAddDay: Date?       // 길게 누른 날짜 → 빠른 일정 시트(2026-07-25)
    @State private var quickAddEnd: Date?       // 드래그 기간 선택의 끝 날짜 — nil = 하루(2026-07-27)
    @State private var dragStart: Date?         // 드래그 중 선택 앵커(누른 셀)
    @State private var dragEnd: Date?           // 드래그 중 현재 셀
    @State private var gridSize: CGSize = .zero // 드래그 좌표 → 셀 역산용
    @State private var dragX: CGFloat = 0       // 월 캐러셀 손가락 추종 오프셋(2026-07-27 사용자 지시)
    @State private var monthDragEngaged = false // 수평 의도 확정 후에만 추종
    @State private var monthAnimating = false   // 정착/스냅백 애니메이션 중(옆 달 유지용)
    // 드래그 프레임마다 body가 재평가된다 — 월 렌더 데이터(마크·띠·스타일·형광펜)는 여기 캐시로만
    // 읽는다. 드래그 시작 때 3개 달을 한 번 계산하고, 전환이 끝나면 비운다(성능 결함 수정 2026-07-27).
    @State private var renderCache: [Date: MonthRender] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme   // 상단 계절광 다크 감쇠
    @State private var pressFeedback = 0        // 길게 누르기 진입 햅틱(중간 — 탭보다 강하게)
    @State private var lightFeedback = 0        // 작은 햅틱(§4 — 월 이동·날짜 셀 탭. 셀 탭은 .selection→작은 승격, 2026-07-23 체감 피드백)
    // 체크인 완료일(2026-08-09) — 과거 완료일 숫자 흐림 표시의 근거 집합
    @State private var completedDays: Set<Date> = []

    // v16 확정: 개방형·풀하이트 — 그리드가 남은 세로를 균등 분할(grid-auto-rows: 1fr).
    // 고정 셀 높이 폐기, 최소 높이만 보장(일정 글줄 노출 여지 — 프로토 min-height 54px).
    private let minCellHeight: CGFloat = 54
    // 여러 날 띠 — 계절 밑줄(~29.5)과 3.5pt 간격을 두고(2026-07-28 시안 결정), 레인 간격 포함 13pt씩
    private let bandHeight: CGFloat = 11
    private let bandTop: CGFloat = 33.5
    private let bandGap: CGFloat = 3.5   // 숫자 영역(30)과 띠·박스·글줄 사이 간격
    private var bandSlot: CGFloat { bandHeight + 2 }
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
    // CycleParams 경유(개정 M) — 직접 CyclePredictor를 부르면 prior·M 반영이 스냅샷과 갈라진다
    private var avgLength: Int { CycleParams.averageLength(starts: starts) }
    private var menstrualLength: Int { CycleParams.menstrualLength(days: periodDays.map(\.day)) }

    /// §5.6.2 투영 지평 — low=1 / medium=2 / high=3 주기까지만 예측 렌더.
    private var horizonCycles: Int {
        switch CyclePredictor.confidence(periodStarts: starts) {
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }

    // ── 월 그리드 파라미터 — 캐러셀이 이전/현재/다음 달을 함께 그려서 파라미터화(2026-07-27) ──
    private struct MonthLayout {
        let start: Date
        let daysInMonth: Int
        let leadingBlanks: Int
        let rowCount: Int
        private let calendar: Calendar

        init(anchor: Date, calendar: Calendar) {
            self.calendar = calendar
            self.start = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)) ?? anchor
            self.daysInMonth = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
            self.leadingBlanks = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
            self.rowCount = (leadingBlanks + daysInMonth + 6) / 7
        }

        func date(at index: Int) -> Date? {
            let dayNumber = index - leadingBlanks + 1
            guard dayNumber >= 1 && dayNumber <= daysInMonth else { return nil }
            return calendar.date(byAdding: .day, value: dayNumber - 1, to: start)
                .map { calendar.startOfDay(for: $0) }
        }
    }

    private func layout(offsetMonths: Int) -> MonthLayout {
        let base = cal.date(byAdding: .month, value: offsetMonths, to: monthAnchor) ?? monthAnchor
        return MonthLayout(anchor: base, calendar: cal)
    }
    private var currentLayout: MonthLayout { layout(offsetMonths: 0) }
    private var monthStart: Date { currentLayout.start }

    var body: some View {
        // 바깥 ZStack = 빠른 일정 바의 그릇. 본문에만 키보드 무시를 걸어야
        // 캘린더는 제자리에 있고 바만 키보드를 따라 올라온다 — 순서를 뒤집으면 바가 키보드에 가린다.
        ZStack(alignment: .bottom) {
            calendarBody
                .ignoresSafeArea(.keyboard, edges: .bottom)
            quickAddLayer
        }
        .animation(.easeOut(duration: 0.22), value: quickAddDay)
        .sheet(isPresented: $showLogSheet) {
            PeriodTrackerSheet()
        }
        .coachOverlay(id: .calendar, steps: CoachSteps.calendar)   // 기능 튜토리얼(2026-07-23)
        .sensoryFeedback(.impact(weight: .light), trigger: lightFeedback)
        .sensoryFeedback(.impact(weight: .medium), trigger: pressFeedback)
        .navigationDestination(isPresented: Binding(
            get: { pushedDay != nil },
            set: { if !$0 { pushedDay = nil } }
        )) {
            if let pushedDay {
                DayDetailView(day: pushedDay)
            }
        }
        // 체크인 완료일(2026-08-09) — 집합은 상태로 들고 셀은 조회만(드래그 프레임 경로 규칙).
        // ⚠ 씨앗 스티커는 같은 날 베타 피드백("스티커같지 않다")으로 폐기 — 과거 완료일 숫자
        // 흐림으로 대체. 등장 연출·하단 토글도 함께 걷음.
        .task(id: seedStamp) { completedDays = Seeds.completedDays(checkIns) }
    }

    /// 도장 유무·개수만 요약한 스탬프 — body 평가당 O(n) 1회로 재계산 트리거를 만든다
    /// (@Query 배열은 Equatable이 아니라 onChange 불가, 셀마다 파생 계산은 드래그 규칙 위반).
    private var seedStamp: Int {
        checkIns.count &* 1000 &+ checkIns.filter { $0.completedAt != nil }.count
    }

    /// 캘린더 본문 — 지면·계절광·(아이패드)분할. body에서 떼어내 타입체크 부담을 줄인다.
    private var calendarBody: some View {
        ZStack {
            // 캘린더 자체 지면(2026-07-28 시안 결정) — frost 바탕 + 계절광은 상단에만 걸리고
            // 사그라든다(그리드 영역은 깨끗하게 — 글로우 밑줄 가독 담보)
            Ink.frost.ignoresSafeArea()
            if ThemeStore.current == .modern {
                DotGrid().ignoresSafeArea()   // 모던 전용 질감(시안 §1.3-1)
            }
            calendarTopGlow
            if hSize == .regular {
                // 아이패드: 캘린더 + 하루 상세 분할(2026-07-23). 우측 계절광은 선택일 단계를 따름.
                HStack(alignment: .top, spacing: 0) {
                    calendarColumn()
                        .frame(maxWidth: 560)
                    Divider().overlay(Ink.text.opacity(0.12))
                    DayDetailView(day: selectedDay ?? today)
                        .id(selectedDay ?? today)
                        .frame(maxWidth: .infinity)
                }
            } else {
                calendarColumn()
            }
        }
    }

    /// 빠른 일정 = 시트가 아니라 키보드 위에 붙는 바(2026-08-01 사용자 지시) — 뒤 캘린더가 그대로 보인다.
    @ViewBuilder
    private var quickAddLayer: some View {
        if quickAddDay != nil {
            // 바깥 탭 = 닫기. 옅은 dim으로 입력 중임을 알리되 뒤 화면은 계속 읽힌다.
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture { closeQuickAdd() }
                .transition(.opacity)
        }
        if let quickAddDay {
            QuickScheduleBar(day: quickAddDay, endDay: quickAddEnd, onClose: closeQuickAdd)
                .transition(.move(edge: .bottom))
        }
    }

    /// 빠른 일정 바 걷기 — 저장 후·바깥 탭 공용(2026-08-01)
    private func closeQuickAdd() {
        quickAddDay = nil
        quickAddEnd = nil
    }

    /// 오늘의 단계 — 상단 글로우 색 결정용(seasonLine과 같은 계산 경로)
    private var todayPhase: CyclePhase? {
        guard let r = CyclePredictor.cycleDay(of: today, periodStarts: starts, averageLength: avgLength) else {
            return nil
        }
        return CyclePredictor.phaseForDay(r.day, cycleLength: avgLength, menstrualLength: menstrualLength)
    }

    /// 상단 계절광(2026-07-28 시안 결정) — SeasonLight 원색 2겹을 상단 앵커로만, 다크는 감쇠
    private var calendarTopGlow: some View {
        let l = SeasonLight.lightColors(for: todayPhase)
        let top = RadialGradient(colors: [l.a, .clear],
                                 center: UnitPoint(x: 0.18, y: -0.10),
                                 startRadius: 0, endRadius: 430)
        let side = RadialGradient(colors: [l.b, .clear],
                                  center: UnitPoint(x: 0.88, y: -0.06),
                                  startRadius: 0, endRadius: 320)
        return ZStack {
            Rectangle().fill(top)
            Rectangle().fill(side)
        }
        // 모던은 항상 다크 단일 외관 — 시스템 다크 감쇠 미적용(시안 --light-dim 1)
        .opacity(ThemeStore.current == .modern ? 1.0 : (colorScheme == .dark ? 0.35 : 1.0))
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 캘린더 열 — compact에선 전체 화면, regular에선 분할 좌측(2026-07-23)
    private func calendarColumn() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 상단 순서(시안 §1.3-6, 모던 전용 분기 — 2026-07-29 사용자 결정):
            // 모던 = 계절 라인·기록 버튼이 상단 제자리, 거대 표제는 그 아래
            if ThemeStore.current == .modern {
                seasonHeaderRow
                monthHeader
            } else {
                monthHeader
                seasonHeaderRow
            }
            weekdayRow
            // 월 표면이 손가락을 따라 움직인다(2026-07-27 사용자 지시 — 인식 후 전환에서 추종으로).
            // 이전/현재/다음 달을 나란히 렌더하고 오프셋으로 민다 — 놓으면 임계 판정 후 정착.
            monthCarousel
                .coachAnchor(.calendarGrid)
            legend
            Spacer(minLength: 0)
        }
        .padding(20)
        // 가로 드래그 = 월 이동(손가락 추종). 셀 기간 선택과의 분리는 종전과 동일 —
        // 롱프레스는 정지 0.4s 인식이라 먼저 움직이면 이 드래그가 이긴다. 선택 중엔 개입 안 함.
        .gesture(monthDragGesture)
    }

    /// 계절 라인 + 생리 기록 버튼 — 상단 순서 분기용 추출(2026-07-29, 내용 무변화)
    private var seasonHeaderRow: some View {
        HStack(alignment: .firstTextBaseline) {
            // 번들 서체 명시(2026-08-09 베타 피드백 "봄 10일차 저거도" — New York은 한글 글리프가
            // 없어 고딕 폴백되던 것, 08-01 계절 라벨 2건과 같은 뿌리)
            Text(seasonLine)
                .font(.almanacBody(.subheadline, size: 15))
                .foregroundStyle(Ink.text.opacity(0.65))
            Spacer()
            // 기록 편집 진입 — 캘린더 탭 자체는 조회 전용
            Button {
                showLogSheet = true
            } label: {
                HStack(spacing: 5) {
                    Circle().fill(Ink.record).frame(width: 7, height: 7)
                    Text("생리 기록")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ink.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(Capsule().stroke(Ink.text.opacity(0.3), lineWidth: 1))
            }
            .coachAnchor(.calendarLog)   // 기능 튜토리얼(2026-07-23)
        }
    }

    /// 옆 달은 드래그·전환 중에만 실렌더 — 유휴 렌더 비용을 종전(1개 달)으로 유지
    private var sidesVisible: Bool { monthDragEngaged || monthAnimating || dragX != 0 }

    private var monthCarousel: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            HStack(spacing: 0) {
                sidePanel(-1, width: w)
                monthGrid(offsetMonths: 0, width: w)
                sidePanel(1, width: w)
            }
            .offset(x: -w + dragX)
        }
        .clipped()
    }

    @ViewBuilder
    private func sidePanel(_ offsetMonths: Int, width: CGFloat) -> some View {
        if sidesVisible {
            monthGrid(offsetMonths: offsetMonths, width: width)
        } else {
            Color.clear.frame(width: width)
        }
    }

    private func monthGrid(offsetMonths: Int, width: CGFloat) -> some View {
        grid(layout: layout(offsetMonths: offsetMonths), interactive: offsetMonths == 0)
            .frame(width: width)
    }

    private func warmMonthCache() {
        var cache: [Date: MonthRender] = [:]
        for offset in -1...1 {
            let l = layout(offsetMonths: offset)
            cache[l.start] = computeRender(l)
        }
        renderCache = cache
    }

    private func endMonthTransition() {
        monthAnimating = false
        renderCache = [:]   // 전환 종료 — 다음 렌더는 신선 계산(데이터 변경 반영)
    }

    private var monthDragGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                guard dragStart == nil else { return }   // 기간 선택 중엔 월 이동 금지
                let t = value.translation
                if !monthDragEngaged {
                    guard abs(t.width) > abs(t.height) else { return }   // 수평 의도만 개입
                    warmMonthCache()   // 프레임마다 3개 달 재계산 방지 — 시작 때 한 번
                    monthDragEngaged = true
                }
                dragX = t.width
            }
            .onEnded { value in
                defer { monthDragEngaged = false }
                guard monthDragEngaged else { return }
                settleMonthDrag(translation: value.translation.width,
                                predicted: value.predictedEndTranslation.width)
            }
    }

    /// 놓는 순간 정착 — 플릭(예측 이동)도 인정. 폭 25% 넘으면 넘기고, 아니면 되돌린다.
    private func settleMonthDrag(translation: CGFloat, predicted: CGFloat) {
        let width = max(gridSize.width, 1)
        let effective = abs(predicted) > abs(translation) ? predicted : translation
        let delta: Int = effective < -width * 0.25 ? 1 : (effective > width * 0.25 ? -1 : 0)
        guard delta != 0, let next = cal.date(byAdding: .month, value: delta, to: monthStart) else {
            monthAnimating = true
            withAnimation(.snappy(duration: 0.25), completionCriteria: .logicallyComplete) {
                dragX = 0
            } completion: {
                endMonthTransition()
            }
            return
        }
        lightFeedback += 1
        if reduceMotion {
            monthAnchor = next
            dragX = 0
            endMonthTransition()
            return
        }
        monthAnimating = true
        withAnimation(.snappy(duration: 0.28), completionCriteria: .logicallyComplete) {
            dragX = delta > 0 ? -width : width
        } completion: {
            // 끝난 프레임에 달을 갈아끼우고 오프셋을 0으로 — 같은 그림이라 눈에는 이어진다
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                monthAnchor = next
                dragX = 0
            }
            endMonthTransition()
        }
    }

    /// 이 달의 잉크 글줄(§5.9-4: resolve가 캘린더에 뜨는지) — 일정 + cycle-anchored occurrence.
    /// 매일 Input은 셀에 그리지 않음(전 셀 노이즈). projected는 faded.
    private func monthMarks(_ layout: MonthLayout) -> [Date: [(title: String, projected: Bool, isSchedule: Bool)]] {
        var marks: [Date: [(title: String, projected: Bool, isSchedule: Bool)]] = [:]
        let snap = CycleSnapshot(periodDays: periodDays)
        for dayNumber in 1...layout.daysInMonth {
            guard let d = cal.date(byAdding: .day, value: dayNumber - 1, to: layout.start) else { continue }
            let day = cal.startOfDay(for: d)
            for s in schedules where s.occurs(on: day) {
                if s.isMultiDay { continue }   // 여러 날 일정은 잉크 글줄 대신 띠로(§8.2.3)
                marks[day, default: []].append((s.title, false, true))   // 일정 = 박스 문법(2026-07-28)
            }
        }
        guard let monthEnd = cal.date(byAdding: .day, value: layout.daysInMonth, to: layout.start) else { return marks }
        for item in inputs {
            if case .cycleAnchored(let r) = item.schedule {
                for occ in snap.occurrences(of: r, createdAt: cal.startOfDay(for: item.createdAt))
                where occ.date >= layout.start && occ.date < monthEnd {
                    marks[cal.startOfDay(for: occ.date), default: []].append((item.title, occ.projected, false))
                }
            }
        }
        for item in outputs {
            guard case .cycleAnchored(let r) = item.schedule else { continue }   // 매일 Input과 동일 — 노이즈 방지
            for occ in snap.occurrences(of: r, createdAt: cal.startOfDay(for: item.createdAt))
            where occ.date >= layout.start && occ.date < monthEnd {
                if item.isComplete && occ.projected { continue }   // §5.5.2 완료된 Output 미래 미표시
                marks[cal.startOfDay(for: occ.date), default: []].append((item.title, occ.projected, false))
            }
        }
        return marks
    }

    // ── 표제 (책력 조판: 거대 월 + 연도, 월 이동) ──
    private var monthHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // 모던 = 아웃라인 표제(시안 §1.3-2), 그 외 = 종전 솔리드(v6 확정 58px)
            almanacDisplay("\(cal.component(.month, from: monthStart))월", size: 58, color: Ink.text)
            Text(String(cal.component(.year, from: monthStart)))
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.5))
            Spacer()
            Button {
                lightFeedback += 1
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            Button {
                lightFeedback += 1
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(Ink.text)
    }

    /// 버튼도 같은 캐러셀 슬라이드(HIG Familiarity). Reduce Motion·폭 미확정이면 즉시 전환.
    private func shiftMonth(_ delta: Int) {
        guard dragX == 0, !monthAnimating else { return }   // 전환 중 중복 입력 무시
        guard let next = cal.date(byAdding: .month, value: delta, to: monthStart) else { return }
        let width = gridSize.width
        if reduceMotion || width <= 0 {
            monthAnchor = next
            return
        }
        warmMonthCache()
        monthAnimating = true
        withAnimation(.snappy(duration: 0.32), completionCriteria: .logicallyComplete) {
            dragX = delta > 0 ? -width : width
        } completion: {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                monthAnchor = next
                dragX = 0
            }
            endMonthTransition()
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortWeekdaySymbols
        let shift = cal.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// 숫자 잉크색(2026-07-28 2차 개정) — 계절은 글씨에서 배경 글로우로 이동. 숫자는 먹색,
    /// 주말·공휴일만 관례색(일·공휴일=빨강, 토=파랑) 유지.
    private func numberColor(date: Date, seasonColor: Color, render: MonthRender, isToday: Bool) -> Color {
        if isToday { return Ink.paper }
        if render.holidays[date]?.isPublic == true { return Ink.holiday }
        switch cal.component(.weekday, from: date) {
        case 1: return Ink.holiday
        case 7: return Ink.saturday
        default: return Ink.text
        }
    }

    /// 계절 = 날짜 뒤 이어지는 빛 띠(2026-07-28 2차 — 같은 계절 연속 구간 연결, 사용자 지시).
    /// 형광펜 밴드와 같은 문법: 구간 양 끝만 둥글게, 행 경계는 각지게. 세로는 위아래로 사그라드는
    /// 그래디언트(빛의 질감). 예상 구간은 절반 감쇠. 색은 glow 팔레트(채도·명도 상향판).
    private func seasonBand(date: Date, index: Int, meta: SeasonMeta, projected: Bool,
                            render: MonthRender) -> some View {
        let name = meta.name
        let prev = cal.date(byAdding: .day, value: -1, to: date)
            .map { render.style[$0]?.meta?.name == name } ?? false
        let next = cal.date(byAdding: .day, value: 1, to: date)
            .map { render.style[$0]?.meta?.name == name } ?? false
        let col = index % 7
        let roundLeft = !prev || col == 0
        let roundRight = !next || col == 6
        // 밑줄형 — 직각 사각(2026-07-28 5차: 라운드 제거, 사용자 지시). 숫자 영역(상단 3+27pt)
        // 바로 밑 y 25.5~29.5. 일정 띠·박스는 3.5pt 간격을 두고 33.5부터(시안 결정).
        return Rectangle()
            .fill(meta.glow.opacity(projected ? 0.25 : 0.5))
            .frame(height: 4)
            .padding(.leading, roundLeft ? 3 : 0)
            .padding(.trailing, roundRight ? 3 : 0)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 25.5)
            .allowsHitTesting(false)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, s in
                let weekday = (cal.firstWeekday - 1 + index) % 7 + 1
                Text(s)
                    .font(.system(size: 11))
                    .foregroundStyle(weekday == 1 ? Ink.holiday
                                     : weekday == 7 ? Ink.saturday : Ink.accent)   // 구조색(기본=winter 동값)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 4)
        .almanacRule(opacity: 0.28)   // 은필 괘선
    }

    // ── 월 렌더 데이터 — 셀이 프레임마다 재계산하던 것 전부(스타일·형광펜·마크·띠) ──
    private struct MonthRender {
        let marks: [Date: [(title: String, projected: Bool, isSchedule: Bool)]]
        let bands: BandLayout
        let style: [Date: (color: Color, meta: SeasonMeta?, projected: Bool)]
        let recorded: Set<Date>
        let predicted: Set<Date>   // a11y용(시각 표시는 겨울 글로우가 대체 — 2026-07-28 사용자 결정)
        let periodShown: Set<Date> // 코랄 형광펜 표시일 = 기록 && 겨울 띠와 안 겹침(±1일 여유 포함)
        let holidays: [Date: KoreanHoliday]   // 셀 표기용 대표 1건(공휴일 우선, 2026-07-28)
    }

    private func computeRender(_ layout: MonthLayout) -> MonthRender {
        let recordedAll = recordedDays
        var recorded = Set<Date>()
        var predicted = Set<Date>()
        var periodShown = Set<Date>()
        var style: [Date: (color: Color, meta: SeasonMeta?, projected: Bool)] = [:]
        var holidays: [Date: KoreanHoliday] = [:]
        // 소스 우선순위(2026-07-28 사용자 지시): 애플 기본 캘린더의 공휴일 구독 캘린더(연동 시)
        // → 내장 테이블 폴백(미연동·구독 꺼짐). 임시공휴일 등은 애플 캘린더만 안다.
        let ekHolidays: [Date: [String]]?
        if let monthEnd = cal.date(byAdding: .day, value: layout.daysInMonth, to: layout.start) {
            ekHolidays = EventOverlay.shared.holidayNames(from: layout.start, to: monthEnd)
        } else {
            ekHolidays = nil
        }
        for offset in -1...layout.daysInMonth {
            guard let d = cal.date(byAdding: .day, value: offset, to: layout.start) else { continue }
            let day = cal.startOfDay(for: d)
            if recordedAll.contains(day) {
                recorded.insert(day)
                // 겨울 글로우와 겹치는 기록은 표시 생략(중복 — 2026-07-28 사용자 결정).
                // 모델과 어긋난 기록(월경기 밖·S0)만 코랄로 남아 "실측이 다르다"는 신호가 된다.
                if cellStyle(for: day).meta?.name != "겨울" {
                    periodShown.insert(day)
                }
            } else if isPredictedPeriod(day) {
                predicted.insert(day)
            }
            if offset >= 0 && offset < layout.daysInMonth {
                style[day] = cellStyle(for: day)
                if let ekHolidays {
                    if let name = ekHolidays[day]?.first {
                        holidays[day] = KoreanHoliday(name: name,
                                                      isPublic: !KoreanHolidays.isCommemorationName(name))
                    }
                } else {
                    holidays[day] = KoreanHolidays.holidays(on: day, calendar: cal).first
                }
            }
        }
        return MonthRender(marks: monthMarks(layout), bands: bandLayout(layout),
                           style: style, recorded: recorded, predicted: predicted,
                           periodShown: periodShown, holidays: holidays)
    }

    // ── 그리드 (캐러셀 한 패널 — interactive = 중앙 달만 제스처·접근성) ──
    private func grid(layout: MonthLayout, interactive: Bool) -> some View {
        let render = renderCache[layout.start] ?? computeRender(layout)
        return VStack(spacing: 4) {
            ForEach(0..<layout.rowCount, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        cell(layout: layout, index: row * 7 + col, render: render,
                             interactive: interactive)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(minHeight: minCellHeight, maxHeight: .infinity)   // 풀하이트 균등 분할
                .overlay(alignment: .topLeading) { bandRow(row: row, bars: render.bands.bars) }
            }
        }
        .frame(maxHeight: .infinity)
        .coordinateSpace(name: interactive ? "calGrid" : "calGridSide")   // 기간 선택 좌표계(중앙만)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            if interactive { gridSize = size }
        }
        .accessibilityHidden(!interactive)   // VoiceOver가 양옆 달을 순회하지 않게
    }

    // ── 길게 누른 채 드래그 = 기간 선택 (2026-07-27 사용자 지시) ──
    private var selectionRange: ClosedRange<Date>? {
        guard let s = dragStart, let e = dragEnd else { return nil }
        return min(s, e)...max(s, e)
    }

    private func isSelected(_ date: Date) -> Bool {
        selectionRange?.contains(date) ?? false
    }

    /// 그리드 좌표 → 날짜. 행 스트라이드 = (높이+간격)/행수 — H = n·h + (n-1)·4에서 유도.
    /// 달 밖 빈 칸이면 nil(선택은 마지막 유효 셀에 머문다).
    private func dayAt(_ location: CGPoint) -> Date? {
        let layout = currentLayout
        guard gridSize.width > 0, gridSize.height > 0, layout.rowCount > 0 else { return nil }
        let col = min(6, max(0, Int(location.x / (gridSize.width / 7))))
        let rowStride = (gridSize.height + 4) / CGFloat(layout.rowCount)
        let row = min(layout.rowCount - 1, max(0, Int(location.y / rowStride)))
        return layout.date(at: row * 7 + col)
    }

    /// 길게 누르기(0.4s) → 그대로 끌면 기간 확장 → 놓으면 빠른 일정(하루=단일, 구간=여러 날).
    /// 셀→셀 이동마다 작은 햅틱(§4). 시퀀스라 0.4s 전에 떼면 탭(하루 상세)과 충돌하지 않는다.
    private func pressDrag(from date: Date) -> some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("calGrid")))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if dragStart == nil {
                    pressFeedback += 1
                    dragStart = date
                    dragEnd = date
                }
                if let drag, let hovered = dayAt(drag.location), hovered != dragEnd {
                    lightFeedback += 1
                    dragEnd = hovered
                }
            }
            .onEnded { value in
                defer {
                    dragStart = nil
                    dragEnd = nil
                }
                guard case .second(true, _) = value, let s = dragStart, let e = dragEnd else { return }
                guard s != e else {
                    // 제자리에서 떼면 하루 상세(2026-08-01 반전) — compact = push / regular = 우측 패널 선택
                    if hSize == .regular { selectedDay = s } else { pushedDay = s }
                    return
                }
                // 끌었으면 기간 빠른 일정 — 기간 선택의 진입점은 여전히 길게 누르기다
                quickAddDay = min(s, e)
                quickAddEnd = max(s, e)
            }
    }

    // ── 여러 날 일정 = 이어지는 띠 (2026-07-25 사용자 지시 — 하루짜리는 잉크 글줄 그대로) ──
    // 생리 형광펜은 숫자 뒤를 지나는 별도 레이어라 겹치지 않는다. 레인은 2개까지(셀 2줄 예산).
    private struct BandBar: Identifiable {
        let id: String
        let title: String
        let segment: BandSegment
        let lane: Int
        let isPast: Bool
    }

    private struct BandLayout {
        let bars: [BandBar]
        /// 셀별로 예약할 슬롯 수 = 그 셀을 지나는 띠의 최대 lane+1 — 지나는 "개수"로 예약하면
        /// lane 1 단독 셀(레인 0이 다른 주에서만 점유)에서 띠가 잉크 글줄을 덮는다(2026-07-27 리뷰)
        let countByIndex: [Int: Int]
    }

    private func bandLayout(_ layout: MonthLayout) -> BandLayout {
        let cellCount = layout.rowCount * 7
        let items = schedules.filter(\.isMultiDay).sorted { ($0.date, $0.title) < ($1.date, $1.title) }
        var bars: [BandBar] = []
        var laneCells: [Set<Int>] = [[], []]
        var countByIndex: [Int: Int] = [:]

        for item in items {
            var cells = [Bool](repeating: false, count: cellCount)
            var occupied: Set<Int> = []
            for i in 0..<cellCount {
                guard let d = layout.date(at: i), item.occurs(on: d) else { continue }
                cells[i] = true
                occupied.insert(i)
            }
            guard !occupied.isEmpty,
                  let lane = laneCells.indices.first(where: { laneCells[$0].isDisjoint(with: occupied) })
            else { continue }
            laneCells[lane].formUnion(occupied)
            for i in occupied { countByIndex[i] = max(countByIndex[i] ?? 0, lane + 1) }

            for (n, segment) in ScheduleSpan.bandSegments(cells: cells).enumerated() {
                let adjusted = clampToMonth(segment, item: item, layout: layout)
                let lastDay = layout.date(at: segment.row * 7 + segment.column + segment.length - 1)
                bars.append(BandBar(id: "\(item.id)-\(n)", title: item.title, segment: adjusted,
                                    lane: lane, isPast: (lastDay ?? today) < today))
            }
        }
        return BandLayout(bars: bars, countByIndex: countByIndex)
    }

    /// 달 밖에서 이어지는 쪽은 둥글게 닫지 않는다 — 다음 달로 넘어가는 게 보이도록
    private func clampToMonth(_ segment: BandSegment, item: ScheduleItem, layout: MonthLayout) -> BandSegment {
        let firstIndex = segment.row * 7 + segment.column
        let lastIndex = firstIndex + segment.length - 1
        var isStart = segment.isStart
        var isEnd = segment.isEnd
        if isStart, firstIndex == layout.leadingBlanks,
           let before = cal.date(byAdding: .day, value: -1, to: layout.start), item.occurs(on: before) {
            isStart = false
        }
        if isEnd, lastIndex == layout.leadingBlanks + layout.daysInMonth - 1,
           let after = cal.date(byAdding: .day, value: layout.daysInMonth, to: layout.start), item.occurs(on: after) {
            isEnd = false
        }
        return BandSegment(row: segment.row, column: segment.column, length: segment.length,
                           isStart: isStart, isEnd: isEnd)
    }

    private func bandRow(row: Int, bars: [BandBar]) -> some View {
        GeometryReader { proxy in
            let unit: CGFloat = proxy.size.width / 7
            ForEach(bars.filter { $0.segment.row == row }) { bar in
                bandView(bar: bar, unit: unit)
            }
        }
        .allowsHitTesting(false)   // 탭·길게 누르기는 셀이 받는다
    }

    // 타입 체커 과부하를 피해 조각냄(2026-07-25 CI 실측: 한 식에 몰면 unable to type-check)
    private func bandView(bar: BandBar, unit: CGFloat) -> some View {
        let ink: Color = bar.isPast ? Ink.oxide : Ink.text
        let radius: CGFloat = 2   // 직각화(2026-07-28 시안 결정 — 계절 밑줄과 같은 결)
        let width: CGFloat = max(0, unit * CGFloat(bar.segment.length) - 2)
        let x: CGFloat = unit * CGFloat(bar.segment.column) + 1
        let y: CGFloat = bandTop + CGFloat(bar.lane) * bandSlot
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: bar.segment.isStart ? radius : 0,
            bottomLeadingRadius: bar.segment.isStart ? radius : 0,
            bottomTrailingRadius: bar.segment.isEnd ? radius : 0,
            topTrailingRadius: bar.segment.isEnd ? radius : 0
        )
        return shape
            .fill(ink.opacity(0.13))
            .frame(width: width, height: bandHeight)
            .overlay(alignment: .leading) { bandTitle(bar: bar, ink: ink) }
            .offset(x: x, y: y)
    }

    /// 제목은 시작 조각에만 — 잘린 조각은 띠만 이어진다
    @ViewBuilder
    private func bandTitle(bar: BandBar, ink: Color) -> some View {
        if bar.segment.isStart {
            Text(bar.title)
                .font(.system(size: 8.5, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(ink.opacity(0.85))
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private func cell(layout: MonthLayout, index: Int, render: MonthRender,
                      interactive: Bool) -> some View {
        if let date = layout.date(at: index) {
            if interactive {
                cellBody(date: date, index: index, render: render)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        lightFeedback += 1
                        // 2026-08-01 베타 피드백으로 반전: 탭 = 빠른 일정(가장 잦은 동작을 가장 싼 제스처에)
                        quickAddDay = date
                        quickAddEnd = nil
                    }
                    .gesture(pressDrag(from: date))   // 길게 = 하루 상세, 끌면 기간 빠른 일정(2026-08-01)
                    .overlay {
                        // 드래그 기간 선택 명암 — 어디까지 잡혔는지(2026-07-27 사용자 지시)
                        if isSelected(date) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Ink.text.opacity(0.10))
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel(accessibilityText(for: date,
                                                          style: render.style[date] ?? (Ink.text, nil, false),
                                                          recorded: render.recorded.contains(date),
                                                          predicted: render.predicted.contains(date)))
                    .accessibilityAddTraits(.isButton)
                    // 길게 누르기 대체 — 탭이 빠른 일정이 됐으므로 대체 액션은 하루 상세(2026-08-01)
                    .accessibilityAction(named: "하루 상세 보기") {
                        if hSize == .regular { selectedDay = date } else { pushedDay = date }
                    }
            } else {
                cellBody(date: date, index: index, render: render)
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func cellBody(date: Date, index: Int, render: MonthRender) -> some View {
        let style = render.style[date] ?? (Ink.text, nil, false)
            let recorded = render.recorded.contains(date)
            let predicted = render.predicted.contains(date)
            let isToday = date == today
            let bandCount = render.bands.countByIndex[index] ?? 0
            let holiday = render.holidays[date]
            let markBudget = max(0, 2 - bandCount - (holiday == nil ? 0 : 1))
            let cellMarks = render.marks[date] ?? []
            VStack(spacing: 0) {
                Text("\(cal.component(.day, from: date))")
                    .font(numberFont(isToday: isToday))
                    .monospacedDigit()
                    .foregroundStyle(numberColor(date: date, seasonColor: style.color,
                                                 render: render, isToday: isToday))
                    // 과거 완료일 = 숫자 흐림(2026-08-09 베타 피드백 — 씨앗 스티커 대체)
                    .opacity(isCompletedPast(date) ? 0.38 : 1)
                    .frame(width: 27, height: 27)
                    .background {
                        // 오늘 = accent 채운 원(기본=은필 흑청 동값 / 모던=흰색, §8.1·시안 §1.2).
                        // 모던 기록일 = 형광펜 대신 회색 원(시안 §1.3-4). 원에는 지면색 링(3pt)
                        // — 계절 밑줄이 원을 파고들어 보이는 겹침 해소.
                        ZStack {
                            if ThemeStore.current == .modern && (isToday || render.periodShown.contains(date)) {
                                Circle().fill(Ink.frost).frame(width: 33, height: 33)
                            }
                            if isToday {
                                // 기본 = 표제와 같은 먹색(2026-08-09 베타 피드백 "8월 글씨색이랑 같게"
                                // — §8.1 은필 확정을 뒤집는 사용자 결정) / 모던 = accent(흰) 시안 유지
                                Circle().fill(ThemeStore.current == .modern ? Ink.accent : Ink.text)
                            } else if ThemeStore.current == .modern && render.periodShown.contains(date) {
                                Circle().fill(Ink.record.opacity(0.3))
                            }
                        }
                    }
                Color.clear.frame(height: bandGap)   // 계절 밑줄과 간격(2026-07-28 시안 결정)
                if bandCount > 0 {
                    Color.clear.frame(height: CGFloat(bandCount) * bandSlot)   // 여러 날 띠 자리
                }
                // 공휴일·기념일 = 첫 글줄(빨간날 관례, 2026-07-28) — 일정 글줄과 같은 조판
                if let holiday {
                    Text(holiday.name)
                        .font(.system(size: 8.5, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(holiday.isPublic ? Ink.holiday : Ink.text.opacity(0.5))
                }
                // 일정 = 기간 띠와 같은 박스 문법(2026-07-28 시안 결정 — 통일성) /
                // occurrence = 종전 잉크 글줄(먹색 78% / 과거 산화색 75% / 예상 옅게, 프로토 v15·16)
                // 한 칸의 줄 예산은 2 — 띠·공휴일이 차지한 만큼 줄인다
                ForEach(Array(cellMarks.prefix(markBudget).enumerated()), id: \.offset) { _, mark in
                    if mark.isSchedule {
                        scheduleBox(title: mark.title, past: date < today)
                    } else {
                        Text(mark.title)
                            .font(.system(size: 8.5, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(mark.projected ? Ink.text.opacity(0.45)
                                             : (date < today ? Ink.oxide.opacity(0.75) : Ink.text.opacity(0.78)))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 3)
            .padding(.horizontal, 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    // 계절 빛 띠(맨 아래 — 오늘 셀도 이어진다, 은필 원이 위에 얹힘)
                    if let meta = style.meta {
                        seasonBand(date: date, index: index, meta: meta,
                                   projected: style.projected, render: render)
                    }
                    // 모던은 형광펜 밴드 대신 숫자 원이 기록을 담당(시안 §1.3-4)
                    if ThemeStore.current != .modern, render.periodShown.contains(date) {
                        highlightBand(for: date, index: index, recorded: true, render: render)
                            .transaction { $0.animation = nil }   // 형광펜 on/off 즉시 전환
                    }
                }
            }
            .overlay {
                // regular 분할 뷰의 선택일 표시(색만 X — 테두리)
                if hSize == .regular && (selectedDay ?? today) == date {
                    RoundedRectangle(cornerRadius: 10).stroke(Ink.text.opacity(0.28), lineWidth: 1)
                }
            }
    }

    /// 과거 완료일 숫자 흐림(2026-08-09 베타 피드백 — 씨앗 스티커 대체).
    /// 오늘은 제외(은필 원이 담당), 미래는 완료가 성립하지 않는다.
    private func isCompletedPast(_ date: Date) -> Bool {
        date < today && completedDays.contains(date)
    }

    /// 캘린더 숫자 서체 — 모던 = Pretendard 500(오늘 600, 시안 §1.3-3),
    /// 기본 = 표제와 같은 번들 서체(2026-08-09 베타 피드백 "8월 폰트랑 같게" — 시스템 산세리프 폐기)
    private func numberFont(isToday: Bool) -> Font {
        if ThemeStore.current == .modern, ThemeFont.available {
            return .custom(isToday ? "Pretendard-SemiBold" : "Pretendard-Medium", size: 14)
        }
        guard AlmanacFont.available else {
            return .system(size: 14, weight: isToday ? .bold : .semibold, design: .serif)
        }
        return .custom(isToday ? "GowunBatang-Bold" : "GowunBatang-Regular", size: 14)
    }

    /// 하루짜리 일정 = 기간 띠와 같은 박스 문법(2026-07-28 시안 결정 — 통일성). 높이·R2·서체 = 띠 동일
    private func scheduleBox(title: String, past: Bool) -> some View {
        let ink: Color = past ? Ink.oxide : Ink.text
        return RoundedRectangle(cornerRadius: 2)
            .fill(ink.opacity(0.13))
            .frame(height: bandHeight)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                Text(title)
                    .font(.system(size: 8.5, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(ink.opacity(0.85))
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 1)
            .padding(.bottom, 1)
    }

    /// 형광펜 밴드 — 연속 구간은 이어지고 양 끝만 둥글게 (행 경계 포함).
    private func highlightBand(for date: Date, index: Int, recorded: Bool, render: MonthRender) -> some View {
        let prev = cal.date(byAdding: .day, value: -1, to: date)
            .map { sameKind($0, recorded: recorded, render: render) } ?? false
        let next = cal.date(byAdding: .day, value: 1, to: date)
            .map { sameKind($0, recorded: recorded, render: render) } ?? false
        let col = index % 7
        let roundLeft = !prev || col == 0
        let roundRight = !next || col == 6
        return UnevenRoundedRectangle(
            topLeadingRadius: roundLeft ? 9 : 0,
            bottomLeadingRadius: roundLeft ? 9 : 0,
            bottomTrailingRadius: roundRight ? 9 : 0,
            topTrailingRadius: roundRight ? 9 : 0
        )
        .fill(Ink.record.opacity(0.22))   // 기록 = 진한 회색(2026-07-28, 예측 회색은 폐기됨)
        .frame(height: 20)
        .padding(.leading, roundLeft ? 4 : 0)
        .padding(.trailing, roundRight ? 4 : 0)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 6)   // 숫자(상단 27pt 원역) 뒤를 지나는 마커 — 프로토 z-계층과 동일
    }

    private func sameKind(_ date: Date, recorded: Bool, render: MonthRender) -> Bool {
        // 표시되는 형광펜 기준 — 숨겨진 기록일(겨울 겹침)과는 이어 그리지 않는다
        render.periodShown.contains(date)
    }

    // ── 단계 → 렌더 규칙 ──
    private func cellStyle(for date: Date) -> (color: Color, meta: SeasonMeta?, projected: Bool) {
        guard let last = starts.max() else { return (Ink.text, nil, false) }   // S0 = 전부 먹색
        // 투영 지평 밖 미래 = 먹색 (예측 렌더 중단 — h번째 예상 월경 구간 끝까지, off-by-one 정정 2026-07-28)
        if let horizon = CyclePredictor.projectionHorizon(lastStart: last, averageLength: avgLength,
                                                          horizonCycles: horizonCycles,
                                                          menstrualLength: menstrualLength, calendar: cal),
           date > horizon {
            return (Ink.text, nil, false)
        }
        guard let r = CyclePredictor.cycleDay(of: date, periodStarts: starts, averageLength: avgLength) else {
            return (Ink.text, nil, false)
        }
        let meta = seasonMeta(for: CyclePredictor.phaseForDay(r.day, cycleLength: avgLength,
                                                              menstrualLength: menstrualLength))
        return (meta.color.opacity(r.projected ? 0.55 : 1.0), meta, r.projected)   // 미래/역투영 = faded
    }

    /// 회색 형광펜 = 예상 생리일 (I-2b). 미래·투영 구간의 월경기만, 오늘 이전 소급 금지.
    private func isPredictedPeriod(_ date: Date) -> Bool {
        guard date >= today, let last = starts.max() else { return false }
        if let horizon = CyclePredictor.projectionHorizon(lastStart: last, averageLength: avgLength,
                                                          horizonCycles: horizonCycles,
                                                          menstrualLength: menstrualLength, calendar: cal),
           date > horizon {
            return false
        }
        guard let r = CyclePredictor.cycleDay(of: date, periodStarts: starts, averageLength: avgLength),
              r.projected else { return false }
        return CyclePredictor.phaseForDay(r.day, cycleLength: avgLength,
                                          menstrualLength: menstrualLength) == .menstrual
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
        let meta = seasonMeta(for: CyclePredictor.phaseForDay(r.day, cycleLength: avgLength,
                                                              menstrualLength: menstrualLength))
        let hedge = starts.count == 1 ? "아마 " : ""
        let projected = r.projected ? " · 예상" : ""
        return "\(hedge)\(meta.name) \(r.day)일차\(projected)"
    }

    // ── 범례 (색맹 담보: 글리프+계절명 병행 — §8.1 SeasonGlyph) ──
    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(CyclePhase.displayOrder, id: \.self) { legendItem($0) }   // 봄→여름→가을→겨울(2026-07-29 피드백)
            Spacer()
            // 「기록」 스와치 폐기(2026-08-01 베타 피드백) — 상단 「생리 기록」 버튼과 중복 안내였다
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

    private func accessibilityText(for date: Date, style: (color: Color, meta: SeasonMeta?, projected: Bool),
                                   recorded: Bool, predicted: Bool) -> String {
        var parts = [date.formatted(.dateTime.month().day())]
        if let meta = style.meta {
            // 개정 M-1c: 단계명 제거 — VoiceOver는 소리로 읽혀 프라이버시 표면이기도 하다.
            // "예상"은 유지: faded 시각 hedge가 전달되지 않는 채널이라 텍스트가 유일한 hedge(§5.6.2).
            parts.append(style.projected ? "\(meta.name) 예상" : meta.name)
        }
        if recorded { parts.append("생리 기록") }
        if predicted { parts.append("생리 예상") }
        return parts.joined(separator: ", ")
    }

}
