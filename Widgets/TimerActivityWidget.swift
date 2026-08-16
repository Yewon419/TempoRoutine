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
                DynamicIslandExpandedRegion(.bottom) {
                    HStack { Spacer(); controlButton(context); Spacer() }
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
                Text(subtitle(context))
                    .font(.caption2)
                    .opacity(0.55)
            }
            Spacer(minLength: 8)
            timerText(context)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            controlButton(context)
        }
        .padding(14)
        // 배경 틴트 없음(2026-08-09 베타 피드백 "기본 알림들이랑 같은 색으로") —
        // 시스템 기본 재질·라벨색을 그대로 쓴다(종이색 커스텀 폐기)
        //
        // ⚠ **절전모드 「하얀 박스」의 진짜 원인은 redaction이었다**(2026-08-16 정정).
        // 잠금·AOD에서 시스템은 위젯·Live Activity 콘텐츠를 privacy redaction 처리하고,
        // 그 placeholder가 **내용 없는 흰 덩어리**로 그려진다. 이 배너는 배경을 두지 않아
        // 화면 전체가 빈 흰 사각형으로 보였다. 앞서 의심한 body의 Date.now는 원인이 아니었다
        // (그 수정은 그대로 두는 게 맞다 — 미리 렌더된 뷰에서 현재 시각을 읽는 건 별개의 결함).
        //
        // 싣는 것이 Output 제목과 남은 시간뿐이라 가릴 이유가 없다(§8.2.8 — 주기 정보 0,
        // 제목 노출은 2026-08-02 허용 범위). 잠금화면에서 이미 보이던 것을 AOD에서도 보이게 한다.
        .unredacted()
    }

    private func subtitle(_ context: ActivityViewContext<TimerActivityAttributes>) -> String {
        guard context.state.isRunning else { return "멈춤" }
        return context.state.countsDown ? "타이머" : "스톱워치"
    }

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

    /// 잠금화면 정지·재개(2026-08-14 사용자 지시). LiveActivityIntent라 탭은 **앱 프로세스**에서
    /// 처리된다 — 위젯은 SwiftData를 만지지 않는다는 §8.2.8 계약이 그대로 산다.
    private func controlButton(_ context: ActivityViewContext<TimerActivityAttributes>) -> some View {
        let itemID = context.attributes.itemID
        let isInput = context.attributes.isInput
        return Group {
            if context.state.isRunning {
                Button(intent: PauseTimerIntent(itemID: itemID, isInput: isInput)) {
                    controlGlyph("pause.fill")
                }
                .accessibilityLabel("멈추기")
            } else {
                Button(intent: ResumeTimerIntent(itemID: itemID, isInput: isInput)) {
                    controlGlyph("play.fill")
                }
                .accessibilityLabel("다시 시작")
            }
        }
        .buttonStyle(.plain)
    }

    private func controlGlyph(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .bold))
            .frame(width: 36, height: 36)
            .background(.primary.opacity(0.12), in: Circle())
    }

    /// 앱 format()과 동값 사본(위 헤더의 의도적 중복 원칙)
    private func clockText(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
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
