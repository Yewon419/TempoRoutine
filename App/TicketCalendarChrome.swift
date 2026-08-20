// 템포루틴 — 티켓 테마 캘린더 문법 (시안 SSOT: ui-mockup/theme/DESIGN.md §3.4)
// 화면 자체가 한 장의 발권물이다. 박스를 새로 치지 않는다 — 지면은 흰 티켓 풀블리드로 두고,
// 발권 정보와 격자를 가르는 경계선 양 끝(= 화면 좌우 가장자리)에 노치만 판다.
//
// ⚠ 발권 정보 블록 높이를 150pt로 고정하는 게 이 문법의 전제다. 절취선 y가 콘텐츠 높이와
// 무관해져야 노치를 뚫을 수 있다(시안 §3.4 "노치가 왜 이제 가능한가").
// ⚠ SeasonCalendarView가 이미 1100줄이라 티켓 전용 조판만 여기로 뗀다. 표시 문법
// (계절 밑줄·일정 띠·기록)은 건드리지 않는다 — MASTER §8.2.3 룰.

import SwiftUI
import TempoCore

// ── 노치 = 안쪽을 향한 V홈 ──
// 원이 아니라 삼각형이다(2026-08-14 사용자 확정). 원은 펀치 구멍으로 읽히고,
// 절취선 끝을 끊는 건 V홈이다.
struct TicketNotch: Shape {
    /// true = 화면 우측 가장자리에서 왼쪽(안쪽)을 향한다
    let pointsLeft: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointsLeft {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

/// 가로 절취선 한 줄. 점선 자체는 여기, 노치는 호출부가 오버레이로 얹는다
/// (노치는 화면 폭 기준이라 padding 밖에서 그려야 한다).
struct TicketPerforation: View {
    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 1)
            .overlay {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0.5))
                    path.addLine(to: CGPoint(x: 4000, y: 0.5))
                }
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Ink.text.opacity(0.34))
            }
            .clipped()
    }
}

/// 세로 바코드 — 가변폭 막대를 세로로 쌓는다. 시안의 repeating-linear-gradient 대응.
struct TicketBarcode: View {
    /// 막대 두께 패턴(pt). 시안 패턴을 그대로 옮긴 값이다.
    private static let bars: [CGFloat] = [1, 2, 2, 1, 1, 2, 2, 1, 1, 3, 2, 1, 2, 2, 1, 1, 2, 3, 1, 2]
    private static let gap: CGFloat = 2

    var body: some View {
        VStack(spacing: Self.gap) {
            ForEach(Array(Self.bars.enumerated()), id: \.offset) { _, thickness in
                Rectangle()
                    .fill(Ink.text.opacity(0.7))
                    .frame(height: thickness)
            }
        }
        .frame(width: 12)
        .clipped()
    }
}

/// 스텁 = 세로 점선 절취선 + 일련 조판 + 세로 바코드
struct TicketStub: View {
    let serial: String

    var body: some View {
        HStack(spacing: 6) {
            Text(serial)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .kerning(1.4)
                .fixedSize()
                .rotationEffect(.degrees(90))
                .frame(width: 14)
            TicketBarcode()
        }
        .frame(width: TicketSpec.stubWidth)
        .foregroundStyle(Ink.text)
        .overlay(alignment: .leading) {
            // 세로 절취선
            Path { path in
                path.move(to: CGPoint(x: 0.5, y: 0))
                path.addLine(to: CGPoint(x: 0.5, y: TicketSpec.headerHeight))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .foregroundStyle(Ink.text.opacity(0.32))
        }
    }
}

/// 발권 정보 블록 — 좌측 조판 / 세로 괘선 / 도판 / 스텁.
/// 좌측 열은 155pt 남짓이라 계절 캡션과 기록 버튼을 한 행에 두면 캡션이 두 줄로 접힌다
/// (시안 실측) — 세로로 쌓는다.
struct TicketMonthHeader: View {
    let year: Int
    let month: Int
    let seasonLine: String
    let phase: CyclePhase?
    let onLogTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            leftColumn
            plate
            TicketStub(serial: String(format: "%d · %02d", year, month))
        }
        .frame(height: TicketSpec.headerHeight)
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(year))
                .font(.system(size: 9, design: .monospaced))
                .kerning(2.2)
                .foregroundStyle(TicketSpec.label)
            // 표제는 아웃라인이 아니라 솔리드 — 티켓 크롬은 outlineDisplay가 false다
            Text(Loc.fmt("%1$@월", "\(month)"))
                .font(.almanac(size: 38))
                .foregroundStyle(Ink.text)
            Spacer(minLength: 12)
            Text(seasonLine)
                .font(.system(size: 11.5))
                .foregroundStyle(Ink.text.opacity(0.7))
                .lineLimit(1)
            logButton
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 13)
        .overlay(alignment: .trailing) {
            // 선 ① 조판과 도판을 가르는 세로 괘선
            Rectangle()
                .fill(Ink.text.opacity(0.2))
                .frame(width: 1)
        }
    }

    /// 생리 기록 = 알약이 아니라 직각 모노 라벨. 둥근 캡슐은 이 테마의 직각·모노 문법에서 튄다.
    private var logButton: some View {
        Button(action: onLogTap) {
            HStack(spacing: 5) {
                Circle().fill(Ink.record).frame(width: 6, height: 6)
                Text("생리 기록")
                    .font(.system(size: 9, design: .monospaced))
                    .kerning(1.1)
            }
            .foregroundStyle(Ink.text)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay(
                Rectangle().stroke(Ink.text.opacity(0.26), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// 도판은 블록 높이를 꽉 채우지 않는다 — 상하 여백이 있어야 "얹힌 그림"으로 읽힌다.
    private var plate: some View {
        Image(TicketSpec.plateAsset(for: phase))
            .resizable()
            .scaledToFill()
            .frame(width: TicketSpec.plateSize.width, height: TicketSpec.plateSize.height)
            .clipped()
            .frame(height: TicketSpec.headerHeight)   // 세로 중앙 정렬
            .accessibilityHidden(true)
    }
}

/// 달 이동 — 계절 범례 줄 양 끝. 표제 옆에 붙이면 38pt 활자에 눌려 자리를 못 잡는다.
/// ⚠ 시각 요소는 22pt지만 히트 영역은 44pt를 확보한다(HIG 최소 타깃).
struct TicketMonthNav: View {
    let onPrev: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            navButton(systemName: "chevron.left", action: onPrev)
                .accessibilityLabel("이전 달")
            Spacer()
            navButton(systemName: "chevron.right", action: onNext)
                .accessibilityLabel("다음 달")
        }
    }

    private func navButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Ink.text.opacity(0.55))
                .frame(width: 22, height: 22)
                .background(TicketSpec.ticketPaper)   // 마감 점선을 끊고 자리를 만든다
                .frame(width: 44, height: 44)         // 히트 영역
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
