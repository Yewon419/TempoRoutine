// 템포루틴 — 나의 리듬 탭 (MASTER §8.2.5 — 2026-08-09 재편 2차: 단일 칩 행)
// 칩 한 줄 [에너지 | 기분 | 수면 | 나의 루틴 | 한 줄 기록] (베타 피드백 "탭 별도 구분하지말고
// 한 줄로 쭉" — 구 [나의 사계]+신호 하위 칩 2단 병합). 마지막 본 탭 = AppStorage 복원.
//   에너지·기분·수면 = 관측 패턴(콜드/진행 카드 + 신호 패널)
//   나의 루틴 = 구 「나의 사계」 낱장 개명(§3.5.1 공유 안전 화면 — 렌더 금지: 날짜·주기 시점·
//               체크인·메모·진행도, 루틴 이름·종류 태그만)
//   한 줄 기록 = 일기 모음(구 하단 상시 카드에서 분리)
// 신호 패널·집계 서술은 §5.6.3 계약. 카피 = 프로토 v77 전사.

import SwiftUI
import SwiftData
import TempoCore

struct RhythmView: View {
    @Query(sort: \PeriodDay.day) private var periodDays: [PeriodDay]
    @Query(sort: \InputItem.createdAt) private var inputs: [InputItem]
    @Query(sort: \OutputItem.createdAt) private var outputs: [OutputItem]
    @Query(sort: \DailyCheckIn.day, order: .reverse) private var checkIns: [DailyCheckIn]

    private static let allPhases: [CyclePhase] = CyclePhase.displayOrder   // 봄→여름→가을→겨울(2026-07-29 피드백)

