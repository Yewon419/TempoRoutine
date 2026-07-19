// 템포루틴 — 루트 탭 (§8.1 Tab Bar. P0 진행분만: 오늘·캘린더. 나의 리듬·설정은 후속 단계에서 추가)

import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("오늘", systemImage: "circle.inset.filled") }
            SeasonCalendarView()
                .tabItem { Label("캘린더", systemImage: "calendar") }
        }
        .tint(Ink.text)
    }
}
