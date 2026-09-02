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

// ── 히어로 밴드(2026-08-31 시안 §3.4 증강, 베타 "공지 버튼 바로 아래에서 흰색 부분 끊어줘.
// 그 위는 다른 탭들처럼 어둡게" + 대표님 레퍼런스 편집 포스터) ──
// 화면 상단에 계절 유화 + 스크림을 깔고, 브랜드 표식·소식란을 그 위에 흰 잉크로 얹는다.
// 경계는 하드 엣지(흐린 페이드 기각) + 실물 티켓 가장자리 문법 — 발권지가 안쪽으로
// 파여 그 구멍으로 유화가 보인다(볼록 아님, 3차 교정 확정).

/// 반원 스캘럽 마스크 — 뷰 너비에 맞춰 반원 개수를 동적으로 계산한다(디바이스 폭 무관).
/// 문법(시안 3차 확정 + 2026-09-02 베타 「동글동글이가 위쪽이야」 재교정): **발권지가 파여
/// 유화 반원이 경계 아래로 매달린다** — 유화 본체는 maxY−r에서 끝나고, 반원(중심이 그
/// 경계선 위)만 maxY까지 볼록하게 내려간다. 호출부는 뷰 높이에 r(지름/2)을 더해 볼록분이
/// 잘리지 않게 해야 한다. 57차의 「위로 파기」는 시안과 반대 기하였다.
struct TicketScallopMask: Shape {
    var diameter: CGFloat
    var period: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = diameter / 2
        let base = rect.maxY - r   // 발권지 경계선 — 유화 본체의 하단
        var centers: [CGFloat] = []
        var cx = rect.minX + period / 2
        while cx - r < rect.maxX + period {
            centers.append(cx)
            cx += period
        }
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: base))
        // 우→좌로 걸으며 각 스캘럽에서 아래(발권지 쪽)로 볼록한 반원을 돈다.
        // ⚠ y-down 좌표계에서 clockwise:false = 3시→6시(아래)→9시(repo CLAUDE.md 함정 항목)
        for cx in centers.reversed() {
            path.addLine(to: CGPoint(x: cx + r, y: base))
            path.addArc(center: CGPoint(x: cx, y: base), radius: r,
                       startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX, y: base))
        path.closeSubpath()
        return path
    }
}

/// 히어로 밴드 — 계절 유화 + 스크림 + 라틴 라벨 + 하단 스캘럽. 브랜드 표식·소식란은
/// 이 밴드 위에 흰 잉크로 얹힌다(호출부인 SeasonCalendarView가 조합한다 — 이 뷰는 배경만).
struct TicketHeroArtwork: View {
    let phase: CyclePhase?
    let label: String

    /// 스크림 = 오늘 탭 유화 지면과 같은 계열(§3.3-⑥ 흰 잉크 담보). 하단 페이드 기각
    /// (2026-08-31 "흐릿하게 끊지 말고 명확하게 확 끊어") — 끝까지 균일, 경계는 색면 대 색면.
    private static let scrimTop = Color(red: 46 / 255, green: 64 / 255, blue: 90 / 255).opacity(0.62)
    private static let scrimBottom = Color(red: 46 / 255, green: 64 / 255, blue: 90 / 255).opacity(0.8)

    var body: some View {
        // scaledToFill을 ZStack에 직접 두면 레이아웃 프레임까지 커진다(2026-08-18 확대 버그
        // 이력, TicketGround 전례) — Color.clear.overlay 패턴으로 그리기만 자른다.
        Color.clear
            .overlay {
                ZStack(alignment: .bottomLeading) {
                    Image(TicketSpec.plateAsset(for: phase))
                        .resizable()
                        .scaledToFill()
                    LinearGradient(colors: [Self.scrimTop, Self.scrimBottom],
                                   startPoint: .top, endPoint: .bottom)
                    Text(label)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .kerning(2.4)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.leading, 20)
                        .padding(.bottom, 13)
                }
            }
            .clipped()
            .mask(TicketScallopMask(diameter: 7.3, period: 11))
            .accessibilityHidden(true)
    }
}

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
        // 높이를 블록(150)에 못 박는다(2026-09-02 베타 「사진 옆에 점선 아랫칸으로 안넘어오게」
        // — 뷰 높이가 콘텐츠(바코드) 기준이라 아래 절취선 Path(0→150)가 세로 중앙 배치에서
        // 블록 밖 격자까지 흘러내렸다. 프레임 = Path 좌표계 기준이어야 한다)
        .frame(width: TicketSpec.stubWidth, height: TicketSpec.headerHeight)
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
    /// nil = 생리 기록 버튼 없음(2026-09-02 숨기기 스위치 — 설정 행이 진입점)
    let onLogTap: (() -> Void)?

    var body: some View {
        // 세로 중앙(2026-08-31 대표님 "아래 디자인 요소들 정렬, 위로 쏠린 느낌") — 도판·스텁은
        // 150을 꽉 채우니 무영향, 조판 칸(leftColumn)만 짧아서 이 alignment로 실제 센터가 잡힌다.
        HStack(alignment: .center, spacing: 13) {
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
            // 색 스와치(2026-08-31 레퍼런스) — 현재 계절색 명도 5단 램프
            seasonSwatch
                .padding(.top, 8)
                .padding(.bottom, 6)
            Text(seasonLine)
                .font(.system(size: 11.5))
                .foregroundStyle(Ink.text.opacity(0.7))
                .lineLimit(1)
            if onLogTap != nil {
                logButton
                    .padding(.top, 8)
            }
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

    /// 색 스와치 — 콜드(기록 없음)는 겨울로 접는다(도판 폴백과 같은 규칙, plateAsset 전례)
    private var seasonSwatch: some View {
        let color = seasonMeta(for: phase ?? .menstrual).color
        return HStack(spacing: 3) {
            ForEach([0.26, 0.44, 0.62, 0.8, 1.0], id: \.self) { opacity in
                Rectangle().fill(color.opacity(opacity)).frame(width: 17, height: 9)
            }
        }
        .accessibilityHidden(true)
    }

    /// 생리 기록 = 알약이 아니라 직각 모노 라벨. 둥근 캡슐은 이 테마의 직각·모노 문법에서 튄다.
    private var logButton: some View {
        Button(action: onLogTap ?? {}) {
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
            // 오프셋 프레임(2026-08-31 레퍼런스) — 도판 밖으로 어긋난 얇은 테두리 한 겹.
            // 편집 포스터가 사진을 "놓았다"고 말하는 방식. 도판을 키우지 않고 인상만 바꾼다.
            .overlay {
                Rectangle()
                    .stroke(Ink.text.opacity(0.42), lineWidth: 1)
                    .frame(width: TicketSpec.plateSize.width, height: TicketSpec.plateSize.height)
                    .offset(x: 9, y: -9)
            }
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
