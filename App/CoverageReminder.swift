// 템포루틴 — 사분면 커버 리마인더 (MASTER §5.12 ⑤ / 핸드오프 v1.5 §3-5)
//
// 기록이 주기 한쪽에만 몰리면 그 주기가 축 엔진에서 통째로 버려진다(§5.12 ②).
// **비어 있는 사분면에만** 알린다 — 매일 조르는 체크인 알림이 아니다(§7 재촉 금지).
//
// 계약(§5.11과 공유): 로컬 노티만 · 옵트인 기본 꺼짐 · confidence=low면 스케줄 안 함 ·
// 앵커가 움직이면(새 생리 기록) pending 전부 취소·재스케줄. 재스케줄이 없으면 틀린 날에 울린다.

import Foundation
import SwiftData
import UserNotifications
import TempoCore

@MainActor
enum CoverageReminder {
    /// 설정 토글. 기본 꺼짐 — 알림은 사용자가 고른 뒤에만 존재한다(§5.11 옵트인).
    static let storageKey = "coverageReminderOn"

    /// 발화 시각. 일정 알림의 오전 9시와 다르다 — 체크인은 하루를 돌아보고 남기는 기록이다.
    private static let fireHour = 20
    private static let identifierPrefix = "coverage-quadrant-"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: storageKey) }

    /// 토글을 켜는 순간 1회 — 시스템 권한 시트(§3.6.1 더블 컨센트, ScheduleReminder와 같은 문법).
    /// 거부 상태면 false. 호출측이 「알림 설정 열기」를 붙일지 판단한다.
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        return allows(settings.authorizationStatus)
    }

    /// 예약 가능 상태. 요청 쪽과 판정을 같은 함수로 묶는다 —
    /// 한쪽만 provisional을 허용하면 "켜졌는데 아무것도 안 오는" 상태가 생긴다.
    private static func allows(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    /// 진행 중인 주기의 빈 사분면만 예약한다. 항상 전부 취소 후 다시 건다 —
    /// 부분 갱신은 앵커가 움직였을 때 지난 계산의 잔재를 남긴다.
    /// 체크인은 여기서 직접 읽는다 — 루트 뷰에 @Query를 하나 더 다는 것보다 재렌더가 적다.
    static func reschedule(periodDays: [PeriodDay], context: ModelContext) {
        cancelAll()
        guard isOn else { return }
        let checkIns = (try? context.fetch(FetchDescriptor<DailyCheckIn>())) ?? []

        let snapshot = CycleSnapshot(periodDays: periodDays)
        // 예측이 흔들리는 상태에서 거는 알림은 틀린 날에 울린다(§5.11 원칙 4).
        guard CyclePredictor.confidence(periodStarts: snapshot.starts) != .low else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let start = snapshot.starts.sorted().last(where: { $0 <= today }) else { return }
        let length = snapshot.averageLength
        guard length > 0 else { return }
        // 다음 앵커가 이미 지났으면(overdue) 진행 중 주기의 길이를 신뢰할 수 없다.
        guard let dayInCycle = cal.dateComponents([.day], from: start, to: today).day,
              dayInCycle < length else { return }

        let coverage = QuadrantCoverage.coverage(signals(checkIns: checkIns, start: start, length: length))

        Task {
            let center = UNUserNotificationCenter.current()
            guard allows(await center.notificationSettings().authorizationStatus) else { return }

            for quadrant in 0..<QuadrantCoverage.count where coverage[quadrant] == 0 {
                guard let day = QuadrantCoverage.reminderDay(quadrant: quadrant, cycleLength: length),
                      let dayStart = cal.date(byAdding: .day, value: day - 1, to: start),
                      let fireDate = cal.date(bySettingHour: fireHour, minute: 0, second: 0, of: dayStart),
                      fireDate > .now else { continue }   // 지난 사분면은 만회할 수 없다

                let content = UNMutableNotificationContent()
                content.title = title(quadrant: quadrant)
                content.body = "이맘때 기록이 하나만 있어도 이번 주기가 리듬 계산에 들어가요."
                content.sound = .default
                // 화면을 깨우지 않는다 — 재촉이 아니라 안내다(§7).
                content.interruptionLevel = .passive

                let components = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: identifierPrefix + String(quadrant),
                                                            content: content, trigger: trigger))
            }
        }
    }

    static func cancelAll() {
        let ids = (0..<QuadrantCoverage.count).map { identifierPrefix + String($0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// 진행 중인 주기의 체크인 → DailySignal. 커버 판정은 "적합에 들어가는 행"과 같은 기준이어야 한다
    /// (AxisProfile과 같은 변환을 거친다 — 여기서만 다른 기준을 쓰면 알림과 엔진이 어긋난다).
    private static func signals(checkIns: [DailyCheckIn], start: Date, length: Int) -> [DailySignal] {
        let cal = Calendar.current
        return checkIns.compactMap { entry in
            let day = cal.startOfDay(for: entry.day)
            guard day >= start,
                  let offset = cal.dateComponents([.day], from: start, to: day).day,
                  offset < length else { return nil }
            let emotional = SignalConversion.emotional(mood: entry.mood, irritability: entry.irritability)
            let bodily = SignalConversion.bodily(pain: entry.pain)
            guard emotional != nil || bodily != nil else { return nil }
            return DailySignal(cycleDay: offset + 1, cycleLength: length,
                               emotional: emotional, bodily: bodily,
                               isBackfilled: entry.isBackfilled)
        }
    }

    /// 사분면 이름은 계절 이름을 쓰지 않는다 — 경계가 다르다(QuadrantCoverage 주석).
    /// 단정 대신 위치만 말한다(§5.11 hedge 고정).
    private static func title(quadrant: Int) -> String {
        switch quadrant {
        case 0: "이번 주기 초반이 비어 있어요"
        case 1: "이번 주기 중반이 비어 있어요"
        case 2: "이번 주기 후반이 비어 있어요"
        default: "이번 주기 끝자락이 비어 있어요"
        }
    }
}
