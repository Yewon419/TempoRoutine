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
        /// 실행 중인가(2026-08-14 잠금화면 정지·재개). ⚠ 자생 설계는 **실행 중일 때만** 성립한다 —
        /// 멈춘 순간부터 anchor는 흘러가는 값이라, 정지 표시는 아래 `frozenSeconds`가 맡는다.
        var isRunning: Bool = true
        /// 정지 중 보여줄 초 — 타이머 = 남은 시간, 스톱워치 = 누적. 실행 중엔 쓰지 않는다.
        var frozenSeconds: Double = 0
    }

    var title: String
    var itemID: UUID
    /// 저장처 구분(2026-08-14) — Output은 아이템 자신, Input은 **그날 레코드**에 값이 있다.
    /// 잠금화면 버튼이 어느 쪽을 열지 알아야 해서 액티비티에 싣는다(§5.5.2 값 위치 계약).
    var isInput: Bool = false
    /// 타이머 목표(초). 스톱워치는 0. 재개할 때 남은 시간을 다시 계산하는 데 쓴다.
    var targetSeconds: Int = 0
}
