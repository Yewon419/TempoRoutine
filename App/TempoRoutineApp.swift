// 템포루틴 — 앱 엔트리
// 저장 = 2층 스토어(§5.2, StoreBootstrap): 민감층 로컬 전용 + 플래너층·체크인 CloudKit.
// 새 @Model 추가 시 AppStores의 모델 목록에 등록(구 .modelContainer(for:) 규칙의 승계 — repo CLAUDE.md).

import SwiftUI
import SwiftData

@main
struct TempoRoutineApp: App {
    private let container: ModelContainer

    init() {
        container = AppStores.makeContainer()
        AppStores.migrateLegacyStoreIfNeeded(into: container)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
            // 다크 = 적응형 토큰으로 대응(Ink — 2026-07-20 사용자 결정). 정식 다크 테마는 미학 패스.
        }
        .modelContainer(container)
    }
}
