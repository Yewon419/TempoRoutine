// 템포루틴 — 루트 탭 (§8.1 Tab Bar. P0 진행분: 오늘·캘린더·설정. 나의 리듬은 후속 단계에서 추가)
// HK 미러 sync는 여기서 — 실행·포그라운드 복귀 시(§5.7 read 병합 + 삭제 전파).

import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var periodDays: [PeriodDay]
    @Query(sort: \ScheduleItem.date) private var schedules: [ScheduleItem]   // 위젯 스냅샷용(Phase 2)
    @Query(sort: \InputItem.createdAt) private var inputs: [InputItem]        // 오늘 카드 위젯(2026-07-27)
    @Query(sort: \OutputItem.createdAt) private var outputs: [OutputItem]
    @Query private var completions: [ItemCompletion]
    @AppStorage("onboardingDone") private var onboardingDone = false
    @AppStorage(ThemeStore.storageKey) private var appTheme = AppTheme.standard.rawValue

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("오늘", systemImage: "circle.inset.filled") }
            NavigationStack {
                SeasonCalendarView()
            }
            .tabItem { Label("캘린더", systemImage: "calendar") }
            RhythmView()
                .tabItem { Label("나의 리듬", systemImage: "chart.xyaxis.line") }
            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("설정", systemImage: "gearshape") }
        }
        .tint(Ink.text)
        // 테마 변경 = 전체 트리 리빌드(정적 팔레트 캐시 갱신 반영 — Theme.swift 반응성 설계).
        // 변경 진입점은 설정뿐이라 스택·스크롤 초기화는 허용 범위(2026-07-29 계획 리스크 ①).
        .id(appTheme)
        .onChange(of: appTheme) { _, newValue in
            ThemeStore.apply(newValue)   // 설정의 선(先)apply 보완 벨트 — 외부 변경(백업 복원 등) 대비
            // 위젯도 즉시 테마 추종(Phase 5) — 스냅샷 재발행 + reloadAllTimelines(publish 내장)
            WidgetBridge.publish(periodDays: periodDays, schedules: schedules,
                                 inputs: inputs, outputs: outputs, completions: completions)
        }
        // 온보딩 = fullScreenCover, 첫 실행 1회(§8.2.1)
        .fullScreenCover(isPresented: Binding(get: { !onboardingDone }, set: { if !$0 { onboardingDone = true } })) {
            OnboardingFlow()
        }
        .task {
            await HealthMirror.shared.sync(context: modelContext, periodDays: periodDays)
            WidgetBridge.publish(periodDays: periodDays, schedules: schedules,
                                 inputs: inputs, outputs: outputs, completions: completions)   // 위젯 스냅샷
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                let current = periodDays
                Task { await HealthMirror.shared.sync(context: modelContext, periodDays: current) }
            } else if phase == .background {
                // 세션 중 편집 반영 — 백그라운드 진입 때 최신 상태로 재발행
                WidgetBridge.publish(periodDays: periodDays, schedules: schedules,
                                     inputs: inputs, outputs: outputs, completions: completions)
            }
        }
    }
}
