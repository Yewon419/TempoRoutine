// 템포루틴 — 온보딩 (Phase 0 ⑧, MASTER §3.10 / §8.2.1 — ②는 개정 M 2026-08-08 프로토 onboarding-m 확정)
// ① 인트로 탭 진행 3장면(원 드로잉→사이클 싱킹 곡선→네 계절, 자동 타이머 없음·Reduce Motion=완성 상태)
// ② 기준일 순차 플로우(개정 M — 3분기 칩 폐기): 연동 스위치 카드 → 분기 = 권한 아님 **병합 결과
//    에피소드 수**(§5.7 read 거부 판별 불가) → 지속일 스피너 → 월 캘린더 자동 채움(지난달 가능,
//    스킵 secondary) → 에피소드 1개일 때만 주기 스피너(→ N prior, T1b).
// ③ 세 가지 카드 소개(일정·Input·Output — 문안 = CardKind.info, 2026-08-09)
// ④ 추적 항목(에너지·기분 기본 + 옵션 → TrackedSignals, 항목 ⓘ 설명) ⑤ 저장 위치 조건부 카피+체크 카드
// ⑥ 리듬 설문 — primary 「시작하기」 + 「지금은 넘어가기」 secondary(2026-08-09 승격.
//    사전 설문 코드 장은 같은 날 폐기 — 웹 사전 설문 자체를 접음)
// 진행 점은 인트로 숨김·2단계부터. 실권한은 실제 연동 순간만(§3.6.1).

