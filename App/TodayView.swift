// 템포루틴 — 오늘 탭 (MASTER §8.2.2, 프로토 v29~v77 확정 문법)
// 위→아래: 컬랩싱 계절 헤더(2-layer crossfade — font-size 보간 금지, DESIGN v44) → 무드라인(플레인 조판)
// → S0/S4 상태 → 일정·Input·Output 3구획 직접 노출(하루 상세와 동일 데이터 — 뷰별 로컬 상태 금지)
// → 데일리 체크인 인라인 카드(§3.4). 문장형 제안 한 줄은 계절별 카피 미확정 — PENDING.

import SwiftUI
import SwiftData
import TempoCore
import UIKit

// ── 디자인 토큰 (ui-mockup DESIGN.md — 계절 잉크·먹색·지면. 정식 미학 패스는 §5.9-8) ──
// 다크 = 기준 대응 팔레트(2026-07-20 사용자 결정: 정식 다크 테마는 추후, 지금은 가독 대응).
// 라이트 = 종이 지면 + 먹색 잉크 / 다크 = 먹지 지면 + 종이색 잉크, 계절 잉크는 명도 보정.
private extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

enum Ink {
    static let winter = Color(light: .rgb(0x55, 0x60, 0x6C), dark: .rgb(0x98, 0xA6, 0xB4))
    static let spring = Color(light: .rgb(0x8F, 0x7C, 0x2E), dark: .rgb(0xC2, 0xAC, 0x52))
    static let summer = Color(light: .rgb(0x6E, 0x7C, 0x46), dark: .rgb(0xA3, 0xB3, 0x78))
    static let autumn = Color(light: .rgb(0xA8, 0x4B, 0x38), dark: .rgb(0xD6, 0x82, 0x6B))
    static let text   = Color(light: .rgb(0x2C, 0x2B, 0x27), dark: .rgb(0xE8, 0xE6, 0xE1))   // 잉크
    static let paper  = Color(light: .rgb(0xF1, 0xEE, 0xE6), dark: .rgb(0x1C, 0x1B, 0x19))   // 지면(2026-07-21 종이톤 재검토)
    static let coral  = Color(light: .rgb(0xD6, 0x64, 0x4C), dark: .rgb(0xE0, 0x7A, 0x63))   // ⚠ 2026-07-28 기록 표기서 은퇴 — record로 대체
    /// 생리 기록 표기(2026-07-28 사용자 결정: 붉은색 → 겨울 톤과 통일된 진한 회색)
    static let record = Color(light: .rgb(0x5B, 0x62, 0x6B), dark: .rgb(0xA9, 0xB0, 0xB8))
    /// 파괴적 액션 전용 (--danger) — 기록 코랄·가을 잉크와 역할 분리
    static let danger = Color(light: .rgb(0xB2, 0x3A, 0x30), dark: .rgb(0xD0, 0x68, 0x5E))
    /// 완료 상태 = 짙은 회색(--ink-dim). 산화 갈색은 캘린더 타임라인 전용(v29 정정)
    static let dim = Color(light: Color(red: 44 / 255, green: 43 / 255, blue: 39 / 255).opacity(0.55),
                           dark: Color(red: 232 / 255, green: 230 / 255, blue: 225 / 255).opacity(0.5))
    /// 산화 은필 — 캘린더 과거 일정 글줄 전용
    static let oxide = Color(light: .rgb(0x8B, 0x6F, 0x55), dark: .rgb(0xB2, 0x94, 0x77))
    /// 공휴일 빨간날 표기 전용(2026-07-28) — 기록 코랄·파괴 danger와 역할 분리
    static let holiday = Color(light: .rgb(0xC2, 0x45, 0x3C), dark: .rgb(0xE0, 0x7A, 0x70))
    /// 토요일 파랑(달력 관례, 2026-07-28 사용자 결정 — 주말·공휴일은 숫자색을 관례에 양보)
    static let saturday = Color(light: .rgb(0x3D, 0x6B, 0xC4), dark: .rgb(0x7F, 0xA4, 0xE8))
    /// 캘린더 지면 — 앱 아이콘 frost(#F2F3F0, 2026-07-28 사용자 지시: 깨끗한 흰 배경)
    static let frost = Color(light: .rgb(0xF2, 0xF3, 0xF0), dark: .rgb(0x1A, 0x1B, 0x1B))
    // 계절 글로우 팔레트(2026-07-28 3차 — 사용자 제공 스와치 픽셀 실측 채택.
    // 다크는 기존 관례대로 라이트값 15% 백색 블렌드 명도 보정)
    static let glowWinter = Color(light: .rgb(0x96, 0xAE, 0xCA), dark: .rgb(0xA6, 0xBA, 0xD2))
    static let glowSpring = Color(light: .rgb(0xF4, 0xDC, 0xA9), dark: .rgb(0xF6, 0xE1, 0xB6))
    static let glowSummer = Color(light: .rgb(0xBD, 0xD0, 0x85), dark: .rgb(0xC7, 0xD7, 0x97))
    static let glowAutumn = Color(light: .rgb(0xD0, 0x8C, 0x86), dark: .rgb(0xD7, 0x9D, 0x98))
    /// 카드 표면 — 라이트: 밀크 글래스 근사 / 다크: 옅은 상승면
    static let surface = Color(light: Color.white.opacity(0.55), dark: Color.white.opacity(0.07))
}

