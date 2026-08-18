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
import TempoCore   // CyclePhase — 계절 유화 매핑(repo CLAUDE.md 심볼 확인 3종)

/// 사진 지면(시안 `.season-ground`) — 계절 유화 + 블루그레이 스크림.
/// 오늘·나의 템포·설정·하루 상세의 지면이다(캘린더는 흰 티켓 풀블리드라 제외).
/// 스크림 없이는 흰 표제가 그림에 묻힌다(시안 주석 그대로). 시안은 가을 고정이지만
/// 구현은 현재 계절을 따른다 — 에셋 매핑은 캘린더 도판과 같은 `TicketSpec.plateAsset`.
struct TicketGround: View {
    let phase: CyclePhase?

    var body: some View {
        // ⚠ scaledToFill을 ZStack에 직접 두면 **레이아웃 프레임까지 커진다** — 2026-08-18 빌드
        // 380에서 티켓 전 화면이 확대된 사고의 뿌리(clipped는 그리기만 자를 뿐 프레임은 그대로).
        // Color.clear가 제안 크기를 정확히 차지하고, 이미지는 overlay로만 얹는다(레이아웃 무영향).
        // 현재 티켓은 흰 지면 전환으로 이 뷰를 쓰지 않지만, 결함은 고쳐 둔다(재사용 대비).
        Color.clear
            .overlay {
                ZStack {
                    Ink.paper   // 이미지 로드 실패 폴백 = 종전 색면
                    Image(TicketSpec.plateAsset(for: phase))
                        .resizable()
                        .scaledToFill()
                    LinearGradient(
                        colors: [Color(red: 74 / 255, green: 96 / 255, blue: 124 / 255).opacity(0.62),
                                 Color(red: 46 / 255, green: 64 / 255, blue: 90 / 255).opacity(0.82)],
                        startPoint: .top, endPoint: .bottom)
                }
            }
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 발권 필드명 — 시안 프로토 마크업의 tk-label 문구(schedule/input/output, CSS가 대문자화).
/// CardKind는 rawValue가 사용자 표기(「일정」)라 별도 매핑으로 둔다.
func ticketFieldName(_ kind: CardKind) -> String {
    switch kind {
    case .schedule: "schedule"
    case .input: "input"
    case .output: "output"
    }
}

/// 카드 제목 위 극소 대문자 모노 라벨(시안 §3.3-④ `.tk-label`) — 발권물의 필드명.
/// 티켓 테마가 아니면 아무것도 그리지 않는다.
struct TicketFieldLabel: View {
    let text: String

    var body: some View {
        if ThemeStore.chrome.ticketChrome {
            Text(text)
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .kerning(1.8)
                .textCase(.uppercase)
                .foregroundStyle(TicketSpec.label)
                .accessibilityHidden(true)   // 제목이 이미 같은 말을 한다
        }
    }
}

/// 일련번호 스트립(시안 §3.3-⑤ `.tk-serial`) — 오늘 탭 상단, 발권물의 발권 번호.
/// 형식 = TR-YYYYMMDD-NNNN(NNNN = 그해 몇 번째 날). 장식이되 매일 바뀌는 진짜 값이다.
struct TicketSerial: View {
    let date: Date

    var body: some View {
        if ThemeStore.chrome.ticketChrome {
            Text(serial)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .kerning(1.6)
                .foregroundStyle(TicketSpec.label)   // 흰 지면 전환(2026-08-18) — 흰 62%는 안 보인다
                .accessibilityHidden(true)
        }
    }

    private var serial: String {
        let cal = Calendar.current
        let ymd = date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
            .filter(\.isNumber)
        let ordinal = cal.ordinality(of: .day, in: .year, for: date) ?? 0
        return "TR-\(ymd)-\(String(format: "%04d", ordinal))"
    }
}

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
