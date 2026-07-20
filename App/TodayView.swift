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
    static let paper  = Color(light: .rgb(0xF2, 0xF3, 0xF0), dark: .rgb(0x1C, 0x1B, 0x19))   // 지면
    static let coral  = Color(light: .rgb(0xD6, 0x64, 0x4C), dark: .rgb(0xE0, 0x7A, 0x63))
    /// 파괴적 액션 전용 (--danger) — 기록 코랄·가을 잉크와 역할 분리
    static let danger = Color(light: .rgb(0xB2, 0x3A, 0x30), dark: .rgb(0xD0, 0x68, 0x5E))
    /// 카드 표면 — 라이트: 밀크 글래스 근사 / 다크: 옅은 상승면
    static let surface = Color(light: Color.white.opacity(0.55), dark: Color.white.opacity(0.07))
}

struct SeasonMeta {
    let name: String
    let phaseName: String
    let color: Color
    let moodline: String
    let lever: String      // Output 계절 레버 카피 (§3.6 — 허락 톤, 프로토 v70 확정)
}

func seasonMeta(for phase: CyclePhase) -> SeasonMeta {
    switch phase {
    case .menstrual:
        SeasonMeta(name: "겨울", phaseName: "월경기", color: Ink.winter,
                   moodline: "이번 주는 겨울이에요. 쉬어가도 괜찮아요.",
                   lever: "쉬어가는 주기예요. 이어가도, 미뤄도 좋아요.")
    case .follicular:
        SeasonMeta(name: "봄", phaseName: "난포기", color: Ink.spring,
                   moodline: "봄이에요. 가볍게 시작해보기 좋은 때예요.",
                   lever: "시동 거는 주기예요. 가볍게 시작해도 좋아요.")
    case .ovulation:
        SeasonMeta(name: "여름", phaseName: "배란기", color: Ink.summer,
                   moodline: "여름이에요. 하고 싶은 만큼 빛나도 좋아요.",
                   lever: "흐름이 오르는 주기예요. 하고 싶은 만큼 몰입해도 좋아요.")
    case .luteal:
        SeasonMeta(name: "가을", phaseName: "황체기", color: Ink.autumn,
                   moodline: "가을이에요. 하나씩 매듭지어도 좋은 때예요.",
                   lever: "매듭짓는 주기예요. 하나씩 마무리해도 좋아요.")
    }
}

