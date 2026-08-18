// 템포루틴 — 루트 탭 (§8.1 Tab Bar. P0 진행분: 오늘·캘린더·설정. 나의 리듬은 후속 단계에서 추가)
// HK 미러 sync는 여기서 — 실행·포그라운드 복귀 시(§5.7 read 병합 + 삭제 전파).

import SwiftUI
import SwiftData
import UIKit   // 하단바 지면·라벨색은 UITabBarAppearance로만 잡힌다(티켓, 2026-08-16)

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
    @Query private var periodDays: [PeriodDay]
    @Query(sort: \ScheduleItem.date) private var schedules: [ScheduleItem]   // 위젯 스냅샷용(Phase 2)
    @Query(sort: \InputItem.createdAt) private var inputs: [InputItem]        // 오늘 카드 위젯(2026-07-27)
    @Query(sort: \OutputItem.createdAt) private var outputs: [OutputItem]
    @Query private var completions: [ItemCompletion]
    @AppStorage("onboardingDone") private var onboardingDone = false
    @AppStorage(ThemeStore.storageKey) private var appTheme = AppTheme.plain.rawValue
    /// 포인트색(2026-08-17) — 아래 `.id`에 함께 태운다. 테마 키만 보면 포인트색 변경이
    /// 리빌드를 못 일으켜, 이미 그려진 화면이 옛 색으로 남았다("되었다 안 되었다" 베타 보고 —
    /// 색을 바꾼 직후엔 그대로였다가 테마 왕복·재실행 등 다른 이유로 리빌드될 때만 반영됐다).
    @AppStorage(PointColor.storageKey) private var pointColor = PointColor.vermilion.rawValue
    /// 선택 탭을 뷰 밖(UserDefaults)에 둔다 — 아래 `.id(appTheme)` 리빌드가 TabView의 내부
    /// 선택 상태를 통째로 버려서, 테마를 갈아입을 때마다 첫 탭으로 튕기던 결함(2026-08-11).
    /// 실행 간 이월은 안 한다(TempoRoutineApp.init에서 「오늘」로 되돌린다) — 이번 수정 범위는
    /// 리빌드 생존까지다.
    @AppStorage(RootTab.storageKey) private var rootTab = RootTab.today.rawValue
    /// 테마 탭 시트 — 진입점은 둘(오늘 탭 씨앗 배지·설정 테마 행)이지만 표시는 여기 한 곳이다.
    /// 각 화면에서 띄우면 같은 플래그를 보는 시트가 두 개가 된다.
    @AppStorage(RootTab.themeShopKey) private var showThemeShop = false

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
                .tabItem { tabLabel("나의 리듬", symbol: "chart.xyaxis.line", ticketAsset: "TicketIconWave") }
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
        .preferredColorScheme((AppTheme(rawValue: appTheme) ?? .plain).chrome.forcesDarkAppearance ? .dark : nil)
        // 테마 변경 = 전체 트리 리빌드(정적 팔레트 캐시 갱신 반영 — Theme.swift 반응성 설계).
        // 변경 진입점은 설정뿐이라 스택·스크롤 초기화는 허용 범위(2026-07-29 계획 리스크 ①).
        .id(appTheme + "·" + pointColor)   // 포인트색 변경도 같은 리빌드 경로(2026-08-17)
        .onChange(of: appTheme) { _, newValue in
            ThemeStore.apply(newValue)   // 설정의 선(先)apply 보완 벨트 — 외부 변경(백업 복원 등) 대비
            // 위젯도 즉시 테마 추종(Phase 5) — 스냅샷 재발행 + reloadAllTimelines(publish 내장)
            WidgetBridge.publish(periodDays: periodDays, schedules: schedules,
                                 inputs: inputs, outputs: outputs, completions: completions)
        }
        .onChange(of: pointColor) { _, newValue in
            // 시트의 선 apply와 같은 경로의 보완 벨트(외부 변경 대비) — apply는 멱등이라 무해
            ThemeStore.apply(appTheme, pointRawValue: newValue)
            WidgetBridge.publish(periodDays: periodDays, schedules: schedules,
                                 inputs: inputs, outputs: outputs, completions: completions)
        }
        .sheet(isPresented: $showThemeShop) { ThemeShopView() }
        // 온보딩 = fullScreenCover, 첫 실행 1회(§8.2.1)
        .fullScreenCover(isPresented: Binding(get: { !onboardingDone }, set: { if !$0 { onboardingDone = true } })) {
            OnboardingFlow()
        }
        .task {
            await HealthMirror.shared.sync(context: modelContext, periodDays: periodDays)
            WidgetBridge.publish(periodDays: periodDays, schedules: schedules,
                                 inputs: inputs, outputs: outputs, completions: completions)   // 위젯 스냅샷
            CoverageReminder.reschedule(periodDays: periodDays, context: modelContext)
            DailyNotices.reschedule(periodDays: periodDays, schedules: schedules)
            PlannerSync.shared.kick()   // 기기 간 동기화(2026-08-10) — 실행 시 왕복
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                let current = periodDays
                Task { await HealthMirror.shared.sync(context: modelContext, periodDays: current) }
                DailyNotices.reschedule(periodDays: periodDays, schedules: schedules)
                PlannerSync.shared.kick()   // 복귀 시 다른 기기 변경 당겨오기
            } else if phase == .background {
                // 세션 중 편집 반영 — 백그라운드 진입 때 최신 상태로 재발행
                WidgetBridge.publish(periodDays: periodDays, schedules: schedules,
                                     inputs: inputs, outputs: outputs, completions: completions)
                // 이 세션의 체크인·일정까지 반영해 다시 건다(§5.12 ⑤ / §5.11 재스케줄 계약)
                CoverageReminder.reschedule(periodDays: periodDays, context: modelContext)
                DailyNotices.reschedule(periodDays: periodDays, schedules: schedules)
                PlannerSync.shared.kick()   // 이 세션의 편집 올리기
            }
        }
        // 앵커가 움직이면 사분면 경계도, 예측일도 통째로 움직인다 — 생리 기록 변화는 즉시 재스케줄.
        .onChange(of: periodDays.map(\.day)) { _, _ in
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
    private func tabLabel(_ title: String, symbol: String, ticketAsset: String) -> some View {
        if ThemeStore.chrome.ticketChrome {
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
        guard ThemeStore.chrome.ticketChrome else {
            // 종전 테마는 시스템 기본(유리) 그대로 — 프록시가 남아 오염되지 않게 되돌린다
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
