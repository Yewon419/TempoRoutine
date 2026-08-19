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
            Text("\(meta.phaseName) · \(date.formatted(.dateTime.month().day().weekday(.wide)))")
                .font(.caption)
                .foregroundStyle(Ink.dim)
                .padding(.top, 1)
            PlaylistSeekBar(progress: progress)
                .padding(.top, 12)
            HStack {
                Text("\(dayInCycle)일차")
                Spacer(minLength: 0)
                Text("\(cycleLength)일")
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
            Text("NOW PLAYING")
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