    // 나의 사계 → 루틴 추가 연동(2026-08-01 베타 피드백): 계절 칸 + → 종류 선택 → 그 계절 앵커 시트
    @State private var addingSeason: SeasonAnchor?
    @State private var addKind: CardKind?
    // 루틴 행 살리기(2026-08-08 베타 피드백 "기본적인 기능이 없다시피") — 탭=수정, 길게=삭제
    @Query private var completions: [ItemCompletion]
    @State private var editingInput: InputItem?
    @State private var editingOutput: OutputItem?
    @State private var pendingDelete: QuickDeleteTarget?
    @State private var confirmFeedback = 0
    @Query private var selfReports: [SelfReportRecord]
    @State private var showSelfReport = false
    // 단일 칩 행(2026-08-09 베타 피드백 "탭 별도 구분하지말고 한 줄로 쭉") — 2단 스위처 병합.
    // 마지막 본 탭은 재진입·재실행 때 복원("들어갈때마다 마지막 탭" — AppStorage).
    @AppStorage("rhythmLastTab") private var lastTabRaw = RhythmTab.energy.rawValue

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: .now) }
    private var snapshot: CycleSnapshot { CycleSnapshot(periodDays: periodDays) }
    private var profile: EnergyProfile { EnergyProfile(checkIns: checkIns, snapshot: snapshot) }
    // 유형 카드(비바체·안단테·루바토)는 2026-08-09 사용자 결정으로 UI에서 내림 —
    // 엔진(WindowStats)·내보내기(rhythmSummary)·자기돌봄 소비처(AxisProfile)는 유지.
    private var unlockedPhases: [CyclePhase] { Self.allPhases.filter { profile.level(for: $0) != nil } }

    // ── 신호 패널 입력 (§5.6.3 — DailyCheckIn → SignalSample, 계산은 RhythmEngine) ──
    private var signalSamples: [SignalSample] {
        checkIns.map { SignalSample(day: $0.day, energy: $0.energy, mood: $0.mood, sleep: $0.sleep) }
    }
    private var signalSummaries: [PhaseSignalSummary] {
        RhythmEngine.summaries(samples: signalSamples, periodStarts: snapshot.starts,
                               averageLength: snapshot.averageLength,
                               menstrualLength: snapshot.menstrualLength)
    }
    /// 패널 노출 = 비교 서술 가능한 신호가 하나라도 있을 때(§5.6.3 임계).
    /// 그 전엔 콜드 문법 유지 — 진행 카드만.
    private var showSwitcher: Bool {
        SignalKind.allCases.contains { RhythmEngine.narratable(signalSummaries, signal: $0) }
    }

    var body: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()
            SeasonLight(phase: snapshot.phase(on: today), motif: .open)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 모던 = 아웃라인 표제(시안 §1.3-2 — 나의 리듬은 아웃라인 승격 이력)
                    almanacDisplay("나의 리듬", size: 44, color: Ink.text)
                        .padding(.top, 12)
                    selfReportPrompt
                    sectionSwitcher
                    switch tab {
                    case .energy, .mood, .sleep:
                        // 관측 패턴 — 콜드 문법 승계: 서술 가능한 신호가 없으면 진행 카드만
                        coldCard
                        if unlockedPhases.isEmpty {   // 패턴이 하나라도 열리면 일반론 카드는 물러남(2026-07-23)
                            meanwhileCard
                        }
                        if showSwitcher {
                            signalPanelArea
                        }
                    case .routines:
                        routinesSheet
                    case .diary:
                        diarySheet
                    }
                }
                .padding(20)
                .centeredColumn(720)   // 아이패드 중앙 조판(2026-07-23)
            }
        }
        .confirmationDialog("무엇을 추가할까요?",
                            isPresented: Binding(get: { addingSeason != nil && addKind == nil },
                                                 set: { if !$0 && addKind == nil { addingSeason = nil } }),
                            titleVisibility: .visible) {
            Button("Input — 매일 챙길 것") { addKind = .input }
            Button("Output — 만들어낼 것") { addKind = .output }
            Button("취소", role: .cancel) { addingSeason = nil }
        }
        .sheet(isPresented: $showSelfReport) { SelfReportFlow() }
        .sheet(item: $addKind, onDismiss: { addingSeason = nil }) { kind in
            switch kind {
            case .input:
                InputAddSheet(currentSeason: addingSeason.map { seasonMeta(for: $0.phase) },
                              energyLevel: addingSeason.flatMap { profile.level(for: $0.phase) },
                              presetSeason: addingSeason)
            case .output:
                OutputAddSheet(presetSeason: addingSeason)
            case .schedule:
                EmptyView()   // 사계는 루틴(Input·Output)만 다룬다 — 일정은 캘린더 몫
            }
        }
        // 루틴 행 탭 = 수정 시트(2026-08-08) — 오늘 탭 일정 행과 같은 문법
        .sheet(item: $editingInput) { item in
            InputAddSheet(currentSeason: nil, editing: item)
        }
        .sheet(item: $editingOutput) { item in
            OutputAddSheet(editing: item)
        }
        .quickDeleteDialog($pendingDelete, completions: completions, context: modelContext)
        .sensoryFeedback(.impact(weight: .medium), trigger: confirmFeedback)
    }

    @Environment(\.modelContext) private var modelContext

    // ── 자기보고 설문 제안 (v1.6 §4) ──
    // 첫 주기를 다 기록한 사람에게 1회만. 그 사람은 이탈 위험이 낮고,
    // 침묵하는 문구의 이유("아직 당신의 이맘때를 모르겠어요")를 이미 체감했다.
    @ViewBuilder
    private var selfReportPrompt: some View {
        if SelfReportStore.shouldPrompt(snapshot: snapshot, records: selfReports) {
            VStack(alignment: .leading, spacing: 10) {
                Text("이맘때 이야기를 하려면 몇 가지 알아야 해요.")
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(Ink.text)
                HStack(spacing: 10) {
                    Button("답해보기") { showSelfReport = true }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Ink.paper)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Ink.text, in: Capsule())
                    Button("나중에") { SelfReportStore.hasPrompted = true }
                        .font(.footnote)
                        .foregroundStyle(Ink.text.opacity(0.55))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .milkGlass()
        }
    }

    // ── 단일 칩 행 (2026-08-09 — 구 [나의 사계]+신호 하위 칩 2단을 한 줄로 병합, 사용자 지시) ──
    private enum RhythmTab: String, CaseIterable, Identifiable {
        case energy = "에너지"
        case mood = "기분"
        case sleep = "수면"
        case routines = "나의 루틴"
        case diary = "한 줄 기록"
        var id: String { rawValue }
        var signalTab: RhythmSignalTab? {
            switch self {
            case .energy: .energy
            case .mood: .mood
            case .sleep: .sleep
            case .routines, .diary: nil
            }
        }
    }

    /// 수면 칩은 추적 끔+표본 0이면 숨김(구 signalTabs 규칙 승계 — 꺼진 항목 거짓 안내 방지)
    private var visibleTabs: [RhythmTab] {
        RhythmTab.allCases.filter { t in
            guard t == .sleep else { return true }
            return AppSettings.trackedSignals.sleep
                || signalSummaries.contains { $0.signal == .sleep }
        }
    }

    /// 저장된 마지막 탭 복원 — 숨겨진 칩(수면 추적 끔)이면 에너지 폴백
    private var tab: RhythmTab {
        let stored = RhythmTab(rawValue: lastTabRaw) ?? .energy
        return visibleTabs.contains(stored) ? stored : .energy
    }

    private var sectionSwitcher: some View {
        // 5칩 한 줄 — 작은 기기(SE) 폭 대비 수평 스크롤 허용
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleTabs) { item in
                    chip(label: item.rawValue, selected: tab == item) { lastTabRaw = item.rawValue }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("보기 선택")
    }

    /// SwiftUI 타입체크 폭발 방지(CLAUDE.md) — 패널 분기를 body 식에서 뗀다.
    private var signalPanelArea: some View {
        let signal = (tab.signalTab ?? .energy).signal
        return SignalPanel(signal: signal,
                           summaries: signalSummaries,
                           topPhases: RhythmEngine.perCycleTopPhases(signal: signal,
                                                                     samples: signalSamples,
                                                                     periodStarts: snapshot.starts,
                                                                     menstrualLength: snapshot.menstrualLength),
                           // "지난 N주기" = 표본이 든 주기만(2026-08-05 실기기 — HK 이어받기 사용자는
                           // 전체 주기 수가 23 같은 값이 되어 서술이 어긋난다)
                           completedCycles: RhythmEngine.cyclesWithData(signal: signal,
                                                                        samples: signalSamples,
                                                                        periodStarts: snapshot.starts),
                           currentPhase: snapshot.phase(on: today))
    }

    /// 칩 공용 렌더 — v68 칩 시각 그대로(2026-08-09 단일 행 병합 후에도 유지).
    private func chip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .foregroundStyle(selected ? Ink.paper : Ink.text.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? AnyShapeStyle(Ink.text)
                                     : AnyShapeStyle(Ink.text.opacity(0.08)), in: Capsule())
        }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // ── 콜드스타트 카드 (§8.2.5 개정 2026-07-23 — "약 41일" 폐기) ──
    // 날짜 약속 대신 가까운 마일스톤: 이번 계절 기록 3회(EnergyProfile.minSamples) → 네 계절 채우기.
    private var progressInfo: (progress: Double, title: String, body: String, label: String) {
        if snapshot.isColdStart {
            return (0, "첫 패턴을 기다리는 중", "당신만의 패턴이 보이기 시작할 거예요.",
                    "첫 생리일을 기록하면 시작돼요")
        }
        let goal = EnergyProfile.minSamples
        let curPhase = snapshot.phase(on: today)
        let curName = curPhase.map { seasonMeta(for: $0).name } ?? "이번 계절"
        let curCount = curPhase.map { min(goal, profile.sampleCount(for: $0)) } ?? 0
        let unlocked = unlockedPhases
        if unlocked.isEmpty {
            let body = curCount == 0
                ? "\(curName)의 에너지를 세 번 기록하면, 이 계절의 첫 패턴이 보여요."
                : "\(curName)의 에너지 기록이 \(curCount)번 쌓였어요. 세 번이면 이 계절의 첫 패턴이 보여요."
            return (Double(curCount) / Double(goal), "첫 패턴을 기다리는 중", body,
                    "\(curName) 기록 \(curCount) / \(goal)")
        }
        let names = unlocked.map { seasonMeta(for: $0).name }.joined(separator: "·")
        var body = "\(names)의 패턴이 열렸어요. 네 계절이 모두 채워지면 리듬 전체가 이어져요."
        if let phase = curPhase, profile.level(for: phase) == nil {
            body += " \(curName)은 \(curCount) / \(goal)회째예요."
        }
        return (Double(unlocked.count) / 4.0, "패턴이 보이기 시작했어요", body,
                "네 계절 중 \(unlocked.count)")
    }

    private var coldCard: some View {
        let info = progressInfo
        return VStack(alignment: .leading, spacing: 10) {
            Text(info.title)
                .font(.almanac(size: 17, weight: .bold))
                .foregroundStyle(Ink.text)
            Text(info.body)
                .font(.subheadline)
                .foregroundStyle(Ink.text.opacity(0.75))
            GeometryReader { geo in
                // 모던 = 니어블랙 대비 상향(시안 §1.3-7): 트랙 12%·채움 75%
                let modern = ThemeStore.current == .modern
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.text.opacity(modern ? 0.12 : 0.08))
                    Capsule().fill(Ink.text.opacity(modern ? 0.75 : 0.55))
                        .frame(width: max(6, geo.size.width * info.progress))
                }
            }
            .frame(height: 6)
            .accessibilityLabel("패턴 수집 진행")
            .accessibilityValue(info.progress.formatted(.percent.precision(.fractionLength(0))))
            Text(info.label)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Ink.text.opacity(0.5))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .milkGlass()
    }

    private var meanwhileCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("그동안은")
                .font(.almanac(size: 17, weight: .bold))
                .foregroundStyle(Ink.text)
            Text("많은 사람이 겨울엔 에너지가 낮아진다고 느껴요. 당신의 리듬은 곧 여기에 쌓입니다.")
                .font(.subheadline)
                .foregroundStyle(Ink.text.opacity(0.75))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .milkGlass()
    }

    // ── 나의 루틴 낱장 (§3.5.1 — 구 「나의 사계」, 2026-08-09 개명. 개방형 4단 책력) ──
    /// 행 모델 — 제목 문자열이 아니라 실물 아이템을 문다(2026-08-08 행 살리기).
    /// 종전 `ForEach(id: \.self)`는 같은 제목 두 개면 렌더 ID가 충돌했다.
    private enum SeasonRoutine: Identifiable {
        case input(InputItem)
        case output(OutputItem)

        var id: UUID {
            switch self {
            case .input(let item): item.id
            case .output(let item): item.id
            }
        }
        var title: String {
            switch self {
            case .input(let item): item.title
            case .output(let item): item.title
            }
        }
        /// 종류 구분 태그 — §3.5.1 렌더 금지 목록(날짜·주기 시점·체크인·메모·진행도) 밖
        var kindLabel: String {
            switch self {
            case .input: "Input"
            case .output: "Output"
            }
        }
        var deleteTarget: QuickDeleteTarget {
            switch self {
            case .input(let item): .input(item)
            case .output(let item): .output(item)
            }
        }
    }

    private var routinesBySeason: [CyclePhase: [SeasonRoutine]] {
        var map: [CyclePhase: [SeasonRoutine]] = [:]
        for item in inputs {
            if case .cycleAnchored(let r) = item.schedule {
                map[anchorPhase(r), default: []].append(.input(item))
            }
        }
        for item in outputs {
            if case .cycleAnchored(let r) = item.schedule {
                map[anchorPhase(r), default: []].append(.output(item))
            }
        }
        return map
    }

    private func anchorPhase(_ r: CycleRecurrence) -> CyclePhase {
        switch r.anchor {
        case .cycleStart: .menstrual
        case .phase(let p): p
        }
    }

    private var routinesSheet: some View {
        let routines = routinesBySeason
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("계절별 루틴")
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Ink.text.opacity(0.5))
                    .kerning(2)
                Text("나의 루틴")
                    .font(.almanac(size: 28, weight: .bold))
                    .foregroundStyle(Ink.text)
            }
            ForEach(CyclePhase.displayOrder, id: \.self) { phase in
                seasonRow(phase: phase, routines: routines[phase] ?? [])
            }
            Text("템포루틴 · 당신 몸의 템포에 맞게")
                .font(.almanacBody(.caption, size: 12))
                .foregroundStyle(Ink.text.opacity(0.45))
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .milkGlass(radius: 18)
    }

    // ── 한 줄 기록 (2026-07-22 사용자 요청 — 오늘 탭 "오늘 한 줄"의 열람 표면. 2026-08-09 섹션 분리) ──
    // 루틴 낱장과 별도 화면: 낱장은 공유 안전 화면(§3.5.1 메모 렌더 금지)이라 일기는 섞지 않는다.
    private var diaryEntries: [DailyCheckIn] {
        checkIns.filter { !($0.note ?? "").isEmpty }
    }

    private var diarySheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("오늘 한 줄 모음")
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Ink.text.opacity(0.5))
                    .kerning(2)
                Text("한 줄 기록")
                    .font(.almanac(size: 28, weight: .bold))
                    .foregroundStyle(Ink.text)
            }
            if diaryEntries.isEmpty {
                Text("오늘 탭에서 한 줄을 남기면 여기에 모여요.")
                    .font(.subheadline)
                    .foregroundStyle(Ink.text.opacity(0.6))
                    .padding(.vertical, 8)
            } else {
                ForEach(diaryEntries) { entry in
                    diaryRow(entry)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .milkGlass(radius: 18)
    }

    private func diaryRow(_ entry: DailyCheckIn) -> some View {
        let phase = snapshot.phase(on: entry.day)
        let meta = phase.map(seasonMeta(for:))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(entry.day.formatted(.dateTime.month().day().weekday(.abbreviated)))
                    .font(.almanacBody(.caption, size: 12))
                    .foregroundStyle(Ink.text.opacity(0.55))
                if let meta {
                    Text(meta.name)
                        .font(.almanacBody(.caption, size: 12))
                        .foregroundStyle(meta.color.opacity(0.85))
                }
                Spacer()
            }
            // 한 줄 일기 본문 — 한글이 주라 시스템 세리프면 고딕 폴백(2026-08-01 베타 피드백)
            Text(entry.note ?? "")
                .font(.almanacBody(.subheadline, size: 15))
                .foregroundStyle(Ink.text)
        }
        .padding(.vertical, 8)
        .almanacRule()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.day.formatted(.dateTime.month().day())), \(meta?.name ?? ""), \(entry.note ?? "")")
    }

    private func seasonRow(phase: CyclePhase, routines: [SeasonRoutine]) -> some View {
        let meta = seasonMeta(for: phase)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                SeasonGlyph(phase: phase)
                Text(meta.name)
                    .font(.almanacBody(.subheadline, size: 15, weight: .bold))   // 한글 세리프 폴백 해소(2026-08-01)
                    .foregroundStyle(meta.color)
                Spacer()
                // 계절 칸에서 바로 루틴 추가(2026-08-01 베타 피드백) — 그 계절 앵커로 시트가 열린다
                Button {
                    addingSeason = SeasonAnchor.allCases.first { $0.phase == phase }
                } label: {
                    Image(systemName: "plus")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Ink.text.opacity(0.6))
                        .frame(width: 44, height: 32)   // §8.1 터치 여유
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(meta.name)에 루틴 추가")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(routines.isEmpty ? "\(meta.name), 루틴 없음" : meta.name)
            // 빈 계절 = 여백 + 행 구분 괘선만(빈 낱장도 캡처물 성립 — §3.5.1).
            // 안쪽 괘선은 행 구분선과 겹쳐 이중 줄로 보여 걷음(2026-08-08 조판).
            ForEach(routines) { routine in
                routineRow(routine)
            }
        }
        .padding(.vertical, routines.isEmpty ? 12 : 8)
        .almanacRule()
    }

    /// 루틴 행(2026-08-08 행 살리기) — 탭=수정 시트, 길게=빠른 삭제. 오늘 탭 행과 같은 문법.
    private func routineRow(_ routine: SeasonRoutine) -> some View {
        Button {
            switch routine {
            case .input(let item): editingInput = item
            case .output(let item): editingOutput = item
            }
        } label: {
            HStack(spacing: 8) {
                Text(routine.title)
                    .font(.subheadline)
                    .foregroundStyle(Ink.text)
                Spacer(minLength: 8)
                Text(routine.kindLabel)
                    .font(.caption2)
                    .foregroundStyle(Ink.text.opacity(0.4))
            }
            .padding(.leading, 24)   // 계절명 텍스트에 맞춘 들여쓰기 — 낱장 위계(2026-08-08 조판)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(quickDeleteGesture(routine.deleteTarget, into: $pendingDelete,
                                                feedback: $confirmFeedback))
        .accessibilityHint("탭하면 수정, 길게 누르면 삭제할 수 있어요")
        .accessibilityAction(named: "삭제") { pendingDelete = routine.deleteTarget }
    }
}
