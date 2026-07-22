// 템포루틴 — 일정 로컬 알림 (2026-07-22 베타 피드백: 일정 시트 개편의 알림 필드)
// 로컬 노티만(서버 없음, §5.11과 동일 원칙). 시스템 권한 요청 = 사용자가 알림을 고른 저장 순간(§3.6.1 더블 컨센트 — 옵션 선택이 앱 레벨 동의).
// 하루종일 일정의 알림 기준 시각 = 오전 9시(캘린더 앱 관례): 0 = 당일 9시, 1440 = 전날 9시.

import Foundation
import UserNotifications
import TempoCore

enum ScheduleReminder {
    /// 하루종일 일정 알림 기준 시각
    private static let allDayHour = 9

    /// 저장 시 1회 호출 — 권한 요청(미결정 상태에서만 시스템 시트) 후 스케줄.
    /// 거부 상태면 조용히 스킵(§8.1 상태 어휘 — 에러 상태를 만들지 않음, 재촉 금지).
    static func schedule(id: UUID, title: String, date: Date, isAllDay: Bool,
                         repeatRule: ScheduleRepeat, reminderMinutes: Int) {
        guard reminderMinutes >= 0 else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
                guard granted else { return }
            } else if settings.authorizationStatus != .authorized {
                return
            }

            guard let trigger = trigger(date: date, isAllDay: isAllDay,
                                        repeatRule: repeatRule, reminderMinutes: reminderMinutes) else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = if isAllDay {
                reminderMinutes >= 1440 ? "내일 일정이에요." : "오늘 일정이에요."
            } else {
                "\(date.formatted(date: .omitted, time: .shortened))에 시작해요."
            }
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: id.uuidString,
                                                        content: content, trigger: trigger))
        }
    }

    static func cancel(id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    private static func trigger(date: Date, isAllDay: Bool, repeatRule: ScheduleRepeat,
                                reminderMinutes: Int) -> UNCalendarNotificationTrigger? {
        let cal = Calendar.current
        let fireDate: Date
        if isAllDay {
            let dayStart = cal.startOfDay(for: date)
            guard let nineAM = cal.date(bySettingHour: allDayHour, minute: 0, second: 0, of: dayStart) else { return nil }
            fireDate = nineAM.addingTimeInterval(-Double(reminderMinutes) * 60)   // 0 = 당일 9시 / 1440 = 전날 9시
        } else {
            fireDate = date.addingTimeInterval(-Double(reminderMinutes) * 60)
        }

        let repeats = repeatRule != .none
        // 반복 없는 일정의 과거 발화 시각은 스케줄 무의미
        if !repeats && fireDate <= .now { return nil }

        let components: DateComponents
        switch repeatRule {
        case .none:
            components = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        case .daily:
            components = cal.dateComponents([.hour, .minute], from: fireDate)
        case .weekly:
            components = cal.dateComponents([.weekday, .hour, .minute], from: fireDate)
        case .monthly:
            components = cal.dateComponents([.day, .hour, .minute], from: fireDate)
        case .yearly:
            components = cal.dateComponents([.month, .day, .hour, .minute], from: fireDate)
        }
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
    }
}
