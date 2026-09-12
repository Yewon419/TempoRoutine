// 템포루틴 — 온보딩 「템포 렌즈」 (2026-09-07 대표님 컨셉 승인 "하 이거지" — ui-mockup/onboarding-v2 이식)
// 유리 렌즈 하나가 전 단계를 관통한다: 언어(심플 지면) → 브랜드 진입 때 렌즈 중심에서 은필 지면이 원형으로
// 열리며 주기 원이 그려진다 → 곡선 → 사계 → 우상단 진행 다이얼(점 폐기) → 지속일·주기는 자(ruler)로 답하고
// 렌즈에 호·눈금·숫자로 비친다 → 카드 선화는 렌즈 안 → 마지막에 렌즈가 화면을 덮으며 「오늘」로.
// 입력은 하단 유리 시트(앱 자체 유리 공식, 블러 없음). 유리는 렌즈·시트뿐, 컨트롤은 무광(먹 번짐 채움).
//
// 단계 논리는 종전 그대로(MASTER §3.10 / §8.2.1 개정 M): ② 기준일 순차 플로우(연동 → 분기 = 병합 결과
// 에피소드 수 → 지속일 → 월 캘린더 → 에피소드 1개일 때만 주기), ③ 세 가지 카드 + 예시 담기,
// ④ 추적 항목, ⑤ 저장 위치(아이패드·iCloud 행 추가 — §5.2 2층 계약: 생리 기록은 기기 잔류),
// ⑥ 리듬 설문(primary + 「지금은 넘어가기」). 실권한은 실제 연동 순간만(§3.6.1).
// 상태(step·baselinePage)와 찰칵 런치 인자 계약은 유지 — 표현층만 바뀌었다.

import SwiftUI
import SwiftData
import TempoCore
import UIKit

