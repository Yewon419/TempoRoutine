// 템포루틴 — 앱 엔트리 (Phase 0 ②: 생리 로깅 + 단계계산)
// 저장은 로컬 SwiftData. 스키마는 §5.5 CloudKit 호환 규칙 준수 — 동기화 활성은 후속 단계.

import SwiftUI
import SwiftData

@main
struct TempoRoutineApp: App {
    var body: some Scene {
        WindowGroup {
            TodayView()
        }
        .modelContainer(for: PeriodDay.self)
    }
}
