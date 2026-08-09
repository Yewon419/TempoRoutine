// 템포루틴 — 타이머·스톱워치 Live Activity 표시 (2026-08-09, MASTER §5.5.2 타이머 진행 방식)
// 잠금화면 배너 + 다이내믹 아일랜드. anchor 하나로 시스템 타이머 텍스트가 자생(갱신 호출 없음).
// 잉크 토큰·씨앗 글리프는 앱과 동값 사본 — 위젯 타깃을 앱 소스와 얽지 않는다(의도적 중복).

import ActivityKit
import WidgetKit
import SwiftUI

struct TimerActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            lockScreenBanner(context)
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

    private func lockScreenBanner(_ context: ActivityViewContext<TimerActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            WSeedMark()
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.title)
                    .font(WFont.almanac(15, weight: .bold))
                    .lineLimit(1)
                Text(context.state.countsDown ? "타이머" : "스톱워치")
                    .font(.caption2)
                    .opacity(0.55)
            }
            Spacer(minLength: 8)
            timerText(context)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
        .padding(14)
        .activityBackgroundTint(Color(red: 0xF1 / 255, green: 0xEE / 255, blue: 0xE6 / 255).opacity(0.85))
    }

    /// 타이머 = 카운트다운(0:00에서 멈춤), 스톱워치 = 카운트업 — 시스템이 초를 굴린다
    @ViewBuilder
    private func timerText(_ context: ActivityViewContext<TimerActivityAttributes>) -> some View {
        if context.state.countsDown {
            Text(timerInterval: Date.now...max(Date.now, context.state.anchor), countsDown: true)
        } else {
            Text(context.state.anchor, style: .timer)
        }
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
