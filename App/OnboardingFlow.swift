// 템포루틴 — 온보딩 4단계 (Phase 0 ⑧, MASTER §3.10 / §8.2.1 — 카피는 프로토 v77 확정본 전사)
// ① 인트로 탭 진행 3장면(원 드로잉→사이클 싱킹 곡선→네 계절, 자동 타이머 없음·Reduce Motion=완성 상태)
// ② 기준일 3분기(건강 앱 연동 스위치=시스템 권한 / 직접 입력=트래커 재사용[사용자 결정] / 기억 안 나요)
// ③ 추적 항목(에너지·기분 기본 + 옵션 4종 → TrackedSignals) ④ 저장 위치 조건부 카피+체크 카드.
// 진행 점은 인트로 숨김·2단계부터. 실권한은 실제 연동 순간만(§3.6.1).

import SwiftUI
import SwiftData
import TempoCore

extension View {
    /// 스태거 등장 — 시안 `ob-in` 이식(fade + translateY 10px, ease-out + delay). reduceMotion=true면 애니메이션 없이 즉시 표시.
    func staggerIn(_ appeared: Bool, delay: Double, duration: Double = 0.42, reduceMotion: Bool) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(reduceMotion ? nil : .easeOut(duration: duration).delay(delay), value: appeared)
    }

    /// 페이드만(오프셋 없음) — 시안 `node-in` 이식. SVG 노드처럼 이미 배치된 요소에 사용(§ 노드 opacity만).
    func fadeIn(_ appeared: Bool, delay: Double, duration: Double = 0.38, reduceMotion: Bool) -> some View {
        opacity(appeared ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: duration).delay(delay), value: appeared)
    }
}

