// 템포루틴 — 온보딩 (Phase 0 ⑧, MASTER §3.10 / §8.2.1 — ②는 개정 M 2026-08-08 프로토 onboarding-m 확정)
// ① 인트로 탭 진행 3장면(원 드로잉→사이클 싱킹 곡선→네 계절, 자동 타이머 없음·Reduce Motion=완성 상태)
// ② 기준일 순차 플로우(개정 M — 3분기 칩 폐기): 연동 스위치 카드 → 분기 = 권한 아님 **병합 결과
//    에피소드 수**(§5.7 read 거부 판별 불가) → 지속일 스피너 → 월 캘린더 자동 채움(지난달 가능,
//    스킵 secondary) → 에피소드 1개일 때만 주기 스피너(→ N prior, T1b).
// ③ 세 가지 카드 소개(일정·Input·Output — 탭 진행형 3장 + Input·Output 예시 담기 칩, 2026-08-09.
//    문안 = CardKind.info)
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
    /// 첫 화면 언어 선택(2026-08-21) — 저장값이 없으면 시스템 따름이라 어느 칩도 선택 상태가 아니다
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue
    /// ①.5 테마 선택(2026-08-19) — 기본 선택 = 은필(사용자: "우리 정체성"). 저장은 case 2,
    /// 적용은 finishOnboarding(진행 중 적용 = 루트 `.id` 리빌드가 step을 날린다).
    @State private var themeChoice: AppTheme = .standard
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
    // ③ 세 가지 카드 — 탭 진행형(2026-08-09): 0=일정 / 1=Input / 2=Output + 예시 담기
    @State private var cardPage = 0
    @State private var addedExamples: Set<String> = []
    // 재탭 = 빠짐(2026-08-09 베타 피드백) — 지우려면 참조가 필요해 담은 실물을 들고 있는다
    @State private var exampleInputs: [String: InputItem] = [:]
    @State private var exampleOutputs: [String: OutputItem] = [:]
    @State private var cardDraw: CGFloat = 0   // 장별 선화 드로잉(인트로 trim 문법)
    // 설정 「온보딩 다시 보기」 재진입 표식(2026-08-09 베타 피드백) — 좌상단 X 노출 조건.
    // 첫 실행 온보딩엔 X가 없다(최초 설정은 건너뛸 수 없음).
    @AppStorage("onboardingRevisit") private var isRevisit = false

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
                    case 2: themeStep     // ①.5 테마 선택(2026-08-19 — 7일 체험 고지 포함)
                    case 3: baselineStep
                    case 4: cardsStep
                    case 5: signalsStep
                    case 6: storageStep
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
            if !selfReports.isEmpty { finishOnboarding() }
        }) { SelfReportFlow().themeColorScheme() }
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
            if step == 3 && baselinePage == 0 {
                ghostButton("직접 기록할게요") { pushBaseline(1) }
            } else {
                primaryButton(primaryLabel, action: primaryAction)
                    .staggerIn(step == 1 ? introEntered : true, delay: step == 1 ? 1.0 : 0, reduceMotion: reduceMotion)
                    .allowsHitTesting((step != 1 || introEntered || reduceMotion) && primaryEnabled)
                    .opacity(primaryEnabled ? 1 : 0.35)
            }
            if step == 3 && baselinePage == 2 {
                ghostButton("나중에 기록할게요") { step = 4 }   // 구 "기억 안 나요" 승계 — S0 처리
            }
            if step == 3 && baselinePage == 3 {
                ghostButton("잘 모르겠어요") { AppSettings.cycleLengthPrior = nil; step = 4 }
            }
            // ⑥ 설문 건너뛰기(2026-08-09 사용자 결정) — 설문은 primary로 승격하되 강요는 안 한다.
            // ② 생리주기 질문의 secondary와 별개다(그쪽은 넘어가기가 있어도 필수 성격).
            if step == 7 && selfReports.isEmpty {
                ghostButton("지금은 넘어가기") { finishOnboarding() }
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
        if step == 3 && baselinePage == 2 { return episodeCount >= 1 }
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
        guard pendingLinkAdvance, step == 3 else { return }
        pendingLinkAdvance = false
        let n = episodeCount
        if n >= 2 { step = 4 }              // 실측 gap 확보 → ②-2~④ 전부 스킵
        else if n == 1 { pushBaseline(3) }  // 주기 질문만
        else { pushBaseline(1) }            // 거부·빈 건강앱 → 직접 기록
    }

    private var primaryLabel: String {
        switch step {
        case 1: introScene == 0 ? "시작" : "다음"
        case 2, 3, 4, 5, 6: "다음"
        // ⑥ 설문 미답 = 설문 시작이 primary(2026-08-09 승격). 답이 있으면 마무리만 남는다.
        default: selfReports.isEmpty ? "시작하기" : "오늘 화면으로"
        }
    }

    private func primaryAction() {
        switch step {
        case 1: advanceIntro()
        case 2:
            // 테마 선택 저장(2026-08-19) — 종료 시트의 기본 선택값으로도 쓴다("이전 거랑 연결").
            // 적용은 여기서 하지 않는다 — 테마 변경 = 루트 `.id` 리빌드가 이 플로우의 step을
            // 날린다(2026-08-11 결함과 같은 경로). finishOnboarding에서 적용.
            UserDefaults.standard.set(themeChoice.rawValue, forKey: ThemeTrial.choiceKey)
            step = 3
        case 3:
            switch baselinePage {
            case 1:
                AppSettings.periodLengthPrior = periodLength   // §5.3 층 2 M 초기값(개정 M)
                pushBaseline(2)
            case 2:
                if episodeCount == 1 { pushBaseline(3) }   // 실측 gap 없음 → 주기 질문
                else { step = 4 }                          // ≥2 = 실측 gap 있음 → 안 묻는다
            case 3:
                AppSettings.cycleLengthPrior = cycleLengthAnswer
                step = 4
            default: break
            }
        case 4: advanceCardPage()   // ③ 세 가지 카드 — 장 안에서 진행, 마지막 장이면 ④로
        case 5:
            // pain·irritability = false 고정(2026-08-05 병합) — 입력 행이 없는데 켜두면
            // 설정 복원·백업 경로에서 유령 행이 부활한다. 스키마 필드는 저장 호환 위해 유지.
            AppSettings.trackedSignals = TrackedSignals(sleep: trackSleep, pain: false,
                                                        appetite: trackAppetite, note: trackNote,
                                                        irritability: false)
            step = 6
        case 6: step = 7   // ⑥ 리듬 설문(2026-08-05 사용자 결정 — 코드 장은 2026-08-09 폐기)
        default:
            if selfReports.isEmpty { showSurvey = true }   // 「시작하기」 — 제출·닫힘 처리는 sheet onDismiss
            else { finishOnboarding() }
        }
    }

    /// 온보딩 종료 한 창구 — 재진입 표식도 여기서 내린다(다음 첫 실행과 혼동 방지)
    private func finishOnboarding() {
        // 테마 적용(2026-08-19) — 신규 온보딩만. 닫히는 순간이라 루트 `.id` 리빌드가 무해하다.
        // 재진입은 테마 단계를 안 거치지만, 남아 있는 옛 choiceKey로 덮지 않게 이중 가드.
        if !isRevisit, let raw = UserDefaults.standard.string(forKey: ThemeTrial.choiceKey) {
            ThemeStore.apply(raw)
            UserDefaults.standard.set(raw, forKey: ThemeStore.storageKey)
        }
        isRevisit = false
        onboardingDone = true
    }

    // ── 상단: back — 2단계부터, 그리고 인트로 씬B·C에서도 이전 씬으로(2026-07-22 사용자 요청) ──
    // 재진입(설정 「온보딩 다시 보기」)이면 좌상단 X = 즉시 나가기(2026-08-09 베타 피드백).
    private var topBar: some View {
        HStack {
            if isRevisit {
                Button {
                    lightFeedback += 1
                    finishOnboarding()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(Ink.text.opacity(0.6))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("온보딩 닫기")
            }
            if step >= 2 || (step == 1 && introScene > 0) {
                Button {
                    lightFeedback += 1
                    if step == 1 {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) { introScene -= 1 }
                    } else if step == 3, let prev = baselineStack.popLast() {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { baselinePage = prev }
                    } else if step == 4 && cardPage > 0 {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { cardPage -= 1 }
                    } else {
                        step -= 1
                        if isRevisit && step == 2 { step = 1 }   // 재진입은 테마 단계를 안 거친다
                        if step == 1 { introScene = 2 }
                        if step == 4 { cardPage = 2 }   // ④에서 돌아오면 마지막 장부터(인트로와 동형)
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
            ForEach(1...7, id: \.self) { i in
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
            // 재진입(다시 보기)은 테마 단계 스킵(2026-08-19) — 이미 쓰는 테마가 있는데
            // 여기서 고르게 하면 닫는 순간 그 선택으로 갈아타 버린다.
            step = isRevisit ? 3 : 2
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
                Text("당신만의 속도를 찾아서.")
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
            languagePicker
                .staggerIn(sceneAppeared, delay: 1.34, duration: 0.48, reduceMotion: reduceMotion)
        }
    }

    // ── 언어 선택 (2026-08-21 대표님 요청 — 첫 화면) ────────────────────────────
    /// 기본값은 **기기 설정 따름**이다. 여기서 고르는 건 그 위의 덮개이고, 고르면 즉시 전환된다.
    /// 이름을 각자의 언어로 적는 이유: 지금 화면이 무슨 언어로 떠 있든 자기 언어를 찾을 수 있어야 한다.
    /// ⚠ 인트로는 아무 데나 탭하면 다음 씬으로 넘어간다 — 버튼이 탭을 먹으므로 여기선 안 넘어간다.
    private var languagePicker: some View {
        // 언어가 넷이라 한 줄에 안 들어가는 폭이 있다 — 적응형 그리드로 자연히 접힌다
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8, alignment: .leading)],
                  alignment: .leading, spacing: 8) {
            ForEach(AppLanguage.allCases.filter { $0 != .system }) { lang in
                Button {
                    lightFeedback += 1
                    Loc.apply(lang)          // 즉시 반영(정적 캐시) — @AppStorage 변화가 트리를 리빌드한다
                    appLanguage = lang.rawValue
                } label: {
                    Text(verbatim: lang.nativeName)   // 이름 자체가 그 언어 — 번역 대상이 아니다
                        .font(.footnote.weight(appLanguage == lang.rawValue ? .semibold : .regular))
                        .foregroundStyle(appLanguage == lang.rawValue ? Ink.paper : Ink.text.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(appLanguage == lang.rawValue ? Ink.text : Ink.text.opacity(0.08),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(appLanguage == lang.rawValue ? [.isSelected] : [])
            }
        }
        .accessibilityLabel("언어 선택")
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
                Text("한 주기 안에서도 에너지와 컨디션은 오르내립니다.")
                Text("사이클 싱킹은 그 흐름을 계획에 맞추는 대신,")
                Text("계획을 당신에게 맞추는 방법이에요.")
            }
            .font(.system(.subheadline, design: .serif))
            .foregroundStyle(Ink.text.opacity(0.75))
            Spacer()
            energyWave
                .frame(height: 150)
                .frame(maxWidth: .infinity)
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("사람마다 리듬은 모두 달라요.")
                Text("템포루틴이 당신만의 리듬을 찾게 도와줄게요.")
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
            // eyebrow 추가(2026-08-16 베타 피드백) — 앞 장(sceneWave)과 같은 형식으로 맞춘다
            Text("사이클 싱킹")
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.5))
                .kerning(2)
            Text("한 달 안의 사계절")
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
                Text("상단의 설명은 일반적인 경향입니다.")
                Text("당신의 계절은 기록이 쌓이며 맞춰집니다.")
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
                Text("건강 앱에 남은 생리 기록을 불러오면")
                Text("보다 편한 시작을 할 수 있어요.")
            }
            .font(.system(.footnote, design: .serif))
            .foregroundStyle(Ink.text.opacity(0.55))
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: linkBinding) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("건강 앱과 연동")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Ink.text)
                        // 줄바꿈 정리(2026-08-20 베타 피드백) — 종전 문장은 「불러올 / 수」로 꺾였다
                        Text("쓰던 앱이 건강 앱에 남긴 기록을 불러올 수 있어요.")
                            .font(.caption)
                            .foregroundStyle(Ink.text.opacity(0.5))
                    }
                }
                .tint(Ink.text)
                .disabled(!mirror.available)
                .onChange(of: mirror.linked) { _, _ in lightFeedback += 1 }
                if !mirror.available {
                    Text("이 기기에선 건강 앱을 사용할 수 없습니다.")
                        .font(.caption)
                        .foregroundStyle(Ink.text.opacity(0.55))
                }
                if mirror.available && mirror.linked {
                    // 읽기 권한은 애플이 재요청 못 하게 막음 — 안 불러와지면 설정 원탭 이동(2026-07-24)
                    // 수동 \n 제거(2026-08-20 베타 피드백 "줄바꿈 난리") — 버튼 다중행은
                    // 중앙 정렬돼 둘째 줄이 떠 보였다. 왼쪽 정렬로 자연 줄바꿈에 맡긴다
                    Button("정상적으로 가져올 수 없나요? 건강 권한 설정 열기") {
                        lightFeedback += 1
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.text)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                            syncMessage = "건강 앱 권한을 허용하지 않으면 연동할 수 없습니다. 직접 기록으로 이어갈게요."
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
            Spacer(minLength: 0)
            DrumPicker(value: $periodLength, range: 1...10, unit: "일")
                .onChange(of: periodLength) { _, _ in lightFeedback += 1 }
            Spacer(minLength: 72)
        }
    }

    // ②-3 월 캘린더 — 시작일 탭 = 자동 채움·개별 토글·지난달 이동(전용 뷰, 미결 3 사용자 확정)
    private var calendarPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(eyebrow: "기준일", title: "마지막 생리는...")
            // 문장 단위 3줄 + fixedSize — 캘린더에 밀려 압축될 때 둘째 줄이 말줄임으로 잘리던
            // 결함 수정(2026-08-08 베타 피드백 "이전 생리도 기록할 수 있어요 하고 문장 마무리").
            VStack(alignment: .leading, spacing: 2) {
                Text("마지막 생리 시작일을 선택해주세요.")
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
            Text("지난 생리에서 다음 생리까지의 간격을 알려주세요.")
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.55))
            Spacer(minLength: 0)
            DrumPicker(value: $cycleLengthAnswer, range: 21...35, unit: "일")
                .onChange(of: cycleLengthAnswer) { _, _ in lightFeedback += 1 }
            Spacer(minLength: 72)
        }
    }

    // ══ ③ 세 가지 카드 (2026-08-09 사용자 지시 — 탭 진행형: 한 장에 한 항목) ══
    // 문안 = CardKind.info 그대로(코치마크 §3.6 계열) — 온보딩에서 배운 말을
    // 오늘 탭·하루 상세의 ⓘ가 같은 말로 받아야 어휘가 하나로 남는다.
    // Input·Output 장엔 예시 칩 — 탭하면 실제 아이템으로 바로 담긴다(사용자 지정 예시 4종).
    private var cardsStep: some View {
        Group {
            cardPageView(CardKind.allCases[cardPage])
        }
        .id(cardPage)
        .transition(.opacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { advanceCardPage() }   // 인트로와 같은 탭 진행 문법
        // 장별 선화 드로잉 — 인트로 원·곡선과 같은 trim 문법(2026-08-09 그림 추가)
        .task(id: cardPage) {
            cardDraw = 0
            guard !reduceMotion else { cardDraw = 1; return }
            try? await Task.sleep(nanoseconds: 60_000_000)
            withAnimation(.easeOut(duration: 1.0)) { cardDraw = 1 }
        }
    }

    private func cardPageView(_ kind: CardKind) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(eyebrow: Loc.fmt("하루의 구성 %1$@ / 3", "\(cardPage + 1)"), title: kind.rawValue)
            cardSketch(kind)
            Text(kind.info)
                .font(.system(.body, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.78))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            if kind == .input {
                exampleBlock(chips: [("아침명상 5분", "input-meditation"),
                                     ("잠들기 전 차 한 잔", "input-tea")])
            } else if kind == .output {
                exampleBlock(chips: [("시험공부 6챕터", "output-study"),
                                     ("영어 듣기 30분", "output-listening")])
            }
        }
    }

    /// 장별 선화 — 일정=닻(못 옮기는 날) / Input=찻잔(채우는 일) / Output=종이비행기(내보내는 일).
    /// 은필 단색 스트로크, 카피의 은유를 그대로 그림으로(§4 선화 계열).
    @ViewBuilder
    private func cardSketch(_ kind: CardKind) -> some View {
        let style = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
        let ink = Ink.text.opacity(0.65)
        Group {
            switch kind {
            case .schedule:
                AnchorSketch().trim(from: 0, to: cardDraw).stroke(ink, style: style)
            case .input:
                TeacupSketch().trim(from: 0, to: cardDraw).stroke(ink, style: style)
            case .output:
                PaperPlaneSketch().trim(from: 0, to: cardDraw).stroke(ink, style: style)
            }
        }
        .frame(width: 128, height: 108)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }

    private func advanceCardPage() {
        lightFeedback += 1
        if cardPage < 2 {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { cardPage += 1 }
        } else {
            step = 5
        }
    }

    /// 예시 칩 — 탭 = 실제 아이템 추가, 다시 탭 = 빠짐(2026-08-09 베타 피드백 토글 전환).
    private func exampleBlock(chips: [(label: String, key: String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 2026-08-12 베타 피드백("간단하게만 안내") — 빠지는 법은 눌러 보면 알게 되는 동작이라
            // 첫 안내에서 뺀다. 담는 법 한 가지만 남긴다.
            Text("탭해서 담아볼 수 있어요.")
                .font(.caption)
                .foregroundStyle(Ink.text.opacity(0.5))
            ForEach(chips, id: \.key) { chip in
                exampleChip(chip.label, key: chip.key)
            }
        }
        .padding(.top, 6)
    }

    private func exampleChip(_ label: String, key: String) -> some View {
        let added = addedExamples.contains(key)
        return Button {
            toggleExample(key)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: added ? "checkmark" : "plus")
                    .font(.caption2.weight(.bold))
                Text(label)
                    .font(.footnote)
            }
            .foregroundStyle(Ink.text.opacity(added ? 0.55 : 1))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Ink.text.opacity(added ? 0.04 : 0.08), in: Capsule())
        }
        .accessibilityValue(added ? "담김" : "")
    }

    private func toggleExample(_ key: String) {
        lightFeedback += 1
        if addedExamples.contains(key) {
            addedExamples.remove(key)
            if let item = exampleInputs.removeValue(forKey: key) { modelContext.delete(item) }
            if let item = exampleOutputs.removeValue(forKey: key) { modelContext.delete(item) }
            return
        }
        addedExamples.insert(key)
        switch key {
        case "input-meditation":
            let item = InputItem(title: "아침명상 5분", category: .other, schedule: .daily)
            exampleInputs[key] = item
            modelContext.insert(item)
        case "input-tea":
            let item = InputItem(title: "잠들기 전 차 한 잔", category: .food, schedule: .daily)
            exampleInputs[key] = item
            modelContext.insert(item)
        case "output-study":
            let item = OutputItem(title: "시험공부", schedule: .once, progressKind: .subtasks)
            item.subtasks = (1...6).map { OutputSubtask(title: Loc.fmt("%1$@챕터", "\($0)"), order: $0 - 1) }
            exampleOutputs[key] = item
            modelContext.insert(item)
        case "output-listening":
            let item = OutputItem(title: "영어 듣기", schedule: .once, progressKind: .timer)
            item.targetSeconds = 30 * 60
            exampleOutputs[key] = item
            modelContext.insert(item)
        default:
            break
        }
    }

    // ══ ④ 추적 항목 ══
    private var signalsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(eyebrow: "기록할 것", title: "무엇을 기록할까요?")
            VStack(alignment: .leading, spacing: 2) {
                Text("절댓값보다는 오르내림과 편차를 알아보는 데 의미를 가집니다.")
                Text("나중에 설정에서 바꿀 수 있어요.")
            }
            .font(.system(.footnote, design: .serif))
            .foregroundStyle(Ink.text.opacity(0.55))
            // 항목 ⓘ 설명(2026-08-08 베타 피드백) — 체크인 행에서 걷어낸 설명의 새 자리.
            // 롱프레스 중간값 힌트도 여기서 알린다(체크인 ⓘ 제거로 사라진 발견 경로 승계).
            VStack(spacing: 0) {
                baseRow("에너지", info: "몸의 에너지와 컨디션을 기록합니다.")
                baseRow("기분", info: "감정과 기분을 기록합니다.")
                toggleRow("수면", $trackSleep, info: "지난밤 수면의 질을 기록합니다.")
                toggleRow("식욕", $trackAppetite, info: "입맛과 식사량 등 종합적인 식욕을 기록합니다.")
                toggleRow("오늘 한 줄", $trackNote, info: "자유롭게 하루를 한 문장으로 남기는 특별한 기록입니다. 일기도 좋고, 메모도 좋습니다.")
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

    // ══ ①.5 테마 선택 (2026-08-19 사용자 결정 — 기본·은필 택1 + 7일 체험 고지) ══
    // 재진입(다시 보기)은 이 단계를 건너뛴다(advanceIntro) — 쓰는 테마를 여기서 덮으면 안 된다.
    private var themeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(eyebrow: "당신의 테마", title: "어떤 지면으로\n시작할까요?")
            ForEach([AppTheme.standard, AppTheme.plain]) { theme in
                themeChoiceCard(theme)
            }
            Text("앞으로 7일간 모든 테마를 자유롭게 바꿔볼 수 있어요.")
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.55))
        }
    }

    private func themeChoiceCard(_ theme: AppTheme) -> some View {
        let selected = themeChoice == theme
        return Button {
            lightFeedback += 1
            themeChoice = theme
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ThemePreview(theme: theme)
                HStack(spacing: 8) {
                    Text(theme.displayName)
                        .font(.almanac(size: 17, weight: .bold))
                        .foregroundStyle(Ink.text)
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(Ink.text.opacity(selected ? 0.9 : 0.3))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .milkGlass()
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(Ink.text.opacity(selected ? 0.8 : 0), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Loc.fmt("%1$@ 테마", "\(theme.displayName)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // ══ ⑤ 저장 위치 ══
    // 2026-07-23 개정(§5.2 동기화 실장): iCloud 행·카피는 실제 활성일 때만(정확성 — §7 privacy-washing 금지).
    // iPad 타깃 추가로 "이 아이폰" → "이 기기". 마지막 줄 = §3.10 공유·통제 고정 한 줄.
    private var storageStep: some View {
        let healthOn = mirror.linked && mirror.writeAuthorized
        let cloudOn = AppStores.cloudEnabled
        return VStack(alignment: .leading, spacing: 14) {
            stepHeader(eyebrow: "저장 위치", title: "기록의 저장은 \n오로지 이곳에만")
            VStack(alignment: .leading, spacing: 2) {
                if healthOn {
                    Text("기록은 이 기기와 Apple 건강 앱에 저장돼요.")
                    Text("건강 앱 설정에 따라 동기화될 수 있어요.")
                } else {
                    Text(cloudOn ? "기록은 이 기기에 저장됩니다." : "기록은 이 기기에만 저장됩니다.")
                }
                if cloudOn {
                    Text("플래너와 체크인은 당신의 iCloud로 기기 간에 이어지고,")
                    Text("별도의 서버나 데이터베이스에 저장되지 않습니다.")
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
            Text("당신만이 언제든 내보내고 지울 수 있어요.")
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
            stepHeader(eyebrow: "마지막으로", title: "당신의 리듬,\n조금 더 알려주실래요?")
            VStack(alignment: .leading, spacing: 2) {
                Text("리듬의 모양은 사람마다 다르기에,")
                Text("2분짜리 설문으로 초기 세팅을 빠르게 할 수 있어요.")
                Text("응답은 이 기기에만 저장됩니다.")
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

// ── 온보딩 ③ 장별 선화 (2026-08-09 그림 추가 — 은필 스트로크, trim 드로잉) ──
// 카피의 은유를 그대로: 일정 = "하루의 닻" / Input = 채우는 찻잔 / Output = 내보내는 종이비행기.

/// 닻 — 일정 장
struct AnchorSketch: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var p = Path()
        // 고리
        p.addEllipse(in: CGRect(x: rect.minX + 0.43 * rect.width, y: rect.minY + 0.02 * rect.height,
                                width: 0.14 * rect.width, height: 0.13 * rect.height))
        // 축·가로대
        p.move(to: pt(0.5, 0.15)); p.addLine(to: pt(0.5, 0.82))
        p.move(to: pt(0.34, 0.30)); p.addLine(to: pt(0.66, 0.30))
        // 양 팔 + 갈고리 촉
        p.move(to: pt(0.5, 0.82))
        p.addQuadCurve(to: pt(0.20, 0.58), control: pt(0.26, 0.84))
        p.move(to: pt(0.5, 0.82))
        p.addQuadCurve(to: pt(0.80, 0.58), control: pt(0.74, 0.84))
        p.move(to: pt(0.20, 0.58)); p.addLine(to: pt(0.29, 0.61))
        p.move(to: pt(0.80, 0.58)); p.addLine(to: pt(0.71, 0.61))
        return p
    }
}

/// 찻잔 — Input 장 (예시 "잠들기 전 차 한 잔"과 이어지는 그림)
struct TeacupSketch: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var p = Path()
        // 잔 몸통 + 입구
        p.move(to: pt(0.22, 0.50))
        p.addLine(to: pt(0.27, 0.74))
        p.addQuadCurve(to: pt(0.57, 0.74), control: pt(0.42, 0.85))
        p.addLine(to: pt(0.62, 0.50))
        p.move(to: pt(0.22, 0.50)); p.addLine(to: pt(0.62, 0.50))
        // 손잡이
        p.move(to: pt(0.62, 0.55))
        p.addQuadCurve(to: pt(0.62, 0.69), control: pt(0.79, 0.62))
        // 받침 괘선
        p.move(to: pt(0.16, 0.85)); p.addLine(to: pt(0.68, 0.85))
        // 김 두 줄
        p.move(to: pt(0.35, 0.41))
        p.addQuadCurve(to: pt(0.39, 0.24), control: pt(0.28, 0.32))
        p.move(to: pt(0.50, 0.41))
        p.addQuadCurve(to: pt(0.54, 0.24), control: pt(0.43, 0.32))
        return p
    }
}

/// 종이비행기 — Output 장
struct PaperPlaneSketch: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var p = Path()
        let nose = pt(0.86, 0.26)
        // 윗날개
        p.move(to: nose)
        p.addLine(to: pt(0.10, 0.52))
        p.addLine(to: pt(0.47, 0.59))
        p.addLine(to: nose)
        // 용골(아랫날개)
        p.move(to: pt(0.47, 0.59))
        p.addLine(to: pt(0.40, 0.80))
        p.addLine(to: nose)
        return p
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
