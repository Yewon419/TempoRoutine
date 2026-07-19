// 템포루틴 — 앱 엔트리 (Phase 0 ④까지: 오늘 + 계절 캘린더 + 하루 상세 3카드)
// 저장은 로컬 SwiftData. 스키마는 §5.5 CloudKit 호환 규칙 준수 — 동기화 활성은 후속 단계.

import SwiftUI
import SwiftData

@main
struct TempoRoutineApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                // 디자인 언어(종이 지면·먹색 잉크)는 라이트 전용 설계 — 다크 기기에서 시스템
                // 시트·Form이 다크로 전환되면 먹색 버튼 글자가 안 보임(TestFlight 피드백 2026-07-20).
                // 다크 외관은 미학 패스(§5.9-8)에서 별도 결정.
                .preferredColorScheme(.light)
        }
        .modelContainer(for: [PeriodDay.self, ScheduleItem.self, InputItem.self,
                              OutputItem.self, OutputSubtask.self, ItemCompletion.self])
    }
}
