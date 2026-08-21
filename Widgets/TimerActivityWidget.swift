// 템포루틴 — 타이머·스톱워치 Live Activity 표시 (2026-08-09, MASTER §5.5.2 타이머 진행 방식)
// 잠금화면 배너 + 다이내믹 아일랜드. anchor 하나로 시스템 타이머 텍스트가 자생(갱신 호출 없음).
// 잉크 토큰·씨앗 글리프는 앱과 동값 사본 — 위젯 타깃을 앱 소스와 얽지 않는다(의도적 중복).

import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

struct TimerActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            TimerLockBanner(context: context)
                .environment(\.locale, Loc.locale)   // 앱의 언어 선택 추종(2026-08-21)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timerText(context)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        // 정지↔재개 때 숫자가 옮겨 앉지 않게 폭 고정(2026-08-17 베타 피드백 —
                        // 자동 갱신 텍스트는 최대 폭을 예약하고 정적 텍스트는 제 폭만 차지한다)
                        .frame(width: 84, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack { Spacer(); TimerControlButton(context: context); Spacer() }
                }
            } compactLeading: {
                WSeedMark()
            } compactTrailing: {
                timerText(context)
                    .font(.caption2)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                WSeedMark()
            }
        }
    }

    // (잠금화면 배너는 TimerLockBanner로 분리 — isLuminanceReduced 환경값이 필요해서다)

    /// 실행 중 = 시스템이 초를 굴린다(타이머는 카운트다운, 스톱워치는 카운트업).
    /// 멈춤 = 굳은 값을 정적으로 — anchor는 멈춘 순간부터 흘러가는 값이라 쓸 수 없다(2026-08-14).
    /// ⚠ **body에서 Date.now를 쓰지 않는다**(2026-08-14 절전모드 결함). 시스템이 미리 렌더해 둔
    /// 뷰를 다시 그릴 때 그 값이 어긋나면 구간이 무너지고, 배경 없는 배너라 렌더 실패가 곧
    /// 빈 지면으로 보인다. 구간은 상태에서만 만든다 — 언제 평가되든 결과가 같다.
    @ViewBuilder
    private func timerText(_ context: ActivityViewContext<TimerActivityAttributes>) -> some View {
        if !context.state.isRunning {
            Text(clockText(context.state.frozenSeconds))
        } else if context.state.countsDown {
            // 시작 == 끝인 빈 구간을 만들지 않는다(목표를 이미 채운 채 다시 시작한 경우)
            let start = context.state.startedAt
            let end = max(start.addingTimeInterval(1), context.state.anchor)
            Text(timerInterval: start...end, countsDown: true)
        } else {
            Text(context.state.anchor, style: .timer)
        }
    }

    // 정지·재개 버튼은 TimerControlButton(배너와 공용)으로 이동(2026-08-17)

    /// 앱 format()과 동값 사본(위 헤더의 의도적 중복 원칙)
    private func clockText(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// 잠금화면 배너 — 구조체로 뗀 이유 = `isLuminanceReduced` 환경값(절전모드 감지).
///
/// **절전모드 「하얀 박스」 3차 수정(2026-08-17).** 1차(Date.now 제거)·2차(.unredacted())가
/// 배포 후에도 증상을 못 잡았다. 남은 용의자 = **자동 갱신 타이머 텍스트**: AOD는 초 단위
/// 갱신이 없는 저갱신 모드라 `Text(timerInterval:)` 계열이 렌더에서 비는 사례가 보고돼 있다.
/// → 절전모드에선 자동 갱신 텍스트를 **아예 쓰지 않는다.** 시각 의존 없는 정적 값만 그린다
///   (정지 = 굳은 값 / 타이머 = 종료 예정 시각 / 스톱워치 = 시작 시각 — 셋 다 상태에서 나온다).
/// .unredacted()는 유지한다 — redaction까지 겹치면 어느 쪽이 원인이든 다시 빈다.
struct TimerLockBanner: View {
    let context: ActivityViewContext<TimerActivityAttributes>
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        HStack(spacing: 12) {
            WSeedMark()
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.title)
                    .font(WFont.almanac(15, weight: .bold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .opacity(0.55)
            }
            Spacer(minLength: 8)
            timeText
            if !dimmed { TimerControlButton(context: context) }
        }
        .padding(14)
        // 배경 틴트 없음(2026-08-09 베타 피드백 "기본 알림들이랑 같은 색으로") —
        // 시스템 기본 재질·라벨색을 그대로 쓴다(종이색 커스텀 폐기)
        .unredacted()
    }

    private var subtitle: String {
        guard context.state.isRunning else { return "멈춤" }
        return context.state.countsDown ? "타이머" : "스톱워치"
    }

    @ViewBuilder
    private var timeText: some View {
        if dimmed {
            aodText
        } else {
            runningOrFrozenText
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                // 정지↔재개 때 숫자가 옮겨 앉지 않게 폭 고정(2026-08-17 베타 피드백) —
                // 자동 갱신 텍스트는 최대 폭을 예약하고 정적 텍스트는 제 폭만 차지해서,
                // 상태가 바뀔 때마다 숫자가 좌우로 튀었다. 두 상태 모두 같은 상자에 담는다.
                .frame(width: 96, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var runningOrFrozenText: some View {
        if !context.state.isRunning {
            Text(clock(context.state.frozenSeconds))
        } else if context.state.countsDown {
            // body에서 Date.now 금지(repo CLAUDE.md) — 구간은 상태에서만 만든다
            let start = context.state.startedAt
            let end = max(start.addingTimeInterval(1), context.state.anchor)
            Text(timerInterval: start...end, countsDown: true)
        } else {
            Text(context.state.anchor, style: .timer)
        }
    }

    /// 절전모드 — 자동 갱신 없는 정적 표기. 상태 값만 쓰므로 언제 렌더돼도 같은 결과다.
    @ViewBuilder
    private var aodText: some View {
        if !context.state.isRunning {
            Text(clock(context.state.frozenSeconds))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        } else if context.state.countsDown {
            Text(Loc.fmt("%1$@ 종료", "\(context.state.anchor.formatted(date: .omitted, time: .shortened))"))
                .font(.subheadline.weight(.semibold))
        } else {
            Text(Loc.fmt("%1$@ 시작", "\(context.state.anchor.formatted(date: .omitted, time: .shortened))"))
                .font(.subheadline.weight(.semibold))
        }
    }

    private func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// 정지·재개 버튼 — 배너·다이내믹 아일랜드 공용(TimerActivityWidget.controlButton에서 분리)
struct TimerControlButton: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        let itemID = context.attributes.itemID
        let isInput = context.attributes.isInput
        Group {
            if context.state.isRunning {
                Button(intent: PauseTimerIntent(itemID: itemID, isInput: isInput)) {
                    glyph("pause.fill")
                }
                .accessibilityLabel("멈추기")
            } else {
                Button(intent: ResumeTimerIntent(itemID: itemID, isInput: isInput)) {
                    glyph("play.fill")
                }
                .accessibilityLabel("다시 시작")
            }
        }
        .buttonStyle(.plain)
    }

    private func glyph(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .bold))
            .frame(width: 36, height: 36)
            .background(.primary.opacity(0.12), in: Circle())
    }
}

/// 씨앗 글리프 — 앱 SeedGlyph와 동값 사본(위 헤더의 의도적 중복 원칙)
private struct WSeedMark: View {
    var body: some View {
        WSeedShape()
            .fill(.primary.opacity(0.7))
            .frame(width: 9, height: 12)
            .rotationEffect(.degrees(16))
    }
}

private struct WSeedShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.5, y: 0))
        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h),
                       control: CGPoint(x: w * 1.12, y: h * 0.68))
        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: 0),
                       control: CGPoint(x: -w * 0.12, y: h * 0.68))
        return p
    }
}
