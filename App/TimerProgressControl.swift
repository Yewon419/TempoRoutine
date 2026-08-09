// 템포루틴 — Output 타이머·스톱워치 진행 컨트롤 (2026-08-09 사용자 결정, MASTER §5.5.2)
// 오늘 탭·하루 상세 공용(SessionProgressControl과 같은 배치 문법).
// 상태 영속 = OutputItem.timerStartedAt 앵커 — 앱이 죽어도 경과가 이어진다.
// 실행 중 표시는 Text(timerInterval:)로 시스템이 갱신한다(뷰 재평가 없이 초가 간다).
// 시작·정지 순간 잠금화면 Live Activity를 함께 켠다/끈다(TimerLiveActivity).

import SwiftUI
import TempoCore

struct TimerProgressControl: View {
    @Bindable var item: OutputItem
    /// completed = 이번 정지로 목표를 채웠는가(타이머만 true 가능) — 햅틱 콜백
    var onEvent: (Bool) -> Void = { _ in }

    private var isTimer: Bool { item.progressKind == .timer }
    private var target: Int { max(0, item.targetSeconds ?? 0) }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                toggle()
            } label: {
                Image(systemName: item.isTimerRunning ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Ink.text.opacity(item.isTimerRunning ? 0.9 : 0.7))
            }
            .accessibilityLabel(item.isTimerRunning ? "일시정지" : "시작")
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
            if item.elapsedAccumSeconds > 0 || item.isTimerRunning {
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
        if let started = item.timerStartedAt {
            if isTimer {
                let remaining = max(0, Double(target) - item.elapsedSeconds())
                Text(timerInterval: Date.now...Date.now.addingTimeInterval(remaining),
                     countsDown: true)
            } else {
                // 카운트업 기준점을 누적만큼 과거로 밀어 "누적+진행"이 이어져 보이게 한다
                Text(started.addingTimeInterval(-item.elapsedAccumSeconds), style: .timer)
            }
        } else {
            Text(format(isTimer ? max(0, Double(target) - item.elapsedAccumSeconds)
                                : item.elapsedAccumSeconds))
        }
    }

    private func toggle() {
        if item.isTimerRunning {
            let wasComplete = item.isComplete
            item.elapsedAccumSeconds = item.elapsedSeconds()
            item.timerStartedAt = nil
            TimerLiveActivity.end(itemID: item.id)
            onEvent(isTimer && !wasComplete && item.isComplete)
        } else {
            item.timerStartedAt = .now
            TimerLiveActivity.start(item: item)
            onEvent(false)
        }
    }

    private func reset() {
        item.elapsedAccumSeconds = 0
        item.timerStartedAt = nil
        TimerLiveActivity.end(itemID: item.id)
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
