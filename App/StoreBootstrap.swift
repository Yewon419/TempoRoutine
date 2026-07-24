// 템포루틴 — 스토어 상태 플래그 (2026-07-24 — 2층 CloudKit 분리 롤백)
// 2층 스토어(tempo-sensitive/tempo-planner)는 실기기 영속화 결함으로 롤백됨:
// 저장 직후 fetchCount N이어도 재시작 시 @Query가 0을 읽음(split-brain 수정·회수 재시도 모두 실패,
// Windows/CI-only라 SwiftData 멀티컨피그 디버그 불가). 저장은 단일 default.store로 복귀(TempoRoutineApp).
// 기기 간 동기화는 맥 확보 후 이 파일에서 다시 설계(§5.2 계약은 유효, 실장만 보류).

import Foundation

@MainActor
enum AppStores {
    /// 현재 빌드에서 기기 간 CloudKit 동기화가 켜져 있는가 — 롤백으로 항상 false.
    /// 온보딩 저장 위치 카피·설정 동기화 표시가 참조(§3.10 정확성).
    static let cloudEnabled = false
}