import SwiftUI
import SwiftData
import TempoCore
import UIKit

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
    @State private var orbitAngle: Double = 0   // 궤도 도는 잉크 점 회전각(3.1s 후 26s 무한 선형 회전)
    @State private var introEntered = false     // "시작/다음" 버튼 1000ms 지연 노출 — 스텝1 (재)진입마다 리셋
    @State private var lightFeedback = 0        // 작은 햅틱(§4 — 단계 진행·토글, 확정 아님)

    // 브랜드 스플래시 — 온보딩 최초 1회. 로고 + 시그니처 사운드(2026-07-28)
    @State private var showSplash = true
    @State private var splashLogoIn = false

    // ② 기준일 — 순차 플로우(개정 M): 0=연동 / 1=지속일 / 2=캘린더 / 3=주기
    @State private var baselinePage = 0
    @State private var baselineStack: [Int] = []      // 내부 back 스택(연동→③처럼 건너뛴 경로 복원)
    @State private var periodLength = 5               // ②-2 지속일 답 → 캘린더 자동 채움 일수
    @State private var cycleLengthAnswer = 28         // ②-4 주기 답 → N prior(T1b)
    @State private var pendingLinkAdvance = false     // 연동 알럿 닫힌 뒤 분기 진행 플래그
    @State private var syncMessage: String?    // 건강 앱 동기화 결과 안내(2026-07-22 — 침묵 실패 진단용)
    @State private var syncOffersPermission = false   // 읽기 권한 안내일 때만 설정 버튼(2026-08-01)
    private let mirror = HealthMirror.shared

    /// 분기의 유일한 기준 = 병합 결과 에피소드 수(§5.7 — 권한 거부는 판별 불가)
    private var episodeCount: Int { PeriodMath.episodeStarts(days: periodDays.map(\.day)).count }

    // ③ 추적 항목 — 예민함·몸은 2026-08-05 사용자 결정으로 제거(기분·에너지와 겹침).
    // M축 수집이 함께 중단됐다(§3.11 개정). 과거 저장분은 리듬 집계에 계속 유효.
    @State private var trackSleep = true
    @State private var trackAppetite = true
    @State private var trackNote = true
    // ⑤ 리듬 설문(2026-08-05 사용자 결정) — 온보딩 마지막 단계에서 제안, 강요하지 않는다
    @State private var showSurvey = false
    @Query private var selfReports: [SelfReportRecord]

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
                    case 3: cardsStep
                    case 4: signalsStep
                    case 5: storageStep
                    default: surveyStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 8)   // 뒤로가기 버튼을 위로(2026-07-22 사용자 요청)
            .centeredColumn(560)   // 아이패드 중앙 조판(2026-07-23)
        }
        .safeAreaInset(edge: .bottom) { bottomBar.centeredColumn(560) }
        // 설문을 제출하고 닫혔으면 온보딩도 끝낸다 — "오늘 화면으로"를 한 번 더 누르게 하지 않는다.
        .sheet(isPresented: $showSurvey, onDismiss: {
            if !selfReports.isEmpty { onboardingDone = true }
        }) { SelfReportFlow() }
        .alert("건강 앱 연동", isPresented: Binding(get: { syncMessage != nil },
                                              set: { if !$0 { syncMessage = nil; syncOffersPermission = false; consumeLinkAdvance() } })) {
            if syncOffersPermission {
                Button("권한 설정 열기") { syncMessage = nil; syncOffersPermission = false; HealthMirror.openAppSettings() }
            }
            Button("확인") { syncMessage = nil; syncOffersPermission = false; consumeLinkAdvance() }
        } message: {
            Text(syncMessage ?? "")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: lightFeedback)
        .overlay { if showSplash { splash } }
        // 스플래시가 걷힌 뒤에야 인트로 연출이 시작되도록 스플래시 상태를 id에 넣는다.
        // 안 그러면 씬A의 원 그리기(2.8s)가 스플래시 뒤에서 다 끝나버린다.
        .task(id: [step, showSplash ? 1 : 0]) {
            guard step == 1, !showSplash else { return }
            introEntered = false
            guard !reduceMotion else { introEntered = true; return }
            try? await Task.sleep(nanoseconds: 30_000_000)
            introEntered = true
        }
        .task {
            guard showSplash else { return }
            try? await Task.sleep(nanoseconds: 30_000_000)    // 상태 변화가 관측되도록 한 틱 양보
            splashLogoIn = true
            try? await Task.sleep(nanoseconds: 250_000_000)   // 로고가 먼저 읽히고 소리가 붙는다
            guard showSplash, !Task.isCancelled else { return }
            SignatureSound.shared.play()
            // 음원 2.83초. 페이드아웃 0.5초를 겹쳐 소리가 자연히 끝나는 자리에서 화면이 걷힌다.
            try? await Task.sleep(nanoseconds: 2_450_000_000)
            guard !Task.isCancelled else { return }
            dismissSplash(silencing: false)
        }
    }

    // ── 브랜드 스플래시 ──
    // 로고를 띄우고 시그니처 사운드를 한 번 낸다. 탭하면 즉시 건너뛴다.
    private var splash: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()
            // 108 → 72(2026-08-03 베타 피드백 "글씨 너무 커"): 워드마크 크기는 외경에 비례하고
            // (0.8965배) 108이면 4글자 폭이 화면 폭을 거의 채운다. 비율 SSOT(build_final.py)는 불변.
            BrandLogo(diameter: 72)
                .opacity(splashLogoIn ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.7), value: splashLogoIn)
        }
        .transition(.opacity)
        .contentShape(Rectangle())
        .onTapGesture { dismissSplash(silencing: true) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("템포루틴")
        .accessibilityHint("탭하면 건너뜁니다")
    }

    /// - Parameter silencing: 사용자가 건너뛴 경우에만 true. 끝까지 재생된 소리는 건드리지 않는다.
    private func dismissSplash(silencing: Bool) {
        guard showSplash else { return }
        if silencing { SignatureSound.shared.fadeOut() }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { showSplash = false }
    }

    // ── 하단 액션 바 — 전 스텝 공통 위치(2026-07-22 베타 피드백: 버튼 위치 통일·점과 겹침 정정) ──
    private var bottomBar: some View {
        VStack(spacing: 10) {
            // ② 연동 페이지의 주 행동은 콘텐츠의 스위치 카드 — 하단은 secondary만(프로토 확정 위계)
            if step == 2 && baselinePage == 0 {
                ghostButton("직접 기록할게요") { pushBaseline(1) }
            } else {
                primaryButton(primaryLabel, action: primaryAction)
                    .staggerIn(step == 1 ? introEntered : true, delay: step == 1 ? 1.0 : 0, reduceMotion: reduceMotion)
                    .allowsHitTesting((step != 1 || introEntered || reduceMotion) && primaryEnabled)
                    .opacity(primaryEnabled ? 1 : 0.35)
            }
            if step == 2 && baselinePage == 2 {
                ghostButton("나중에 기록할게요") { step = 3 }   // 구 "기억 안 나요" 승계 — S0 처리
            }
            if step == 2 && baselinePage == 3 {
                ghostButton("잘 모르겠어요") { AppSettings.cycleLengthPrior = nil; step = 3 }
            }
            // ⑥ 설문 건너뛰기(2026-08-09 사용자 결정) — 설문은 primary로 승격하되 강요는 안 한다.
            // ② 생리주기 질문의 secondary와 별개다(그쪽은 넘어가기가 있어도 필수 성격).
            if step == 6 && selfReports.isEmpty {
                ghostButton("지금은 넘어가기") { onboardingDone = true }
                Text("언제든 설정에서 다시 답변할 수 있어요.")
                    .font(.caption)
                    .foregroundStyle(Ink.text.opacity(0.45))
                    .frame(maxWidth: .infinity)
            }
            if step >= 2 { dots }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    /// ② 캘린더 페이지의 「다음」은 에피소드 1개 이상일 때만 — 스킵은 secondary가 담당
    private var primaryEnabled: Bool {
        if step == 2 && baselinePage == 2 { return episodeCount >= 1 }
        return true
    }

    private func ghostButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            lightFeedback += 1
            action()
        } label: {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Ink.text.opacity(0.55))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
        }
    }

    private func pushBaseline(_ page: Int) {
        lightFeedback += 1
        baselineStack.append(baselinePage)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { baselinePage = page }
    }

    /// 연동 알럿이 닫힌 뒤 1회 — 분기 = 병합 결과 에피소드 수(프로토 확정)
    private func consumeLinkAdvance() {
        guard pendingLinkAdvance, step == 2 else { return }
        pendingLinkAdvance = false
        let n = episodeCount
        if n >= 2 { step = 3 }              // 실측 gap 확보 → ②-2~④ 전부 스킵
        else if n == 1 { pushBaseline(3) }  // 주기 질문만
        else { pushBaseline(1) }            // 거부·빈 건강앱 → 직접 기록
    }

    private var primaryLabel: String {
        switch step {
        case 1: introScene == 0 ? "시작" : "다음"
        case 2, 3, 4, 5: "다음"
        // ⑥ 설문 미답 = 설문 시작이 primary(2026-08-09 승격). 답이 있으면 마무리만 남는다.
        default: selfReports.isEmpty ? "시작하기" : "오늘 화면으로"
        }
    }

    private func primaryAction() {
        switch step {
        case 1: advanceIntro()
        case 2:
            switch baselinePage {
            case 1:
                AppSettings.periodLengthPrior = periodLength   // §5.3 층 2 M 초기값(개정 M)
                pushBaseline(2)
            case 2:
                if episodeCount == 1 { pushBaseline(3) }   // 실측 gap 없음 → 주기 질문
                else { step = 3 }                          // ≥2 = 실측 gap 있음 → 안 묻는다
            case 3:
                AppSettings.cycleLengthPrior = cycleLengthAnswer
                step = 3
            default: break
            }
        case 3: step = 4   // ③ 세 가지 카드 소개(2026-08-09 사용자 지시) → ④ 추적 항목
        case 4:
            // pain·irritability = false 고정(2026-08-05 병합) — 입력 행이 없는데 켜두면
            // 설정 복원·백업 경로에서 유령 행이 부활한다. 스키마 필드는 저장 호환 위해 유지.
            AppSettings.trackedSignals = TrackedSignals(sleep: trackSleep, pain: false,
                                                        appetite: trackAppetite, note: trackNote,
                                                        irritability: false)
            step = 5
        case 5: step = 6   // ⑥ 리듬 설문(2026-08-05 사용자 결정 — 코드 장은 2026-08-09 폐기)
        default:
            if selfReports.isEmpty { showSurvey = true }   // 「시작하기」 — 제출·닫힘 처리는 sheet onDismiss
            else { onboardingDone = true }
        }
    }

    // ── 상단: back — 2단계부터, 그리고 인트로 씬B·C에서도 이전 씬으로(2026-07-22 사용자 요청) ──
    private var topBar: some View {
        HStack {
            if step >= 2 || (step == 1 && introScene > 0) {
                Button {
                    lightFeedback += 1
                    if step == 1 {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) { introScene -= 1 }
                    } else if step == 2, let prev = baselineStack.popLast() {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { baselinePage = prev }
                    } else {
                        step -= 1
                        if step == 1 { introScene = 2 }
                    }
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
            ForEach(1...6, id: \.self) { i in
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
        .task(id: [introScene, showSplash ? 1 : 0]) {
            sceneAppeared = false
            orbitAngle = 0
            guard !showSplash else { return }       // 스플래시 뒤에서 연출을 소모하지 않는다
            if introScene != 0 { startDrawing() }   // 씬B·C는 기존 방식 유지(Phase 2에서 정합)
            guard !reduceMotion else { sceneAppeared = true; return }
            try? await Task.sleep(nanoseconds: 30_000_000)   // 상태 변화가 관측되도록 한 틱 양보
            sceneAppeared = true
            guard introScene == 0 else { return }
            try? await Task.sleep(nanoseconds: 3_070_000_000)   // 원 완성 후(1.3+1.5=2.8s) 여유 두고 궤도 시작(총 3.1s)
            guard introScene == 0, !Task.isCancelled else { return }
            withAnimation(.linear(duration: 26).repeatForever(autoreverses: false)) {
                orbitAngle = 360
            }
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
                // "생리 주기 기반"을 첫 화면에 명시한다(v1.6 §9 3-6 — App Store 2.3 메타데이터 방어)
                Text("생리 주기를 네 계절로 보고,")
                    .staggerIn(sceneAppeared, delay: 0.56, duration: 0.48, reduceMotion: reduceMotion)
                Text("계절에 맞게 계획하는 플래너예요.")
                    .staggerIn(sceneAppeared, delay: 0.82, duration: 0.48, reduceMotion: reduceMotion)
            }
            .font(.system(.body, design: .serif))
            .foregroundStyle(Ink.text.opacity(0.75))
            // 비의료 고지(5.1.1(ix) 방어) — 문구 = 2026-08-05 사용자 지정(베타 피드백, 부정 정의 → 긍정 정의)
            Text("템포루틴은 당신이 기록해 놓은 과거를 기반으로\n당신만의 템포를 보여주는 앱입니다.\n의학적 진단이나 조언은 포함되어 있지 않습니다.")
                .font(.caption)
                .foregroundStyle(Ink.text.opacity(0.45))
                .lineSpacing(2)
                .staggerIn(sceneAppeared, delay: 1.08, duration: 0.48, reduceMotion: reduceMotion)
            Spacer()
            cycleWheel
                .frame(maxWidth: .infinity)
            Spacer()
        }
    }

    private static let wheelPhases: [CyclePhase] = [.menstrual, .follicular, .ovulation, .luteal]
    private static let wheelNodeDelays: [Double] = [1.36, 1.68, 2.06, 2.44]   // 시안 ob-node-winter~autumn

    /// 주기 원 드로잉 — 은필 원(1.5s, 1.3s 지연 후) + 4계절 노드(원이 지나가는 시점에 개별 페이드인)
    private var cycleWheel: some View {
        ZStack {
            if !reduceMotion { orbitDot }   // 원보다 아래 레이어(2026-07-22 사용자 결정) — 완성 후 도는 잉크 점, Reduce Motion엔 숨김
            // 노드 위치의 끊김 = 지우개 하드컷 폐기 → 잉크가 옅어지며 스러지는 테이퍼(2026-08-08
            // 베타 피드백 "끊어놓은 게 약간 부자연스럽네"). 은필 선이 손을 든 자리처럼 읽힌다.
            // 부수 변화: 궤도 점이 끊긴 구간에서도 라벨 아래로 계속 보인다(지우개가 점까지 덮던 종전과 다름).
            Circle()
                .trim(from: 0, to: sceneAppeared ? 1 : 0)
                .stroke(ringGradient, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.5).delay(1.3), value: sceneAppeared)
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

    /// 원이 완성된 뒤 천천히 도는 잉크 점(3.1s 지연 페이드인 + 26s 무한 선형 회전)
    private var orbitDot: some View {
        Circle()
            .fill(Ink.winter)
            .frame(width: 5, height: 5)
            .offset(y: -95)
            .rotationEffect(.degrees(orbitAngle))
            .fadeIn(sceneAppeared, delay: 3.1, duration: 0.6, reduceMotion: reduceMotion)
    }

    /// 노드 4곳에서 잉크가 옅어지며 자연히 끊기는 각도 그라데이션(2026-08-08 베타 피드백).
    /// AngularGradient의 0도와 Circle trim 0은 둘 다 +x에서 시작하고 같은 rotationEffect(-90)를
    /// 받으므로 프랙션 공간이 그대로 정렬된다. 노드 중심 ±0.02 = 완전 공백, ±0.055까지 본색 복귀.
    private var ringGradient: AngularGradient {
        let ink = Ink.winter.opacity(0.7)
        let clear = Ink.winter.opacity(0)
        let gapHalf = 0.02
        let fadeHalf = 0.055
        var stops: [Gradient.Stop] = []
        for t in [0.0, 0.25, 0.5, 0.75, 1.0] {
            if t - fadeHalf > 0 { stops.append(.init(color: ink, location: t - fadeHalf)) }
            stops.append(.init(color: clear, location: max(0, t - gapHalf)))
            stops.append(.init(color: clear, location: min(1, t + gapHalf)))
            if t + fadeHalf < 1 { stops.append(.init(color: ink, location: t + fadeHalf)) }
        }
        return AngularGradient(gradient: Gradient(stops: stops), center: .center)
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
            // 2026-08-08 베타 피드백: 나열 순서 = 표시 순서(봄여름가을겨울 — §8.1 온보딩 예외 폐지,
            // 원·곡선 드로잉의 겨울 시작 서사는 유지) + 카피 = 사용자 지정 문안 그대로(위치 앵커 걷음).
            seasonRow(.follicular, "미뤄둔 일이 만만해지는 시간")
            seasonRow(.ovulation, "의욕이 충만해지는 시간")
            seasonRow(.luteal, "나를 돌보기 시작하는 시간")
            seasonRow(.menstrual, "스스로에게 휴식을 줘도 괜찮은 시간")
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
                .fixedSize(horizontal: false, vertical: true)   // 압축 시 말줄임 금지 — 줄바꿈으로(2026-08-08 베타 피드백)
                .lineSpacing(2)
            Spacer()
        }
        .padding(.vertical, 13)   // 계절 행 간 간격 확대(2026-07-22 베타 피드백)
        .almanacRule(opacity: 0.18)
    }

    // ══ ② 기준일 — 순차 플로우(개정 M 2026-08-08, 프로토 onboarding-m 확정) ══
    private var baselineStep: some View {
        Group {
            switch baselinePage {
            case 0: linkPage
            case 1: durationPage
            case 2: calendarPage
            default: cyclePage
            }
        }
        .transition(.opacity)
    }

    // ②-1 연동 — 주 행동 = 스위치 카드(§8.2.1 스위치 켜기 = 시스템 시트). 분기는 consumeLinkAdvance.
    private var linkPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(eyebrow: "기준일", title: "쓰던 기록이 있다면,\n그대로 이어져요.")
            VStack(alignment: .leading, spacing: 2) {
                Text("건강 앱에 남은 생리 기록으로")
                Text("계절을 바로 시작할 수 있어요.")
            }
            .font(.system(.footnote, design: .serif))
            .foregroundStyle(Ink.text.opacity(0.55))
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: linkBinding) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("건강 앱과 연동")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Ink.text)
                        Text("쓰던 앱이 건강 앱에 기록을 남겼다면, 그대로 이어져요.")
                            .font(.caption)
                            .foregroundStyle(Ink.text.opacity(0.5))
                    }
                }
                .tint(Ink.text)
                .disabled(!mirror.available)
                .onChange(of: mirror.linked) { _, _ in lightFeedback += 1 }
                if !mirror.available {
                    Text("이 기기에선 건강 앱을 사용할 수 없어요.")
                        .font(.caption)
                        .foregroundStyle(Ink.text.opacity(0.55))
                }
                if mirror.available && mirror.linked {
                    // 읽기 권한은 애플이 재요청 못 하게 막음 — 안 불러와지면 설정 원탭 이동(2026-07-24)
                    Button("가져와지지 않나요? 건강 권한 설정 열기") {
                        lightFeedback += 1
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.text)
                }
            }
            .padding(16)
            .milkGlass()
        }
    }

    private var linkBinding: Binding<Bool> {
        Binding(
            get: { mirror.linked },
            set: { on in
                if on {
                    Task {
                        guard await mirror.requestAccess() else {
                            // 거부 = 스위치 되돌아감 + 알럿 닫으면 직접 기록으로(프로토 확정 — 0에피소드 분기)
                            pendingLinkAdvance = true
                            syncMessage = "건강 앱 권한을 허용하지 않으면 연동할 수 없어요. 직접 기록으로 이어갈게요."
                            return
                        }
                        await mirror.sync(context: modelContext, periodDays: periodDays)
                        // 0건 = read 거부일 수 있음(§5.7 — 판별 불가라 안내로 보완, 2026-07-23)
                        let outcome = mirror.lastOutcome
                        syncOffersPermission = outcome.suggestsPermissionCheck
                        pendingLinkAdvance = true
                        syncMessage = outcome.message
                    }
                } else {
                    mirror.linked = false
                }
            }
        )
    }

    // ②-2 지속일 스피너 — 가운데 고정·무게중심 위(프로토: padding-bottom 72)
    private var durationPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(eyebrow: "기준일", title: "생리는 보통\n며칠간 하나요?")
            VStack(alignment: .leading, spacing: 2) {
                Text("다음 화면에서 날짜를 고르면")
                Text("이 일수만큼 채워 드려요.")
            }
            .font(.system(.footnote, design: .serif))
            .foregroundStyle(Ink.text.opacity(0.55))
            Spacer(minLength: 0)
            DrumPicker(value: $periodLength, range: 1...10, unit: "일")
                .onChange(of: periodLength) { _, _ in lightFeedback += 1 }
            Spacer(minLength: 72)
        }
    }

    // ②-3 월 캘린더 — 시작일 탭 = 자동 채움·개별 토글·지난달 이동(전용 뷰, 미결 3 사용자 확정)
    private var calendarPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(eyebrow: "기준일", title: "마지막 생리는\n언제 시작했나요?")
            // 문장 단위 3줄 + fixedSize — 캘린더에 밀려 압축될 때 둘째 줄이 말줄임으로 잘리던
            // 결함 수정(2026-08-08 베타 피드백 "이전 생리도 기록할 수 있어요 하고 문장 마무리").
            VStack(alignment: .leading, spacing: 2) {
                Text("시작한 날을 누르면 \(periodLength)일만큼 채워져요.")
                Text("칸을 다시 누르면 지워져요.")
                Text("지난달로 넘기면 이전 생리도 기록할 수 있어요.")
            }
            .font(.system(.footnote, design: .serif))
            .foregroundStyle(Ink.text.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
            OnboardingCalendar(periodDays: periodDays, fillLength: periodLength) {
                lightFeedback += 1
            }
            .padding(12)
            .milkGlass()
        }
    }

    // ②-4 주기 스피너 — 에피소드 정확히 1개일 때만 도달(§3.10 개정 M). 답 → N prior(T1b).
    private var cyclePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(eyebrow: "기준일", title: "주기가 보통\n며칠쯤인가요?")
            VStack(alignment: .leading, spacing: 2) {
                Text("지난 생리에서 다음 생리까지의 간격이에요.")
                Text("첫 예측의 출발점으로만 쓰이고, 기록이 쌓이면 자동으로 대체돼요.")
            }
            .font(.system(.footnote, design: .serif))
            .foregroundStyle(Ink.text.opacity(0.55))
            Spacer(minLength: 0)
            DrumPicker(value: $cycleLengthAnswer, range: 21...35, unit: "일")
                .onChange(of: cycleLengthAnswer) { _, _ in lightFeedback += 1 }
            Spacer(minLength: 72)
        }
    }

    // ══ ③ 세 가지 카드 (2026-08-09 사용자 지시 — 일정·Input·Output 소개) ══
    // 문안 = CardKind.info 그대로(코치마크 §3.6 계열) — 온보딩에서 배운 말을
    // 오늘 탭·하루 상세의 ⓘ가 같은 말로 받아야 어휘가 하나로 남는다.
    private var cardsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(eyebrow: "하루의 구성", title: "하루를 세 가지로\n담아요.")
            Text("오늘 탭과 하루 상세에서 이 세 구획을 만나요.")
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.55))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(CardKind.allCases) { kind in
                    cardIntroRow(kind)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .milkGlass()
        }
    }

    private func cardIntroRow(_ kind: CardKind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kind.rawValue)
                .font(.almanac(size: 17, weight: .bold))
                .foregroundStyle(Ink.text)
            Text(kind.info)
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    // ══ ④ 추적 항목 ══
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
            // 항목 ⓘ 설명(2026-08-08 베타 피드백) — 체크인 행에서 걷어낸 설명의 새 자리.
            // 롱프레스 중간값 힌트도 여기서 알린다(체크인 ⓘ 제거로 사라진 발견 경로 승계).
            VStack(spacing: 0) {
                baseRow("에너지", info: "하루를 지내는 힘이 얼마나 있었는지예요. 좋고 나쁨이 아니라 오르내림을 봐요. 기록할 때 칩을 길게 누르면 중간값이 돼요.")
                baseRow("기분", info: "마음의 날씨예요. 맑음도 흐림도 그대로 적으면 돼요. 기록할 때 칩을 길게 누르면 중간값이 돼요.")
                toggleRow("수면", $trackSleep, info: "지난밤 잠의 결이에요. 뒤척였는지, 푹 잤는지.")
                toggleRow("식욕", $trackAppetite, info: "그날 입맛이 어땠는지예요.")
                toggleRow("오늘 한 줄", $trackNote, info: "하루를 한 문장으로 남기는 자리예요. 나의 리듬 탭에서 모아 볼 수 있어요.")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .milkGlass()
        }
        .onAppear {
            let current = AppSettings.trackedSignals
            trackSleep = current.sleep
            trackAppetite = current.appetite
            trackNote = current.note
        }
    }

    private func baseRow(_ name: String, info: String) -> some View {
        HStack(spacing: 4) {
            InfoBadge(title: name, message: info)
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

    private func toggleRow(_ name: String, _ value: Binding<Bool>, info: String) -> some View {
        Toggle(isOn: value) {
            HStack(spacing: 4) {
                InfoBadge(title: name, message: info)
                Text(name).font(.subheadline).foregroundStyle(Ink.text)
            }
        }
        .tint(Ink.text)
        .padding(.vertical, 7)
        .onChange(of: value.wrappedValue) { _, _ in lightFeedback += 1 }
    }

    // ══ ⑤ 저장 위치 ══
    // 2026-07-23 개정(§5.2 동기화 실장): iCloud 행·카피는 실제 활성일 때만(정확성 — §7 privacy-washing 금지).
    // iPad 타깃 추가로 "이 아이폰" → "이 기기". 마지막 줄 = §3.10 공유·통제 고정 한 줄.
    private var storageStep: some View {
        let healthOn = mirror.linked && mirror.writeAuthorized
        let cloudOn = AppStores.cloudEnabled
        return VStack(alignment: .leading, spacing: 14) {
            stepHeader(eyebrow: "저장 위치", title: "기록은 여기에만\n저장돼요.")
            VStack(alignment: .leading, spacing: 2) {
                if healthOn {
                    Text("기록은 이 기기와 Apple 건강 앱에 저장돼요.")
                    Text("건강 앱 설정에 따라 동기화될 수 있어요.")
                } else {
                    Text(cloudOn ? "기록은 이 기기에 저장돼요." : "기록은 이 기기에만 저장돼요.")
                }
                if cloudOn {
                    Text("플래너와 체크인은 당신의 iCloud로 기기 간에 이어져요.")
                    Text("생리 기록은 iCloud로 보내지 않아요.")
                }
            }
            .font(.system(.footnote, design: .serif))
            .foregroundStyle(Ink.text.opacity(0.65))
            VStack(spacing: 0) {
                placeRow(icon: "iphone", name: "이 기기")
                if healthOn {
                    placeRow(icon: "heart", name: "Apple 건강 앱")
                }
                if cloudOn {
                    placeRow(icon: "icloud", name: "iCloud (플래너·체크인)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .milkGlass()
            Text("아무와도 공유하지 않아요. 언제든 내보내고 지울 수 있어요.")
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.55))
        }
    }

    // ══ ⑥ 리듬 설문 (2026-08-05 신설 → 2026-08-09 승격, 사용자 결정) ══
    // 설문이 primary(「시작하기」)다 — 생리 앱의 신뢰를 첫인상에서 세우는 단계라서.
    // 강요하지 않기는 유지: 바로 아래 「지금은 넘어가기」 + 설정 재답변 안내(bottomBar).
    // 여기서 답하면 나의 리듬 탭의 설문 프롬프트는 다시 뜨지 않는다(레코드 존재로 판정).
    private var surveyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(eyebrow: "마지막으로", title: "당신의 리듬,\n조금만 알려주세요.")
            VStack(alignment: .leading, spacing: 2) {
                Text("리듬의 모양은 사람마다 달라요.")
                Text("17개 문항이고 2분쯤 걸려요.")
                Text("답은 이 기기에만 저장돼요.")
            }
            .font(.system(.footnote, design: .serif))
            .foregroundStyle(Ink.text.opacity(0.55))
            if !selfReports.isEmpty {
                Label("답이 담겼어요. 고마워요.", systemImage: "checkmark.seal")
                    .font(.footnote)
                    .foregroundStyle(Ink.text.opacity(0.6))
            }
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
