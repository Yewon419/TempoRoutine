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

/// 앨범 헤더 — 캘린더 상단(시안 §4.4 ③). 좌측 조판(연도 극소 라벨 → 월 38 + 이전·정지·다음 →
/// 월 진행 바 → 계절 라인 → 「생리 기록」) + 우측 커버 96pt. 월 = 앨범, 오늘 = 재생 위치.
/// 정지 = **오늘 달로 되돌아오기**(계약). 히트 영역 44pt, 글리프만 작게 그린다(§4.7).
struct PlaylistAlbumHeader: View {
    let year: Int
    let month: Int
    /// 이 달 트랙의 재생 위치 — 오늘 이전 달 1, 미래 달 0, 이 달은 일/일수
    let monthProgress: Double
    let seasonLine: String
    let phase: CyclePhase?
    let date: Date
    let onPrev: () -> Void
    let onStop: () -> Void
    let onNext: () -> Void
    let onLogTap: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            main
            cover
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .milkGlass()
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(year))
                .font(.system(size: 10, weight: .medium))
                .kerning(1.8)
                .foregroundStyle(Ink.dim)
            HStack(alignment: .center, spacing: 2) {
                Text(Loc.monthName(month))
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Ink.text)
                Spacer(minLength: 0)
                navButton(action: onPrev, label: Loc.str("이전 달")) {
                    PlaylistTriangle(pointsRight: false).fill(Ink.text)
                        .frame(width: 9, height: 12)
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
                        .frame(width: 9, height: 12)
                }
            }
            PlaylistSeekBar(progress: monthProgress, barHeight: 2, knobSize: 7)
                .padding(.top, 8)
            Text(seasonLine)
                .font(.caption)
                .foregroundStyle(Ink.dim)
                .padding(.top, 8)
            logButton
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func navButton(action: @escaping () -> Void, label: String,
                           @ViewBuilder glyph: () -> some View) -> some View {
        Button(action: action) {
            glyph().frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
    }

    private var logButton: some View {
        Button(action: onLogTap) {
            HStack(spacing: 5) {
                Circle().fill(Ink.record).frame(width: 7, height: 7)
                Text("생리 기록")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Ink.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(Capsule().stroke(Ink.text.opacity(0.3), lineWidth: 1))
        }
    }

    private var cover: some View {
        let day: Int = Calendar.current.component(.day, from: date)
        return RoundedRectangle(cornerRadius: 10)
            .fill(phase.map { seasonMeta(for: $0).glow } ?? Ink.glowWinter)   // 콜드 = 겨울(티켓 전례)
            .overlay {
                Image(PlaylistSpec.coverAsset(for: phase, day: day))
                    .resizable()
                    .scaledToFill()
            }
            .frame(width: PlaylistSpec.albumCoverSize, height: PlaylistSpec.albumCoverSize)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
            .accessibilityHidden(true)
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