struct SeasonMeta {
    let name: String
    let phaseName: String
    let color: Color
    let glow: Color        // 캘린더 지면 빛 전용(채도·명도 상향판, 2026-07-28)
    let moodline: String
    let lever: String      // Output 계절 레버 카피 (§3.6 — 허락 톤, 프로토 v70 확정)
}

func seasonMeta(for phase: CyclePhase) -> SeasonMeta {
    switch phase {
    case .menstrual:
        SeasonMeta(name: "겨울", phaseName: "월경기", color: Ink.winter, glow: Ink.glowWinter,
                   moodline: "이번 주는 겨울이에요. 쉬어가도 괜찮아요.",
                   lever: "쉬어가는 주기예요. 이어가도, 미뤄도 좋아요.")
    case .follicular:
        SeasonMeta(name: "봄", phaseName: "난포기", color: Ink.spring, glow: Ink.glowSpring,
                   moodline: "봄이에요. 가볍게 시작해보기 좋은 때예요.",
                   lever: "시동 거는 주기예요. 가볍게 시작해도 좋아요.")
    case .ovulation:
        SeasonMeta(name: "여름", phaseName: "배란기", color: Ink.summer, glow: Ink.glowSummer,
                   moodline: "여름이에요. 하고 싶은 만큼 빛나도 좋아요.",
                   lever: "흐름이 오르는 주기예요. 하고 싶은 만큼 몰입해도 좋아요.")
    case .luteal:
        SeasonMeta(name: "가을", phaseName: "황체기", color: Ink.autumn, glow: Ink.glowAutumn,
                   moodline: "가을이에요. 하나씩 매듭지어도 좋은 때예요.",
                   lever: "매듭짓는 주기예요. 하나씩 마무리해도 좋아요.")
    }
}

struct TodayView: View {
    /// §5.6.2 S4 배너 유예 — 예측일 경과 즉시가 아니라 +2일부터.
    static let overdueGraceDays = 2

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSize   // 아이패드 2열(2026-07-23)
    @Query(sort: \PeriodDay.day) private var periodDays: [PeriodDay]
    @Query(sort: \ScheduleItem.date) private var schedules: [ScheduleItem]
    @Query(sort: \InputItem.createdAt) private var inputs: [InputItem]
    @Query(sort: \OutputItem.createdAt) private var outputs: [OutputItem]
    @Query private var completions: [ItemCompletion]
    @Query private var checkIns: [DailyCheckIn]

