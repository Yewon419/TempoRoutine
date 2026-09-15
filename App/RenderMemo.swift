// 템포루틴 — 렌더 메모 (2026-09-15 전체 최적화 패스)
// SwiftUI body는 햅틱 카운터 하나만 바뀌어도 다시 돈다. 그때마다 파생값(스냅샷·프로필·집계)을 새로 만들면
// 화면 하나에 O(N) 계산이 수십 번 겹친다(오늘 탭 snapshot 접근 22회, 나의 템포 23회 실측).
// 참조형에 넣어 두면 body 안에서 채워도 상태 갱신을 안 부르고, 입력 도장(stamp)이 같을 때만 재사용한다.

import Foundation

final class RenderMemo<Value> {
    private var stamp: Int?
    private var value: Value?

    func get(stamp: Int, _ compute: () -> Value) -> Value {
        if let value, self.stamp == stamp { return value }
        let fresh = compute()
        self.stamp = stamp
        value = fresh
        return fresh
    }
}

/// 입력 도장 — 렌더에 닿는 필드만 해시한다. 값이 같으면 같은 도장, 편집·추가·삭제는 전부 잡힌다.
enum RenderStamp {
    static func periodDays(_ days: [PeriodDay]) -> Int {
        var h = Hasher()
        h.combine(days.count)
        for p in days { h.combine(p.day) }
        return h.finalize()
    }

    static func checkIns(_ records: [DailyCheckIn]) -> Int {
        var h = Hasher()
        h.combine(records.count)
        for c in records {
            h.combine(c.day); h.combine(c.energy); h.combine(c.mood); h.combine(c.sleep); h.combine(c.appetite)
            h.combine(c.aggregationWeight); h.combine(c.completedAt); h.combine(c.isBackfilled)
        }
        return h.finalize()
    }

    static func combine(_ stamps: Int...) -> Int {
        var h = Hasher()
        for s in stamps { h.combine(s) }
        return h.finalize()
    }
}
