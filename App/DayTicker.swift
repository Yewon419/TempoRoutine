// 템포루틴 — 하루 경계 시계 (2026-09-16)
//
// `AppDay.today()`는 계산 프로퍼티라, 뷰가 다시 그려져야 새 날짜가 나온다. 그런데 탭 뷰는 유지되고
// SwiftUI엔 벽시계 변화라는 무효화 계기가 없다 — 앱을 열어둔 채 새벽 4시를 넘기면 오늘 탭·캘린더가
// 어제에 박제된다. 종전엔 @Query 변동(건강 앱 동기화 등)이 우연히 다시 그려주기를 기다리는 꼴이었고,
// 그래서 「어제 넣은 사진이 오늘도 있다」가 절반만 갱신된 상태로 잡혔다. `AppDay.nextBoundary`는
// 이 자리를 위해 있었는데 호출부가 없었다.
// WeatherSky가 같은 문제를 @AppStorage 방송으로 풀었던 자리(2026-09-01 "같은날인데 두 탭에서 날씨 다름").
// 날짜는 값이 하나뿐이라 방송지를 따로 만들지 않고 관측 가능한 시계 하나로 둔다.
//
// 백그라운드에선 sleep이 늦거나 안 깬다 — 씬 복귀(RootTabView .active)에서도 한 번 맞춘다.

import Foundation
import SwiftUI   // @Observable·@ObservationIgnored (리포의 다른 @Observable 싱글턴과 같은 조합)

@MainActor
@Observable
final class DayTicker {
    static let shared = DayTicker()

    /// 논리적 오늘(새벽 4시 경계). 이 값을 body에서 읽는 뷰는 경계에서 자동으로 다시 그려진다.
    private(set) var day: Date = AppDay.today()

    /// 예약 타이머는 추적에서 뺀다 — 재예약이 뷰 무효화를 부르면 안 된다(EventOverlay 캐시와 같은 규칙).
    @ObservationIgnored private var pending: Task<Void, Never>?

    private init() { schedule() }

    /// 지금 시각으로 다시 맞춘다 — 씬 복귀·수동 갱신용. 날짜가 그대로면 발행하지 않는다.
    func refresh() {
        let current = AppDay.today()
        if current != day { day = current }
        schedule()
    }

    private func schedule() {
        pending?.cancel()
        let now = Date.now
        let seconds = max(1, AppDay.nextBoundary(after: now).timeIntervalSince(now))
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
