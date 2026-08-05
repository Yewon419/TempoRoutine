// 템포루틴 — 나의 리듬 탭 (MASTER §8.2.5 P0 표면: 콜드스타트 + 나의 사계 낱장 기본 노출)
// 신호 패널·집계 서술은 P1 로직(§5.6.3 — P0는 데이터 형태만 락). 카피 = 프로토 v77 전사.
// 나의 사계(§3.5.1 공유 안전 화면): 렌더 금지 = 날짜·주기 시점·체크인·메모·진행도 — 루틴 이름만.

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
    @Query private var selfReports: [SelfReportRecord]
    @State private var showSelfReport = false
    // 신호 스위처(§8.2.5 v68) — 사계 칩 선택 시 패널 자리에 낱장 스왑
    @State private var signalTab: RhythmSignalTab = .energy

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: .now) }
    private var snapshot: CycleSnapshot { CycleSnapshot(periodDays: periodDays) }
    private var profile: EnergyProfile { EnergyProfile(checkIns: checkIns, snapshot: snapshot) }
    private var axis: AxisProfile { AxisProfile(checkIns: checkIns, snapshot: snapshot) }
    private var unlockedPhases: [CyclePhase] { Self.allPhases.filter { profile.level(for: $0) != nil } }

    // ── 신호 패널 입력 (§5.6.3 — DailyCheckIn → SignalSample, 계산은 RhythmEngine) ──
    private var signalSamples: [SignalSample] {
        checkIns.map { SignalSample(day: $0.day, energy: $0.energy, mood: $0.mood, sleep: $0.sleep) }
    }
    private var signalSummaries: [PhaseSignalSummary] {
        RhythmEngine.summaries(samples: signalSamples, periodStarts: snapshot.starts,
                               averageLength: snapshot.averageLength)
    }
    /// 스위처에 올릴 신호 칩. 수면은 추적을 껐고 표본도 없으면 숨긴다 —
    /// 사용자가 끈 항목에 "기록이 쌓이면"이라고 말하면 거짓 안내가 된다.
    private var signalTabs: [RhythmSignalTab] {
        RhythmSignalTab.allCases.filter { tab in
            guard tab == .sleep else { return true }
            return AppSettings.trackedSignals.sleep
                || signalSummaries.contains { $0.signal == .sleep }
        }
    }
    /// 스위처 노출 = 비교 서술 가능한 신호가 하나라도 있을 때(§5.6.3 임계).
    /// 그 전엔 콜드 문법 유지 — 콜드 카드 + 사계 낱장 상시(v77).
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
                    rhythmTypeCard
                    selfReportPrompt
                    coldCard
                    if unlockedPhases.isEmpty {   // 패턴이 하나라도 열리면 일반론 카드는 물러남(2026-07-23)
                        meanwhileCard
                    }
                    if showSwitcher {
                        // 완료 상태(v68): 스위처 + 패널, 사계는 4번째 칩으로 낱장 스왑
                        signalSwitcher
                        signalPanelArea
                    } else {
                        // 콜드(v77): 스위처 부재 — 사계 낱장 상시 노출(§3.5.1 체크인 비의존)
                        seasonsSheet
                    }
                    diarySheet
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
    }

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

    // ── 신호 스위처 (v68 — 칩 [에너지|기분|수면|나의 사계]) ──
    /// 선택 탭이 숨겨진 칩(수면 추적 끔)이면 에너지로 폴백 — 아무 칩도 선택 안 된 상태 방지.
    private var activeTab: RhythmSignalTab {
        signalTabs.contains(signalTab) ? signalTab : .energy
    }

    /// SwiftUI 타입체크 폭발 방지(CLAUDE.md) — 패널 분기를 body 식에서 뗀다.
    @ViewBuilder
    private var signalPanelArea: some View {
        if let signal = activeTab.signal {
            SignalPanel(signal: signal,
                        summaries: signalSummaries,
                        topPhases: RhythmEngine.perCycleTopPhases(signal: signal,
                                                                  samples: signalSamples,
                                                                  periodStarts: snapshot.starts),
                        completedCycles: max(0, snapshot.starts.count - 1),
                        currentPhase: snapshot.phase(on: today))
        } else {
            seasonsSheet
        }
    }

    private var signalSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(signalTabs) { tab in
                let selected = activeTab == tab
                Button {
                    signalTab = tab
                } label: {
                    Text(tab.label)
                        .font(.caption)
                        .foregroundStyle(selected ? Ink.paper : Ink.text.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(selected ? AnyShapeStyle(Ink.text)
                                             : AnyShapeStyle(Ink.text.opacity(0.08)), in: Capsule())
                }
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("신호 선택")
    }

    // ── 유형 카드 (§3.11 — A축=이름, M축=한 줄 서술) ──
    // 로그가 없으면 아예 올리지 않는다. 카드가 없는 상태가 콜드 스타트의 정상 모습이고,
    // 그 침묵이 §3.11의 "할 말이 없으면 하지 않는다"를 화면에서 구현한다.
    @ViewBuilder
    private var rhythmTypeCard: some View {
        if axis.hasEnoughData, let name = axis.typeName {
            VStack(alignment: .leading, spacing: 8) {
                Text(name)
                    .font(.almanac(size: 32, weight: .bold))
                    .foregroundStyle(Ink.text)
                if let line = axis.amplitudeLine {
                    Text(line)
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Ink.text.opacity(0.8))
                }
                if let line = axis.modalityLine {
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(Ink.text.opacity(0.6))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .milkGlass()
            .accessibilityElement(children: .combine)
        }
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
            Text("많은 사람이 월경기엔 에너지가 낮아진다고 느껴요. 당신의 리듬은 곧 여기에 쌓입니다.")
                .font(.subheadline)
                .foregroundStyle(Ink.text.opacity(0.75))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .milkGlass()
    }

    // ── 나의 사계 낱장 (§3.5.1 — 기본 노출, 개방형 4단 책력) ──
    private var routinesBySeason: [CyclePhase: [String]] {
        var map: [CyclePhase: [String]] = [:]
        for item in inputs {
            if case .cycleAnchored(let r) = item.schedule {
                map[anchorPhase(r), default: []].append(item.title)
            }
        }
        for item in outputs {
            if case .cycleAnchored(let r) = item.schedule {
                map[anchorPhase(r), default: []].append(item.title)
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

    private var seasonsSheet: some View {
        let routines = routinesBySeason
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("계절별 루틴")
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Ink.text.opacity(0.5))
                    .kerning(2)
                Text("나의 사계")
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

    // ── 한 줄 일기 모음 (2026-07-22 사용자 요청 — 오늘 탭 "오늘 한 줄"의 열람 표면) ──
    // 나의 사계 낱장과 별도 카드: 사계는 공유 안전 화면(§3.5.1 메모 렌더 금지)이라 일기는 섞지 않는다.
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
                Text("한 줄 일기")
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

    private func seasonRow(phase: CyclePhase, routines: [String]) -> some View {
        let meta = seasonMeta(for: phase)
        return VStack(alignment: .leading, spacing: 6) {
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
            if routines.isEmpty {
                // 빈 계절 = 밑줄 괘선(빈 낱장도 캡처물 성립 — §3.5.1)
                Rectangle().fill(Ink.winter.opacity(0.18)).frame(height: 1)
                    .padding(.vertical, 8)
            } else {
                ForEach(routines, id: \.self) { name in
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(Ink.text)
                }
            }
        }
        .padding(.vertical, 8)
        .almanacRule()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(meta.name), \(routines.isEmpty ? "루틴 없음" : routines.joined(separator: ", "))")
    }
}