struct TodayView: View {
    /// §5.6.2 S4 배너 유예 — 예측일 경과 즉시가 아니라 +2일부터.
    static let overdueGraceDays = 2

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PeriodDay.day) private var periodDays: [PeriodDay]
    @Query(sort: \ScheduleItem.date) private var schedules: [ScheduleItem]
    @Query(sort: \InputItem.createdAt) private var inputs: [InputItem]
    @Query(sort: \OutputItem.createdAt) private var outputs: [OutputItem]
    @Query private var completions: [ItemCompletion]
    @Query private var checkIns: [DailyCheckIn]

    @State private var showLogSheet = false
    @State private var addSheet: CardKind?
    @State private var isCollapsed = false

    // 체크인 드래프트 — energy·mood 둘 다 기록되는 순간 upsert(§5.5: 저장 행은 항상 1...5)
    @State private var draftEnergy = 0
    @State private var draftMood = 0
    @State private var draftSleep = 0
    @State private var draftNote = ""
    @State private var draftLoaded = false

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: .now) }
    private var snapshot: CycleSnapshot { CycleSnapshot(periodDays: periodDays) }
    private var todayInfo: (meta: SeasonMeta, dayInCycle: Int, projected: Bool)? { snapshot.phaseInfo(on: today) }

    var body: some View {
        ZStack(alignment: .top) {
            Ink.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    largeHeader
                    stateSurfaces
                    if !snapshot.isColdStart {
                        section(kind: .schedule) { scheduleSection }
                        section(kind: .input) { inputSection }
                        section(kind: .output) { outputSection }
                    }
                    checkInCard
                }
                .padding(20)
                .padding(.top, 4)
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
                                withAnimation(.easeOut(duration: 0.2)) { isCollapsed = true }
                            } else if shouldExpand && isCollapsed {
                                withAnimation(.easeOut(duration: 0.2)) { isCollapsed = false }
                            }
                        }
                        .frame(width: geo.size.width, height: 1)
                    }
                }
            }
            .coordinateSpace(name: "todayScroll")
            compactBar
        }
        .sheet(isPresented: $showLogSheet) { PeriodTrackerSheet() }
        .sheet(item: $addSheet) { kind in
            switch kind {
            case .schedule: ScheduleAddSheet(defaultDate: today)
            case .input:    InputAddSheet(currentSeason: todayInfo?.meta)
            case .output:   OutputAddSheet()
            }
        }
        .onAppear(perform: loadDraft)
    }

    // ── 컬랩싱 헤더: 큰 층 ──
    private var largeHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let info = todayInfo {
                Text(info.meta.name)
                    .font(.system(size: 56, weight: .bold, design: .serif))
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
                Text(info.meta.moodline)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Ink.text.opacity(0.85))
                    .padding(.top, 2)
            } else {
                Text("계절 기록 전")
                    .font(.system(size: 44, weight: .bold, design: .serif))
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
                .font(.system(.headline, design: .serif))
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
                .background(Ink.coral.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
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
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(Ink.text)
                Spacer()
                Button {
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
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    // ① 일정 (오늘)
    private var todaySchedules: [ScheduleItem] { schedules.filter { $0.occurs(on: today) } }

    @ViewBuilder
    private var scheduleSection: some View {
        if todaySchedules.isEmpty && EventOverlay.shared.events(on: today).isEmpty {
            Text("아직 없어요").font(.footnote).foregroundStyle(Ink.text.opacity(0.45))
        }
        ForEach(todaySchedules) { item in
            HStack(spacing: 10) {
                Text(item.isAllDay ? "종일" : item.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Ink.text.opacity(0.5))
                    .frame(width: 56, alignment: .leading)
                Text(item.title).font(.subheadline).foregroundStyle(Ink.text)
                Spacer()
            }
        }
        OverlayEventRows(day: today)      // EventKit read-only 오버레이(§3.6.1 — 미저장)
        CalendarConnectRow()
    }

    // ② Input (오늘) — 하루 상세와 동일 데이터(ItemCompletion) 양방향 동기화
    private var todayInputs: [InputItem] {
        inputs.filter { item in
            switch item.schedule {
            case .daily: true
            case .cycleAnchored(let r):
                snapshot.occurrence(of: r, createdAt: cal.startOfDay(for: item.createdAt), on: today) != nil
                    || isChecked(item.id)
            }
        }
    }

    private func isChecked(_ itemID: UUID) -> Bool {
        completions.contains { $0.itemID == itemID && cal.isDate($0.occurredOn, inSameDayAs: today) }
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
                    toggleCheck(item.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(checked ? Ink.text : Ink.text.opacity(0.35))
                        Text(item.title)
                            .font(.subheadline)
                            .foregroundStyle(Ink.text)
                            .strikethrough(checked, color: Ink.text.opacity(0.5))
                        Spacer()
                    }
                }
                .accessibilityValue(checked ? "완료" : "미완료")
            }
        }
    }

    // ③ Output (오늘 occurrence) + 계절 레버 카피
    private var todayOutputs: [OutputItem] {
        outputs.filter { item in
            guard let occ = snapshot.occurrence(of: item.recurrence,
                                                createdAt: cal.startOfDay(for: item.createdAt), on: today) else {
                return false
            }
            return !(item.isComplete && occ.projected)
        }
    }

    @ViewBuilder
    private var outputSection: some View {
        if todayOutputs.isEmpty {
            Text("아직 없어요").font(.footnote).foregroundStyle(Ink.text.opacity(0.45))
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
                    sub.isDone.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: sub.isDone ? "checkmark.square.fill" : "square")
                            .foregroundStyle(sub.isDone ? Ink.text : Ink.text.opacity(0.35))
                        Text(sub.title).font(.footnote).foregroundStyle(Ink.text)
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
                    .font(.footnote).monospacedDigit().foregroundStyle(Ink.text.opacity(0.7))
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
                    .font(.footnote).monospacedDigit()
                    .foregroundStyle(Ink.text.opacity(0.7))
                    .frame(width: 44, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(item.percent.formatted(.percent.precision(.fractionLength(0))))
        }
    }

    // ── 데일리 체크인 (§3.4 — 라벨 조사형, 3탭 = 1·3·5, 스킵 무벌점) ──
    private var todayCheckIn: DailyCheckIn? { checkIns.first { $0.day == today } }

    private var checkInCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("오늘의 체크인")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Ink.text)
            checkInRow(label: "에너지는", options: ["낮음", "보통", "높음"], value: $draftEnergy)
            checkInRow(label: "기분은", options: ["흐림", "보통", "맑음"], value: $draftMood)
            checkInRow(label: "지난밤 잠은", options: ["뒤척임", "보통", "푹 잤어요"], value: $draftSleep)
            VStack(alignment: .leading, spacing: 6) {
                Text("오늘 한 줄").font(.caption).foregroundStyle(Ink.text.opacity(0.5))
                TextField("남기고 싶은 만큼만, 짧게.", text: $draftNote, axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(Ink.text)
                    .onChange(of: draftNote) { persistDraft() }
            }
            if draftEnergy > 0 && draftMood > 0 {
                Text("오늘 기록이 나의 리듬에 담겼어요.")
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Ink.text.opacity(0.6))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func checkInRow(label: String, options: [String], value: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Ink.text.opacity(0.75))
                .frame(width: 88, alignment: .leading)
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let mapped = index * 2 + 1   // 3탭 = 1·3·5
                let selected = value.wrappedValue == mapped
                Button {
                    value.wrappedValue = selected ? 0 : mapped
                    persistDraft()
                } label: {
                    Text(option)
                        .font(.caption)
                        .foregroundStyle(selected ? Ink.paper : Ink.text.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(selected ? AnyShapeStyle(Ink.text) : AnyShapeStyle(Ink.text.opacity(0.08)),
                                    in: Capsule())
                }
                .accessibilityLabel("\(label) \(option)")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
    }

    private func loadDraft() {
        guard !draftLoaded else { return }
        draftLoaded = true
        if let existing = todayCheckIn {
            draftEnergy = existing.energy
            draftMood = existing.mood
            draftSleep = existing.sleep ?? 0
            draftNote = existing.note ?? ""
        }
    }

    /// energy·mood 둘 다 있으면 upsert — 저장 행은 항상 §5.5 계약(1...5)을 지킨다.
    private func persistDraft() {
        if let existing = todayCheckIn {
            if draftEnergy > 0 && draftMood > 0 {
                existing.energy = draftEnergy
                existing.mood = draftMood
                existing.sleep = draftSleep > 0 ? draftSleep : nil
                existing.note = draftNote.isEmpty ? nil : draftNote
            } else {
                modelContext.delete(existing)   // 필수 신호 해제 = 기록 철회(스킵 무벌점)
            }
        } else if draftEnergy > 0 && draftMood > 0 {
            let record = DailyCheckIn(day: today, energy: draftEnergy, mood: draftMood)
            record.sleep = draftSleep > 0 ? draftSleep : nil
            record.note = draftNote.isEmpty ? nil : draftNote
            modelContext.insert(record)
        }
    }
}
