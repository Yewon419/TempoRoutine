// 템포루틴 — 플레이리스트 전용 문법 (시안 SSOT: ui-mockup/theme/DESIGN.md §4, 2026-08-19 이식)
// 플레이어 카드(오늘 탭 헤더 대체) + 공용 시크바. 팔레트로 표현되지 않는 조판은
// 여기 모은다 — TicketCard.swift 전례. 은유(§4.2): 계절 = 지금 재생 중인 트랙,
// 주기 일차 = 재생 위치, 계절 사진 = 앨범 커버.

import SwiftUI
import TempoCore

/// 시크바 — 재생 위치 = 주기 진행(§4.2). 리듬 진행 바·위젯 미니 시크바도 같은 문법(§4.4 ⑧).
struct PlaylistSeekBar: View {
    /// 0...1
    let progress: Double
    var barHeight: CGFloat = 3
    var knobSize: CGFloat = 9

    var body: some View {
        GeometryReader { geo in
            let clamped: Double = min(max(progress, 0), 1)
            let x: CGFloat = geo.size.width * CGFloat(clamped)
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.text.opacity(0.22))
                    .frame(height: barHeight)
                Capsule().fill(Ink.accent)
                    .frame(width: max(x, barHeight), height: barHeight)
                Circle().fill(Ink.accent)
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: x - knobSize / 2)
            }
            .frame(height: geo.size.height)
        }
        .frame(height: knobSize)
        .accessibilityHidden(true)   // 값은 옆의 일차 텍스트가 담당
    }
}

/// 플레이어 카드 — 오늘 탭 헤더 대체(시안 §4.4 ①②). 좌측 조판(극소 라벨 + 괘선 →
/// 계절명 30 → 부제 → 시크바 → 일차/주기 길이 → 컨트롤 3개) + 우측 커버 정사각.
/// 컨트롤은 장식이다(2026-08-19 사용자 확정 — 오늘 탭은 항상 오늘, 이동 개념이 없다).
struct PlaylistPlayerCard: View {
    let meta: SeasonMeta
    let dayInCycle: Int
    let cycleLength: Int
    let phase: CyclePhase?
    let date: Date

    private var progress: Double {
        Double(dayInCycle) / Double(max(cycleLength, 1))
    }