    @State private var showLogSheet = false
    @State private var addSheet: CardKind?
    @State private var editingSchedule: ScheduleItem?   // 일정 행 탭 = 수정 시트(2026-07-23)
    @State private var pendingDelete: QuickDeleteTarget?   // 행 길게 누르기 = 빠른 삭제(2026-07-27)
    @State private var isCollapsed = false
    @State private var confirmFeedback = 0   // 확정 순간 햅틱(§4 — 아이템 완료)
    @State private var lightFeedback = 0     // 작은 햅틱(§4 — 진행도 조정 등, 확정 아님)


    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: .now) }
    private var snapshot: CycleSnapshot { CycleSnapshot(periodDays: periodDays) }
    private var todayInfo: (meta: SeasonMeta, dayInCycle: Int, projected: Bool)? { snapshot.phaseInfo(on: today) }

    // 단계별 에너지 프로필(2026-07-23) — 표본 3개+면 무드라인·Input 예시 개인화, 미달이면 기본 유지
    private var energyProfile: EnergyProfile { EnergyProfile(checkIns: checkIns, snapshot: snapshot) }
    private var todayEnergyLevel: EnergyLevel? {
        snapshot.phase(on: today).flatMap { energyProfile.level(for: $0) }
    }
    private var moodlineText: String? {
        guard let info = todayInfo else { return nil }
        if let phase = snapshot.phase(on: today), let level = todayEnergyLevel {
            return EnergyProfile.moodline(for: phase, level: level)
        }
        return info.meta.moodline
    }

    var body: some View {
        ZStack(alignment: .top) {
            Ink.paper.ignoresSafeArea()
            SeasonLight(phase: snapshot.phase(on: today))   // 계절광(§4) — 지면 위 고정 빛
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    largeHeader
                    stateSurfaces
                    if hSize == .regular && !snapshot.isColdStart {
                        // 아이패드: 3구획 좌열 + 체크인 우측 레일(2026-07-23)
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 16) {
                                section(kind: .schedule) { scheduleSection }
                                section(kind: .input) { inputSection }
                                section(kind: .output) { outputSection }
                            }
                            .frame(maxWidth: .infinity)
                            CheckInCard(day: today).frame(width: 360)
                        }
                    } else {
                        if !snapshot.isColdStart {
                            section(kind: .schedule) { scheduleSection }
                            section(kind: .input) { inputSection }
                            section(kind: .output) { outputSection }
                        }
                        CheckInCard(day: today)
                    }
                }
                .padding(20)
                .padding(.top, 4)
                .centeredColumn(1000)
                .background {
                    GeometryReader { geo in
                        Color.clear.onGeometryChange(for: CGFloat.self) {
                            $0.frame(in: .named("todayScroll")).minY
                        } action: { offset in
                            // 성능: 프레임마다 상태 갱신 금지 — 임계 통과 순간에만 flip
                            // (연속 crossfade가 매 프레임 전체 재계산을 유발해 스크롤 버벅임)
                            let shouldCollapse = offset < -56
                            let shouldExpand = offset > -40
                            if shouldCollapse && !isCollapsed {
                                isCollapsed = true
                            } else if shouldExpand && isCollapsed {
                                isCollapsed = false
                            }
                        }
                        .frame(width: geo.size.width, height: 1)
                    }
                }
            }
            .coordinateSpace(name: "todayScroll")
            .scrollDismissesKeyboard(.interactively)   // 스크롤로도 키보드 닫힘
            compactBar
        }
        .sheet(isPresented: $showLogSheet) { PeriodTrackerSheet() }
        .sheet(item: $addSheet) { kind in
            switch kind {
            case .schedule: ScheduleAddSheet(defaultDate: today)
            case .input:    InputAddSheet(currentSeason: todayInfo?.meta, energyLevel: todayEnergyLevel)
            case .output:   OutputAddSheet()
            }
        }
        .sheet(item: $editingSchedule) { item in
            ScheduleAddSheet(defaultDate: today, editing: item)
        }
        .quickDeleteDialog($pendingDelete, completions: completions, context: modelContext)
        .sensoryFeedback(.impact(weight: .medium), trigger: confirmFeedback)
        .sensoryFeedback(.impact(weight: .light), trigger: lightFeedback)
        .coachOverlay(id: .today, steps: CoachSteps.today)   // 기능 튜토리얼(2026-07-23)
    }

    // ── 컬랩싱 헤더: 큰 층 ──
    private var largeHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let info = todayInfo {
                Text(info.meta.name)
                    .font(.almanac(size: 58, weight: .bold))   // v39~41 확정: 계절 표제 58px
                    .foregroundStyle(info.meta.color.opacity(snapshot.isSingleRecord ? 0.6 : 1.0))
                HStack(spacing: 6) {
                    Text("\(info.meta.phaseName) \(info.dayInCycle)일차")
                        .foregroundStyle(info.meta.color.opacity(0.85))
                    Text(today.formatted(.dateTime.month().day().weekday(.wide)))
                        .foregroundStyle(Ink.text.opacity(0.55))
                    if snapshot.isSingleRecord { Text("예측 기반").foregroundStyle(Ink.text.opacity(0.45)) }
                    else if info.projected { Text("예상").foregroundStyle(Ink.text.opacity(0.45)) }
                }
                .font(.system(.footnote, design: .serif))
                Text(moodlineText ?? info.meta.moodline)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Ink.text.opacity(0.85))
                    .padding(.top, 2)
            } else {
                Text("계절 기록 전")
                    .font(.almanac(size: 44, weight: .bold))
                    .foregroundStyle(Ink.text)
            }
        }
        .padding(.top, 24)
    }

    // ── 컬랩싱 헤더: 컴팩트 바 층 ──
    private var compactBar: some View {
        HStack {
            Spacer()
            Text(todayInfo?.meta.name ?? "템포루틴")
                .font(.almanac(size: 28, weight: .bold))   // v39~41: 58 → 28px 컴팩트 바
                .foregroundStyle(todayInfo?.meta.color ?? Ink.text)
            Spacer()
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .opacity(isCollapsed ? 1 : 0)
        .allowsHitTesting(false)
    }

    // ── S0 / S4 상태 표면 ──
    @ViewBuilder
    private var stateSurfaces: some View {
        if snapshot.isColdStart {
            VStack(alignment: .leading, spacing: 14) {
                Text("첫 생리 시작일을 기록하면, 당신의 계절이 시작돼요.")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Ink.text.opacity(0.8))
                Button {
                    showLogSheet = true
                } label: {
                    Text("첫 생리일 기록")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Ink.paper)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Ink.text, in: Capsule())
                }
            }
            .padding(.vertical, 12)
        } else if overdueDiff >= avgLength + Self.overdueGraceDays {
            Text("예정일에서 \(overdueDiff - avgLength)일이 지났어요. 리듬은 늘 조금씩 다르니, 시작되면 캘린더에서 기록해 주세요.")
                .font(.footnote)
                .foregroundStyle(Ink.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Ink.record.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var avgLength: Int { snapshot.averageLength }
    private var overdueDiff: Int {
        guard let last = snapshot.starts.max() else { return 0 }
        return cal.dateComponents([.day], from: last, to: today).day ?? 0
    }

    // ── 3구획 공통 셸 ──
    private func section(kind: CardKind, @ViewBuilder rows: () -> some View) -> some View {
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
            }
            rows()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .milkGlass()
        .coachAnchor(kind == .schedule ? .todaySchedule : kind == .input ? .todayInput : .todayOutput)
    }

    // ① 일정 (오늘)
    private var todaySchedules: [ScheduleItem] { schedules.filter { $0.occurs(on: today) } }

    @ViewBuilder
    private var scheduleSection: some View {
        if todaySchedules.isEmpty && EventOverlay.shared.events(on: today).isEmpty {
            Text("아직 없어요").font(.footnote).foregroundStyle(Ink.text.opacity(0.45))
        }
        ForEach(todaySchedules) { item in
            Button {
                lightFeedback += 1
                editingSchedule = item
            } label: {
                HStack(spacing: 10) {
                    Text(item.isAllDay ? "종일" : item.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(Ink.text.opacity(0.5))
                        .frame(width: 56, alignment: .leading)
                    Text(item.title).font(.subheadline).foregroundStyle(Ink.text)
                    // 여러 날 일정 — 오늘이 몇 일차인지(§8.2.3)
                    if let index = item.dayIndex(on: today) {
                        Text("\(index)/\(item.spanDays)일차")
                            .font(.caption2)
                            .foregroundStyle(Ink.text.opacity(0.5))
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(quickDeleteGesture(.schedule(item), into: $pendingDelete,
                                                    feedback: $confirmFeedback))
            .accessibilityHint("탭하면 수정, 길게 누르면 삭제할 수 있어요")
            .accessibilityAction(named: "삭제") { pendingDelete = .schedule(item) }
        }
        OverlayEventRows(day: today)      // EventKit read-only 오버레이(§3.6.1 — 미저장)
        CalendarConnectRow()
    }

    // ② Input (오늘) — 하루 상세와 동일 데이터(ItemCompletion) 양방향 동기화
    private var todayInputs: [InputItem] {
        inputs.filter { item in
            switch item.schedule {
            case .once:
                if item.backfilled {
                    item.onceShows(on: today)   // 소급 기록은 적어 넣은 그날에만(2026-07-27)
                } else {
                    // 단발 체크(2026-07-23): 완료 전까지 계속, 완료하면 완료한 그날만 남음
                    item.occursByCalendar(on: today) && (!hasAnyCompletion(item.id) || isChecked(item.id))
                }
            case .daily, .weekly, .monthly:
                item.occursByCalendar(on: today)
            case .cycleAnchored(let r):
                snapshot.occurrence(of: r, createdAt: cal.startOfDay(for: item.createdAt), on: today) != nil
                    || isChecked(item.id)
            }
        }
    }

    private func isChecked(_ itemID: UUID) -> Bool {
        completions.contains { $0.itemID == itemID && cal.isDate($0.occurredOn, inSameDayAs: today) }
    }

    private func hasAnyCompletion(_ itemID: UUID) -> Bool {
        completions.contains { $0.itemID == itemID }
    }

    private func toggleCheck(_ itemID: UUID) {
        if let existing = completions.first(where: { $0.itemID == itemID && cal.isDate($0.occurredOn, inSameDayAs: today) }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(ItemCompletion(itemID: itemID, occurredOn: today))
        }
    }

    @ViewBuilder
    private var inputSection: some View {
        if todayInputs.isEmpty {
            Text("아직 없어요").font(.footnote).foregroundStyle(Ink.text.opacity(0.45))
        } else {
            ForEach(todayInputs) { item in
                let checked = isChecked(item.id)
                Button {
                    confirmFeedback += 1
                    toggleCheck(item.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(checked ? Ink.text : Ink.text.opacity(0.35))
                        Text(item.title)
                            .font(.subheadline)
                            .foregroundStyle(Ink.text)
                            .strikethrough(checked, color: Ink.dim)
                        Spacer()
                    }
                }
                .simultaneousGesture(quickDeleteGesture(.input(item), into: $pendingDelete,
                                                        feedback: $confirmFeedback))
                .accessibilityValue(checked ? "완료" : "미완료")
                .accessibilityAction(named: "삭제") { pendingDelete = .input(item) }
            }
        }
    }

    // ③ Output (오늘 occurrence) + 계절 레버 카피
    private var todayOutputs: [OutputItem] {
        outputs.filter { item in
            switch item.schedule {
            case .once, .daily, .weekly, .monthly:
                return item.occursByCalendar(on: today)
            case .cycleAnchored(let r):
                guard let occ = snapshot.occurrence(of: r, createdAt: cal.startOfDay(for: item.createdAt), on: today) else {
                    return false
                }
                return !(item.isComplete && occ.projected)
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

    @ViewBuilder
    private var outputSection: some View {
        if todayOutputs.isEmpty {
            Text(outputEmptyMessage).font(.footnote).foregroundStyle(Ink.text.opacity(0.45))
        } else {
            ForEach(todayOutputs) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                        if item.isComplete {
                            Text("완료").font(.caption2.weight(.semibold)).foregroundStyle(Ink.text.opacity(0.6))
                        }
                        Spacer()
                    }
                    outputProgress(item)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .simultaneousGesture(quickDeleteGesture(.output(item), into: $pendingDelete,
                                                        feedback: $confirmFeedback))
                .accessibilityAction(named: "삭제") { pendingDelete = .output(item) }
            }
        }
        if let meta = todayInfo?.meta, !todayOutputs.isEmpty {
            Text(meta.lever)
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.55))
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func outputProgress(_ item: OutputItem) -> some View {
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
                        Text(sub.title).font(.footnote).foregroundStyle(Ink.text)
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
                    .font(.footnote).monospacedDigit()
                    .foregroundStyle(Ink.text.opacity(0.7))
                    .frame(width: 44, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(item.percent.formatted(.percent.precision(.fractionLength(0))))
        }
    }

}
