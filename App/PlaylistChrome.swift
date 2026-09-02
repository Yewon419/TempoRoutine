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
    /// B1(2026-08-31) 트랙명 탭 음표 — s0 호출부는 끈다(카드 전체 탭 제스처 보호)
    var noteTapEnabled = true

    @State private var noteTick = 0
    @State private var noteHaptic = 0

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
            // 트랙명 = 영어 각인. Geist → Raleway Thin(2026-09-02 3차 비교 판정 "3안" —
            // "얇고 세련" 방향, 베타 「Spring 영어 폰트가 살짝 구리다」)
            Text(verbatim: playlistTrackName(for: meta.phase))
                .font(.ralewayDisplay(size: 32))
                .tracking(0.8)
                .foregroundStyle(Ink.text)   // 트랙명 = 잉크 — 색은 커버가 담당(§4.3)
                .padding(.top, 6)
                // B1(2026-08-31) — 트랙명 탭 = 음표(링 탭 음표의 오늘 탭 판본).
                // s0에선 끈다: 카드 전체 탭 = 전체 열기 제스처를 안쪽 탭이 가로채면 안 된다.
                .overlay(alignment: .top) {
                    if noteTick > 0 { TrackNoteFX(color: meta.color).id(noteTick) }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard noteTapEnabled else { return }
                    Achievements.shared.unlock(.seasonTap)
                    noteTick += 1
                    noteHaptic += 1
                }
                .sensoryFeedback(.impact(weight: .light), trigger: noteHaptic)
            // 날짜 부제는 kicker 줄 우측으로 이동(2026-09-02 대표님 지시 — 트랙명 아래를
            // 비워 Thin 표제가 혼자 선다). 의학 단계명 금지 이력(M-1c)은 그대로 유효.
            PlaylistSeekBar(progress: progress)
                .padding(.top, 14)
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
                .font(.geist(size: 10, weight: .medium))
                .kerning(1.8)
                .foregroundStyle(Ink.dim)
            Rectangle().fill(Ink.text.opacity(0.22))
                .frame(height: 1)
            // 날짜 = 줄 우측(2026-09-02 대표님 판정 — 종전 트랙명 아래 부제에서 이동)
            Text(date.formatted(Loc.dateTime.month().day().weekday(.wide)))
                .font(.caption2)
                .foregroundStyle(Ink.dim)
                .fixedSize()
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
    // year 파라미터 제거(2026-09-02 "2026도 빼" — 안 쓰는 건 삭제, 08-15 원칙)
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
    /// 생리 기록(2026-09-02 재배치 — 범례 줄에서 컨트롤 줄 우측으로. nil = 버튼 없음)
    var onLog: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    // 시안 §4.4 ③ 치수(라벨 118은 파스텔 바이닐 disc 안에 직접 — 2026-09-02)
    private let discSize: CGFloat = 256
    private let ringSize: CGFloat = 284

    private var progress: Double {
        trackLength > 0 ? min(1, Double(trackDay) / Double(trackLength)) : 0
    }
    private var meta: SeasonMeta { seasonMeta(for: phase ?? .menstrual) }

    var body: some View {
        typeStack
            .frame(maxWidth: .infinity)
            // LP 시각 비중 축소(2026-09-02 "반이 넘게 노출") — 본체는 소식란 줄 44pt를 걷어
            // 헤더가 위로 올라간 것. 패딩은 +12(96→108/76→88): 라벨 각인·중앙 심볼이 화면에
            // 남는 최소 노출(중심부가 세이프에어리어 위로 나가면 각인이 통째로 안 보인다).
            .padding(.top, compact ? 88 : 108)
            .background(alignment: .top) {
                // |offset| = 296 − 패딩 관계 유지 — 디스크 하단 라인이 패딩을 따라간다
                discAssembly.offset(y: compact ? -208 : -188)
            }
    }

    // ── 조판(지면 직결) — 7월 / 가을 센터 스택 → 시크바 → 컨트롤 정가운데.
    // 연도 각인 제거(2026-09-02 대표님 "2026도 빼" — 정보 과밀 정리) ──
    private var typeStack: some View {
        VStack(spacing: 0) {
            // 베타 "이 탭 빼고 플리테마는 폰트반영이 아예 안돼있어" — 캘린더 레코드판 월명이
            // .system() 하드코딩으로 남아 표제 서체 개정(Gmarket)을 안 타고 있었다.
            Text(Loc.monthName(month))
                .font(.almanac(size: 26))
                .foregroundStyle(Ink.text)
            if phase != nil {
                // 한국어 복귀(2026-09-02 대표님 "9월 아래 계절명 다시 한국어로" — 라틴 각인은
                // 오늘 탭 카드만 유지). 서체 = 플리 표제 Gmarket Light(almanac), 계절색 유지.
                Text(meta.name)
                    .font(.almanac(size: 16))
                    .foregroundStyle(meta.color)
                    .padding(.top, 1)
            }
            seek
                .padding(.top, 14)   // 8 → 14(2026-08-31 베타 "재생바랑 n일차 좀만 더 아래로")
            controls
                .padding(.top, 2)
                // 생리 기록 = 컨트롤 줄 우측(2026-09-02 재배치 — 범례 줄이 4계절+캡슐로
                // 꽉 차 지저분하던 것. 컨트롤은 중앙 유지, 빈 우측을 쓴다)
                .overlay(alignment: .trailing) {
                    if let onLog {
                        Button(action: onLog) {
                            HStack(spacing: 5) {
                                Circle().fill(Ink.record).frame(width: 7, height: 7)
                                Text("생리 기록")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Ink.text)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .overlay(Capsule().stroke(Ink.text.opacity(0.3), lineWidth: 1))
                        }
                    }
                }
        }
    }

    private var seek: some View {
        // 일차/일 숫자 줄 제거(2026-09-02 대표님 "정보가 너무 과해") — 바(진행)만 남긴다
        PlaylistSeekBar(progress: progress, barHeight: 3, knobSize: 7)
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
                // ⏸ 두 막대(2026-08-31 베타 "정지표지 저거 말고 ㅣㅣ 이렇게 생긴걸로")
                ZStack {
                    Circle().stroke(Ink.text, lineWidth: 1.4)
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 1).fill(Ink.text).frame(width: 2.6, height: 11)
                        RoundedRectangle(cornerRadius: 1).fill(Ink.text).frame(width: 2.6, height: 11)
                    }
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

    /// 라벨 아치 각인(2026-09-02 파스텔 바이닐) — 문자를 원호에 한 자씩 세운다.
    /// flipped = 아래 아치(6시 중심, 글자 머리가 중심을 향해 뒤집힘 — 레퍼런스 BTS 문법).
    /// stepDegrees = 문자당 각도(폭 실측 대신 고정 근사 — 장식 각인이라 충분).
    private struct ArcText: View {
        let text: String
        let radius: CGFloat
        let size: CGFloat
        let stepDegrees: Double
        let flipped: Bool
        let color: Color

        var body: some View {
            let chars = Array(text)
            let total = Double(chars.count - 1) * stepDegrees
            ZStack {
                ForEach(chars.indices, id: \.self) { index in
                    let angle = -total / 2 + Double(index) * stepDegrees
                    Text(String(chars[index]))
                        .font(RalewayFont.available
                              ? .custom("RalewayRoman-Medium", size: size)
                              : .system(size: size, weight: .medium))
                        .foregroundStyle(color)
                        .rotationEffect(.degrees(flipped ? 180 : 0))
                        .offset(y: flipped ? radius : -radius)
                        .rotationEffect(.degrees(flipped ? -angle : angle))
                }
            }
            .accessibilityHidden(true)   // 장식 각인 — 정보는 조판이 담당
        }
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

    /// 파스텔 바이닐(2026-09-02 대표님 2차 레퍼런스 — 흰 판·계절색 라벨 은퇴).
    /// 연한 계절 파스텔 판 + 밝은 라벨 + 라벨 아치 각인(계절 라틴명 / TEMPOROUTINE) +
    /// 그 사이 중앙 = 브랜드 심볼(좌상단 표식을 여기로 이사 — "글씨 사이에 박아").
    /// 각인·심볼이 디스크와 함께 돌아 회전이 저절로 보인다(민무늬 회전 불가시성의 답).
    private static let vinylBase = Color.flatRGB(0xEB, 0xF1, 0xF4)
    private static let labelBase = Color.flatRGB(0xF4, 0xF8, 0xFA)

    private var disc: some View {
        ZStack {
            Circle().fill(Self.vinylBase)
            Circle().fill(meta.color.opacity(0.30))
            // 그루브 — 파스텔 위 흰 선(시안 rgba(255,255,255,.10) 대응)
            ForEach(0..<14, id: \.self) { ring in
                Circle().stroke(Color.white.opacity(0.30), lineWidth: 1.5)
                    .frame(width: 128 + CGFloat(ring) * 9, height: 128 + CGFloat(ring) * 9)
            }
            // 라벨 = 판보다 한 단 밝은 같은 톤(사진·본색 라벨 은퇴)
            ZStack {
                Circle().fill(Self.labelBase)
                Circle().fill(meta.color.opacity(0.14))
            }
            .frame(width: 118, height: 118)
            .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
            // 아치 각인 — 위 = 계절 라틴명, 아래 = 앱 각인(흰 잉크, 시안 동값)
            ArcText(text: playlistTrackName(for: meta.phase), radius: 44, size: 15,
                    stepDegrees: 12, flipped: false, color: .white.opacity(0.95))
            ArcText(text: "TEMPOROUTINE", radius: 40, size: 8,
                    stepDegrees: 10.5, flipped: true, color: .white.opacity(0.75))
            // 중앙 = 브랜드 심볼(스핀들 겸 — 2026-09-02 "좌상단 심볼 빼고 글씨 사이에")
            BrandMark(diameter: 24, color: .white.opacity(0.95))
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
