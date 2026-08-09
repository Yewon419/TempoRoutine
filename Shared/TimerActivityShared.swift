// 템포루틴 — 타이머·스톱워치 Live Activity 계약 (2026-08-09, 앱 ↔ 위젯 공용)
// 프라이버시: 싣는 건 Output 제목뿐 — 주기·계절 정보 없음(§8.2.8 잠금화면 원칙과 정합.
// 제목 노출은 2026-08-02 사용자 결정으로 허용된 범위).
// 갱신 없이 자생하는 설계: anchor 시각 하나로 시스템 타이머 텍스트가 스스로 간다(푸시·주기 갱신 불요).

import ActivityKit
import Foundation

struct TimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 카운트 기준점 — 타이머 = 종료 예정 시각(카운트다운), 스톱워치 = 누적을 뺀 과거 시각(카운트업)
        var anchor: Date
        var countsDown: Bool
    }

    var title: String
    var itemID: UUID
}
