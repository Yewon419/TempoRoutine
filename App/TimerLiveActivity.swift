// 템포루틴 — Live Activity 시작·정지·종료 (2026-08-09 사용자 결정 "시작하면 잠금화면에도")
// 표시 UI는 위젯 익스텐션(TimerActivityWidget), 여기는 앱 쪽 수명 관리와 잠금화면 버튼 실행부.
// anchor 하나로 자생하는 설계(TimerActivityShared)라 **실행 중엔** 갱신 호출이 없다 —
// 시작·정지·재개·초기화 순간에만 요청/갱신/종료.
//
// ⚠ 2026-08-14 동작 변경: **정지해도 액티비티를 걷지 않는다.** 잠금화면에서 다시 시작하려면
// 남아 있어야 한다(사용자 지시). 걷는 건 초기화와 완료뿐.

import ActivityKit
import Foundation
import SwiftData

enum TimerLiveActivity {
    /// 시작 또는 재개 — 정지 상태로 남아 있던 액티비티가 있으면 **걷지 않고 갱신**한다.
    /// 걷고 다시 걸면 잠금화면에서 한 번 사라졌다 나타난다(2026-08-14 정지 보존 이후의 경로).
    /// Input·Output 공용이라 모델을 받지 않고 값만 받는다(2026-08-13 통일).
    static func start(itemID: UUID, title: String, countsDown: Bool,
                      remaining: Double, elapsedAccum: Double,
                      isInput: Bool, targetSeconds: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = runningState(countsDown: countsDown, remaining: remaining,
                                 elapsedAccum: elapsedAccum)
        Task {
            let existing = await matching(itemID: itemID)
            guard existing.isEmpty else {
                for activity in existing {
                    await activity.update(ActivityContent(state: state, staleDate: nil))
                }
                return
            }
            let attributes = TimerActivityAttributes(title: title, itemID: itemID,
                                                     isInput: isInput, targetSeconds: targetSeconds)
            _ = try? Activity.request(attributes: attributes,
                                      content: ActivityContent(state: state, staleDate: nil))
        }
    }

    /// 정지 — 액티비티는 남기고 멈춘 값으로 굳힌다(잠금화면 재개 버튼의 전제).
    static func pause(itemID: UUID, frozenSeconds: Double) {
        Task {
            for activity in await matching(itemID: itemID) {
                var state = activity.content.state
                state.isRunning = false
                state.frozenSeconds = max(0, frozenSeconds)
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
        }
    }

    /// 재개 — 다시 자생 모드로. remaining·elapsedAccum은 정지 시점 값이다.
    static func resume(itemID: UUID, countsDown: Bool, remaining: Double, elapsedAccum: Double) {
        Task {
            for activity in await matching(itemID: itemID) {
                let state = runningState(countsDown: countsDown, remaining: remaining,
                                         elapsedAccum: elapsedAccum)
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
        }
    }

    static func end(itemID: UUID) {
        Task { await endActivities(itemID: itemID) }
    }

    /// 실행 중 상태 — 타이머는 종료 예정 시각, 스톱워치는 누적을 뺀 과거 시각이 기준점
    private static func runningState(countsDown: Bool, remaining: Double,
                                     elapsedAccum: Double) -> TimerActivityAttributes.ContentState {
        countsDown
            ? .init(anchor: Date.now.addingTimeInterval(remaining), countsDown: true,
                    isRunning: true, frozenSeconds: remaining)
            : .init(anchor: Date.now.addingTimeInterval(-elapsedAccum), countsDown: false,
                    isRunning: true, frozenSeconds: elapsedAccum)
    }

    private static func matching(itemID: UUID) async -> [Activity<TimerActivityAttributes>] {
        Activity<TimerActivityAttributes>.activities.filter { $0.attributes.itemID == itemID }
    }

    private static func endActivities(itemID: UUID) async {
        for activity in await matching(itemID: itemID) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

/// 잠금화면 버튼(PauseTimerIntent·ResumeTimerIntent)의 실행부 — 다리 건너편(Shared/TimerIntents).
/// 인텐트는 앱 프로세스에서 돌지만 **화면은 떠 있지 않을 수 있다.** 그래서 뷰가 아니라 여기서
/// 스토어를 직접 열고, 앱 내 컨트롤(TimerProgressControl.toggle)과 같은 규칙으로 값을 옮긴다.
@MainActor
final class TimerIntentHandler: TimerIntentHandling {
    static let shared = TimerIntentHandler()

    private init() {}

    func apply(_ command: TimerIntentBridge.Command) async {
        let context = TempoRoutineApp.container.mainContext
        guard let backing = Self.backing(for: command, in: context) else { return }

        let target = Double(Self.target(for: command, in: context))
        if command.run {
            guard !backing.isTimerRunning else { return }
            backing.timerStartedAt = .now
            let remaining = max(0, target - backing.elapsedAccumSeconds)
            TimerLiveActivity.resume(itemID: command.itemID, countsDown: target > 0,
                                     remaining: remaining,
                                     elapsedAccum: backing.elapsedAccumSeconds)
        } else {
            guard backing.isTimerRunning else { return }
            backing.elapsedAccumSeconds = backing.elapsedSeconds(at: .now)
            backing.timerStartedAt = nil
            let frozen = target > 0 ? max(0, target - backing.elapsedAccumSeconds)
                                    : backing.elapsedAccumSeconds
            TimerLiveActivity.pause(itemID: command.itemID, frozenSeconds: frozen)
        }
        try? context.save()
    }

    /// 값의 저장처 — Output은 아이템 자신, Input은 **그날 레코드**(§5.5.2)
    private static func backing(for command: TimerIntentBridge.Command,
                                in context: ModelContext) -> (any TimerBacking)? {
        let id = command.itemID
        if command.isInput {
            let day = Calendar.current.startOfDay(for: .now)
            var descriptor = FetchDescriptor<InputProgress>(
                predicate: #Predicate { $0.itemID == id && $0.occurredOn == day })
            descriptor.fetchLimit = 1
            return (try? context.fetch(descriptor))?.first
        }
        var descriptor = FetchDescriptor<OutputItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// 타이머 목표(초). 스톱워치는 0 — Input은 목표가 아이템(InputItem)에 있고 값만 그날 레코드에 있다.
    private static func target(for command: TimerIntentBridge.Command,
                               in context: ModelContext) -> Int {
        let id = command.itemID
        if command.isInput {
            var descriptor = FetchDescriptor<InputItem>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return (try? context.fetch(descriptor))?.first?.targetSeconds ?? 0
        }
        var descriptor = FetchDescriptor<OutputItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.targetSeconds ?? 0
    }
}