struct OnboardingFlow: View {
    @AppStorage("onboardingDone") private var onboardingDone = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \PeriodDay.day) private var periodDays: [PeriodDay]

    @State private var step = 1
    @State private var introScene = 0          // 0=A 브랜드·원 / 1=B 곡선 / 2=C 네 계절
    @State private var drawProgress: CGFloat = 0
    @State private var sceneAppeared = false    // 씬A 전용 스태거 트리거(Phase 1 — 씬B·C는 기존 drawProgress 유지, Phase 2에서 정합)
    @State private var introEntered = false     // "시작/다음" 버튼 1000ms 지연 노출 — 스텝1 (재)진입마다 리셋
    @State private var lightFeedback = 0        // 작은 햅틱(§4 — 단계 진행·토글, 확정 아님)

    // ② 기준일
    @State private var dateSource = 0          // 0=건강 앱 / 1=직접 입력 / 2=기억 안 나요
    @State private var showTracker = false
    private let mirror = HealthMirror.shared

    // ③ 추적 항목
    @State private var trackSleep = true
    @State private var trackPain = false
    @State private var trackAppetite = false
    @State private var trackNote = true

    var body: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()
            SeasonLight(phase: .menstrual, motif: .onboarding)   // 온보딩 = 겨울 배경 고정(사용자 확정)
            VStack(alignment: .leading, spacing: 0) {
                topBar
                Group {
                    switch step {
                    case 1: intro
                    case 2: baselineStep
                    case 3: signalsStep
                    default: storageStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sheet(isPresented: $showTracker) { PeriodTrackerSheet() }
        .sensoryFeedback(.impact(weight: .light), trigger: lightFeedback)
        .task(id: step) {
            guard step == 1 else { return }
            introEntered = false
            guard !reduceMotion else { introEntered = true; return }
            try? await Task.sleep(nanoseconds: 30_000_000)
            introEntered = true
        }
    }

    // ── 하단 액션 바 — 전 스텝 공통 위치(2026-07-22 베타 피드백: 버튼 위치 통일·점과 겹침 정정) ──
    private var bottomBar: some View {
        VStack(spacing: 10) {
            primaryButton(primaryLabel, action: primaryAction)
                .staggerIn(step == 1 ? introEntered : true, delay: step == 1 ? 1.0 : 0, reduceMotion: reduceMotion)
                .allowsHitTesting(step != 1 || introEntered || reduceMotion)
            if step >= 2 { dots }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var primaryLabel: String {
        switch step {
        case 1: introScene == 0 ? "시작" : "다음"
        case 2, 3: "다음"
        default: "오늘 화면으로"
        }
    }

    private func primaryAction() {
        switch step {
        case 1: advanceIntro()
        case 2: step = 3
        case 3:
            AppSettings.trackedSignals = TrackedSignals(sleep: trackSleep, pain: trackPain,
                                                        appetite: trackAppetite, note: trackNote)
            step = 4
        default: onboardingDone = true
        }
    }

    // ── 상단: back (2단계부터) ──
    private var topBar: some View {
        HStack {
            if step >= 2 {
                Button {
                    lightFeedback += 1
                    step -= 1
                    if step == 1 { introScene = 2 }
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(Ink.text.opacity(0.6))
                        .frame(width: 44, height: 44)
                }
            }
            Spacer()
        }
        .frame(height: 44)
    }

    // ── 진행 점 (인트로 숨김) — 지난·현재 스텝 채움 + 현재 스텝만 알약형(시안 .ob-dot 이식) ──
    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(1...4, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Ink.text : Ink.text.opacity(0.22))
                    .frame(width: i == step ? 16 : 6, height: 6)
                    .animation(.easeOut(duration: 0.2), value: step)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            lightFeedback += 1
            action()
        } label: {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Ink.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Ink.text, in: Capsule())
        }
    }

    // ══ ① 인트로 3장면 ══
    private var intro: some View {
        Group {
            switch introScene {
            case 0: sceneBrand
            case 1: sceneWave
            default: sceneSeasons
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { advanceIntro() }
        .transition(.opacity)   // 씬 전환 크로스페이드(시안 500ms — advanceIntro의 withAnimation이 구동)
        .task(id: introScene) {
            sceneAppeared = false
            if introScene != 0 { startDrawing() }   // 씬B·C는 기존 방식 유지(Phase 2에서 정합)
            guard !reduceMotion else { sceneAppeared = true; return }
            try? await Task.sleep(nanoseconds: 30_000_000)   // 상태 변화가 관측되도록 한 틱 양보
            sceneAppeared = true
        }
    }

    private func advanceIntro() {
        if introScene < 2 {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) { introScene += 1 }
        } else {
            step = 2
        }
    }

    private func startDrawing() {
        drawProgress = 0
        if reduceMotion {
            drawProgress = 1        // Reduce Motion = 완성 상태 즉시 스왑(§8.2.1)
        } else {
            withAnimation(.easeInOut(duration: 1.1)) { drawProgress = 1 }
        }
    }

    private var sceneBrand: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("템포루틴")
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.5))
                .kerning(2)
            Text("당신 몸의\n템포에 맞게.")
                .font(.almanac(size: 38, weight: .bold))
                .foregroundStyle(Ink.text)
                .lineSpacing(4)
            VStack(alignment: .leading, spacing: 2) {
                Text("몰아치지 않아도 괜찮아요.")
                    .staggerIn(sceneAppeared, delay: 0.30, duration: 0.48, reduceMotion: reduceMotion)
                Text("주기를 네 계절로 보고,")
                    .staggerIn(sceneAppeared, delay: 0.56, duration: 0.48, reduceMotion: reduceMotion)
                Text("계절에 맞게 계획하는 플래너예요.")
                    .staggerIn(sceneAppeared, delay: 0.82, duration: 0.48, reduceMotion: reduceMotion)
            }
            .font(.system(.body, design: .serif))
            .foregroundStyle(Ink.text.opacity(0.75))
            Spacer()
            cycleWheel
                .frame(maxWidth: .infinity)
            Spacer()
        }
    }

    private static let wheelPhases: [CyclePhase] = [.menstrual, .follicular, .ovulation, .luteal]
    private static let wheelNodeDelays: [Double] = [1.36, 1.68, 2.06, 2.44]   // 시안 ob-node-winter~autumn
    private static let wheelGapHalf: CGFloat = 0.035   // 노드당 원 스트로크 gap 절반 폭(트림 프랙션, 약 12.6° — 글리프+라벨 폭 커버, 2026-07-22 재조정)

    /// 주기 원 드로잉 — 은필 원(1.5s, 1.3s 지연 후) + 4계절 노드(원이 지나가는 시점에 개별 페이드인)
    private var cycleWheel: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: sceneAppeared ? 1 : 0)
                .stroke(Ink.winter.opacity(0.7), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.5).delay(1.3), value: sceneAppeared)
            if sceneAppeared { ringGapErasers }   // 헤일로 대신 원 자체를 노드 위치에서 끊음(2026-07-22 베타 피드백)
            ForEach(Array(Self.wheelPhases.enumerated()), id: \.offset) { index, phase in
                let angle = Double(index) * 90.0 - 90.0
                let meta = seasonMeta(for: phase)
                VStack(spacing: 4) {
                    SeasonGlyph(phase: phase, size: 14)
                    Text(meta.name)
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(meta.color)
                }
                .fadeIn(sceneAppeared, delay: Self.wheelNodeDelays[index], reduceMotion: reduceMotion)
                .offset(x: 95 * cos(angle * .pi / 180), y: 95 * sin(angle * .pi / 180))
            }
        }
        .frame(width: 190, height: 190)
        .padding(.vertical, 12)
        .accessibilityHidden(true)
    }

    /// 계절 노드 위치에서 원 스트로크를 끊는다 — 헤일로 대신(2026-07-22 베타 피드백: "가독성 높이지 말고 큰 원을 계절 위치에서 끊는 식으로")
    private var ringGapErasers: some View {
        ForEach(0..<4, id: \.self) { index in
            let t = CGFloat(index) * 0.25
            let half = Self.wheelGapHalf
            Circle()
                .trim(from: max(0, t - half), to: min(1, t + half))
                .stroke(Ink.paper, style: StrokeStyle(lineWidth: 1.4 + 2, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            if index == 0 {
                Circle()   // 이음매(0≡1 = 겨울 위치) 반대편도 지워야 대칭으로 끊김
                    .trim(from: 1 - half, to: 1)
                    .stroke(Ink.paper, style: StrokeStyle(lineWidth: 1.4 + 2, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    private var sceneWave: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("사이클 싱킹")
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.5))
                .kerning(2)
            Text("리듬에 맞춰\n계획하는 법")
                .font(.almanac(size: 32, weight: .bold))
                .foregroundStyle(Ink.text)
                .lineSpacing(4)
            VStack(alignment: .leading, spacing: 2) {
                Text("한 주기 안에서도 에너지와 컨디션은 오르내려요.")
                Text("사이클 싱킹은 그 흐름을 거스르는 대신,")
                Text("계획을 리듬에 맞추는 방법이에요.")
            }
            .font(.system(.subheadline, design: .serif))
            .foregroundStyle(Ink.text.opacity(0.75))
            Spacer()
            energyWave
                .frame(height: 150)
                .frame(maxWidth: .infinity)
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("사람마다 리듬은 달라요.")
                Text("템포루틴은 당신의 기록에서 당신의 리듬을 찾아요.")
            }
            .font(.system(.footnote, design: .serif))
            .foregroundStyle(Ink.text.opacity(0.55))
        }
    }

    /// 에너지 흐름 곡선 드로잉 (겨울 저점→봄 상승→여름 정점→가을 하강) + 글리프 라벨 4점
    private var energyWave: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                EnergyWaveShape()
                    .trim(from: 0, to: drawProgress)
                    .stroke(Ink.winter.opacity(0.7), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                waveLabel(.menstrual, visible: drawProgress > 0.05)
                    .position(x: w * 0.07, y: h * 0.86)
                waveLabel(.follicular, visible: drawProgress > 0.35)
                    .position(x: w * 0.33, y: h * 0.28)
                waveLabel(.ovulation, visible: drawProgress > 0.55)
                    .position(x: w * 0.54, y: h * 0.06)
                waveLabel(.luteal, visible: drawProgress > 0.85)
                    .position(x: w * 0.81, y: h * 0.76)
            }
        }
        .accessibilityHidden(true)
    }

    private func waveLabel(_ phase: CyclePhase, visible: Bool) -> some View {
        let meta = seasonMeta(for: phase)
        return VStack(spacing: 3) {
            SeasonGlyph(phase: phase, size: 12)
            Text(meta.name).font(.system(size: 11, design: .serif)).foregroundStyle(meta.color)
        }
        .opacity(visible ? 1 : 0)
    }

    private var sceneSeasons: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("주기를 네 계절로\n볼게요.")
                .font(.almanac(size: 32, weight: .bold))
                .foregroundStyle(Ink.text)
                .lineSpacing(4)
                .padding(.bottom, 6)
            seasonRow(.menstrual, "월경기 · 쉬어가는 때")
            seasonRow(.follicular, "난포기 · 가볍게 시작하는 때")
            seasonRow(.ovulation, "배란기 · 빛나도 좋은 때")
            seasonRow(.luteal, "황체기 · 매듭짓는 때")
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("일반적인 경향이에요.")
                Text("당신의 계절은 기록이 쌓이며 당신에게 맞춰져요.")
            }
            .font(.system(.footnote, design: .serif))
            .foregroundStyle(Ink.text.opacity(0.55))
        }
    }

    private func seasonRow(_ phase: CyclePhase, _ desc: String) -> some View {
        let meta = seasonMeta(for: phase)
        return HStack(spacing: 12) {
            SeasonGlyph(phase: phase, size: 14)
            Text(meta.name)
                .font(.system(.body, design: .serif).weight(.bold))
                .foregroundStyle(meta.color)
                .frame(width: 40, alignment: .leading)
            Text(desc)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.7))
            Spacer()
        }
        .padding(.vertical, 13)   // 계절 행 간 간격 확대(2026-07-22 베타 피드백)
        .almanacRule(opacity: 0.18)
    }

    // ══ ② 기준일 ══
    private var baselineStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(eyebrow: "기준일", title: "마지막 생리는\n언제 시작했나요?")
            VStack(alignment: .leading, spacing: 2) {
                Text("계절을 맞추는 기준이에요.")
                Text("나중에 캘린더에서 바꿀 수 있어요.")
            }
            .font(.system(.footnote, design: .serif))
            .foregroundStyle(Ink.text.opacity(0.55))
            VStack(alignment: .leading, spacing: 14) {
                Picker("기준일 출처", selection: $dateSource) {
                    Text("건강 앱과 연동").tag(0)
                    Text("직접 입력").tag(1)
                    Text("기억 안 나요").tag(2)
                }
                .pickerStyle(.segmented)
                switch dateSource {
                case 0: healthSource
                case 1: manualSource
                default:
                    Text("첫 기록부터 시작해도 충분해요.")
                        .font(.footnote)
                        .foregroundStyle(Ink.text.opacity(0.6))
                }
            }
            .padding(16)
            .milkGlass()
        }
    }

    private var healthSource: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("건강 앱에서 불러오기 (읽기·쓰기)", isOn: Binding(
                get: { mirror.linked },
                set: { on in
                    if on {
                        Task {
                            if await mirror.requestAccess() {
                                await mirror.sync(context: modelContext, periodDays: periodDays)
                            }
                        }
                    } else {
                        mirror.linked = false
                    }
                }
            ))
            .font(.subheadline)
            .tint(Ink.text)
            .disabled(!mirror.available)
            .onChange(of: mirror.linked) { _, _ in lightFeedback += 1 }
            Group {
                if !mirror.available {
                    Text("이 기기에선 건강 앱을 사용할 수 없어요.")
                } else if mirror.linked && !mirror.writeAuthorized {
                    Text("건강 앱 접근이 꺼져 있어요. 설정 앱의 건강 > 데이터 접근에서 허용할 수 있어요.")
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("스위치를 켜면 건강 앱 권한을 요청해요.")
                        Text("다른 앱에 기록해둔 생리 시작일이 있다면 합쳐서 보여드려요.")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(Ink.text.opacity(0.55))
        }
    }

    private var manualSource: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                lightFeedback += 1
                showTracker = true
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(Ink.coral).frame(width: 7, height: 7)
                    Text("날짜 고르기")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Ink.text)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Ink.text.opacity(0.4))
                }
                .padding(12)
                .background(Ink.coral.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            }
            Text(periodDays.isEmpty ? "아직 기록이 없어요." : "기록 \(periodDays.count)일이 담겼어요.")
                .font(.caption)
                .foregroundStyle(Ink.text.opacity(0.55))
        }
    }

    // ══ ③ 추적 항목 ══
    private var signalsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(eyebrow: "기록할 것", title: "무엇을 기록할까요?")
            VStack(alignment: .leading, spacing: 2) {
                Text("에너지와 기분은 기본이에요.")
                Text("나머지는 원하는 만큼만요.")
                Text("나중에 설정에서 바꿀 수 있어요.")
            }
            .font(.system(.footnote, design: .serif))
            .foregroundStyle(Ink.text.opacity(0.55))
            VStack(spacing: 0) {
                baseRow("에너지")
                baseRow("기분")
                toggleRow("수면", $trackSleep)
                toggleRow("통증", $trackPain)
                toggleRow("식욕", $trackAppetite)
                toggleRow("오늘 한 줄", $trackNote)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .milkGlass()
        }
        .onAppear {
            let current = AppSettings.trackedSignals
            trackSleep = current.sleep
            trackPain = current.pain
            trackAppetite = current.appetite
            trackNote = current.note
        }
    }

    private func baseRow(_ name: String) -> some View {
        HStack {
            Text(name).font(.subheadline).foregroundStyle(Ink.text)
            Text("기본")
                .font(.caption2)
                .foregroundStyle(Ink.text.opacity(0.5))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .overlay(Capsule().stroke(Ink.text.opacity(0.25), lineWidth: 1))
            Spacer()
        }
        .padding(.vertical, 11)
    }

    private func toggleRow(_ name: String, _ value: Binding<Bool>) -> some View {
        Toggle(name, isOn: value)
            .font(.subheadline)
            .tint(Ink.text)
            .padding(.vertical, 7)
            .onChange(of: value.wrappedValue) { _, _ in lightFeedback += 1 }
    }

    // ══ ④ 저장 위치 ══
    private var storageStep: some View {
        let healthOn = mirror.linked && mirror.writeAuthorized
        return VStack(alignment: .leading, spacing: 14) {
            stepHeader(eyebrow: "저장 위치", title: "기록은 여기에만\n저장돼요.")
            Group {
                if healthOn {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("기록은 이 아이폰과 Apple 건강 앱에 저장돼요.")
                        Text("건강 앱 설정에 따라 동기화될 수 있어요.")
                    }
                } else {
                    Text("기록은 이 아이폰에만 저장돼요.")
                }
            }
            .font(.system(.footnote, design: .serif))
            .foregroundStyle(Ink.text.opacity(0.65))
            VStack(spacing: 0) {
                placeRow(icon: "iphone", name: "이 아이폰")
                if healthOn {
                    placeRow(icon: "heart", name: "Apple 건강 앱")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .milkGlass()
            Text("내보내기와 전체 삭제는 언제든 설정에서.")
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.55))
        }
    }

    private func placeRow(icon: String, name: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Ink.text.opacity(0.6))
            Text(name).font(.subheadline).foregroundStyle(Ink.text)
            Spacer()
            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Ink.text.opacity(0.6))
        }
        .padding(.vertical, 11)
    }

    private func stepHeader(eyebrow: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow)
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.5))
                .kerning(2)
            Text(title)
                .font(.almanac(size: 30, weight: .bold))
                .foregroundStyle(Ink.text)
                .lineSpacing(4)
        }
    }
}

/// 에너지 흐름 곡선 (프로토 v72 path를 정규화 — 겨울 저점→봄 상승→여름 정점→가을 하강)
struct EnergyWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        // 원본 viewBox 280×152 기준 좌표를 rect로 스케일
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 280 * rect.width, y: rect.minY + (y + 8) / 152 * rect.height)
        }
        var path = Path()
        path.move(to: pt(12, 92))
        path.addCurve(to: pt(86, 66), control1: pt(45, 100), control2: pt(62, 92))
        path.addCurve(to: pt(150, 28), control1: pt(108, 43), control2: pt(130, 30))
        path.addCurve(to: pt(216, 62), control1: pt(176, 26), control2: pt(196, 42))
        path.addCurve(to: pt(268, 86), control1: pt(236, 80), control2: pt(254, 88))
        return path
    }
}
