// 템포루틴 — 앱 → 위젯 스냅샷 발행 (위젯 Phase 1, 2026-07-27)
// 오늘-1 ~ +34일치를 전부 계산해 쓴다 — 위젯 타임라인이 자정마다 다음 날을 집어가도
// 앱을 안 연 채 한 달은 버틴다. 발행 시점 = 앱 활성화·백그라운드 진입(RootTabView).

import Foundation
import WidgetKit

@MainActor
enum WidgetBridge {

    static func publish(periodDays: [PeriodDay]) {
        guard let url = WidgetShared.snapshotURL else { return }   // App Group 미프로비저닝이면 조용히 통과
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let snapshot = CycleSnapshot(periodDays: periodDays)
        var days: [WidgetDay] = []
        for offset in -1...34 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            days.append(makeDay(day, snapshot: snapshot))
        }
        let payload = WidgetSnapshot(generatedAt: .now, days: days)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
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
