// 템포루틴 — 스토어 상태 플래그
// 2층 CloudKit 스토어 분리는 2026-07-24 롤백(실기기 영속화 결함 — 그 방식은 재도전 금지).
// 기기 간 동기화는 2026-08-10 PlannerSync(CKSyncEngine 레코드 미러)로 재구현 — 스토어 불변.

import Foundation

@MainActor
enum AppStores {
    /// 기기 간 동기화가 켜져 있는가 — 온보딩 저장 위치 카피·설정 표시가 참조(§3.10 정확성).
    /// 2026-08-10부터 PlannerSync 토글을 따른다(기본 켬, iCloud 계정 없으면 조용히 쉼).
    static var cloudEnabled: Bool { PlannerSync.isEnabled }
}
