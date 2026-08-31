// 템포루틴 — 계절 표제 탭 반응 (2026-08-31 대표님 승인 B1 — "약간 값어치 있는 테마에만")
// 오늘 탭의 계절 표제를 탭하면 테마 문법대로 짧게 반응한다. 대상 = 활판·티켓·날씨(+플리는
// 플레이어 트랙명, PlaylistChrome 쪽). 기본·은필·모던·포인트컬러는 반응 없음.
// 첫 발동 = 히든 업적 「계절을 만진 손」(발견 유도 — 어디에도 안내하지 않는다).
//
// - 활판: 활자가 눌리는 프레스(스케일 0.965 스프링) + 무거운 햅틱 — 인쇄기의 압.
// - 티켓: 검표 도장 「확인」 스탬프가 쾅 찍혔다 사라짐(기울어진 빨강 이중 링) + rigid 햅틱.
// - 날씨: 하늘 파문 2겹이 표제에서 퍼져 나감 + 부드러운 햅틱.
// reduce motion = 반응 전부 생략(햅틱·업적만).

import SwiftUI
import TempoCore

extension View {
    /// 오늘 탭 계절 표제 전용 — 활성 테마가 대상이 아니면 아무것도 얹지 않는다
    func seasonTitleTap() -> some View {
        modifier(SeasonTitleTapFX())
    }
}

private enum TapFXKind {
    case letterpress, ticket, weather
    case none

    static var current: TapFXKind {
        let chrome = ThemeStore.chrome
        if chrome.debossDisplay { return .letterpress }
        if chrome.photographicGround { return .ticket }
        if chrome.skyGround { return .weather }
        return .none
    }
}

private struct SeasonTitleTapFX: ViewModifier {
    @State private var tick = 0          // id 교체 = 1회성 연출 재생(NoteRise 전례)
    @State private var pressed = false   // 활판 프레스
    @State private var heavyTick = 0
    @State private var rigidTick = 0
    @State private var softTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // 활성 테마는 루트 리빌드로만 바뀐다(ThemeStore) — body마다 읽어도 한 값
        let kind = TapFXKind.current
        if kind == .none {
            content
        } else {
            content
                .scaleEffect(pressed ? 0.965 : 1)
                .overlay {
                    if tick > 0, !reduceMotion {
                        fx(kind).id(tick)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { fire(kind) }
                .sensoryFeedback(.impact(weight: .heavy), trigger: heavyTick)
                .sensoryFeedback(.impact(flexibility: .rigid), trigger: rigidTick)
                .sensoryFeedback(.impact(weight: .light), trigger: softTick)
        }
    }

    private func fire(_ kind: TapFXKind) {
        Achievements.shared.unlock(.seasonTap)
        tick += 1
        switch kind {
        case .letterpress:
            heavyTick += 1
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.14, dampingFraction: 0.6)) { pressed = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 140_000_000)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { pressed = false }
            }
        case .ticket: rigidTick += 1
        case .weather: softTick += 1
        case .none: break
        }
    }

    @ViewBuilder
    private func fx(_ kind: TapFXKind) -> some View {
        switch kind {
        case .ticket: TicketStampFX()
        case .weather: SkyRippleFX()
        case .letterpress, .none: EmptyView()   // 활판은 프레스(scale)가 곧 반응
        }
    }
}

/// 검표 스탬프 — 쾅 찍혔다(1.5→1 스프링) 잠시 머물고 사라진다
private struct TicketStampFX: View {
    @State private var shown = false
    @State private var gone = false
    private let red = Color.flatRGB(0xA9, 0x32, 0x26)

    var body: some View {
        ZStack {
            Circle().stroke(red, lineWidth: 2.5).frame(width: 58, height: 58)
            Circle().stroke(red, lineWidth: 1).frame(width: 48, height: 48)
            // 검표 도장 문구 = 한국어 고정(활판 인용문 §2.3-5와 같은 규약 — 인쇄물의 일부)
            Text(verbatim: "확인")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(red)
        }
        .opacity(0.85)
        .rotationEffect(.degrees(-12))
        .scaleEffect(shown ? 1 : 1.6)
        .opacity(gone ? 0 : (shown ? 1 : 0))
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) { shown = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                withAnimation(.easeOut(duration: 0.35)) { gone = true }
            }
        }
    }
}

/// 하늘 파문 — 흰 원 2겹이 시차를 두고 퍼져 나간다
private struct SkyRippleFX: View {
    @State private var spread = false

    var body: some View {
        ZStack {
            ripple(delay: 0)
            ripple(delay: 0.12)
        }
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: 0.8)) { spread = true } }
    }

    private func ripple(delay: Double) -> some View {
        Circle()
            .stroke(.white.opacity(spread ? 0 : 0.7), lineWidth: 1.5)
            .frame(width: spread ? 130 : 20, height: spread ? 130 : 20)
            .animation(.easeOut(duration: 0.8).delay(delay), value: spread)
    }
}

/// 플리 트랙명 음표(B1 — PlaylistChrome 부착용) — SignalPanel NoteRise의 시차 2음 판본
struct TrackNoteFX: View {
    let color: Color

    var body: some View {
        ZStack {
            note(offsetX: -6, delay: 0)
            note(offsetX: 10, delay: 0.12)
        }
        .allowsHitTesting(false)
    }

    private func note(offsetX: CGFloat, delay: Double) -> some View {
        RisingNote(delay: delay)
            .foregroundStyle(color)
            .offset(x: offsetX)
    }

    private struct RisingNote: View {
        let delay: Double
        @State private var risen = false

        var body: some View {
            Image(systemName: "music.note")
                .font(.system(size: 12, weight: .semibold))
                .offset(y: risen ? -26 : -2)
                .opacity(risen ? 0 : 1)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.7).delay(delay)) { risen = true }
                }
        }
    }
}
