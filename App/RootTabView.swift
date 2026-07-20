// 템포루틴 — 루트 탭 (§8.1 Tab Bar. P0 진행분: 오늘·캘린더·설정. 나의 리듬은 후속 단계에서 추가)
// HK 미러 sync는 여기서 — 실행·포그라운드 복귀 시(§5.7 read 병합 + 삭제 전파).

import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var periodDays: [PeriodDay]
    @AppStorage("onboardingDone") private var onboardingDone = false

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
        // 온보딩 = fullScreenCover, 첫 실행 1회(§8.2.1)
        .fullScreenCover(isPresented: Binding(get: { !onboardingDone }, set: { if !$0 { onboardingDone = true } })) {
            OnboardingFlow()
        }
        .task { await HealthMirror.shared.sync(context: modelContext, periodDays: periodDays) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                let current = periodDays
                Task { await HealthMirror.shared.sync(context: modelContext, periodDays: current) }
            }
        }
    }
}
