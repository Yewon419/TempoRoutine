// 템포루틴 — 앱 엔트리
// 저장 = 단일 SwiftData 스토어(default.store). 2층 CloudKit 분리는 2026-07-24 롤백
// (실기기 영속화 결함 — 저장 후 재시작 시 @Query가 0을 읽음, split-brain·회수 시도 모두 실패,
//  Windows/CI-only라 멀티컨피그 디버그 불가). 기기 간 동기화는 맥 확보 후 별도 재구현(§5.2).
// 새 @Model 추가 시 아래 .modelContainer(for:) 배열에 반드시 등록(repo CLAUDE.md).

import SwiftUI
import SwiftData

@main
struct TempoRoutineApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
            // 다크 = 적응형 토큰으로 대응(Ink — 2026-07-20 사용자 결정). 정식 다크 테마는 미학 패스.
        }
        .modelContainer(for: [PeriodDay.self, ScheduleItem.self, InputItem.self,
                              OutputItem.self, OutputSubtask.self, ItemCompletion.self,
                              DailyCheckIn.self])
    }
}
