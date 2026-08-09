// 템포루틴 — 앱 → 위젯 스냅샷 발행 (위젯 Phase 1, 2026-07-27)
// 오늘-1 ~ +34일치를 전부 계산해 쓴다 — 위젯 타임라인이 자정마다 다음 날을 집어가도
// 앱을 안 연 채 한 달은 버틴다. 발행 시점 = 앱 활성화·백그라운드 진입(RootTabView).

import Foundation
import WidgetKit

@MainActor
enum WidgetBridge {

    static func publish(periodDays: [PeriodDay], schedules: [ScheduleItem] = [],
                        inputs: [InputItem] = [], outputs: [OutputItem] = [],
                        completions: [ItemCompletion] = []) {
        guard let url = WidgetShared.snapshotURL else { return }   // App Group 미프로비저닝이면 조용히 통과
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let snapshot = CycleSnapshot(periodDays: periodDays)
        let recordedDays = Set(periodDays.map(\.day))
        var days: [WidgetDay] = []
        // -35부터: 월 캘린더 위젯이 이번 달 전체를 요구한다(오늘이 월말이면 월초 = -30)
        for offset in -35...34 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            var entry = makeDay(day, snapshot: snapshot)
            entry.recorded = recordedDays.contains(day)
            // 회색 형광펜 = 예상 생리일(I-2b) — 미래·투영 월경기만, 소급 금지(§5.6.2)
            entry.predicted = !recordedDays.contains(day) && day >= today && entry.projected
                && snapshot.phase(on: day) == .menstrual
            entry.schedules = scheduleLines(on: day, schedules: schedules)
            // 총계는 잘리기 전 개수 — 위젯 카운터·잠금화면 요약이 이걸 쓴다(잘린 배열을 세면 거짓말)
            if let input = inputLines(on: day, snapshot: snapshot, inputs: inputs, completions: completions) {
                entry.inputs = input.lines
                entry.inputTotal = input.total
                entry.inputDone = input.done
            }
            if let output = outputLines(on: day, snapshot: snapshot, outputs: outputs) {
                entry.outputs = output.lines
                entry.outputTotal = output.total
            }
            days.append(entry)
        }
        let payload = WidgetSnapshot(generatedAt: .now, days: days,
                                     theme: ThemeStore.current.rawValue)   // 위젯 테마 전달(Phase 5)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 그날 일정 줄 — 하루 상세와 같은 소스(occurs 판정). 최대 4줄(위젯 예산).
    /// 시각 있는 것 시간순·종일은 맨 뒤(2026-08-09 사용자 결정 — 앱 행 정렬과 통일, 구 종일 선두 폐기).
    private static func scheduleLines(on day: Date, schedules: [ScheduleItem]) -> [WidgetScheduleLine]? {
        let rows = schedules.filter { $0.occurs(on: day) }
        guard !rows.isEmpty else { return nil }
        let sorted = rows.sorted { a, b in
            if a.isAllDay != b.isAllDay { return b.isAllDay }
            return a.date < b.date
        }
        return sorted.prefix(4).map { item in
            var title = item.title
            if let index = item.dayIndex(on: day) {
                title += " · \(index)/\(item.spanDays)일차"
            }
            let time = item.isAllDay ? "종일" : item.date.formatted(date: .omitted, time: .shortened)
            return WidgetScheduleLine(time: time, title: title)
        }
    }

    /// 그날 Input 줄 — TodayView.todayInputs 판정과 동형(.once 캐리·소급·주기 앵커)
    private static func inputLines(on day: Date, snapshot: CycleSnapshot, inputs: [InputItem],
                                   completions: [ItemCompletion])
    -> (lines: [WidgetCheckLine], total: Int, done: Int)? {
        let cal = Calendar.current
        func checked(_ id: UUID) -> Bool {
            completions.contains { $0.itemID == id && cal.isDate($0.occurredOn, inSameDayAs: day) }
        }
        func hasAny(_ id: UUID) -> Bool { completions.contains { $0.itemID == id } }
        let rows = inputs.filter { item in
            switch item.schedule {
            case .once:
                if item.backfilled { return item.onceShows(on: day) }
                return item.occursByCalendar(on: day) && (!hasAny(item.id) || checked(item.id))
            case .daily, .weekly, .monthly:
                return item.occursByCalendar(on: day)
            case .cycleAnchored(let r):
                return snapshot.occurrence(of: r, createdAt: cal.startOfDay(for: item.createdAt), on: day) != nil
                    || checked(item.id)
            }
        }
        guard !rows.isEmpty else { return nil }
        // 시각 정렬(2026-08-09 — 앱 행과 통일) 후 6줄까지 — 중형 위젯이 5줄을 그린다
        let ordered = sortedByTimeOfDay(rows) { $0.timeMinutes }
        let lines = ordered.prefix(6).map { WidgetCheckLine(title: $0.title, done: checked($0.id), id: $0.id) }
        return (lines, rows.count, rows.filter { checked($0.id) }.count)
    }

