// 템포루틴 — 타이머·스톱워치 진행 컨트롤 (2026-08-09 사용자 결정, MASTER §5.5.2)
// **Input·Output 공용**(2026-08-13 통일). 값이 어디 있느냐만 다르고 조작은 같아서,
// 저장처를 TimerBacking으로 추상화했다 — Output=아이템, Input=그날 레코드.
// existential(any)이 아니라 제네릭인 이유: @Bindable이 구체 Observable 타입을 요구한다.
// 상태 영속 = timerStartedAt 앵커 — 앱이 죽어도 경과가 이어진다.
// 실행 중 표시는 Text(timerInterval:)로 시스템이 갱신한다(뷰 재평가 없이 초가 간다).
// 시작·정지 순간 잠금화면 Live Activity를 함께 켠다/끈다(TimerLiveActivity).

import SwiftUI
import TempoCore

/// 타이머 값의 저장처 — OutputItem(수명 누적)과 InputProgress(그날치)가 같은 이름으로 갖는다.
protocol TimerBacking: AnyObject, Observable {
    var elapsedAccumSeconds: Double { get set }
    var timerStartedAt: Date? { get set }
    var isTimerRunning: Bool { get }
    func elapsedSeconds(at now: Date) -> Double
}

struct TimerProgressControl<Backing: TimerBacking>: View {
    @Bindable var backing: Backing
    /// Live Activity 키 = **아이템** id(Input이라도 그날 레코드 id가 아니다 — 잠금화면은 아이템을 가리킨다)
    let activityID: UUID
    let activityTitle: String
    let isTimer: Bool
    /// 타이머 목표(초). 스톱워치는 0
    let targetSeconds: Int
    /// 값의 저장처 — 잠금화면 버튼이 Output(아이템)과 Input(그날 레코드) 중 어느 쪽을 열지 가른다
    let isInput: Bool
    /// completed = 이번 정지로 목표를 채웠는가(타이머만 true 가능) — 햅틱 콜백
    var onEvent: (Bool) -> Void = { _ in }

    private var target: Int { max(0, targetSeconds) }

    /// 멈춘 누적 기준 목표 도달 — 완료 파생은 소유자가 따로 판정한다(여기선 햅틱 전이만 본다)
    private var reachedByAccum: Bool {
        isTimer && target > 0 && backing.elapsedAccumSeconds >= Double(target)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                toggle()
            } label: {
                Image(systemName: backing.isTimerRunning ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Ink.text.opacity(backing.isTimerRunning ? 0.9 : 0.7))
            }
            .accessibilityLabel(backing.isTimerRunning ? "일시정지" : "시작")
            elapsedText
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Ink.text)
            if isTimer {
                Text("/ \(format(Double(target)))")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Ink.text.opacity(0.5))
            }
            Spacer(minLength: 0)
            if backing.elapsedAccumSeconds > 0 || backing.isTimerRunning {
                Button("초기화") { reset() }
                    .font(.caption)
                    .foregroundStyle(Ink.text.opacity(0.45))
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// 실행 중 = 시스템 자동 갱신 텍스트 / 멈춤 = 누적 정적 표기.
    /// 타이머는 남은 시간 카운트다운, 스톱워치는 경과 카운트업.
    @ViewBuilder
    private var elapsedText: some View {
        if let started = backing.timerStartedAt {
            if isTimer {
                let remaining = max(0, Double(target) - backing.elapsedSeconds(at: .now))
                Text(timerInterval: Date.now...Date.now.addingTimeInterval(remaining),
                     countsDown: true)
            } else {
                // 카운트업 기준점을 누적만큼 과거로 밀어 "누적+진행"이 이어져 보이게 한다
                Text(started.addingTimeInterval(-backing.elapsedAccumSeconds), style: .timer)
            }
        } else {
            Text(format(isTimer ? max(0, Double(target) - backing.elapsedAccumSeconds)
                                : backing.elapsedAccumSeconds))
        }
    }

    private func toggle() {
        if backing.isTimerRunning {
            let wasReached = reachedByAccum
            backing.elapsedAccumSeconds = backing.elapsedSeconds(at: .now)
            backing.timerStartedAt = nil
            // 걷지 않고 멈춘 값으로 굳힌다 — 잠금화면에서 다시 시작하려면 남아 있어야 한다(2026-08-14)
            TimerLiveActivity.pause(itemID: activityID,
                                    frozenSeconds: isTimer
                                        ? max(0, Double(target) - backing.elapsedAccumSeconds)
                                        : backing.elapsedAccumSeconds)
            onEvent(!wasReached && reachedByAccum)
        } else {
            backing.timerStartedAt = .now
            TimerLiveActivity.start(itemID: activityID, title: activityTitle, countsDown: isTimer,
                                    remaining: max(0, Double(target) - backing.elapsedSeconds(at: .now)),
                                    elapsedAccum: backing.elapsedAccumSeconds,
                                    isInput: isInput, targetSeconds: target)
            onEvent(false)
        }
    }

    private func reset() {
        backing.elapsedAccumSeconds = 0
        backing.timerStartedAt = nil
        TimerLiveActivity.end(itemID: activityID)
        onEvent(false)
    }

    private func format(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
