// 템포루틴 — 잠금화면 타이머 정지·재개 (2026-08-14 사용자 지시, 앱 ↔ 위젯 공용)
//
// **왜 LiveActivityIntent인가**: 이 프로토콜을 채택한 인텐트는 시스템이 **앱 프로세스에서**
// 실행한다. 일반 AppIntent를 위젯 타깃에만 두면 위젯 익스텐션에서 돌아, SwiftData를 만질 수
// 없다(위젯은 App Group 스냅샷만 읽는다 — §8.2.8 계약). 그 계약을 깨지 않고 상태를 바꾸는
// 유일한 경로가 이것이다.
//
// **왜 다리(브리지)를 두는가**: 위젯이 Button(intent:)에 쓰려면 인텐트 타입이 두 타깃 공용이어야
// 하는데, 저장처인 @Model(OutputItem·InputProgress)은 앱 타깃에만 있다. 그래서 여기에는 명령과
// 슬롯만 두고 실제 조작은 앱 구현체(TimerIntentHandler)가 맡는다. 위젯 프로세스에서는 슬롯이
// 영영 비어 있지만, 실행이 앱에서만 일어나므로 무해하다.

import AppIntents
import Foundation

/// 앱 타깃이 구현하는 실행부 — 다리 건너편.
@MainActor
protocol TimerIntentHandling: AnyObject {
    func apply(_ command: TimerIntentBridge.Command) async
}

@MainActor
enum TimerIntentBridge {
    struct Command: Sendable {
        let itemID: UUID
        let isInput: Bool
        /// true = 재개, false = 정지
        let run: Bool
    }

    private static var handler: (any TimerIntentHandling)?
    /// 등록 전에 도착한 명령. 앱이 완전히 종료된 상태에서 버튼을 누르면 시스템이 앱을 깨우는데,
    /// 그 launch와 perform() 사이 순서는 문서로 보장되지 않는다. 놓치면 첫 탭이 먹히지 않으므로
    /// 쌓아 뒀다가 등록 직후 흘려보낸다.
    private static var pending: [Command] = []

    static func register(_ newHandler: any TimerIntentHandling) {
        handler = newHandler
        guard !pending.isEmpty else { return }
        let queued = pending
        pending.removeAll()
        // 한 Task 안에서 순차 처리 — 명령마다 Task를 띄우면 정지·재개 순서가 뒤집힐 수 있다
        Task { for command in queued { await newHandler.apply(command) } }
    }

    static func send(_ command: Command) async {
        if let handler {
            await handler.apply(command)
        } else {
            pending.append(command)
        }
    }
}

struct PauseTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "타이머 멈추기"

    // UUID는 인텐트 파라미터 기본 타입이 아니라 문자열로 싣는다
    @Parameter(title: "아이템") var itemID: String
    @Parameter(title: "Input 여부") var isInput: Bool

    init() {}

    init(itemID: UUID, isInput: Bool) {
        self.itemID = itemID.uuidString
        self.isInput = isInput
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: itemID) {
            await TimerIntentBridge.send(.init(itemID: id, isInput: isInput, run: false))
        }
        return .result()
    }
}

struct ResumeTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "타이머 다시 시작"

    @Parameter(title: "아이템") var itemID: String
    @Parameter(title: "Input 여부") var isInput: Bool

    init() {}

    init(itemID: UUID, isInput: Bool) {
        self.itemID = itemID.uuidString
        self.isInput = isInput
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: itemID) {
            await TimerIntentBridge.send(.init(itemID: id, isInput: isInput, run: true))
        }
        return .result()
    }
}
