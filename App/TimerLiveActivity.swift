// 템포루틴 — Live Activity 시작·종료 (2026-08-09 사용자 결정 "시작하면 잠금화면에도")
// 표시 UI는 위젯 익스텐션(TimerActivityWidget), 여기는 앱 쪽 수명 관리만.
// anchor 하나로 자생하는 설계(TimerActivityShared)라 진행 중 갱신 호출이 없다 —
// 시작·정지·초기화 순간에만 요청/종료.

import ActivityKit
import Foundation

enum TimerLiveActivity {
    /// 시작 — 같은 아이템의 기존 액티비티는 걷고 다시 건다(일시정지 후 재개 경로).
    /// 시작 — 같은 아이템의 기존 액티비티는 걷고 다시 건다(일시정지 후 재개 경로).
    /// Input·Output 공용이라 모델을 받지 않고 값만 받는다(2026-08-13 통일).
    static func start(itemID: UUID, title: String, countsDown: Bool,
                      remaining: Double, elapsedAccum: Double) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = TimerActivityAttributes(title: title, itemID: itemID)
        let state = countsDown
            ? TimerActivityAttributes.ContentState(
                anchor: Date.now.addingTimeInterval(remaining), countsDown: true)
            : TimerActivityAttributes.ContentState(
                anchor: Date.now.addingTimeInterval(-elapsedAccum), countsDown: false)
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
