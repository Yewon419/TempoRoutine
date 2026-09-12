// 템포루틴 — 온보딩 사계절 장 「렌즈가 창이 된다」(2026-09-12 대표님 지시 "각 계절에 한 컷씩, 광고 이미지 활용")
//
// 브랜드 장의 렌즈 자리에서 원이 커지며 화면을 덮고, 그 안에 티저 광고 스틸(겨울 창가 · 봄 유채밭 ·
// 여름 숲 · 가을 안락의자, marketing/ad-teaser/clips 그레이딩본 프레임)이 찬다. 정지 화면 = 풀블리드 사진 +
// 상단 서리 스크림(카피 자리) — 시안 B(ui-mockup/onboarding-v2 `?variant=b`), 전환만 렌즈 확장(대표님 선택).
//
// TempoLens를 그대로 키우지 않는 이유: 굴절 셰이더 + 서리 층(.36)이 사진을 뿌옇게 만들고, 전체 화면
// distortionEffect는 GPU 비용이 크다. 창은 원형 마스크의 좌표(렌즈 hero 자리)만 렌즈와 공유한다.

import SwiftUI
import TempoCore

struct SeasonWindow: View {
    let phase: CyclePhase
    /// 창 지름 — 브랜드 렌즈(hero) 지름에서 화면을 덮는 값까지. 바깥에서 애니메이션한다.
    let diameter: CGFloat
    /// 창 중심 — 세이프 영역 좌표(렌즈와 동일). 지면처럼 세이프 영역을 무시하고 깔리므로 인셋만큼 보정한다.
    let center: CGPoint
    let safeInsets: EdgeInsets
    let reduceMotion: Bool

    static func assetName(_ phase: CyclePhase) -> String {
        switch phase {
        case .menstrual: "SeasonPhotoWinter"
        case .follicular: "SeasonPhotoSpring"
        case .ovulation: "SeasonPhotoSummer"
        case .luteal: "SeasonPhotoAutumn"
        }
    }

    var body: some View {
        // ⚠ 명시 프레임(컨테이너 + 인셋)을 주면 부모 ZStack이 그 크기로 커져 하단 시트(overlay bottom)가
        // 세이프 영역 아래로 밀려난다(89차 찰칵: 「다음」이 사라짐). 지면(OnboardingGround)처럼 프레임 없이
        // `.ignoresSafeArea()`만 — 사진은 overlay로 얹어 레이아웃 크기에 안 끼어들게 한다.
        ZStack {
            Color.clear.overlay { photo }.clipped()
            scrim
        }
        .mask {
            Circle()
                .frame(width: diameter, height: diameter)
                .position(x: center.x + safeInsets.leading, y: center.y + safeInsets.top)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // 계절 사이 전환 = 크로스페이드(카피 전환 0.42와 같은 박자). 창 크기는 바깥이 애니메이션한다.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.42), value: phase)
    }

    private var photo: some View {
        Image(Self.assetName(phase))
            .resizable()
            .aspectRatio(contentMode: .fill)
            .id(phase)
            .transition(.opacity)
    }

    /// 서리 스크림 — 위는 카피 자리(56%까지 스러짐), 아래는 CTA 자리(26%). 시안 B 값 그대로.
    private var scrim: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: Ink.frost.opacity(0.94), location: 0),
                .init(color: Ink.frost.opacity(0.86), location: 0.26),
                .init(color: Ink.frost.opacity(0.55), location: 0.40),
                .init(color: Ink.frost.opacity(0), location: 0.56),
            ], startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: [
                .init(color: Ink.frost.opacity(0.9), location: 0),
                .init(color: Ink.frost.opacity(0.6), location: 0.12),
                .init(color: Ink.frost.opacity(0), location: 0.26),
            ], startPoint: .bottom, endPoint: .top)
        }
    }
}
