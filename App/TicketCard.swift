// 템포루틴 — 티켓 테마 카드 문법 (시안 SSOT ui-mockup/theme/DESIGN.md §3.3-②③)
//
// 카드 = 발권물: 흰 지면 + 우측 스텁 + 세로 점선 절취선 + **삼각 V홈**.
// 스텁에는 그 카드의 «핵심 값 하나»만 세로로 세운다(시각·진행률·일차).
//
// ⚠ V홈은 반원이 아니라 삼각형이다(2026-08-14 사용자 확정 — 원은 펀치 구멍으로 읽힌다).
// ⚠ 홈은 «색으로 흉내내지» 않는다. 카드 윤곽을 실제로 도려내 뒤 지면이 비치게 한다 —
//   시안 실측 기록: 지면을 흰색으로 바꾸면 홈이 사라져야 정상이다.
// ⚠ 모서리 라운드(시안 4px)는 두지 않았다. V홈과 라운드를 한 Path에 섞으면 식이 길어져
//   타입 체커가 터진다(repo CLAUDE.md 2026-07-25) — 각진 발권물로 둔다.

import SwiftUI

/// 우측 스텁 경계선 위·아래에 V홈이 파인 카드 윤곽.
struct TicketCardShape: Shape {
    var stubWidth: CGFloat = TicketSpec.stubWidth
    /// 홈이 카드 안으로 파고드는 깊이
    var depth: CGFloat = 6
    /// 홈 입구 반폭
    var half: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        let seam = rect.maxX - stubWidth
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: seam - half, y: rect.minY))
        path.addLine(to: CGPoint(x: seam, y: rect.minY + depth))
        path.addLine(to: CGPoint(x: seam + half, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: seam + half, y: rect.maxY))
        path.addLine(to: CGPoint(x: seam, y: rect.maxY - depth))
        path.addLine(to: CGPoint(x: seam - half, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 카드 스텁 — 세로 모노 값 + 세로 바코드. 점선 경계는 스텁 왼쪽에 선다.
/// ⚠ 캘린더의 `TicketStub`과 별개다: 그쪽은 절취선 길이가 발권 정보 블록(150pt) 고정이라
///   높이가 콘텐츠를 따라가는 카드에는 쓸 수 없다.
struct TicketCardStub: View {
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .kerning(0.7)
                .foregroundStyle(Ink.text)
                .fixedSize()
                .rotationEffect(.degrees(90))
            bars
        }
        .frame(width: TicketSpec.stubWidth)
        .overlay(alignment: .leading) { seam }
        .accessibilityHidden(true)   // 값은 카드 본문이 이미 말한다 — 장식 복창을 만들지 않는다
    }

    /// 세로 점선 절취선
    private var seam: some View {
        Rectangle()
            .fill(Ink.text.opacity(0.3))
            .frame(width: 1)
            .mask {
                VStack(spacing: 3) {
                    ForEach(0..<40, id: \.self) { _ in
                        Rectangle().frame(height: 3)
                    }
                }
            }
    }

    /// 세로 바코드 — 가변폭 막대(시안 repeating-linear-gradient 근사)
    private var bars: some View {
        VStack(spacing: 1) {
            ForEach(Array(Self.pattern.enumerated()), id: \.offset) { _, height in
                Rectangle().frame(height: height)
            }
        }
        .frame(width: 11)
        .foregroundStyle(Ink.text.opacity(0.7))
        .clipped()
    }

    private static let pattern: [CGFloat] = [1, 2, 1, 2, 1, 1, 2, 1, 3, 1, 2, 1, 1, 2, 3, 1, 1, 2, 1, 2]
}
