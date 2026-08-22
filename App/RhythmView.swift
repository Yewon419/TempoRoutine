// 템포루틴 — 나의 리듬 탭 (MASTER §8.2.5 — 2026-08-09 재편 3차: 사계 = 신호 세로 나열)
// 칩 [나의 사계 | 나의 루틴 | 한 줄 기록] (03:08 베타 피드백 "나의 사계 안에 에너지 기분 수면
// 식욕 다 넣어놓되 세로로 쭉 펼쳐놓으란 뜻" — 2차의 신호별 칩 전환 폐기).
//   나의 사계 = 콜드/진행 카드 + 신호 패널 전부 스택(에너지·기분·수면·식욕, 각자 이름표)
//   나의 루틴 = 구 「나의 사계」 낱장 개명(§3.5.1 공유 안전 화면 — 렌더 금지: 날짜·주기 시점·
//               체크인·메모·진행도, 루틴 이름·종류 태그만)
//   한 줄 기록 = 일기 모음(구 하단 상시 카드에서 분리)
// 마지막 본 탭 = AppStorage 복원. 신호 패널·집계 서술은 §5.6.3 계약. 카피 = 프로토 v77 전사.

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
    @State private var lightFeedback = 0   // 작은 햅틱(§4 — 칩 전환, 확정 아님. 2026-08-09 사용자 지시)
    @Query private var selfReports: [SelfReportRecord]
    @State private var showSelfReport = false
    // 단일 칩 행(2026-08-09 베타 피드백 "탭 별도 구분하지말고 한 줄로 쭉") — 2단 스위처 병합.
    // 마지막 본 탭은 재진입·재실행 때 복원("들어갈때마다 마지막 탭" — AppStorage).
    @AppStorage("rhythmLastTab") private var lastTabRaw = RhythmTab.seasons.rawValue
    /// 사계 안의 신호 하위 탭(2026-08-13 사용자: "내리면서 보기 너무 힘들다").
    /// 2026-08-09 재편 3차의 세로 스택을 되돌리되, 신호를 사계 **밖으로** 빼지는 않는다 —
    /// 그때 피드백("사계 안에 에너지·기분·수면을 다 넣어달라")도 같이 지켜야 해서 2단으로 간다.
    @AppStorage("rhythmLastSignal") private var lastSignalRaw = SignalKind.energy.rawValue

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: .now) }
    private var snapshot: CycleSnapshot { CycleSnapshot(periodDays: periodDays) }
    /// 축 프로필 — `P`(생리 전 저컨디션 윈도우) 서술의 출처(§5.3 층 2)
    private var axis: AxisProfile { AxisProfile(checkIns: checkIns, snapshot: snapshot) }
    private var profile: EnergyProfile { EnergyProfile(checkIns: checkIns, snapshot: snapshot) }
    // 유형 카드(비바체·안단테·루바토)는 2026-08-09 사용자 결정으로 UI에서 내림 —
    // 엔진(WindowStats)·내보내기(rhythmSummary)·자기돌봄 소비처(AxisProfile)는 유지.
    private var unlockedPhases: [CyclePhase] { Self.allPhases.filter { profile.level(for: $0) != nil } }

    // ── 신호 패널 입력 (§5.6.3 — DailyCheckIn → SignalSample, 계산은 RhythmEngine) ──
    private var signalSamples: [SignalSample] {
        checkIns.map { SignalSample(day: $0.day, energy: $0.energy, mood: $0.mood,
                                    sleep: $0.sleep, appetite: $0.appetite) }
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
            if ThemeStore.chrome.photographicGround {
                TicketGround(phase: snapshot.phase(on: today))   // 계절 유화 + 스크림(시안 §3)
            } else {
                if ThemeStore.chrome.skyGround {
                    WeatherSky()   // 날씨 = 오늘의 하늘(시안 §5.3-1)
                } else {
                    Ink.paper.ignoresSafeArea()
                    SeasonLight(phase: snapshot.phase(on: today), motif: .open)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 좌상단 브랜드 표식(2026-08-18 사용자 지시) — 오늘·캘린더 탭과 같은 자리·크기
                    HStack {
                        BrandMark(diameter: 22, color: Ink.onGround(Ink.text.opacity(0.75), white: 0.8))
                            .padding(.leading, 6)
                        Spacer()
                    }
                    // 모던 = 아웃라인 표제(시안 §1.3-2 — 표제는 아웃라인 승격 이력)
                    // 「나의 리듬」→「나의 템포」(2026-08-18 사용자 지시 — 앱 이름과 같은 축)
                    almanacDisplay(Loc.str("나의 템포"), size: ThemeStore.chrome.debossDisplay ? 54 : 44,   // 68은 과함(2026-08-18 베타)
                                   color: Ink.onGround(Ink.text, white: 1.0))
                    selfReportPrompt
                    sectionSwitcher
                    switch tab {
                    case .seasons:
                        // 관측 패턴 — 콜드 문법 승계: 서술 가능한 신호가 없으면 진행 카드만.
                        // 네 계절이 다 열리면 진행 카드는 할 일을 끝낸 것 — 내린다(2026-08-18 베타
                        // 피드백 "다 채웠는데 안 없어지나").
                        if unlockedPhases.count < Self.allPhases.count {
                            coldCard
                        }
                        if unlockedPhases.isEmpty {   // 패턴이 하나라도 열리면 일반론 카드는 물러남(2026-07-23)
                            meanwhileCard
                        }
                        if showSwitcher {
                            signalSwitcher    // 신호 하위 칩(2026-08-13)
                            signalStack
                            preWindowNote     // 생리 전 저컨디션 윈도우 서술(§5.3 P 소비처)
                            routineNote       // 계절별 루틴 수행(2026-08-13)
                            cycleLengthNote   // 주기 길이(2026-08-13)
                            predictionErrorNote   // 예측 오차 자가 표시(2026-08-18)
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
            Button("Input") { addKind = .input }
            Button("Output") { addKind = .output }
            Button("취소", role: .cancel) { addingSeason = nil }
        }
        .sheet(isPresented: $showSelfReport) { SelfReportFlow().themeColorScheme() }
        .sheet(item: $addKind, onDismiss: { addingSeason = nil }) { kind in
            Group {
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
            .themeColorScheme()
        }
        // 루틴 행 탭 = 수정 시트(2026-08-08) — 오늘 탭 일정 행과 같은 문법
        .sheet(item: $editingInput) { item in
            InputAddSheet(currentSeason: nil, editing: item).themeColorScheme()
        }
        .sheet(item: $editingOutput) { item in
            OutputAddSheet(editing: item).themeColorScheme()
        }
        .quickDeleteDialog($pendingDelete, completions: completions, context: modelContext)
        .sensoryFeedback(.impact(weight: .medium), trigger: confirmFeedback)
        .sensoryFeedback(.impact(weight: .light), trigger: lightFeedback)
    }

    @Environment(\.modelContext) private var modelContext

    // ── 자기보고 설문 제안 (v1.6 §4) ──
    // 첫 주기를 다 기록한 사람에게 1회만. 그 사람은 이탈 위험이 낮고,
    // 침묵하는 문구의 이유("아직 당신의 이맘때를 모르겠어요")를 이미 체감했다.
    @ViewBuilder
    private var selfReportPrompt: some View {
        if SelfReportStore.shouldPrompt(snapshot: snapshot, records: selfReports) {
            VStack(alignment: .leading, spacing: 10) {
                Text("이맘때 이야기를 하려면 몇 가지를 알아야 해요.")
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

    // ── 칩 3개 (재편 3차 2026-08-09 — 신호별 칩 전환 폐기, 사계 = 세로 나열) ──
    private enum RhythmTab: String, CaseIterable, Identifiable {
        case seasons = "나의 사계"
        case routines = "나의 루틴"
        case diary = "한 줄 기록"
        var id: String { rawValue }
        /// rawValue는 저장 키이자 번역 키 — 표시는 번역을 거친다(2026-08-22 베타 "난리났네")
        var title: String { Loc.text(rawValue) }
    }

    /// 저장된 마지막 탭 복원 — 구 rawValue("에너지" 등)는 init 실패로 사계 폴백
    private var tab: RhythmTab {
        RhythmTab(rawValue: lastTabRaw) ?? .seasons
    }

    private var sectionSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(RhythmTab.allCases) { item in
                chip(label: item.title, selected: tab == item) {
                    lightFeedback += 1   // 칩 전환 햅틱(2026-08-09 사용자 지시)
                    lastTabRaw = item.rawValue
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("보기 선택")
    }

    /// 사계에 올릴 신호 — 수면·식욕은 추적 끔+표본 0이면 숨김(꺼진 항목 거짓 안내 방지, 구 칩 규칙 승계)
    private var visibleSignals: [SignalKind] {
        SignalKind.allCases.filter { signal in
            switch signal {
            case .energy, .mood:
                return true
            case .sleep:
                return AppSettings.trackedSignals.sleep
                    || signalSummaries.contains { $0.signal == .sleep }
            case .appetite:
                return AppSettings.trackedSignals.appetite
                    || signalSummaries.contains { $0.signal == .appetite }
            }
        }
    }

    // ── 계절별 루틴 수행 (2026-08-13) ──
    // 이 앱만 만들 수 있는 통계다 — 주기 앱은 플래너가 없고 플래너는 주기가 없다.
    // ⚠ **「수행률」이 아니라 「하루당 마친 수」**로 잡는다. 예정 occurrence를 분모로 쓰면
    //   앱을 안 연 날이 전부 실패로 잡혀 통계가 왜곡되고, 백분율은 낮은 계절에서 자책을
    //   부른다(§7 재촉 금지). 계절 길이로 나눈 밀도만 비교하고 **비율은 표시하지 않는다.**
    // ⚠ 집계를 TempoCore로 안 뺀 이유: 핵심이 계절 판정(CycleSnapshot, 앱 소유)이고
    //   남는 건 max/min뿐이라 옮길 실익이 없다. 통계적 집계인 신호 패널과는 성격이 다르다.
    private var routineDensityByPhase: [CyclePhase: Double] {
        var done: [CyclePhase: Int] = [:]
        var days: [CyclePhase: Set<Date>] = [:]
        let cal = Calendar.current
        for completion in completions {
            let day = cal.startOfDay(for: completion.occurredOn)
            guard let phase = snapshot.phase(on: day) else { continue }
            done[phase, default: 0] += 1
        }
        // 분모 = 그 계절로 판정된 날 수(기록 구간 안에서만)
        guard let first = completions.map({ cal.startOfDay(for: $0.occurredOn) }).min() else { return [:] }
        var cursor = first
        let end = today
        while cursor <= end {
            if let phase = snapshot.phase(on: cursor) { days[phase, default: []].insert(cursor) }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? end.addingTimeInterval(1)
        }
        return done.reduce(into: [:]) { acc, pair in
            let count = days[pair.key]?.count ?? 0
            if count > 0 { acc[pair.key] = Double(pair.value) / Double(count) }
        }
    }

    /// 임계 — 계절 2개 이상 + 완료 12건 이상일 때만 말한다. 그 아래선 우연이 패턴처럼 읽힌다.
    @ViewBuilder
    private var routineNote: some View {
        let density = routineDensityByPhase
        if density.count >= 2, completions.count >= 12,
           let top = density.max(by: { $0.value < $1.value }) {
            VStack(alignment: .leading, spacing: 6) {
                Text("계절과 루틴")
                    .font(.almanacBody(.footnote, size: 12))
                    .foregroundStyle(Ink.text.opacity(0.5))
                Text(Loc.fmt("기록상 %1$@에 계획한 걸 가장 많이 수행했어요.", "\(seasonMeta(for: top.key).name)"))
                    .font(.almanacBody(.subheadline, size: 15))
                    .foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Loc.fmt("마친 기록 %1$@건 기준", "\(completions.count)"))
                    .font(.caption)
                    .foregroundStyle(Ink.text.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .milkGlass()
        }
    }

    // ── 주기 길이 (2026-08-13) ──
    // ⚠ 추세 서술("짧아지고 있어요")은 단정이라 금지(§7 의료 레인). 숫자만 담백하게 놓는다.
    //   유효 범위 [21,35] 필터는 예측 엔진 v1.1과 같은 기준 — 기록 공백이 만든 gap을 뺀다.
    private var recentCycleLengths: [Int] {
        let starts = snapshot.starts.sorted()
        guard starts.count >= 2 else { return [] }
        let cal = Calendar.current
        return zip(starts, starts.dropFirst()).compactMap { a, b in
            let gap = cal.dateComponents([.day], from: a, to: b).day ?? 0
            return (21...35).contains(gap) ? gap : nil
        }
    }

    @ViewBuilder
    private var cycleLengthNote: some View {
        let lengths = recentCycleLengths
        if let last = lengths.last, lengths.count >= 2 {
            let lo = lengths.min() ?? last
            let hi = lengths.max() ?? last
            VStack(alignment: .leading, spacing: 6) {
                Text("주기 길이")
                    .font(.almanacBody(.footnote, size: 12))
                    .foregroundStyle(Ink.text.opacity(0.5))
                Text(Loc.fmt("최근 주기 %1$@일", "\(last)"))
                    .font(.almanacBody(.subheadline, size: 15))
                    .foregroundStyle(Ink.text)
                Text(lo == hi ? Loc.fmt("기록된 %1$@주기 모두 %2$@일", "\(lengths.count)", "\(lo)")
                              : Loc.fmt("기록된 %1$@주기 %2$@~%3$@일", "\(lengths.count)", "\(lo)", "\(hi)"))
                    .font(.caption)
                    .foregroundStyle(Ink.text.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .milkGlass()
        }
    }

    // ── 예측 오차 자가 표시 (2026-08-18) ──
    // ⚠ 미래 단정 아님 — 과거 예측이 실제와 얼마나 어긋났는지의 기록 서술(§7 의료 레인).
    //   산식 = TempoCore predictionErrors(analyze_export.py 백테스트와 동일) — 유효 오차 최근 5개.
    private var recentPredictionErrors: [Int] {
        CyclePredictor.predictionErrors(startDates: snapshot.starts,
                                        priorLength: AppSettings.cycleLengthPrior)
    }

    @ViewBuilder
    private var predictionErrorNote: some View {
        let errors = recentPredictionErrors
        if errors.count >= 2 {   // 표본 1개는 우연 — 주기 길이 카드(≥2)와 같은 임계
            let mae = Double(errors.map(abs).reduce(0, +)) / Double(errors.count)
            let m = Int(mae.rounded())
            VStack(alignment: .leading, spacing: 6) {
                Text("예측 정확도")
                    .font(.almanacBody(.footnote, size: 12))
                    .foregroundStyle(Ink.text.opacity(0.5))
                Text(m == 0 ? Loc.fmt("지난 %lld번, 예측한 날에 시작했어요.", errors.count)
                            : Loc.fmt("지난 %1$@번, 예측과 실제가 평균 %2$@일 차이였어요.", "\(errors.count)", "\(m)"))
                    .font(.almanacBody(.subheadline, size: 15))
                    .foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("기록된 시작일과 그때까지의 예측을 비교한 값")
                    .font(.caption)
                    .foregroundStyle(Ink.text.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .milkGlass()
        }
    }

    /// 생리 전 저컨디션 윈도우(§5.3 층 2 `P`) 서술. MASTER가 「나의 사계 가을 서사」를 P의
    /// 소비처로 지정해뒀는데 실제 소비처는 하루 상세뿐이었다(2026-08-13 보완).
    /// ⚠ 단정 금지 — 과거형 + 「기록상」(신호 패널과 같은 문법). 채택값이 기본값이면 침묵한다
    /// (학습된 게 없는데 숫자를 말하면 근거 없는 단정이 된다).
    @ViewBuilder
    private var preWindowNote: some View {
        if let learned = axis.preMenstrualWindow, learned > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text("겨울로 넘어가기 전")
                    .font(.almanacBody(.footnote, size: 12))
                    .foregroundStyle(Ink.text.opacity(0.5))
                Text(Loc.fmt("기록상 생리 시작 %1$@일 전부터 컨디션이 낮게 기록됐어요.", "\(learned)"))
                    .font(.almanacBody(.subheadline, size: 15))
                    .foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .milkGlass()
        }
    }

    /// 선택된 신호 — 저장값이 지금 숨김 상태면 첫 노출 신호로 떨어진다(수면·식욕 추적 끔 대응)
    private var selectedSignal: SignalKind {
        let saved = SignalKind(rawValue: lastSignalRaw)
        if let saved, visibleSignals.contains(saved) { return saved }
        return visibleSignals.first ?? .energy
    }

    /// 신호 하위 칩 행 — 사계 안에서만 도는 2단 스위처
    private var signalSwitcher: some View {
        // 하위 스위처는 상위(캡슐 칩)와 모양을 가른다(2026-08-18 베타 "같은 준위같아") —
        // 텍스트 + 선택 밑줄. 캡슐이 두 줄이면 층위가 안 읽혔다.
        HStack(spacing: 18) {
            ForEach(visibleSignals, id: \.self) { signal in
                signalTab(label: signalLabel(signal), selected: selectedSignal == signal) {
                    lightFeedback += 1
                    lastSignalRaw = signal.rawValue
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("신호 선택")
    }

    /// 하위 탭 — 텍스트 + 2pt 밑줄(선택). 캡슐(상위 섹션 칩)보다 한 층 아래로 읽힌다.
    /// 티켓 유화 지면 위에서는 잉크가 묻혀 흰 계열(§3.3-⑥ 연장).
    private func signalTab(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        let base: Color = ThemeStore.chrome.photographicGround ? .white : Ink.text
        return Button(action: action) {
            VStack(spacing: 3) {
                Text(label)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(base.opacity(selected ? 1 : 0.45))
                Rectangle()
                    .fill(selected ? base : .clear)
                    .frame(height: 2)
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func signalLabel(_ signal: SignalKind) -> String {
        switch signal {
        case .energy: Loc.str("에너지")
        case .mood: Loc.str("기분")
        case .sleep: Loc.str("수면")
        case .appetite: Loc.str("식욕")
        }
    }

    /// 선택 신호 패널 하나만(2026-08-13 — 종전 전량 세로 스택은 스크롤이 너무 길었다)
    private var signalStack: some View {
        Group {
            let signal = selectedSignal
            SignalPanel(signal: signal,
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
    }

    /// 칩 공용 렌더 — v68 칩 시각 그대로(2026-08-09 단일 행 병합 후에도 유지).
    @ViewBuilder
    private func chip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        if ThemeStore.chrome.photographicGround {
            // 티켓 = 지면 위 칩(시안 흰 덮기 목록): 미선택 흰 윤곽 + 직각 R3(발권물),
            // 선택 = 잉크 솔리드에 발권지 글자. Ink.paper는 이 테마에서 블루그레이 지면색이라 못 쓴다.
            Button(action: action) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(selected ? TicketSpec.ticketPaper : .white.opacity(0.78))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(selected ? AnyShapeStyle(Ink.text) : AnyShapeStyle(.clear),
                                in: RoundedRectangle(cornerRadius: 3))
                    .overlay {
                        if !selected {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.white.opacity(0.38), lineWidth: 1)
                        }
                    }
            }
            .accessibilityAddTraits(selected ? [.isSelected] : [])
        } else {
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
    }

    // ── 콜드스타트 카드 (§8.2.5 개정 2026-07-23 — "약 41일" 폐기) ──
    // 날짜 약속 대신 가까운 마일스톤: 이번 계절 기록 3회(EnergyProfile.minSamples) → 네 계절 채우기.
    private var progressInfo: (progress: Double, title: String, body: String, label: String) {
        if snapshot.isColdStart {
            return (0, Loc.str("첫 패턴을 기다리는 중"), Loc.str("당신만의 패턴이 보이기 시작할 거예요."),
                    Loc.str("첫 생리일을 기록하면 시작돼요"))
        }
        let goal = EnergyProfile.minSamples
        let curPhase = snapshot.phase(on: today)
        let curName = curPhase.map { seasonMeta(for: $0).name } ?? Loc.str("이번 계절")
        let curCount = curPhase.map { min(goal, profile.sampleCount(for: $0)) } ?? 0
        let unlocked = unlockedPhases
        if unlocked.isEmpty {
            let body = curCount == 0
                ? Loc.fmt("%1$@의 에너지를 세 번 기록하면, 이 계절의 첫 패턴이 보여요.", "\(curName)")
                : Loc.fmt("%1$@의 에너지 기록이 %2$@번 쌓였어요. 세 번이면 이 계절의 첫 패턴이 보여요.", "\(curName)", "\(curCount)")
            return (Double(curCount) / Double(goal), Loc.str("첫 패턴을 기다리는 중"), body,
                    Loc.fmt("%1$@ 기록 %2$@ / %3$@", "\(curName)", "\(curCount)", "\(goal)"))
        }
        let names = unlocked.map { seasonMeta(for: $0).name }.joined(separator: "·")
        // 「채워지면」 뒤에서 줄바꿈(2026-08-16 베타 피드백) — "거에요"만 다음 줄로 넘어가던 것
        var body = Loc.fmt("%1$@의 패턴이 보이기 시작했어요. 네 계절이 모두 채워지면\n리듬 전체가 이어질 거에요.", "\(names)")
        if let phase = curPhase, profile.level(for: phase) == nil {
            body += Loc.fmt(" %1$@은 %2$@ / %3$@회째예요.", "\(curName)", "\(curCount)", "\(goal)")
        }
        return (Double(unlocked.count) / 4.0, Loc.str("패턴이 보이기 시작했어요"), body,
                Loc.fmt("네 계절 중 %1$@", "\(unlocked.count)"))
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
            Group {
                if ThemeStore.chrome.playlistChrome {
                    // 플레이리스트 = 시크바 문법(시안 §4.4 ⑧ — 두툼한 바는 이 테마에서 이질적)
                    PlaylistSeekBar(progress: info.progress)
                } else {
                    GeometryReader { geo in
                        // 모던 = 니어블랙 대비 상향(시안 §1.3-7): 트랙 12%·채움 75%
                        let modern = ThemeStore.chrome.boostsContrast
                        ZStack(alignment: .leading) {
                            Capsule().fill(Ink.text.opacity(modern ? 0.12 : 0.08))
                            Capsule().fill(Ink.text.opacity(modern ? 0.75 : 0.55))
                                .frame(width: max(6, geo.size.width * info.progress))
                        }
                    }
                    .frame(height: 6)
                }
            }
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
            Text("많은 사람이 겨울엔 에너지가 낮아진다고 느껴요. 당신의 리듬도 금방 찾게 될 거에요.")
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

        /// 주기 반복 정의 — 일차 정렬·뱃지의 근거(2026-08-18 타임라인 개편)
        var recurrence: CycleRecurrence? {
            switch self {
            case .input(let item):
                if case .cycleAnchored(let r) = item.schedule { return r }
            case .output(let item):
                if case .cycleAnchored(let r) = item.schedule { return r }
            }
            return nil
        }

        /// 정렬 키 — 계절 전체(매일)가 맨 앞, 그 뒤 일차 오름차순
        var sortDay: Int {
            guard let r = recurrence else { return .max }
            return r.spansWholePhase ? -1 : r.dayOffset
        }

        /// 일차 뱃지 — 「매일」(계절 전체) / 「N일차」. 앵커 일차는 **계획의 속성**이라
        /// 낱장 렌더 허용(§3.5.1 개정 2026-08-18 — 개인 계절 길이·오늘 위치는 여전히 금지).
        var dayBadge: String {
            guard let r = recurrence else { return "" }
            return r.spansWholePhase ? Loc.str("매일") : Loc.fmt("%1$@일차", "\(r.dayOffset + 1)")
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
        // 일차 순 정렬(2026-08-18 타임라인 개편) — 계절 안에서 며칠차에 뭘 하는지가
        // 계획의 축이라, 등록 순이 아니라 시간 순으로 세운다. 매일(계절 전체)이 맨 앞.
        return map.mapValues { $0.sorted { ($0.sortDay, $0.title) < ($1.sortDay, $1.title) } }
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
            cycleGrid   // 주기 한 바퀴 지도(2026-08-18 사용자 지시 — "봄 몇 칸, 여름 몇 칸")
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
                Text(entry.day.formatted(Loc.dateTime.month().day().weekday(.abbreviated)))
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
        .accessibilityLabel("\(entry.day.formatted(Loc.dateTime.month().day())), \(meta?.name ?? ""), \(entry.note ?? "")")
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
                .accessibilityLabel(Loc.fmt("%1$@에 루틴 추가", "\(meta.name)"))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(routines.isEmpty ? Loc.fmt("%1$@, 루틴 없음", "\(meta.name)") : meta.name)
            // 빈 계절 = 여백 + 행 구분 괘선만(빈 낱장도 캡처물 성립 — §3.5.1).
            // 안쪽 괘선은 행 구분선과 겹쳐 이중 줄로 보여 걷음(2026-08-08 조판).
            ForEach(routines) { routine in
                routineRow(routine)
            }
        }
        .padding(.vertical, routines.isEmpty ? 12 : 8)
        .almanacRule()
    }

    // ── 주기 한 바퀴 지도 (2026-08-18 사용자 지시 — "한 달 주기를 볼 수 있는 표") ──
    // 평균 주기를 1일차부터 7열 그리드로 펼친다. 칸 색 = 그 일차의 계절(§5.3 경계),
    // 점 = 그 일차에 걸린 루틴. 주기 순서(겨울 시작)가 시간 축 — 나열 UI의 봄 우선 규칙(§8.1)은
    // 범례·패널용이고 이 표는 타임라인이라 엔진 순서를 따른다.
    // ⚠ §3.5.1 재개정: 이 표는 개인 계절 길이를 드러낸다 — 사용자 결정으로 공유 안전 성격을
    //   일부 양보(2026-08-18. 오늘이 며칠차인지는 여전히 렌더하지 않는다).
    /// 지도 칸 하나 — 계절 + 계절 내 일차(1-indexed)
    private struct GridSlot: Hashable, Identifiable {
        let phase: CyclePhase
        let dayInPhase: Int
        var id: String { "\(phase)-\(dayInPhase)" }
    }

    /// 탭한 칸의 목적지 날짜 — sheet(item:) 식별용 래퍼
    private struct GridDestination: Identifiable {
        let day: Date
        var id: Date { day }
    }

    private var cycleGrid: some View {
        // 표시 순서 = 봄→여름→가을→겨울(2026-08-18 2차 사용자 지시 — 겨울 맨 뒤).
        // 칸 숫자는 **계절 내 일차** — 주기 일차를 유지하면 봄 시작 배열에서 6, 7, …, 1로
        // 뒤섞인다. 앱 전 표면의 일차 표기(2026-08-09 통일)와도 이쪽이 정합.
        let spans = CyclePredictor.phaseSpans(cycleLength: snapshot.averageLength,
                                              menstrualLength: snapshot.menstrualLength)
        let ordered = CyclePhase.displayOrder.compactMap { phase in
            spans.first { $0.phase == phase }
        }
        let slots = ordered.flatMap { span in
            (1...max(1, span.length)).map { GridSlot(phase: span.phase, dayInPhase: $0) }
        }
        let routineSlots = routineSlotMap(spans: spans)
        let wholePhases = wholePhaseRoutinePhases()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
        return VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(slots) { slot in
                    cycleGridCell(slot: slot, hasRoutine: routineSlots.contains(slot),
                                  seasonWide: wholePhases.contains(slot.phase))
                }
            }
            // 계절별 일수 캡션 — "봄 몇 칸"을 숫자로도 읽게. 값은 §5.3 경계 그대로.
            Text(ordered.map { Loc.fmt("%1$@ %2$@일", "\(seasonMeta(for: $0.phase).name)", "\($0.length)") }
                    .joined(separator: " · ") + Loc.fmt(" · 평균 주기 %1$@일 기준", "\(snapshot.averageLength)"))
                .font(.caption2)
                .foregroundStyle(Ink.text.opacity(0.45))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .milkGlass(radius: 14)
        .sheet(item: $gridDestination) { destination in
            // 칸 = 그 위상이 **다음으로 오는 날** — 하루 상세를 그대로 연다(헤더가 「봄 n일차」
            // 문법이고 Input·Output 추가가 이미 그 안에 있다. 2026-08-18 2차 사용자 지시).
            NavigationStack { DayDetailView(day: destination.day, presetsCycleAnchor: true) }
                .themeColorScheme()
        }
    }

    @State private var gridDestination: GridDestination?

    private func cycleGridCell(slot: GridSlot, hasRoutine: Bool, seasonWide: Bool) -> some View {
        let meta = seasonMeta(for: slot.phase)
        return Button {
            guard let day = nextDate(of: slot) else { return }   // 콜드·지평 밖 = 무시
            lightFeedback += 1
            gridDestination = GridDestination(day: day)
        } label: {
            VStack(spacing: 1) {
                Text("\(slot.dayInPhase)")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(Ink.text.opacity(0.65))
                // 채운 점 = 특정 일차 루틴 / 윤곽 점 = 계절 전체 루틴(2026-08-20 사용자 결정 —
                // 목록엔 「매일」 배지로 뜨는데 지도엔 아무 표시가 없어 어긋나 보이던 것)
                if hasRoutine {
                    Circle().fill(Ink.text.opacity(0.75)).frame(width: 4, height: 4)
                } else if seasonWide {
                    Circle().stroke(Ink.text.opacity(0.4), lineWidth: 1).frame(width: 4, height: 4)
                } else {
                    Circle().fill(.clear).frame(width: 4, height: 4)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(meta.glow.opacity(0.32), in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Loc.fmt("%1$@ %2$@일차%3$@", "\(meta.name)", "\(slot.dayInPhase)", "\(hasRoutine ? Loc.str(", 루틴 있음") : "")"))
    }

    /// 그 위상(계절 s의 d일차)이 다음으로 오는 절대 날짜 — 오늘부터 두 주기치 스캔.
    /// 경계·투영 규칙을 새로 만들지 않고 전부 phaseInfo(§5.3·§5.6.2)에 위임한다.
    private func nextDate(of slot: GridSlot) -> Date? {
        for offset in 0...(snapshot.averageLength * 2 + 7) {
            guard let day = cal.date(byAdding: .day, value: offset, to: today),
                  let info = snapshot.phaseInfo(on: day) else { continue }
            if info.meta.phase == slot.phase,   // 이름이 아니라 단계로(표시명은 번역된다)
               info.dayInPhase == slot.dayInPhase {
                return day
            }
        }
        return nil
    }

    /// 계절 전체(매일) 루틴이 걸린 계절 집합 — 그 계절 전 칸에 윤곽 점(2026-08-20 사용자 결정)
    private func wholePhaseRoutinePhases() -> Set<CyclePhase> {
        var phases = Set<CyclePhase>()
        for routine in routinesBySeason.values.joined() {
            guard let r = routine.recurrence, r.spansWholePhase else { continue }
            switch r.anchor {
            case .cycleStart: phases.insert(.menstrual)
            case .phase(let p): phases.insert(p)
            }
        }
        return phases
    }

    /// 루틴이 걸린 칸 집합 — 앵커 계절의 dayOffset+1(계절 내 일차, §5.5.3 기본 clamp).
    /// 계절 전체(매일) 루틴은 특정일 점이 아니라 계절 전 칸 윤곽 점으로(위 함수) — 여기선 제외.
    private func routineSlotMap(spans: [PhaseSpan]) -> Set<GridSlot> {
        var slots = Set<GridSlot>()
        for routine in routinesBySeason.values.joined() {
            guard let r = routine.recurrence, !r.spansWholePhase else { continue }
            let anchorPhase: CyclePhase = {
                switch r.anchor {
                case .cycleStart: .menstrual
                case .phase(let p): p
                }
            }()
            guard let span = spans.first(where: { $0.phase == anchorPhase }) else { continue }
            slots.insert(GridSlot(phase: anchorPhase,
                                  dayInPhase: min(r.dayOffset + 1, span.length)))
        }
        return slots
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
                // 일차 뱃지(2026-08-18 타임라인 개편) — 고정 폭 왼쪽 컬럼이라 세로로 훑으면
                // 그 계절의 계획표로 읽힌다. 「매일」 = 계절 전체 모드.
                Text(routine.dayBadge)
                    .font(.almanacBody(.caption, size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Ink.text.opacity(0.5))
                    .frame(width: 46, alignment: .trailing)
                Text(routine.title)
                    .font(.subheadline)
                    .foregroundStyle(Ink.text)
                Spacer(minLength: 8)
                Text(routine.kindLabel)
                    .font(.caption2)
                    .foregroundStyle(Ink.text.opacity(0.4))
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(quickDeleteGesture(routine.deleteTarget, into: $pendingDelete,
                                                feedback: $confirmFeedback))
        .accessibilityHint("탭하면 수정, 길게 누르면 삭제할 수 있어요")
        .accessibilityAction(named: Loc.str("삭제")) { pendingDelete = routine.deleteTarget }
    }
}
