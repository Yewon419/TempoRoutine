// 템포루틴 — 아침 일정 브리핑 + 생리 예측 알림 (2026-08-05 사용자 지시)
//
// 로컬 노티만(§5.11 원칙 공유). **기본 켬(사용자 결정 2026-08-05)** — 단 시스템 권한이
// 허용된 기기에서만 실제로 예약된다.
// ⚠ 2026-08-08 정정: 종전엔 능동 권한 요청 경로가 없어 기본 상태 사용자에게 영원히 침묵했다
// ("알림 작동하는 걸 본 적이 없다"의 뿌리). 지금은 예약할 내용이 처음 생기는 시점에 오늘 탭
// 안내 카드 1회(shouldOfferPermission → requestPermission — 카드 탭 = §5.11 행동 순간).
// 온보딩에서는 여전히 묻지 않는다.
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

    /// 권한 안내 카드 1회 노출 키(2026-08-08 — "기본 켬인데 권한 요청 경로가 없어 영원히 침묵" 결함)
    static let promptKey = "noticePermissionPrompted"

    static var briefingOn: Bool {
        UserDefaults.standard.object(forKey: briefingKey) as? Bool ?? true
    }
    static var periodOn: Bool {
        UserDefaults.standard.object(forKey: periodKey) as? Bool ?? true
    }

    static var hasPromptedPermission: Bool {
        get { UserDefaults.standard.bool(forKey: promptKey) }
        set { UserDefaults.standard.set(newValue, forKey: promptKey) }
    }

    /// 오늘 탭 안내 카드 노출 판정 — 예약할 내용이 실제로 생겼고, 시스템 권한이 미결정이고,
    /// 아직 물어본 적 없을 때만. "받아볼래요?"를 빈손으로 묻지 않는다(§5.11 행동 순간 원칙의 연장).
    static func shouldOfferPermission(periodDays: [PeriodDay], schedules: [ScheduleItem]) async -> Bool {
        guard !hasPromptedPermission, briefingOn || periodOn else { return false }
        guard !buildRequests(periodDays: periodDays, schedules: schedules).isEmpty else { return false }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .notDetermined
    }

    /// 카드 「알림 받기」 — 여기가 기본 켬 알림의 유일한 능동 권한 요청 지점.
    /// 결과와 무관하게 재노출하지 않는다(거부 재촉 금지 §7 — 이후 경로는 설정 토글).
    static func requestPermission(periodDays: [PeriodDay], schedules: [ScheduleItem]) async -> Bool {
        hasPromptedPermission = true
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        if granted { reschedule(periodDays: periodDays, schedules: schedules) }
        return granted
    }

    static func reschedule(periodDays: [PeriodDay], schedules: [ScheduleItem]) {
        cancelAll()
        let requests = buildRequests(periodDays: periodDays, schedules: schedules)
        guard !requests.isEmpty else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional || status == .ephemeral else { return }
            for request in requests {
                let content = UNMutableNotificationContent()
                content.title = request.title
                content.body = request.body
                content.sound = .signature   // 시그니처 칼림바(2026-08-09)
                let trigger = UNCalendarNotificationTrigger(dateMatching: request.fire, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: request.id,
                                                            content: content, trigger: trigger))
            }
        }
    }

    /// 발화 목록 계산 — 예약(reschedule)과 안내 카드 판정(shouldOfferPermission)이 같은 기준을 쓴다.
    private static func buildRequests(periodDays: [PeriodDay],
                                      schedules: [ScheduleItem])
        -> [(id: String, title: String, body: String, fire: DateComponents)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var requests: [(id: String, title: String, body: String, fire: DateComponents)] = []

        if briefingOn {
            for offset in 0..<briefingDays {
                guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
                // 애플 캘린더(EventKit) 일정 포함(2026-08-09 사용자 결정 — "브리핑이 안 온다"의 원인이
                // 일정을 캘린더 앱으로 관리하는 사용 방식이었음). 종전 제외는 위젯 §8.2.8 경계의 준용
                // 이었는데 위젯(스냅샷 파일)과 달리 브리핑은 예약 시점 라이브 쿼리라 제약이 없다.
                // dedup 없음(§3.6.1 신뢰 식별자 없음) — 같은 제목이 양쪽에 있으면 두 번 나열된다.
                let titles = schedules.filter { $0.occurs(on: day) }.map(\.title)
                    + EventOverlay.shared.events(on: day).map(\.title)
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

        return requests
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