    /// 그날 Output 줄 — TodayView.todayOutputs 판정과 동형(완료된 미래 occurrence 제외 §5.5.2)
    private static func outputLines(on day: Date, snapshot: CycleSnapshot, outputs: [OutputItem])
    -> (lines: [WidgetProgressLine], total: Int)? {
        let cal = Calendar.current
        let rows = outputs.filter { item in
            switch item.schedule {
            case .once, .daily, .weekly, .monthly:
                return item.occursByCalendar(on: day)
            case .cycleAnchored(let r):
                guard let occ = snapshot.occurrence(of: r, createdAt: cal.startOfDay(for: item.createdAt), on: day) else {
                    return false
                }
                return !(item.isComplete && occ.projected)
            }
        }
        guard !rows.isEmpty else { return nil }
        // 시각 정렬(2026-08-09 — 앱 행과 통일)
        let ordered = sortedByTimeOfDay(rows) { $0.timeMinutes }
        // 클로저 반환 타입 명시 — 문장 추가로 암묵 반환이 깨진 자리(CLAUDE.md Swift 6 함정 ②)
        let lines = ordered.prefix(6).map { item -> WidgetProgressLine in
            let dday = ddayLabel(target: item.targetDate, from: day)
            switch item.progressKind {
            case .percent:
                return WidgetProgressLine(title: item.title,
                                          label: item.percent.formatted(.percent.precision(.fractionLength(0))),
                                          fraction: min(1, max(0, item.percent)),
                                          id: item.id, kind: item.progressKind.rawValue, dday: dday)
            case .sessions:
                return WidgetProgressLine(title: item.title,
                                          label: "\(item.loggedSessions)/\(max(1, item.targetSessions))",
                                          fraction: min(1, Double(item.loggedSessions) / Double(max(1, item.targetSessions))),
                                          id: item.id, kind: item.progressKind.rawValue, dday: dday)
            case .subtasks:
                return subtaskLine(item, dday: dday)
            case .timer:
                // 스냅샷은 정적 — 발행 시점 경과로 그린다(진행 중 초는 Live Activity 몫)
                let target = max(1, item.targetSeconds ?? 1)
                let elapsed = min(Double(target), item.elapsedSeconds())
                return WidgetProgressLine(title: item.title,
                                          label: "\(Int(elapsed) / 60)/\(target / 60)분",
                                          fraction: min(1, elapsed / Double(target)),
                                          id: item.id, kind: item.progressKind.rawValue, dday: dday)
            case .stopwatch:
                return WidgetProgressLine(title: item.title,
                                          label: "\(Int(item.elapsedSeconds()) / 60)분",
                                          fraction: 0,
                                          id: item.id, kind: item.progressKind.rawValue, dday: dday)
            }
        }
        return (lines, rows.count)
    }

    private static func subtaskLine(_ item: OutputItem, dday: String?) -> WidgetProgressLine {
        let list = item.subtasks ?? []
        let done = list.filter(\.isDone).count
        return WidgetProgressLine(title: item.title, label: "\(done)/\(max(1, list.count))",
                                  fraction: min(1, Double(done) / Double(max(1, list.count))),
                                  id: item.id, kind: item.progressKind.rawValue, dday: dday)
    }

    /// 목표일 배지 문구 — 앱 DDayBadge(TodayView)와 동형. 기준일은 그 엔트리가 그리는 날.
    private static func ddayLabel(target: Date?, from day: Date) -> String? {
        guard let target else { return nil }
        let cal = Calendar.current
        let remaining = cal.dateComponents([.day], from: cal.startOfDay(for: day),
                                           to: cal.startOfDay(for: target)).day ?? 0
        if remaining == 0 { return "D-DAY" }
        return remaining > 0 ? "D-\(remaining)" : "D+\(-remaining)"
    }

    private static func makeDay(_ day: Date, snapshot: CycleSnapshot) -> WidgetDay {
        if let phase = snapshot.phase(on: day), let info = snapshot.phaseInfo(on: day) {
            let key: String = switch phase {
            case .menstrual: "winter"
            case .follicular: "spring"
            case .ovulation: "summer"
            case .luteal: "autumn"
            }
            let hedge = info.projected ? " · 예상" : ""
            // 일차 = 계절 내 일차(2026-08-09 — 앱 표면과 통일)
            return WidgetDay(day: day, season: key, title: info.meta.name,
                             sub: "\(info.meta.name) \(info.dayInPhase)일차\(hedge)",
                             inline: "\(info.meta.name) \(info.dayInPhase)일차",
                             mood: info.meta.moodline, projected: info.projected)
        }
        // S0(기록 전)·투영 지평 밖 공통 — 중립(§3: 임신·질환 추론 금지, 단정 없는 카피)
        return WidgetDay(day: day, season: nil, title: "템포루틴",
                         sub: snapshot.isColdStart ? "기록하면 계절이 채워져요" : "계절 사이를 지나고 있어요",
                         inline: "템포루틴", mood: nil, projected: false)
    }
}
