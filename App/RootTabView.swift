// 템포루틴 — 루트 탭 (§8.1 Tab Bar. P0 진행분: 오늘·캘린더·설정. 나의 리듬은 후속 단계에서 추가)
// HK 미러 sync는 여기서 — 실행·포그라운드 복귀 시(§5.7 read 병합 + 삭제 전파).

import SwiftUI
import SwiftData
import UIKit   // 하단바 지면·라벨색은 UITabBarAppearance로만 잡힌다(티켓, 2026-08-16)
import StoreKit   // 체험 종료 뒤 앱 평가 요청(2026-08-25)

/// 루트 탭 식별자 — 리빌드를 건너 살아남아야 해서 문자열로 저장한다(§8.1 탭 순서).
enum RootTab: String {
    case today, calendar, rhythm, settings

    static let storageKey = "rootTab"
    /// 테마 탭 시트도 같은 이유로 뷰 밖에 둔다 — 시트가 열린 채 테마를 갈아입어도 닫히지 않는다
    static let themeShopKey = "themeShopOpen"
}

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @Query private var periodDays: [PeriodDay]
    @Query(sort: \ScheduleItem.date) private var schedules: [ScheduleItem]   // 위젯 스냅샷용(Phase 2)
    @Query(sort: \InputItem.createdAt) private var inputs: [InputItem]        // 오늘 카드 위젯(2026-07-27)
    @Query(sort: \OutputItem.createdAt) private var outputs: [OutputItem]
    @Query private var completions: [ItemCompletion]
    @Query private var inputProgresses: [InputProgress]   // 위젯 진행 라벨(2026-08-20)
    @Query private var checkIns: [DailyCheckIn]   // 씨앗 획득 원장 백필(2026-08-20)
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var showLaunchSplash = !LaunchSplashGate.shown
    @AppStorage(ThemeStore.storageKey) private var appTheme = AppTheme.plain.rawValue
    /// 포인트색(2026-08-17) — 아래 `.id`에 함께 태운다. 테마 키만 보면 포인트색 변경이
    /// 리빌드를 못 일으켜, 이미 그려진 화면이 옛 색으로 남았다("되었다 안 되었다" 베타 보고 —
    /// 색을 바꾼 직후엔 그대로였다가 테마 왕복·재실행 등 다른 이유로 리빌드될 때만 반영됐다).
    @AppStorage(PointColor.storageKey) private var pointColor = PointColor.vermilion.rawValue
    /// 앱 언어(2026-08-21) — 테마·포인트색과 같은 리빌드 경로에 태운다. 정적 캐시(Loc)만
    /// 바꾸면 이미 그려진 화면이 옛 언어로 남는다.
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue
    /// 선택 탭을 뷰 밖(UserDefaults)에 둔다 — 아래 `.id(appTheme)` 리빌드가 TabView의 내부
    /// 선택 상태를 통째로 버려서, 테마를 갈아입을 때마다 첫 탭으로 튕기던 결함(2026-08-11).
    /// 실행 간 이월은 안 한다(TempoRoutineApp.init에서 「오늘」로 되돌린다) — 이번 수정 범위는
    /// 리빌드 생존까지다.
    @AppStorage(RootTab.storageKey) private var rootTab = RootTab.today.rawValue
    /// 테마 탭 시트 — 진입점은 둘(오늘 탭 씨앗 배지·설정 테마 행)이지만 표시는 여기 한 곳이다.
    /// 각 화면에서 띄우면 같은 플래그를 보는 시트가 두 개가 된다.
    @AppStorage(RootTab.themeShopKey) private var showThemeShop = false
    /// 체험 종료 선택 시트(2026-08-19) — 리빌드에 날아가도 .task 재판정이 다시 띄운다(@State로 충분)
    @State private var showTrialEnd = false
    /// 시작 작업(HealthKit 동기화·위젯 발행·알림 재예약·동기화 왕복)은 **프로세스당 1회**.
    /// 테마·언어 변경 = 루트 `.id` 리빌드인데, 그때마다 `.task`가 다시 돌아 이 무거운 묶음이
    /// 통째로 재실행됐다 — "적용이 조금씩 느리다"(2026-08-22 베타)의 본체. 쓰기는 메인뿐.
    nonisolated(unsafe) private static var bootstrapped = false

    /// 체험 종료 뒤 시스템 평가 프롬프트 1회(2026-08-25 대표님 지시). 7일을 다 써 본 사람에게
    /// 묻는 자리라 맥락이 맞다 — 기능을 막거나 보상을 걸지 않는다(심사 지침 1.1.7).
    /// ⚠ 표시 여부·횟수는 애플이 정한다(연 3회 상한). **TestFlight·개발 빌드에선 안 뜬다** —
    /// 실기기 확인이 앱스토어 빌드에서만 가능하다는 뜻이라 여기 적어 둔다.
    private func askForReviewAfterTrial() {
        guard onboardingDone, ThemeTrial.hasEnded, !ThemeTrial.reviewAsked else { return }
        ThemeTrial.markReviewAsked()   // 프롬프트가 안 떠도 다시 묻지 않는다(애플 상한과 같은 태도)
        let review = requestReview
        Task { @MainActor in
            // 시트 닫힘·탭 전환 애니메이션과 겹치면 시스템 팝업이 씹힌다
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            review()
        }
    }

    private func dismissLaunchSplash() {
        guard showLaunchSplash else { return }
        LaunchSplashGate.shown = true
        withAnimation(.easeOut(duration: 0.4)) { showLaunchSplash = false }
    }

    var body: some View {
        TabView(selection: $rootTab) {
            TodayView()
                .tabItem { tabLabel("오늘", symbol: "circle.inset.filled", ticketAsset: "TicketIconSun") }
                .tag(RootTab.today.rawValue)
            NavigationStack {
                SeasonCalendarView()
            }
            .tabItem { tabLabel("캘린더", symbol: "calendar", ticketAsset: "TicketIconMoon") }
            .tag(RootTab.calendar.rawValue)
            RhythmView()
                .tabItem { tabLabel("나의 템포", symbol: "chart.xyaxis.line", ticketAsset: "TicketIconWave") }
                .tag(RootTab.rhythm.rawValue)
            NavigationStack {
                SettingsView()
            }
            .tabItem { tabLabel("설정", symbol: "gearshape", ticketAsset: "TicketIconStar") }
            .tag(RootTab.settings.rawValue)
        }
        // 선택 탭 색 — 포인트컬러만 다홍(2026-08-17 사용자 지시). tint는 아이콘·라벨을 함께 물들인다.
        .tint(ThemeStore.chrome.pointTabTint ? Ink.winter : Ink.text)
        // 티켓 = 발권물 흰 지면 하단바(시안 §3.3-⑦, 2026-08-16). 배경·라벨색은 UIKit
        // appearance로만 잡힌다 — 테마 변경 시 아래 `.id(appTheme)`가 탭바를 새로 만들어 반영된다.
        .onAppear { Self.applyTabBarAppearance() }
        // 모던 = 항상 다크 단일 외관(시안 §1.1) — 시스템 라이트에서 탭바 유리·ultraThinMaterial·
        // 설정 insetGrouped가 라이트로 렌더되던 결함의 뿌리(베타 피드백 2026-07-29: 탭바 밝아짐·
        // 설정 순백 카드·카드 과명 3건 동일 원인). 기본 테마는 nil = 시스템 따름(기존 다크 대응 유지).
        // 같은 뿌리가 반대 방향으로도 난다(베타 피드백 2026-08-19) — 인쇄물·유리 문법 테마
        // (티켓·활판·플레이리스트)는 팔레트가 라이트 고정인데, 시스템이 다크면 List 행 배경·
        // glassEffect 재질처럼 내 팔레트를 안 보는 시스템 컴포넌트만 검게 떨어진다.
        .preferredColorScheme({
            let chrome = (AppTheme(rawValue: appTheme) ?? .plain).chrome
            return chrome.forcesDarkAppearance ? .dark : chrome.forcesLightAppearance ? .light : nil
        }())
        // 테마 변경 = 전체 트리 리빌드(정적 팔레트 캐시 갱신 반영 — Theme.swift 반응성 설계).
        // 변경 진입점은 설정뿐이라 스택·스크롤 초기화는 허용 범위(2026-07-29 계획 리스크 ①).
        // 선택 언어 주입 — Text 리터럴은 이 로케일로 다시 조회된다(값 경로는 Loc.bundle 담당)
        .environment(\.locale, Loc.locale)
        .id(appTheme + "·" + pointColor + "·" + appLanguage)   // 포인트색·언어도 같은 리빌드 경로
        .onChange(of: appLanguage) { _, newValue in
            // 외부 변경(백업 복원·설정) 대비 보완 벨트 — 고르는 자리에서 이미 apply 한다
            Loc.apply(AppLanguage(rawValue: newValue) ?? .system)
            // 위젯 스냅샷 안 문구(「템포루틴」·「종일」·무드라인)는 **발행 시점 언어**로 박힌다 — 재발행
            WidgetBridge.publish(periodDays: periodDays, schedules: schedules,
                                 inputs: inputs, outputs: outputs, completions: completions,
                                 inputProgresses: inputProgresses)
        }
        .onChange(of: appTheme) { _, newValue in
            ThemeStore.apply(newValue)   // 설정의 선(先)apply 보완 벨트 — 외부 변경(백업 복원 등) 대비
            // 테마 미디어 온디맨드(2026-08-25) — 적용 순간이 다운로드 트리거. 이미 있으면 no-op
            ThemeMedia.shared.ensure(for: AppTheme(rawValue: newValue) ?? .plain)
            // 프록시를 리빌드 전에 갱신(2026-08-20) — onAppear에만 두면 새 UITabBar가 옛
            // 프록시로 먼저 만들어질 수 있다(테마 전환 직후 하단바만 이전 테마로 남던 증상)
            Self.applyTabBarAppearance()
            // 위젯도 즉시 테마 추종(Phase 5) — 스냅샷 재발행 + reloadAllTimelines(publish 내장)
            WidgetBridge.publish(periodDays: periodDays, schedules: schedules,
                                 inputs: inputs, outputs: outputs, completions: completions,
                                 inputProgresses: inputProgresses)
        }
        .onChange(of: pointColor) { _, newValue in
            // 시트의 선 apply와 같은 경로의 보완 벨트(외부 변경 대비) — apply는 멱등이라 무해
            ThemeStore.apply(appTheme, pointRawValue: newValue)
            WidgetBridge.publish(periodDays: periodDays, schedules: schedules,
                                 inputs: inputs, outputs: outputs, completions: completions,
                                 inputProgresses: inputProgresses)
        }
        // 시트는 자기 presentation — 위 preferredColorScheme이 닿지 않아 루트마다 강제(2026-08-20)
        .sheet(isPresented: $showThemeShop) { ThemeShopView().themeColorScheme() }
        // 체험 종료 선택 시트(2026-08-19) — 선택 전 닫기 불가(TrialEndSheet 쪽 interactiveDismissDisabled)
        .sheet(isPresented: $showTrialEnd) {
            TrialEndSheet {
                showTrialEnd = false
                askForReviewAfterTrial()   // 테마를 고른 직후 — 7일을 다 써 본 자리(2026-08-25)
            }
            .themeColorScheme()
        }
        // 콜드 런치 스플래시(2026-08-25 대표님 "앱 다시 켤 때 로딩화면") — 프로세스당 1회, 무음
        // 1.1s·탭 스킵. 온보딩(첫 실행)은 자체 스플래시(사운드 포함)가 있어 여기선 건너뛴다.
        // 루트 .id 리빌드(테마·언어 변경)엔 게이트가 재등장을 막는다.
        .overlay {
            if showLaunchSplash, onboardingDone {
                // 대표님 제작 정적 이미지(2026-08-30, App/Assets.xcassets/LaunchSplash). 그림 배경
                // 테마(은필·티켓·플리)는 제 지면 + 스크림 위에 로고·심볼만(SplashLogo, 밝은 판) —
                // 전 테마 동일 이미지가 테마 정체성을 지우던 것의 교정(2026-08-30 대표님 지시).
                ZStack {
                    if SplashGround.pictorial {
                        SplashGround(phase: CycleSnapshot(periodDays: periodDays)
                            .phase(on: Calendar.current.startOfDay(for: .now)))
                        Image("SplashLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 148)
                    } else {
                        Image("LaunchSplash")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .ignoresSafeArea()
                    }
                }
                .transition(.opacity)
                .contentShape(Rectangle())
                .onTapGesture { dismissLaunchSplash() }
                .task {
                    try? await Task.sleep(nanoseconds: 1_100_000_000)
                    dismissLaunchSplash()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("템포루틴")
                .accessibilityHint(Loc.str("탭하면 건너뜁니다"))
            }
        }
        // 온보딩 = fullScreenCover, 첫 실행 1회(§8.2.1)
        .fullScreenCover(isPresented: Binding(get: { !onboardingDone }, set: { if !$0 { onboardingDone = true } })) {
            OnboardingFlow().themeColorScheme()
        }
        // dev 자체 표본(2026-08-30) — dev 진입 리빌드마다 돌지만 플래그·빈 스토어 게이트로 1회만
        .task { DevSampleData.seedIfNeeded(context: modelContext) }
        .task {
            // 테마 7일 체험 시작(2026-08-19) — 기존 설치는 업데이트 후 첫 실행이 곧 시작.
            // 신규는 온보딩이 덮여 있는 동안 기록하지 않는다(완료 시 아래 onChange가 잡는다).
            if onboardingDone { ThemeTrial.beginIfNeeded() }
            // 체험 종료 판정 — 시트는 고를 게 있을 때만: 은필 미보유이거나, 미보유 테마를
            // 적용 중일 때. 은필 기보유 + 보유 테마 사용 중이면 조용히 종결(고를 게 없다).
            var trialSheetOpening = showTrialEnd
            if onboardingDone, ThemeTrial.needsResolution, !DevMode.active {
                let current = AppTheme(rawValue: appTheme) ?? .plain
                let currentOwned = current.seedPrice == nil || Seeds.owned.contains(current.rawValue)
                // 기본도 유료(2026-08-27 가격 개편) — 시트는 기본/은필 중 하나를 0원으로 주는
                // 소유의 뿌리다. 둘 다 미보유거나, 미보유 테마를 쓰는 중이면 띄운다.
                let ownsBase = Seeds.owned.contains(AppTheme.plain.rawValue)
                    || Seeds.owned.contains(AppTheme.standard.rawValue)
                if !ownsBase || !currentOwned {
                    showTrialEnd = true
                    trialSheetOpening = true
                } else {
                    ThemeTrial.resolve()
                }
            }
            // 시트가 안 뜨는 경로(조용한 종결·이미 종결된 기존 사용자)에서도 한 번은 묻는다.
            // 시트가 떴으면 그 닫힘 콜백이 맡는다 — 시트 위에 시스템 팝업을 겹치지 않게.
            // ⚠ 판정에 `showTrialEnd`를 다시 읽지 않는다 — 방금 쓴 @State는 같은 갱신 주기에서
            // 옛 값이 나올 수 있어 로컬 플래그로 잇는다.
            if !trialSheetOpening, !DevMode.active { askForReviewAfterTrial() }
            // 아래는 프로세스당 1회 — 리빌드(테마·언어 변경)에서는 건너뛴다. 테마는 자기 onChange가
            // 위젯을 재발행하고, 언어도 아래 onChange(of: appLanguage)가 맡는다.
            guard !Self.bootstrapped else { return }
            Self.bootstrapped = true
            // 개발자 모드(2026-08-27, DevMode.swift) — 아래 시작 작업은 전부 정지: 건강·동기화는
            // 실데이터를 만지고, 위젯 발행·알림 재예약은 dev의 빈 스토어 기준으로 실표면을
            // 덮는다(빈 재예약 = 실알림 취소). 백필도 dev 체크인이 실원장을 벌면 안 되니 막는다.
            guard !DevMode.active else { return }
            // 씨앗 획득 원장 백필(2026-08-20) — 원장 도입 전 획득(행 파생)을 1회 옮겨 적는다(멱등)
            Seeds.backfillEarnedLedger(checkIns)
            await HealthMirror.shared.sync(context: modelContext, periodDays: periodDays)
            WidgetBridge.publish(periodDays: periodDays, schedules: schedules,
                                 inputs: inputs, outputs: outputs, completions: completions,
                                 inputProgresses: inputProgresses)   // 위젯 스냅샷
            CoverageReminder.reschedule(periodDays: periodDays, context: modelContext)
            DailyNotices.reschedule(periodDays: periodDays, schedules: schedules)
            PlannerSync.shared.kick()   // 기기 간 동기화(2026-08-10) — 실행 시 왕복
            // 테마 미디어 온디맨드(2026-08-25) — 현재 테마 몫이 비어 있으면 받는다
            // (테마 적용 시 실패했거나, 백업 복원으로 테마만 넘어온 경우의 회복 경로)
            ThemeMedia.shared.ensureCurrent()
        }
        .onChange(of: onboardingDone) { _, done in
            if done { ThemeTrial.beginIfNeeded() }   // 신규 = 온보딩 완료 시각부터 7일
        }
        .onChange(of: scenePhase) { _, phase in
            guard !DevMode.active else { return }   // 개발자 모드 — 실데이터·실표면 경로 전부 정지
            if phase == .active {
                let current = periodDays
                Task { await HealthMirror.shared.sync(context: modelContext, periodDays: current) }
                DailyNotices.reschedule(periodDays: periodDays, schedules: schedules)
                PlannerSync.shared.kick()   // 복귀 시 다른 기기 변경 당겨오기
            } else if phase == .background {
                // 세션 중 편집 반영 — 백그라운드 진입 때 최신 상태로 재발행
                WidgetBridge.publish(periodDays: periodDays, schedules: schedules,
                                     inputs: inputs, outputs: outputs, completions: completions,
                                 inputProgresses: inputProgresses)
                // 이 세션의 체크인·일정까지 반영해 다시 건다(§5.12 ⑤ / §5.11 재스케줄 계약)
                CoverageReminder.reschedule(periodDays: periodDays, context: modelContext)
                DailyNotices.reschedule(periodDays: periodDays, schedules: schedules)
                PlannerSync.shared.kick()   // 이 세션의 편집 올리기
            }
        }
        // 앵커가 움직이면 사분면 경계도, 예측일도 통째로 움직인다 — 생리 기록 변화는 즉시 재스케줄.
        .onChange(of: periodDays.map(\.day)) { _, _ in
            guard !DevMode.active else { return }   // dev 기록으로 실알림을 다시 걸지 않는다
            CoverageReminder.reschedule(periodDays: periodDays, context: modelContext)
            DailyNotices.reschedule(periodDays: periodDays, schedules: schedules)
        }
    }

    /// 탭 아이콘 — 티켓만 유화 스티커(에셋은 `template-rendering-intent: original`이라
    /// 단색으로 물들지 않는다), 그 외 테마는 종전 SF Symbol.
    /// ⚠ 시안은 미선택 아이콘을 무채로 내리지만 여기서는 원색 그대로다 —
    /// `.tabItem`은 선택/미선택 이미지를 따로 줄 수 없다(UIKit `selectedImage` 상당 API 없음).
    /// 선택 구분은 라벨 색(잉크 100% / 45%)이 담당한다.
    @ViewBuilder
    // 로컬라이제이션(2026-08-20): String이면 Text(변수) 경로라 번역이 안 붙는다 —
    // LocalizedStringKey로 받아야 호출부 리터럴이 카탈로그 키가 된다
    private func tabLabel(_ title: LocalizedStringKey, symbol: String, ticketAsset: String) -> some View {
        if ThemeStore.chrome.textOnlyTabBar {
            // 활판(§2.3-7-2) — 아이콘 은퇴, 활자만. 활판 문법은 선과 활자다.
            Label { Text(title) } icon: { EmptyView() }
        } else if ThemeStore.chrome.ticketChrome {
            Label { Text(title) } icon: { Image(uiImage: Self.ticketTabIcon(named: ticketAsset)) }
        } else {
            Label(title, systemImage: symbol)
        }
    }

    /// 유화 스티커를 탭 아이콘 크기로 다시 그린다(2026-08-17 베타 피드백 — 에셋이 256pt
    /// 원본 그대로 들어가 그림이 하단바 전체를 덮고 라벨을 가렸다). `.tabItem`은 뷰 크기
    /// 지정을 무시하므로 UIImage 자체를 25pt로 만들어야 한다. 원색 유지 = .alwaysOriginal.
    @MainActor private static var ticketIconCache: [String: UIImage] = [:]

    @MainActor
    private static func ticketTabIcon(named name: String) -> UIImage {
        if let hit = ticketIconCache[name] { return hit }
        let side: CGFloat = 25
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            UIImage(named: name)?.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }.withRenderingMode(.alwaysOriginal)
        ticketIconCache[name] = rendered
        return rendered
    }

    /// 하단바 외형 — SwiftUI에 지면색·라벨색 API가 없어 UIKit appearance로 잡는다.
    private static func applyTabBarAppearance() {
        let appearance = UITabBarAppearance()
        if ThemeStore.chrome.textOnlyTabBar {
            // 활판(§2.3-7-2) — 종이 지면 + 상단 1pt 잉크 16% 룰, 라벨 = Gowun Batang 11
            // (시안 명시 서체 — 활판 본문 서체가 아니라 하단바 전용이다), 선택 100% / 42%.
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(Ink.paper)
            appearance.shadowColor = UIColor(Ink.text.opacity(0.16))
            let labelFont = UIFont(name: "GowunBatang-Regular", size: 11)
                ?? UIFont.systemFont(ofSize: 11)
            for layout in [appearance.stackedLayoutAppearance,
                           appearance.inlineLayoutAppearance,
                           appearance.compactInlineLayoutAppearance] {
                layout.normal.titleTextAttributes = [
                    .foregroundColor: UIColor(Ink.text.opacity(0.42)), .font: labelFont]
                layout.selected.titleTextAttributes = [
                    .foregroundColor: UIColor(Ink.text), .font: labelFont]
                // 아이콘이 빠진 만큼 라벨을 세로 중앙으로 — 기본 오프셋은 아이콘 아래 기준이다
                layout.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: -14)
                layout.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: -14)
            }
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
            return
        }
        if ThemeStore.chrome.tintedTabBar {
            // 테마 지면색 틴트 유리(2026-08-20 베타 피드백 "하단바가 한 테마 안에서 통일감이
            // 없다") — 시스템 유리는 탭마다 다른 지면을 샘플링해 바 색이 널뛴다. 블러 위에
            // Ink.paper 60%를 얹어 테마 지면으로 고정하고, 라벨·미선택 아이콘을 잉크로 맞춘다.
            // 선택 아이콘 색은 SwiftUI `.tint`가 담당(티켓 branch 전례).
            appearance.configureWithDefaultBackground()
            appearance.backgroundColor = UIColor(Ink.paper.opacity(0.6))
            let normal = UIColor(Ink.text.opacity(0.45))
            for layout in [appearance.stackedLayoutAppearance,
                           appearance.inlineLayoutAppearance,
                           appearance.compactInlineLayoutAppearance] {
                layout.normal.titleTextAttributes = [.foregroundColor: normal]
                layout.normal.iconColor = normal
                layout.selected.titleTextAttributes = [.foregroundColor: UIColor(Ink.text)]
            }
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
            return
        }
        guard ThemeStore.chrome.ticketChrome else {
            // 기본·포인트컬러 = 시스템 기본(유리) 그대로 — 프록시가 남아 오염되지 않게 되돌린다
            appearance.configureWithDefaultBackground()
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
            return
        }
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(TicketSpec.ticketPaper)
        // 캘린더 지면과 같은 웜 화이트라 경계가 사라진다 — 극세 괘선 한 줄로 나눈다
        appearance.shadowColor = UIColor(Ink.text.opacity(0.12))
        let normal = UIColor(Ink.text.opacity(0.45))
        let selected = UIColor(Ink.text)
        for layout in [appearance.stackedLayoutAppearance,
                       appearance.inlineLayoutAppearance,
                       appearance.compactInlineLayoutAppearance] {
            layout.normal.titleTextAttributes = [.foregroundColor: normal]
            layout.selected.titleTextAttributes = [.foregroundColor: selected]
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