    var body: some View {
        HStack(spacing: 14) {
            main
            cover
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .milkGlass()   // 플레이리스트에서 리퀴드 글래스로 갈아탄다(§4.4 ⑥)
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 0) {
            kicker
            Text(meta.name)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Ink.text)   // 트랙명 = 잉크 — 색은 커버가 담당(§4.3)
                .padding(.top, 6)
            // 부제 = 날짜만. 종전엔 의학 단계명(「배란기 · …」)이 앞에 붙어 있었는데
            // MASTER 개정 M-1c의 「의학 단계명은 사용자 표면 금지」 위반이었다(2026-08-20).
            // 계절명은 바로 위 30px 표제가 이미 말한다 — 부제에 다시 넣지 않는다.
            Text(date.formatted(Loc.dateTime.month().day().weekday(.wide)))
                .font(.caption)
                .foregroundStyle(Ink.dim)
                .padding(.top, 1)
            PlaylistSeekBar(progress: progress)
                .padding(.top, 12)
            HStack {
                Text(Loc.fmt("%1$@일차", "\(dayInCycle)"))
                Spacer(minLength: 0)
                Text(Loc.fmt("%1$@일", "\(cycleLength)"))
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(Ink.dim)
            .padding(.top, 6)
            controls
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var kicker: some View {
        HStack(spacing: 8) {
            // 레코드판 문법의 라틴 각인 — 카피가 아니라 디자인 요소다(번역 대상 아님)
            Text(verbatim: "NOW PLAYING")
                .font(.system(size: 10, weight: .medium))
                .kerning(1.8)
                .foregroundStyle(Ink.dim)
            Rectangle().fill(Ink.text.opacity(0.22))
                .frame(height: 1)
        }
    }

    private var controls: some View {
        HStack(spacing: 22) {
            PlaylistTriangle(pointsRight: false)
                .fill(Ink.text)
                .frame(width: 11, height: 14)
            ZStack {
                Circle().stroke(Ink.text, lineWidth: 1.4)
                PlaylistTriangle(pointsRight: true)
                    .fill(Ink.text)
                    .frame(width: 9, height: 12)
                    .offset(x: 1)
            }
            .frame(width: 30, height: 30)
            PlaylistTriangle(pointsRight: true)
                .fill(Ink.text)
                .frame(width: 11, height: 14)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)   // 장식 — 탭 동작 없음
    }

    /// 커버 = 계절 사진 정사각(§4.4 ④). 날짜 시드 랜덤(§4.5) — 같은 날엔 같은 장.
    /// 계절색 면을 뒤에 깔아 에셋 결손에도 자리가 무너지지 않는다.
    private var cover: some View {
        let day: Int = Calendar.current.component(.day, from: date)
        return RoundedRectangle(cornerRadius: 10)
            .fill(meta.glow)
            .overlay {
                Image(PlaylistSpec.coverAsset(for: phase, day: day))
                    .resizable()
                    .scaledToFill()
            }
            .frame(width: PlaylistSpec.coverSize, height: PlaylistSpec.coverSize)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            // 어두운 사진이 카드 경계에 붙는 걸 막는 극세 흰 테두리(§4.4 ④)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
            .accessibilityHidden(true)   // 계절명 텍스트가 라벨 담당
    }
}

/// 캘린더 = 레코드판(시안 §4.4 ③, 2026-08-25 확정 — 「앨범 헤더」 대체).
/// LP 상단 반노출·회전(플랫 — 명암 없음, 그루브 선만) + 진행 원호·도트(보이는 아래 반원에
/// 좌→우 매핑) + 톤암 + 지면 직결 조판(글래스 없음). 컨트롤 ◀ ■ ▶ 하단 정가운데,
/// 정지 = **오늘 달로 되돌아오기**(계약 유지). 히트 영역 44pt.
/// ⚠ 디스크는 화면 위로 넘쳐 상태바 뒤까지 올라간다 — 시계 가독은 실기기 확인 큐.
struct PlaylistRecordHeader: View {
    let year: Int
    let month: Int
    let phase: CyclePhase?
    let date: Date
    /// 현재 계절 트랙의 재생 위치 — 일차/계절 길이(§4.4 ③ 진행 원호·시크바 공용)
    let trackDay: Int
    let trackLength: Int
    /// 6주 달 — 디스크 노출을 20pt 줄여 격자에 양보(활판 §2.3-10과 같은 축)
    let compact: Bool
    let onPrev: () -> Void
    let onStop: () -> Void
    let onNext: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    // 시안 §4.4 ③ 치수
    private let discSize: CGFloat = 256
    private let ringSize: CGFloat = 284
    private let labelSize: CGFloat = 110

    private var progress: Double {
        trackLength > 0 ? min(1, Double(trackDay) / Double(trackLength)) : 0
    }
    private var meta: SeasonMeta { seasonMeta(for: phase ?? .menstrual) }

    var body: some View {
        typeStack
            .frame(maxWidth: .infinity)
            .padding(.top, compact ? 84 : 104)   // 디스크 보이는 몫
            .background(alignment: .top) {
                discAssembly.offset(y: compact ? -206 : -186)
            }
    }

    // ── 조판(지면 직결) — 2026 / 7월 / 가을 센터 스택 → 시크바 → 컨트롤 정가운데 ──
    private var typeStack: some View {
        VStack(spacing: 0) {
            Text(String(year))
                .font(.system(size: 10, weight: .medium))
                .kerning(1.8)
                .foregroundStyle(Ink.dim)
            Text(Loc.monthName(month))
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Ink.text)
            if phase != nil {
                Text(meta.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Ink.text)
                    .padding(.top, 1)
            }
            seek
                .padding(.top, 8)
            controls
                .padding(.top, 2)
        }
    }

    private var seek: some View {
        VStack(spacing: 4) {
            PlaylistSeekBar(progress: progress, barHeight: 3, knobSize: 7)
            HStack {
                Text(Loc.fmt("%lld일차", trackDay))
                Spacer()
                Text(Loc.fmt("%lld일", trackLength))
            }
            .font(.caption)
            .foregroundStyle(Ink.dim)
        }
        .frame(width: 242)
        .opacity(phase == nil ? 0 : 1)   // 콜드 = 자리 유지, 값 없음
    }

    private var controls: some View {
        HStack(spacing: 12) {
            navButton(action: onPrev, label: Loc.str("이전 달")) {
                PlaylistTriangle(pointsRight: false).fill(Ink.text)
                    .frame(width: 11, height: 14)
            }
            navButton(action: onStop, label: Loc.str("오늘 달로")) {
                ZStack {
                    Circle().stroke(Ink.text, lineWidth: 1.4)
                    RoundedRectangle(cornerRadius: 1.5).fill(Ink.text)
                        .frame(width: 9, height: 9)
                }
                .frame(width: 28, height: 28)
            }
            navButton(action: onNext, label: Loc.str("다음 달")) {
                PlaylistTriangle(pointsRight: true).fill(Ink.text)
                    .frame(width: 11, height: 14)
            }
        }
    }

    private func navButton(action: @escaping () -> Void, label: String,
                           @ViewBuilder glyph: () -> some View) -> some View {
        Button(action: action) {
            glyph().frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
    }

    // ── 디스크 어셈블리 — 회전 디스크 + 고정 진행 링·도트 + 톤암 ──
    private var discAssembly: some View {
        ZStack {
            disc
            progressRing
            progressDot
        }
        .frame(width: ringSize, height: ringSize)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) { tonearm }
        .allowsHitTesting(false)   // 브랜드 표식·소식란 탭을 가로채지 않게(배경 장식)
        .accessibilityHidden(true)   // 장식 — 정보는 조판·시크바가 담당
    }

    private var disc: some View {
        ZStack {
            // 흰 판(2026-08-26 대표님 "LP판이랑 바깥라인 진행도 바 하얗게"). 종전 #202B34 폐기.
            // ⚠ 흰 지면·흰 영상 위에서 판이 사라지지 않게 극세 잉크 테두리를 남긴다 —
            // 없으면 실루엣이 통째로 증발한다(색만 바꾸면 판이 안 읽힌다).
            Circle().fill(Color.white)
                .overlay(Circle().stroke(Ink.text.opacity(0.12), lineWidth: 1))
            // 그루브 — 흰 판이 됐으니 잉크 6%로 뒤집는다(흰 4.5%는 흰 판에서 안 보인다)
            ForEach(0..<14, id: \.self) { ring in
                Circle().stroke(Ink.text.opacity(0.06), lineWidth: 1.5)
                    .frame(width: 122 + CGFloat(ring) * 9.5, height: 122 + CGFloat(ring) * 9.5)
            }
            // 라벨 = 계절색 원만(2026-08-26 베타 "레코드판 가운데의 사진은 빼" — 커버 사진 은퇴).
            // 흰 판 위에서 계절을 말하는 유일한 색면이라 glow가 아니라 본색을 쓴다.
            Circle().fill(meta.color)
                .frame(width: labelSize, height: labelSize)
                .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 3))
            // 스핀들 — 흰 판에서 지면색(#E6EAEE)은 안 보인다. 잉크로 뒤집는다
            Circle().fill(Ink.text.opacity(0.35))
                .frame(width: 6, height: 6)
        }
        .frame(width: discSize, height: discSize)
        .rotationEffect(.degrees(spinning ? 360 : 0))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 26).repeatForever(autoreverses: false)) {
                spinning = true
            }
        }
    }

    // 진행 원호 — 디스크 위쪽이 화면 밖이라 보이는 아래 반원에 좌→우 매핑(시안 동일).
    // trim은 3시에서 시계방향뿐이라 scaleEffect(x:-1)로 뒤집는다(시안 scaleX(-1)와 같은 수).
    private var progressRing: some View {
        // 흰 원호(2026-08-26 대표님 지시) — 지나온 몫은 흰색 100%, 남은 몫은 흰색 35%.
        ZStack {
            Circle().trim(from: 0, to: progress * 0.5)
                .stroke(Color.white, lineWidth: 2)
            Circle().trim(from: progress * 0.5, to: 0.5)
                .stroke(Color.white.opacity(0.35), lineWidth: 2)
        }
        .frame(width: ringSize, height: ringSize)
        .scaleEffect(x: -1)
    }

    // 도트만 잉크로 남긴다 — 원호가 흰색이 된 이상 현재 위치를 짚는 건 이 점 하나뿐이다.
    private var progressDot: some View {
        Circle().fill(Ink.text)
            .frame(width: 8, height: 8)
            .background(Circle().fill(Color.white.opacity(0.9)).frame(width: 14, height: 14))
            .offset(x: ringSize / 2)
            .rotationEffect(.degrees(progress * 180))
            .scaleEffect(x: -1)
    }

    // 톤암 — 우상단 피벗(반쯤 화면 밖) → 로드 40°로 그루브 위. 전부 플랫 단색(명암 없음)
    private var tonearm: some View {
        let rodGray = Color(red: 0x7A / 255, green: 0x87 / 255, blue: 0x94 / 255)
        let headDark = Color(red: 0x39 / 255, green: 0x43 / 255, blue: 0x4D / 255)
        return ZStack(alignment: .top) {
            Capsule().fill(rodGray)
                .frame(width: 5, height: 140)
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4).fill(headDark)
                        .frame(width: 11, height: 24)
                        .offset(y: 14)
                }
                .rotationEffect(.degrees(40), anchor: UnitPoint(x: 0.5, y: 0.07))
            Circle().fill(rodGray)
                .frame(width: 28, height: 28)
                .offset(y: -4)
        }
        .offset(x: 14, y: 62)
    }
}

/// 단일 삼각 글리프 — SF Symbols의 이중 삼각(backward.fill)과 다른 시안 문법(§4.4 ①·③).
struct PlaylistTriangle: Shape {
    let pointsRight: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointsRight {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}
