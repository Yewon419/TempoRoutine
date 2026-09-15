// 템포루틴 — 데이터 변경 → 위젯 스냅샷 재발행 (2026-09-15 베타 "루틴 추가해도 위젯에 안 뜬다")
// 종전 발행 시점은 시작·백그라운드 진입·테마/언어 변경뿐이라 앱 안에서 고친 것이 홈 화면에 늦게 갔다.
// 여기서는 위젯이 그리는 데이터(생리 기록·일정·루틴·목표·완료·진행)가 바뀌면 1.5초 디바운스 뒤 발행한다.
// 앱이 전면일 때의 reloadAllTimelines는 위젯 예산을 안 먹는다(WidgetKit 규칙).
// RootTabView 모디파이어 체인은 타입체크 한계(repo CLAUDE.md)라 오늘 탭의 background로 얹는다.

import SwiftData
import SwiftUI

struct WidgetRefresher: View {
    @Query private var periodDays: [PeriodDay]
    @Query private var schedules: [ScheduleItem]
    @Query private var inputs: [InputItem]
    @Query private var outputs: [OutputItem]
    @Query private var completions: [ItemCompletion]
    @Query private var inputProgresses: [InputProgress]
    @State private var primed = false

    /// 위젯 표면에 닿는 값만 해시 — 제목·날짜·스케줄·완료. 진행(타이머 경과)은 뺀다(초 단위로 튀면 발행 폭주).
    private var stamp: Int {
        var h = Hasher()
        for p in periodDays { h.combine(p.day) }
        for s in schedules {
            h.combine(s.id); h.combine(s.title); h.combine(s.date); h.combine(s.endDate)
            h.combine(s.isAllDay); h.combine(s.repeatRule.rawValue)
        }
        for item in inputs { h.combine(item.id); h.combine(item.title); h.combine(item.scheduleData) }
        for item in outputs {
            h.combine(item.id); h.combine(item.title); h.combine(item.scheduleData); h.combine(item.isComplete)
        }
        h.combine(completions.count)
        h.combine(inputProgresses.count)
        return h.finalize()
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: stamp) {
                // 첫 로드는 시작 작업(RootTabView .task)이 발행한다 — 여기선 변경만 잡는다
                guard primed else { primed = true; return }
                guard !DevMode.active else { return }
                try? await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled else { return }
                WidgetBridge.publish(periodDays: periodDays, schedules: schedules,
                                     inputs: inputs, outputs: outputs, completions: completions,
                                     inputProgresses: inputProgresses)
            }
    }
}
