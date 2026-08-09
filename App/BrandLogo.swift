// 템포루틴 확정 로고 — 끊긴 원 + 점 + 워드마크(세로형).
//
// ⚠ 비율의 SSOT는 marketing/ad-teaser/logo/build_final.py 다. 값을 바꾸려면 그쪽부터 고칠 것.
//   링 두께   = 외경의 3.125%
//   12시 끊김 = 외경의 0.100(호 위 길이의 절반) → 반각 11.91°, 전체 23.8°
//   점        = 반지름 외경의 5.3%, 중심은 링 바깥 가장자리
//   워드마크  = Gowun Batang Regular, 잉크 높이 0.9453em, 심볼 외경 = 잉크높이 × 1.18
//   세로 간격 = 외경의 0.10
//
// 종이색 원반으로 링을 덮지 않고 획을 실제로 끊는다. 원반 방식은 종이톤 배경에서만
// 성립하고 다른 배경에 올리면 밝은 원반이 그대로 드러난다(2026-07-27 결정).

import SwiftUI

struct BrandLogo: View {
    var diameter: CGFloat = 96
    var color: Color = Ink.text

    /// 12시 끊김의 절반을 원둘레 분수로. asin(0.100 / 0.484375) = 0.2079rad → 11.91° → 0.0331
    private static let gapHalf: CGFloat = 0.0331
    private static let strokeRatio: CGFloat = 0.03125
    private static let dotRatio: CGFloat = 0.053
    private static let wordSizeRatio: CGFloat = 0.8965   // 폰트 크기 / 외경
    private static let kerningRatio: CGFloat = -0.0986   // 자간 -110/1000em 환산
    private static let stackGap: CGFloat = 0.10

    private var stroke: CGFloat { diameter * Self.strokeRatio }

    var body: some View {
        VStack(spacing: diameter * Self.stackGap) {
            symbol
            Text("템포루틴")
                .font(.almanac(size: diameter * Self.wordSizeRatio))
                .kerning(diameter * Self.kerningRatio)
                .foregroundStyle(color)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("템포루틴")
    }

    // 한 식에 shape+stroke+frame+offset을 몰면 타입체크가 터진다(repo CLAUDE.md) — 쪼개 둔다.
    private var symbol: some View {
        ZStack {
            ring
            dot
        }
        .frame(width: diameter, height: diameter)
    }

    private var ring: some View {
        let side: CGFloat = diameter - stroke   // 획이 path 양쪽으로 반씩 나가므로 외경이 diameter가 된다
        return Circle()
            .trim(from: Self.gapHalf, to: 1 - Self.gapHalf)
            .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            .rotationEffect(.degrees(-90))      // trim 시작점(3시)의 끊김을 12시로
            .frame(width: side, height: side)
    }

    private var dot: some View {
        let size: CGFloat = diameter * Self.dotRatio * 2
        let lift: CGFloat = -diameter / 2       // 링 바깥 가장자리에 얹는다
        return Circle()
            .fill(color)
            .frame(width: size, height: size)
            .offset(y: lift)
    }
}

/// 심볼 단독(끊긴 원 + 점) — 탭 좌상단 브랜드 표식 등 소형 사용처(2026-08-09 사용자 지시).
/// 소형에선 로고 원비율 획(3.125%)·점(5.3%)이 흐려져 두께·점만 키운다 — 앱 아이콘이
/// 작은 크기에서 링을 두껍게 보정한 것과 같은 근거. 끊김 각도는 원비율 유지.
struct BrandMark: View {
    var diameter: CGFloat = 18
    var color: Color = Ink.text

    private static let gapHalf: CGFloat = 0.0331   // BrandLogo와 동값(12시 끊김)
    private static let strokeRatio: CGFloat = 0.07
    private static let dotRatio: CGFloat = 0.085

    private var stroke: CGFloat { diameter * Self.strokeRatio }

    var body: some View {
        ZStack {
            ring
            dot
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)   // 장식 표식 — 탭 이름이 이미 맥락을 준다
    }

    private var ring: some View {
        let side: CGFloat = diameter - stroke
        return Circle()
            .trim(from: Self.gapHalf, to: 1 - Self.gapHalf)
            .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: side, height: side)
    }

    private var dot: some View {
        let size: CGFloat = diameter * Self.dotRatio * 2
        return Circle()
            .fill(color)
            .frame(width: size, height: size)
            .offset(y: -diameter / 2)
    }
}

#Preview {
    ZStack {
        Ink.paper.ignoresSafeArea()
        VStack(spacing: 30) {
            BrandLogo(diameter: 120)
            BrandMark(diameter: 18)
        }
    }
}
