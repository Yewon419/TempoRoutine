// 템포루틴 — 아침 일정 브리핑 + 생리 예측 알림 (2026-08-05 사용자 지시)
//
// 로컬 노티만(§5.11 원칙 공유). **기본 켬(사용자 결정 2026-08-05)** — 단 시스템 권한이
// 이미 허용된 기기에서만 실제로 예약된다. 권한 요청 자체는 여기서 하지 않는다(온보딩에서
// 묻지 않기 §5.11 — 첫 요청은 일정 알림 저장·설정 토글 등 사용자 행동 순간).
//
// 재스케줄 계약: 앱 활성·백그라운드 진입·생리 기록 변화 때 전부 취소 후 다시 건다.
// 예측 기반 알림은 앵커가 움직이면 틀린 날에 울린다(§5.11 — pending 잔재 금지).

import Foundation
import SwiftData
import UserNotifications
import TempoCore

@MainActor
enum DailyNotices {
    /// 설정 토글 키 — 기본 켬이라 "키 없음 = true"로 읽는다(@AppStorage 기본값과 같은 의미).
    static let briefingKey = "morningBriefingOn"
    static let periodKey = "periodForecastOn"

    private static let briefingHour = 8      // 아침 8시(사용자 지정)
    private static let periodEveHour = 20    // 전날 저녁 8시(커버 리마인더와 같은 관례)
    private static let periodDayHour = 8
    private static let briefingDays = 7      // 예약 지평 — 재스케줄이 앱 진입마다 돌아 7일이면 넉넉
    private static let briefingPrefix = "morning-briefing-"
    private static let periodEveID = "period-forecast-eve"
    private static let periodDayID = "period-forecast-day"

    static var briefingOn: Bool {
        UserDefaults.standard.object(forKey: briefingKey) as? Bool ?? true
    }
    static var periodOn: Bool {
        UserDefaults.standard.object(forKey: periodKey) as? Bool ?? true
    }

    static func reschedule(periodDays: [PeriodDay], schedules: [ScheduleItem]) {
        cancelAll()
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        // 취소 후 예약 사이에 비동기 경계가 없도록 발화 목록을 먼저 계산한다.
        var requests: [(id: String, title: String, body: String, fire: DateComponents)] = []

        if briefingOn {
            for offset in 0..<briefingDays {
                guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
                // EventKit 오버레이 일정은 제외(로컬 일정만 — 위젯 §8.2.8과 같은 경계)
                let titles = schedules.filter { $0.occurs(on: day) }.map(\.title)
                guard !titles.isEmpty,
                      let fire = cal.date(bySettingHour: briefingHour, minute: 0, second: 0, of: day),
                      fire > .now else { continue }
                let shown = titles.prefix(3).joined(separator: " · ")
                let extras = titles.count > 3 ? " 외 \(titles.count - 3)개" : ""
                requests.append((briefingPrefix + dayKey(day),
                                 "오늘은 다음과 같은 일정이 있어요",
                                 shown + extras,
                                 cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)))
            }
        }

        if periodOn {
            let starts = PeriodMath.episodeStarts(days: periodDays.map(\.day))
            // CycleParams 경유(개정 M 정정) — prior 미반영이면 알림 예측일이 오늘 화면과 어긋난다
            let length = CycleParams.averageLength(starts: starts)
            // 예측이 흔들리면 걸지 않는다(§5.11 원칙 4 — confidence=low의 알림은 신뢰를 깎는다)
            if CyclePredictor.confidence(periodStarts: starts) != .low,
               let last = starts.max(), length > 0,
               let predicted = cal.date(byAdding: .day, value: length, to: last),
               predicted > today {   // 이미 지난 예측(overdue)엔 침묵 — 재촉 금지(§7)
                // 카피 = hedge 고정(§5.11) + 계절 은유(잠금화면에 떠도 제3자에겐 계절 문구 — §8.2.8)
                if let eveDay = cal.date(byAdding: .day, value: -1, to: predicted),
                   let fire = cal.date(bySettingHour: periodEveHour, minute: 0, second: 0, of: eveDay),
                   fire > .now {
                    requests.append((periodEveID, "곧 겨울이에요",
                                     "내일쯤 겨울로 접어들 수 있어요. 미리 채비해도 좋아요.",
                                     cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)))
                }
                if let fire = cal.date(bySettingHour: periodDayHour, minute: 0, second: 0, of: predicted),
                   fire > .now {
                    requests.append((periodDayID, "겨울 무렵이에요",
                                     "오늘쯤 겨울이 시작될 수 있어요. 시작되면 기록해 주세요.",
                                     cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)))
                }
            }
        }

        guard !requests.isEmpty else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional || status == .ephemeral else { return }
            for request in requests {
                let content = UNMutableNotificationContent()
                content.title = request.title
                content.body = request.body
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: request.fire, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: request.id,
                                                            content: content, trigger: trigger))
            }
        }
    }

    static func cancelAll() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        // 브리핑 식별자는 날짜 기반 — 어제 예약분(이미 소멸)까지 여유 있게 훑는다
        var ids = [periodEveID, periodDayID]
        for offset in -1...briefingDays {
            if let day = cal.date(byAdding: .day, value: offset, to: today) {
                ids.append(briefingPrefix + dayKey(day))
            }
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func dayKey(_ day: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
