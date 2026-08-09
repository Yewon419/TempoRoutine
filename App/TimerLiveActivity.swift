// 템포루틴 — Live Activity 시작·종료 (2026-08-09 사용자 결정 "시작하면 잠금화면에도")
// 표시 UI는 위젯 익스텐션(TimerActivityWidget), 여기는 앱 쪽 수명 관리만.
// anchor 하나로 자생하는 설계(TimerActivityShared)라 진행 중 갱신 호출이 없다 —
// 시작·정지·초기화 순간에만 요청/종료.

import ActivityKit
import Foundation

enum TimerLiveActivity {
    /// 시작 — 같은 아이템의 기존 액티비티는 걷고 다시 건다(일시정지 후 재개 경로).
    static func start(item: OutputItem) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = TimerActivityAttributes(title: item.title, itemID: item.id)
        let state: TimerActivityAttributes.ContentState
        if item.progressKind == .timer {
            let remaining = max(0, Double(item.targetSeconds ?? 0) - item.elapsedSeconds())
            state = TimerActivityAttributes.ContentState(
                anchor: Date.now.addingTimeInterval(remaining), countsDown: true)
        } else {
            state = TimerActivityAttributes.ContentState(
                anchor: Date.now.addingTimeInterval(-item.elapsedAccumSeconds), countsDown: false)
        }
        let itemID = item.id
        Task {
            await endActivities(itemID: itemID)
            _ = try? Activity.request(attributes: attributes,
                                      content: ActivityContent(state: state, staleDate: nil))
        }
    }

    static func end(itemID: UUID) {
        Task { await endActivities(itemID: itemID) }
    }

    private static func endActivities(itemID: UUID) async {
        for activity in Activity<TimerActivityAttributes>.activities
        where activity.attributes.itemID == itemID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
