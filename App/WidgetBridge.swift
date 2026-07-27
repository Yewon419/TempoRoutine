// 템포루틴 — 앱 → 위젯 스냅샷 발행 (위젯 Phase 1, 2026-07-27)
// 오늘-1 ~ +34일치를 전부 계산해 쓴다 — 위젯 타임라인이 자정마다 다음 날을 집어가도
// 앱을 안 연 채 한 달은 버틴다. 발행 시점 = 앱 활성화·백그라운드 진입(RootTabView).

import Foundation
import WidgetKit

@MainActor
enum WidgetBridge {

    static func publish(periodDays: [PeriodDay], schedules: [ScheduleItem] = []) {
        guard let url = WidgetShared.snapshotURL else { return }   // App Group 미프로비저닝이면 조용히 통과
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let snapshot = CycleSnapshot(periodDays: periodDays)
        let recordedDays = Set(periodDays.map(\.day))
        var days: [WidgetDay] = []
        // -7부터: 주간 스트립이 이번 주 전체를 요구한다(오늘이 주 마지막이면 6일 전까지)
        for offset in -7...34 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            var entry = makeDay(day, snapshot: snapshot)
            entry.recorded = recordedDays.contains(day)
            // 회색 형광펜 = 예상 생리일(I-2b) — 미래·투영 월경기만, 소급 금지(§5.6.2)
            entry.predicted = !recordedDays.contains(day) && day >= today && entry.projected
                && snapshot.phase(on: day) == .menstrual
            entry.schedules = scheduleLines(on: day, schedules: schedules)
            days.append(entry)
        }
        let payload = WidgetSnapshot(generatedAt: .now, days: days)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 그날 일정 줄 — 하루 상세와 같은 소스(occurs 판정). 종일 먼저, 최대 4줄(위젯 예산).
    private static func scheduleLines(on day: Date, schedules: [ScheduleItem]) -> [WidgetScheduleLine]? {
        let rows = schedules.filter { $0.occurs(on: day) }
        guard !rows.isEmpty else { return nil }
        let sorted = rows.sorted { a, b in
            if a.isAllDay != b.isAllDay { return a.isAllDay }
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

    private static func makeDay(_ day: Date, snapshot: CycleSnapshot) -> WidgetDay {
        if let phase = snapshot.phase(on: day), let info = snapshot.phaseInfo(on: day) {
            let key: String = switch phase {
            case .menstrual: "winter"
            case .follicular: "spring"
            case .ovulation: "summer"
            case .luteal: "autumn"
            }
            let hedge = info.projected ? " · 예상" : ""
            return WidgetDay(day: day, season: key, title: info.meta.name,
                             sub: "\(info.meta.phaseName) \(info.dayInCycle)일차\(hedge)",
                             inline: "\(info.meta.name) \(info.dayInCycle)일차",
                             mood: info.meta.moodline, projected: info.projected)
        }
        // S0(기록 전)·투영 지평 밖 공통 — 중립(§3: 임신·질환 추론 금지, 단정 없는 카피)
        return WidgetDay(day: day, season: nil, title: "템포루틴",
                         sub: snapshot.isColdStart ? "기록하면 계절이 채워져요" : "계절 사이를 지나고 있어요",
                         inline: "템포루틴", mood: nil, projected: false)
    }
}