struct OnboardingFlow: View {
    @AppStorage("onboardingDone") private var onboardingDone = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \PeriodDay.day) private var periodDays: [PeriodDay]

    // 단계(2026-09-12 사계절 4장 추가, 최대 12장): 0 언어 · 1 브랜드 · 2 사계절(4장) · 3 테마 · 4 내 주기(최대 4장) · 5 저장 위치 → 오늘.
    // 2026-09-09 다이어트(15 → 8)에서 걷어낸 것 = 사이클 싱킹 강의 2장·하루의 구성 3장·기록할 것·리듬 설문(베타 "설명 없이
    // 못 쓰겠다" — 온보딩은 설정에 필요한 답만 묻고, 개념은 화면의 빈 상태·ⓘ가 그 자리에서 말한다). 사계절은 설명이 아니라
    // 광고 스틸 한 컷 + 두 줄이라 되살렸다(대표님 "온보딩을 줄인 김에 계절 설명만 늘리자").
    @State private var step = 0   // 0 = 언어 선택(2026-08-22 베타 "첫 탭을 따로") — 재진입은 1부터
    @State private var seasonPage = 0   // 2단계 안 계절 인덱스 0~3 = 겨울·봄·여름·가을(앱 순서)
    private static let seasonOrder: [CyclePhase] = [.menstrual, .follicular, .ovulation, .luteal]
    /// 첫 화면 언어 선택(2026-08-21) — 저장값이 없으면 시스템 따름이라 어느 칩도 선택 상태가 아니다
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue
    /// ①.5 테마 선택(2026-08-19) — 기본 선택 = 은필(사용자: "우리 정체성"). 저장은 case 2,
    /// 적용은 finishOnboarding(진행 중 적용 = 루트 `.id` 리빌드가 step을 날린다).
    /// 고르는 순간 지면은 라이브로 바뀐다(2026-09-07 — plainSurface).
    @State private var themeChoice: AppTheme = .standard
    @State private var lightFeedback = 0        // 작은 햅틱(§4 — 단계 진행·토글, 확정 아님)

    // 브랜드 스플래시 — 온보딩 최초 1회. 로고 + 시그니처 사운드(2026-07-28)
    /// 프로세스당 1회 — 언어를 고르면 루트 .id 리빌드로 이 뷰가 새로 만들어지는데, 그때마다
    /// 스플래시·사운드가 다시 재생되면 안 된다(2026-08-22). 쓰기는 메인뿐.
    nonisolated(unsafe) private static var splashShownThisLaunch = false
    @State private var showSplash = !OnboardingFlow.splashShownThisLaunch
    @State private var splashLogoIn = false

    // 은필 열림(2026-09-07 디테일 ①) — 언어 단계는 심플 지면, 브랜드 진입 때 렌즈 중심에서 원형으로 열린다
    @State private var revealProgress: CGFloat = 0
    // 마지막 「오늘」 진입 — 렌즈가 화면을 덮고 표제가 뜬 뒤 실제 종료(commitFinish)
    @State private var entering = false
    /// 재진입(다시 보기)은 쓰던 테마가 무엇이든 온보딩은 은필 지면으로 보여주고, 닫을 때 되돌린다
    @State private var restoreThemeRaw: String?

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

    // 설정 「온보딩 다시 보기」 재진입 표식(2026-08-09 베타 피드백) — 좌상단 X 노출 조건.
    // 첫 실행 온보딩엔 X가 없다(최초 설정은 건너뛸 수 없음).
    @AppStorage("onboardingRevisit") private var isRevisit = false

    init() {
        #if DEBUG
        // 찰칵(CI 스크린샷) 전용 — 런치 인자(argument 도메인)로 단계를 바로 연다(2026-09-06).
        // `-onboardingStep N [-onboardingBaselinePage N] [-onboardingSeasonPage N]`
        // 인자가 없으면 아무것도 건드리지 않는다. 릴리스 빌드엔 이 경로가 없다.
        let args = UserDefaults.standard
        guard args.object(forKey: "onboardingStep") != nil else { return }
        _step = State(initialValue: args.integer(forKey: "onboardingStep"))
        _baselinePage = State(initialValue: args.integer(forKey: "onboardingBaselinePage"))
        _seasonPage = State(initialValue: args.integer(forKey: "onboardingSeasonPage"))
        _showSplash = State(initialValue: false)   // 컷마다 스플래시 2.7초를 안 기다린다
        _revealProgress = State(initialValue: args.integer(forKey: "onboardingStep") > 0 ? 1 : 0)
        #endif
    }

    // ══ 단계 기술(descriptor) — 상태 4개에서 유도. 카피·렌즈 자리·렌즈 속 그림·시트 유무 ══
    private struct Stage {
        var eyebrow: String
        var title: String
        var hero = false
        var mood: String? = nil
        var body: [String] = []
        var fine: [String] = []
        var spot: LensSpot = .dial
        var content = LensContent()
        var hideLens = false
        var bare = false              // 시트 유리 없음(CTA만)
        var dialStep: Int? = nil      // 진행 다이얼 1~3
        var photo: CyclePhase? = nil  // 사계절 장 — 창에 찰 계절 사진(SeasonWindow)
        var titleColor: Color? = nil  // 표제 계절색(사계절 장만)
        var seasonDots: Int? = nil    // 사계절 장 위치(0~3) — eyebrow의 「N / 4」를 대신하는 점 인디케이터
    }

    private static let dialTotal = 3

    private var stage: Stage {
        switch step {
        case 0:
            return Stage(eyebrow: Loc.str("템포루틴"), title: Loc.str("언어"),
                         body: [Loc.str("앱에서 쓸 언어를 골라 주세요.")], spot: .hero, hideLens: true)
        case 1:
            return Stage(eyebrow: Loc.str("템포루틴"), title: Loc.str("몸의 템포에\n맞게."), hero: true,
                         mood: Loc.str("나만의 속도를 찾아서."),
                         body: [Loc.str("생리 주기를 네 계절로 보고,"), Loc.str("계절에 맞게 계획하는 플래너예요.")],
                         // 비의료 고지(5.1.1(ix) 방어) — 문구 = 2026-08-05 사용자 지정
                         fine: [Loc.str("템포루틴은 당신이 기록해 놓은 과거를 기반으로\n당신만의 템포를 보여주는 앱입니다.\n의학적 진단이나 조언은 포함되어 있지 않습니다.")],
                         spot: .hero, content: LensContent(ring: true, drawsRing: true, nodes: true, orbit: true),
                         bare: true)
        case 2:
            // 사계절 4장(2026-09-12) — 계절마다 한 컷, 티저 광고 스틸이 렌즈 창에 찬다(SeasonWindow).
            // 카피 = seasonMeta의 허락 톤 그대로: 단계명(M-1c)·처방·인구 평균 없음. 마지막 장에만 「처방하지 않는다」 고지.
            let phase = Self.seasonOrder[min(max(seasonPage, 0), 3)]
            let meta = seasonMeta(for: phase)
            // 위치는 점 인디케이터가 말한다 — 같은 정보를 eyebrow 카운터로 한 번 더 쓰지 않는다(2026-09-12 C안).
            return Stage(eyebrow: Loc.str("한 달 안의 사계절"), title: meta.name,
                         mood: seasonMood(phase), body: seasonBody(phase),
                         fine: seasonPage == 3
                             ? [Loc.str("같은 계절도 사람마다 다르게 지나가요."),
                                Loc.str("템포루틴은 처방하지 않고, 당신의 기록 안에서 당신의 계절을 찾아요.")]
                             : [],
                         spot: .hero, hideLens: true, bare: true, photo: phase, titleColor: meta.color,
                         seasonDots: seasonPage)
        case 3:
            return Stage(eyebrow: Loc.str("당신의 테마"), title: Loc.str("어떤 지면으로\n시작할까요?"),
                         spot: .dial, content: dial(1), dialStep: 1)
        case 4:
            switch baselinePage {
            case 0:
                return Stage(eyebrow: Loc.str("내 주기"), title: Loc.str("쓰던 기록이 있다면,\n그대로 이어져요."),
                             body: [Loc.str("건강 앱에 남은 생리 기록을 불러오면"), Loc.str("보다 편한 시작을 할 수 있어요.")],
                             spot: .dial, content: dial(2), dialStep: 2)
            case 1:
                var c = dial(2)
                c.ring = true; c.number = periodLength
                c.arcFraction = Double(periodLength) / Double(max(cycleLengthAnswer, 1))
                return Stage(eyebrow: Loc.str("내 주기"), title: Loc.str("생리는 보통\n며칠간 하나요?"),
                             spot: .mid, content: c, dialStep: 2)
            case 2:
                return Stage(eyebrow: Loc.str("내 주기"), title: Loc.str("마지막 생리는..."),
                             body: [Loc.str("마지막 생리 시작일을 선택해주세요."), Loc.str("지난달로 넘기면 이전 생리도 기록할 수 있어요.")],
                             spot: .dial, content: dial(2), dialStep: 2)
            default:
                var c = dial(2)
                c.ring = true; c.number = cycleLengthAnswer; c.ticks = cycleLengthAnswer
                return Stage(eyebrow: Loc.str("내 주기"), title: Loc.str("주기가 보통\n며칠쯤인가요?"),
                             body: [Loc.str("지난 생리에서 다음 생리까지의 간격을 알려주세요.")],
                             spot: .mid, content: c, dialStep: 2)
            }
        default:
            return Stage(eyebrow: Loc.str("저장 위치"), title: Loc.str("기록의 저장은 \n오로지 이곳에만"),
                         body: storageBody, spot: .dial, content: dial(3), dialStep: 3)
        }
    }

    private func dial(_ n: Int) -> LensContent {
        LensContent(progress: Double(n) / Double(Self.dialTotal))
    }

    /// 사계절 장 카피 — 첫 줄은 계절의 평문 뜻(seasonMeta.plain과 같은 어휘), 본문 두 줄은 무드라인 톤.
    private func seasonMood(_ phase: CyclePhase) -> String {
        switch phase {
        case .menstrual: Loc.str("생리 중이에요.")
        case .follicular: Loc.str("생리가 끝난 뒤예요.")
        case .ovulation: Loc.str("배란 무렵이에요.")
        case .luteal: Loc.str("생리 전이에요.")
        }
    }

    private func seasonBody(_ phase: CyclePhase) -> [String] {
        switch phase {
        case .menstrual: [Loc.str("주기는 여기서 시작해요."), Loc.str("조금은 쉬어가도 괜찮아요.")]
        case .follicular: [Loc.str("몸이 다시 가벼워지는 때."), Loc.str("작은 것부터 하나씩 깨워봐요.")]
        case .ovulation: [Loc.str("한 달 중 가장 밝은 때."), Loc.str("하고 싶은 만큼 빛나도 좋아요.")]
        case .luteal: [Loc.str("한 달 중 가장 긴 계절."), Loc.str("스스로를 돌아보는 시간을 가져봐요.")]
        }
    }

    /// 단계 정체성 — 카피·시트 전환(크로스페이드)과 렌즈 이동 애니메이션의 트리거
    private var stageKey: String { "\(step)-\(seasonPage)-\(baselinePage)-\(entering)" }

    /// 심플 지면 — 언어 단계, 그리고 테마 단계부터 심플을 고른 동안(라이브 전환)
    private var plainSurface: Bool { step == 0 || (step >= 3 && themeChoice == .plain) }

    /// 사계절 창(2026-09-12) — 브랜드 렌즈 자리에서 열려 화면을 덮는다. 테마 장부터는 덮인 채 사라지고,
    /// 뒤로 돌아오면 다시 뜬다. 브랜드 장으로 되돌아가면 렌즈 자리로 오므라든다.
    private var seasonWindowOpen: Bool { step == 2 && !entering }

    private func seasonWindow(_ current: Stage, in size: CGSize, column: CGFloat, insets: EdgeInsets) -> some View {
        let hero = LensSpot.hero.resolve(in: size, column: column)
        let cover: CGFloat = max(size.width, size.height) * 2.2
        let phase: CyclePhase = current.photo ?? Self.seasonOrder[min(max(seasonPage, 0), 3)]
        return SeasonWindow(phase: phase, diameter: step >= 2 ? cover : hero.diameter, center: hero.center,
                            safeInsets: insets, reduceMotion: reduceMotion)
            .opacity(seasonWindowOpen ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.86), value: seasonWindowOpen)
    }

    private var healthOn: Bool { mirror.linked && mirror.writeAuthorized }

    /// ⑤ 저장 위치 카피 — 실제 활성 경로만 말한다(§7 privacy-washing 금지)
    private var storageBody: [String] {
        var lines: [String] = []
        if healthOn {
            lines.append(Loc.str("기록은 이 기기와 Apple 건강 앱에 저장돼요."))
            lines.append(Loc.str("건강 앱 설정에 따라 동기화될 수 있어요."))
        } else {
            lines.append(AppStores.cloudEnabled ? Loc.str("기록은 이 기기에 저장됩니다.") : Loc.str("기록은 이 기기에만 저장됩니다."))
        }
        if AppStores.cloudEnabled {
            lines.append(Loc.str("플래너와 컨디션 기록은 당신의 iCloud로 기기 간에 이어지고,"))
            lines.append(Loc.str("별도의 서버나 데이터베이스에 저장되지 않습니다."))
        }
        return lines
    }

    // ══ 본체 ══
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let column = min(size.width, 560)   // 아이패드 중앙 조판(2026-07-23)
            let current = stage
            let lensSpot = lensGeometry(current, in: size, column: column)
            ZStack(alignment: .top) {
                ground(size: size, column: column, safeTop: geo.safeAreaInsets.top)
                seasonWindow(current, in: size, column: column, insets: geo.safeAreaInsets)
                TempoLens(center: lensSpot.center, diameter: lensSpot.diameter,
                          magnify: entering ? 1.02 : current.spot.magnify,
                          containerSize: size, content: entering ? LensContent() : current.content,
                          flat: plainSurface, reduceMotion: reduceMotion,
                          groundInsets: geo.safeAreaInsets) {
                    lensGround
                }
                .opacity(current.hideLens && !entering ? 0 : 1)
                .animation(reduceMotion ? nil : .spring(response: entering ? 0.9 : 0.72, dampingFraction: 0.86), value: stageKey)
                VStack(alignment: .leading, spacing: 0) {
                    topBar(current)
                    // 사계절 장은 카피가 아래로 — 사진의 주 피사체가 상단에 있어 둘이 같은 자리를 다퉜다(C안).
                    if current.photo != nil {
                        Spacer(minLength: 0)
                        copyBlock(current)
                            .padding(.bottom, 86)   // 하단 CTA 시트(52 + 여백)를 비운다
                    } else {
                        copyBlock(current)
                            .padding(.top, 8)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)   // 뒤로가기 버튼을 위로(2026-07-22 사용자 요청)
                .frame(width: column)
                .frame(maxWidth: .infinity)
                .opacity(entering ? 0 : 1)
                if entering { enterTitle }
            }
            .overlay(alignment: .bottom) { sheet(current, column: column).opacity(entering ? 0 : 1) }
        }
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
        .onAppear {
            // 재진입(다시 보기)은 언어 단계를 건너뛴다 — 이미 쓰는 언어가 있다
            if isRevisit && step == 0 { step = 1 }
            if step > 0 { revealProgress = 1 }
            // 온보딩 지면은 은필 고정 — 재진입은 쓰던 테마를 기억했다가 닫을 때 되돌린다
            if isRevisit, ThemeStore.current != .standard {
                restoreThemeRaw = UserDefaults.standard.string(forKey: ThemeStore.storageKey)
                ThemeStore.apply(AppTheme.standard.rawValue)
            }
        }
        // 은필 열림 — 언어에서 브랜드로 넘어가는 순간 렌즈 중심에서 지면이 원형으로 열린다(1.25s)
        .onChange(of: step) { old, new in
            guard old == 0, new == 1, revealProgress < 1 else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 1.25)) { revealProgress = 1 }
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

    private func lensGeometry(_ current: Stage, in size: CGSize, column: CGFloat) -> (center: CGPoint, diameter: CGFloat) {
        if entering {
            // 렌즈가 창이 된다 — 화면을 덮는 지름
            return (CGPoint(x: size.width / 2, y: size.height / 2), max(size.width, size.height) * 2.2)
        }
        return current.spot.resolve(in: size, column: column)
    }

    // ── 지면 — 심플(평면) 위에 은필(frost + 겨울 계절광 + 선화)이 렌즈 중심에서 원형으로 열린다 ──
    /// 온보딩 = 겨울 지면 고정(사용자 확정). 구성은 프로토 `.world` 그대로(OnboardingGround) —
    /// 앱 지면(SeasonLight 두 장)은 굵은 줄기가 가운데를 지나가 프로토와 달랐다(2026-09-07 대조).
    private var silverGround: some View { OnboardingGround() }

    /// 렌즈 속 지면 — 선화 원본 농도. 프로토는 렌즈 안에서 선화가 확대돼 비쳐 「돋보기」로 읽힌다.
    private var lensGround: some View { OnboardingGround(motifOpacity: 1) }

    private func ground(size: CGSize, column: CGFloat, safeTop: CGFloat) -> some View {
        let origin = LensSpot.hero.resolve(in: size, column: column).center
        let reveal = max(1, revealProgress * (max(size.width, size.height) * 2.6))
        return ZStack {
            Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
            silverGround
                .mask {
                    Circle()
                        .frame(width: reveal, height: reveal)
                        .position(x: origin.x, y: origin.y + safeTop)
                }
                .opacity(plainSurface ? 0 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 1.0), value: plainSurface)
        }
        .ignoresSafeArea()
    }

    // ── 브랜드 스플래시 ──
    // 사운드를 한 번 낸다. 탭하면 즉시 건너뛴다.
    // 대표님 제작 정적 이미지(2026-08-29, App/Assets.xcassets/OnboardingSplash) — 온보딩은
    // 테마 선택 전(항상 기본 지면)이라 SplashGround의 테마별 배경 분기가 필요 없다.
    private var splash: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()
            Image("OnboardingSplash")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
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
        Self.splashShownThisLaunch = true
        if silencing { SignatureSound.shared.fadeOut() }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { showSplash = false }
    }

    // ── 마지막: 렌즈가 창이 되고 「오늘」이 뜬다 ──
    private var enterTitle: some View {
        VStack(spacing: 8) {
            Text("오늘")
                .font(LensSpec.serif(44))
                .foregroundStyle(Ink.text)
            Text(enterSubtitle)
                .font(.system(size: 14))
                .foregroundStyle(Ink.text.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.animation(.easeOut(duration: 0.5).delay(0.35)))
        .accessibilityHidden(true)
    }

    private var enterSubtitle: String {
        let today = Calendar.current.startOfDay(for: .now)
        guard let info = CycleSnapshot(periodDays: periodDays).phaseInfo(on: today) else { return "" }
        return "\(info.meta.name) · \(Loc.fmt("%lld일차", info.dayInPhase))"
    }

    // ── 상단: back — 2단계부터, 그리고 인트로 씬B·C에서도 이전 씬으로(2026-07-22 사용자 요청) ──
    // 재진입(설정 「온보딩 다시 보기」)이면 좌상단 X = 즉시 나가기(2026-08-09 베타 피드백).
    // 우상단 진행 다이얼은 렌즈가 그린다 — 여기엔 VoiceOver용 자리만 둔다.
    private func topBar(_ current: Stage) -> some View {
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
            if step >= 2 || (step == 1 && !isRevisit) {
                Button {
                    lightFeedback += 1
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(Ink.text.opacity(0.6))
                        .frame(width: 44, height: 44)
                }
            }
            Spacer()
            if let n = current.dialStep {
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityElement()
                    .accessibilityLabel(Loc.fmt("진행 %lld / 3", n))
            }
        }
        .frame(height: 44)
    }

    private func goBack() {
        let anim: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.4)
        withAnimation(anim) {
            if step == 1 {
                step = 0   // 브랜드 장에서 뒤로 = 언어 단계(신규만)
            } else if step == 2, seasonPage > 0 {
                seasonPage -= 1   // 사계절 안에서는 장 단위로
            } else if step == 4, let prev = baselineStack.popLast() {
                baselinePage = prev
            } else {
                step -= 1
                if isRevisit && step == 3 { step = 2 }   // 재진입은 테마 단계를 안 거친다
                if step == 2 { seasonPage = 3 }          // 사계절로 되돌아오면 마지막 장(가을)부터
            }
        }
    }

    /// 사계절 장 위치 인디케이터 — 활성은 알약(16), 나머지는 점(5).
    /// 화면에서 뺀 「N / 4」는 VoiceOver 라벨로 남긴다(기존 카탈로그 키 재사용).
    private func seasonDots(_ index: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<4, id: \.self) { n in
                Capsule(style: .continuous)
                    .fill(Ink.text.opacity(n == index ? 0.66 : 0.24))
                    .frame(width: n == index ? 16 : 5, height: 5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Loc.fmt("한 달 안의 사계절 %1$lld / 4", index + 1))
    }

    // ── 카피 블록 — 표제·본문은 은필 명조, 언어·심플 지면은 산세리프(지면과 함께 서체도 열린다) ──
    private func copyBlock(_ current: Stage) -> some View {
        let plain = plainSurface
        return Group {
            VStack(alignment: .leading, spacing: 10) {
                Text(current.eyebrow)
                    .font(plain ? .system(size: 12, weight: .medium) : LensSpec.serif(12, bold: false))
                    .kerning(plain ? 1.5 : 2)
                    .foregroundStyle(Ink.text.opacity(0.55))
                if let index = current.seasonDots { seasonDots(index) }
                if let photo = current.photo {
                    // 사계절 장 — 계절 글리프 + 계절색 표제. 글리프는 장식, 라벨은 표제가 담당.
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        SeasonGlyph(phase: photo, size: 22, color: current.titleColor)
                        Text(current.title)
                            .font(LensSpec.serif(36))
                            .foregroundStyle(current.titleColor ?? Ink.text)
                    }
                } else {
                    Text(current.title)
                        .font(plain ? .system(size: current.hero ? 36 : 30, weight: .semibold)
                                    : LensSpec.serif(current.hero ? 36 : 30))
                        .foregroundStyle(Ink.text)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 사계절 장은 mood·body의 대비를 벌린다 — 16/15로 두면 한 덩어리로 읽혔다(2026-09-12 C안).
                let photoStage = current.photo != nil
                if let mood = current.mood {
                    Text(mood)
                        .font(LensSpec.serif(photoStage ? 18 : 16, bold: false))
                        .foregroundStyle(Ink.text.opacity(photoStage ? 0.95 : 0.9))
                }
                if !current.body.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(current.body, id: \.self) { line in Text(line) }
                    }
                    .font(.system(size: photoStage ? 14.5 : 15))
                    .lineSpacing(5)
                    .foregroundStyle(Ink.text.opacity(photoStage ? 0.62 : 0.72))
                    .fixedSize(horizontal: false, vertical: true)
                }
                if !current.fine.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(current.fine, id: \.self) { line in Text(line) }
                    }
                    .font(.system(size: 12))
                    .lineSpacing(4)
                    .foregroundStyle(Ink.text.opacity(0.5))
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .id(stageKey)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)),
                                    removal: .opacity.combined(with: .offset(y: -6))))
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.42), value: stageKey)
        .contentShape(Rectangle())
        .onTapGesture { if current.bare { primaryAction() } }   // 브랜드·곡선·일정 장 = 탭 진행(종전 문법)
        .accessibilityElement(children: .contain)
    }

    // ── 하단 유리 시트 — 단계 콘텐츠 + 행동 ──
    private func sheet(_ current: Stage, column: CGFloat) -> some View {
        VStack(spacing: 10) {
            Group {
                sheetBody(current)
                    .id(stageKey)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)),
                                            removal: .opacity.combined(with: .offset(y: 10))))
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.42), value: stageKey)
            actions(current)
        }
        .padding(.horizontal, 24)
        .padding(.top, current.bare ? 0 : 22)
        .padding(.bottom, 10)
        .frame(width: column)
        .frame(maxWidth: .infinity)
        .modifier(GlassSheet(bare: current.bare))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: current.bare)
    }

    @ViewBuilder
    private func sheetBody(_ current: Stage) -> some View {
        switch step {
        case 0: languageOptions
        case 1, 2: EmptyView()   // 브랜드·사계절 = 시트 없음(bare)
        case 3: themeCards
        case 4:
            switch baselinePage {
            case 0: linkRow
            case 1:
                RulerSlider(value: $periodLength, range: 1...10, unit: Loc.str("일")) { lightFeedback += 1 }
            case 2:
                OnboardingCalendar(periodDays: periodDays, fillLength: periodLength) { lightFeedback += 1 }
            default:
                RulerSlider(value: $cycleLengthAnswer, range: 21...35, unit: Loc.str("일")) { lightFeedback += 1 }
            }
        default: storageRows
        }
    }

    // ── 행동 — 전 스텝 공통 위치(2026-07-22 베타 피드백: 버튼 위치 통일) ──
    private func actions(_ current: Stage) -> some View {
        VStack(spacing: 6) {
            // ② 연동 페이지의 주 행동은 콘텐츠의 스위치 — 하단은 secondary만(프로토 확정 위계)
            if step == 4 && baselinePage == 0 {
                ghostButton("직접 기록할게요") { pushBaseline(1) }
            } else {
                Button(primaryLabel) { lightFeedback += 1; primaryAction() }
                    .buttonStyle(InkCapsuleButtonStyle())
                    .disabled(!primaryEnabled)
                    .opacity(primaryEnabled ? 1 : 0.35)
            }
            if step == 4 && baselinePage == 2 {
                ghostButton("나중에 기록할게요") { advance { step = 5 } }   // 구 "기억 안 나요" 승계 — S0 처리
            }
            if step == 4 && baselinePage == 3 {
                ghostButton("잘 모르겠어요") { AppSettings.cycleLengthPrior = nil; advance { step = 5 } }
            }
            if step == 3 {
                caption("앞으로 7일간 모든 테마를 자유롭게 바꿔볼 수 있어요.")
            }
            if step == 5 {
                caption("언제든 내보내고 지울 수 있어요.")
            }
        }
    }

    private func caption(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 12))
            .foregroundStyle(Ink.text.opacity(0.45))
            .frame(maxWidth: .infinity)
    }

    /// ② 캘린더 페이지의 「다음」은 에피소드 1개 이상일 때만 — 스킵은 secondary가 담당
    private var primaryEnabled: Bool {
        if step == 4 && baselinePage == 2 { return episodeCount >= 1 }
        return true
    }

    private func ghostButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            lightFeedback += 1
            action()
        } label: {
            Text(title)
        }
        .buttonStyle(GhostUnderlineButtonStyle())
    }

    /// 단계 전환 — 카피·시트 크로스페이드와 렌즈 이동이 같은 트랜잭션을 탄다
    private func advance(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.42)) { change() }
    }

    private func pushBaseline(_ page: Int) {
        lightFeedback += 1
        baselineStack.append(baselinePage)
        advance { baselinePage = page }
    }

    /// 연동 알럿이 닫힌 뒤 1회 — 분기 = 병합 결과 에피소드 수(프로토 확정)
    private func consumeLinkAdvance() {
        guard pendingLinkAdvance, step == 4 else { return }
        pendingLinkAdvance = false
        let n = episodeCount
        if n >= 2 { advance { step = 5 } }   // 실측 gap 확보 → ②-2~④ 전부 스킵
        else if n == 1 { pushBaseline(3) }   // 주기 질문만
        else { pushBaseline(1) }             // 거부·빈 건강앱 → 직접 기록
    }

    private var primaryLabel: String {
        switch step {
        case 0, 1, 2, 3, 4: Loc.str("다음")   // 「계속」 → 「다음」 단일 라벨(2026-09-07 규칙)
        default: Loc.str("시작하기")          // 마지막 장 하나만 「시작하기」(한 의도 = 한 라벨)
        }
    }

    private func primaryAction() {
        switch step {
        case 0: advance { step = 1 }
        case 1: advance { step = 2; seasonPage = 0 }   // 사계절은 재진입에도 보여준다(설명 장)
        case 2:
            if seasonPage < 3 {
                advance { seasonPage += 1 }
            } else {
                // 재진입(다시 보기)은 테마 단계 스킵(2026-08-19) — 이미 쓰는 테마가 있는데
                // 여기서 고르게 하면 닫는 순간 그 선택으로 갈아타 버린다.
                advance { step = isRevisit ? 4 : 3 }
            }
        case 3:
            // 테마 선택 저장(2026-08-19) — 종료 시트의 기본 선택값으로도 쓴다("이전 거랑 연결").
            // 적용은 여기서 하지 않는다 — 테마 변경 = 루트 `.id` 리빌드가 이 플로우의 step을
            // 날린다(2026-08-11 결함과 같은 경로). finishOnboarding에서 적용.
            UserDefaults.standard.set(themeChoice.rawValue, forKey: ThemeTrial.choiceKey)
            advance { step = 4 }
        case 4:
            switch baselinePage {
            case 1:
                AppSettings.periodLengthPrior = periodLength   // §5.3 층 2 M 초기값(개정 M)
                pushBaseline(2)
            case 2:
                if episodeCount == 1 { pushBaseline(3) }   // 실측 gap 없음 → 주기 질문
                else { advance { step = 5 } }              // ≥2 = 실측 gap 있음 → 안 묻는다
            case 3:
                AppSettings.cycleLengthPrior = cycleLengthAnswer
                advance { step = 5 }
            default: break
            }
        default: finishOnboarding()   // 저장 위치 = 마지막 장
        }
    }

    /// 온보딩 종료 한 창구 — 마지막 연출(렌즈가 창이 된다) 뒤 commitFinish. 재진입·Reduce Motion은 즉시.
    private func finishOnboarding() {
        guard !entering else { return }
        if reduceMotion || isRevisit {
            commitFinish()
            return
        }
        withAnimation(.spring(response: 0.9, dampingFraction: 0.86)) { entering = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            commitFinish()
        }
    }

    /// 실제 종료 — 재진입 표식도 여기서 내린다(다음 첫 실행과 혼동 방지)
    private func commitFinish() {
        // 테마 적용(2026-08-19) — 신규 온보딩만. 닫히는 순간이라 루트 `.id` 리빌드가 무해하다.
        // 재진입은 테마 단계를 안 거치지만, 남아 있는 옛 choiceKey로 덮지 않게 이중 가드.
        if !isRevisit, let raw = UserDefaults.standard.string(forKey: ThemeTrial.choiceKey) {
            ThemeStore.apply(raw)
            UserDefaults.standard.set(raw, forKey: ThemeStore.storageKey)
        }
        if isRevisit, let raw = restoreThemeRaw {
            ThemeStore.apply(raw, pointRawValue: UserDefaults.standard.string(forKey: PointColor.storageKey))
        }
        // 첫 실행 튜토리얼 체인(2026-09-04)은 폐지(2026-09-09 — 코치는 설정 옵트인 전용, CoachStore).
        // TutorialGate는 잔여 잠금 해제 경로만 남는다.
        isRevisit = false
        onboardingDone = true
    }

    // ══ 시트 콘텐츠 ══

    // ── 언어 선택 — 0단계(2026-08-21 칩 → 08-22 베타 "첫 탭을 따로 빼줘") ──
    /// 기본값은 **기기 설정 따름**. 여기서 고르면 즉시 전환된다(루트 .id 리빌드 — 이 뷰가 새로
    /// 만들어져 step이 0으로 돌아오지만, 0단계가 곧 이 화면이라 제자리다. 스플래시는 프로세스당 1회).
    /// 이름은 각자의 언어로(endonym) — 지금 화면이 무슨 언어든 자기 언어를 찾을 수 있어야 한다.
    private var languageOptions: some View {
        VStack(spacing: 10) {
            ForEach(AppLanguage.allCases) { lang in
                languageRow(lang)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("언어 선택")
    }

    private func languageRow(_ lang: AppLanguage) -> some View {
        let selected = appLanguage == lang.rawValue
        return Button {
            lightFeedback += 1
            Loc.apply(lang)          // 즉시 반영(정적 캐시) — @AppStorage 변화가 트리를 리빌드한다
            appLanguage = lang.rawValue
        } label: {
            HStack(spacing: 10) {
                if lang == .system {
                    Text("기기 설정 따름")
                } else {
                    Text(verbatim: lang.nativeName)   // 이름 자체가 그 언어 — 번역 대상이 아니다
                }
                Spacer(minLength: 0)
                InkRadio(on: selected)
            }
            .font(.system(size: 16, weight: selected ? .medium : .regular))
            .foregroundStyle(Ink.text)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Ink.text.opacity(selected ? 0.10 : 0.05), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // ── 테마 선택(2026-08-19 사용자 결정 — 기본·은필 택1 + 7일 체험 고지). 고르면 지면이 라이브로 바뀐다 ──
    private var themeCards: some View {
        VStack(spacing: 10) {
            ForEach([AppTheme.standard, AppTheme.plain]) { theme in
                themeCard(theme)
            }
        }
    }

    private func themeCard(_ theme: AppTheme) -> some View {
        let on = themeChoice == theme
        let p = theme.palette()
        let month = Date.now.formatted(Loc.dateTime.month(.wide))
        return Button {
            lightFeedback += 1
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { themeChoice = theme }
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text(month)
                        .font(theme == .plain ? .system(size: 15, weight: .bold) : LensSpec.serif(15))
                        .foregroundStyle(p.text)
                    Spacer(minLength: 0)
                    HStack(spacing: 3) {
                        ForEach(Array([p.spring, p.summer, p.autumn, p.winter].enumerated()), id: \.offset) { _, c in
                            Circle().fill(c).frame(width: 6, height: 6)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .frame(width: 150, height: 44)
                .background(p.paper, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                Text(theme.displayName)
                    .font(LensSpec.serif(17))
                    .foregroundStyle(Ink.text)
                Spacer(minLength: 0)
                InkRadio(on: on)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(red: 250 / 255, green: 250 / 255, blue: 248 / 255).opacity(0.72),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Ink.text.opacity(on ? 0.8 : 0.18), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Loc.fmt("%1$@ 테마", "\(theme.displayName)"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // ── ②-1 연동 — 주 행동 = 스위치(§8.2.1 스위치 켜기 = 시스템 시트). 분기는 consumeLinkAdvance ──
    private var linkRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: linkBinding) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("건강 앱과 연동")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Ink.text)
                    Text("쓰던 앱이 건강 앱에 남긴 기록을 불러올 수 있어요.")
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.text.opacity(0.55))
                }
            }
            .toggleStyle(MatteToggleStyle())
            .disabled(!mirror.available)
            .onChange(of: mirror.linked) { _, _ in lightFeedback += 1 }
            if !mirror.available {
                Text("이 기기에선 건강 앱을 사용할 수 없습니다.")
                    .font(.caption)
                    .foregroundStyle(Ink.text.opacity(0.55))
            }
            if mirror.available && mirror.linked {
                // 읽기 권한은 애플이 재요청 못 하게 막음 — 안 불러와지면 설정 원탭 이동(2026-07-24)
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
                            syncMessage = Loc.str("건강 앱 권한을 허용하지 않으면 연동할 수 없습니다. 직접 기록으로 이어갈게요.")
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

    // ── ③ 예시 칩 — 탭 = 실제 아이템 추가, 다시 탭 = 빠짐(2026-08-09 베타 피드백 토글 전환) ──
    // ── ⑤ 저장 위치 — 아이패드·iCloud 행(2026-09-07 디테일 ②): 같은 Apple ID면 플래너·체크인만 이어진다 ──
    // 2026-07-23 개정(§5.2 동기화 실장): iCloud 행·카피는 실제 활성일 때만(정확성 — §7 privacy-washing 금지).
    private var storageRows: some View {
        let cloudOn = AppStores.cloudEnabled
        return VStack(spacing: 0) {
            placeRow(icon: "iphone", name: Loc.str("이 기기"),
                     sub: cloudOn ? Loc.str("생리 기록은 여기에만") : Loc.str("생리 기록 · 플래너 · 컨디션 기록 전부"), first: true)
            if healthOn {
                placeRow(icon: "heart", name: Loc.str("Apple 건강 앱"), sub: nil, first: false)
            }
            if cloudOn {
                placeRow(icon: "ipad", name: Loc.str("아이패드 · iCloud"),
                         sub: Loc.str("같은 Apple ID면 플래너와 컨디션 기록이 이어져요. 생리 기록은 넘어가지 않아요."), first: false)
            }
        }
    }

    private func placeRow(icon: String, name: String, sub: String?, first: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Ink.text.opacity(0.6)).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 16)).foregroundStyle(Ink.text)
                if let sub {
                    Text(sub).font(.system(size: 13)).foregroundStyle(Ink.text.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Ink.text.opacity(0.6))
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(Ink.text.opacity(0.12)).frame(height: 1) }
        }
    }
}

// ── 온보딩 ③ 장별 선화 (2026-08-09 그림 추가 — 은필 스트로크, trim 드로잉. 2026-09-07부터 렌즈 안에 뜬다) ──
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

/// 에너지 흐름 곡선 (프로토 v72 path를 정규화 — 겨울 저점→봄 상승→여름 정점→가을 하강).
/// 2026-09-07부터 온보딩은 렌즈 속 LensWaveShape를 쓴다 — 다른 참조가 있을 수 있어 존치.
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
