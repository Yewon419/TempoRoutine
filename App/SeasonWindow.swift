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
        // 계절 사이 전환 = 크로스페이드 0.6(J2 — 카피 등장 스태거와 겹치게 조금 길게). 창 크기는 바깥이 애니메이션한다.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: phase)
    }

    private var photo: some View {
        // 사진마다 새 인스턴스(.id) — 느린 확대 드리프트가 장마다 처음부터(J2 전환, 2026-09-13)
        SeasonPhotoDrift(assetName: Self.assetName(phase), reduceMotion: reduceMotion)
            .id(phase)
            .transition(.opacity)
    }

    /// 서리 스크림 — 위는 카피 자리(56%까지 스러짐), 아래는 CTA 자리(26%). 시안 B 값 그대로.
    /// 먹 그라데이션(J2, 2026-09-13 대표님 확정 — 프로토 ?variant=j 값 그대로): 아래는 카피 자리(68%까지),
    /// 위는 상태바·뒤로가기 보호(24%까지). 활자는 전부 지면색(흰)이라 스크림이 어둡다.
    /// (C안의 서리 스크림은 2026-09-12 하루 살았다 — "매거진스러운 디자인" 요청으로 어두운 방향 확정.)
    private static let inkShade = Color(red: 18 / 255, green: 20 / 255, blue: 23 / 255)

    private var scrim: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: Color.black.opacity(0.46), location: 0),
                .init(color: Color.black.opacity(0), location: 0.24),
            ], startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: [
                .init(color: Self.inkShade.opacity(0.94), location: 0),
                .init(color: Self.inkShade.opacity(0.74), location: 0.24),
                .init(color: Self.inkShade.opacity(0.22), location: 0.50),
                .init(color: Self.inkShade.opacity(0), location: 0.68),
            ], startPoint: .bottom, endPoint: .top)
        }
    }
}

/// 사진 한 장 = 필름 그레인 + 느린 확대 드리프트(1.06 → 1.0, 1.6초). 장이 바뀌면 SeasonWindow가 새 인스턴스를
/// 만들어 드리프트가 처음부터 다시 돈다(크로스페이드와 겹쳐 「사진이 숨 쉬는」 전환). Reduce Motion = 정지.
private struct SeasonPhotoDrift: View {
    let assetName: String
    let reduceMotion: Bool
    @State private var settled = false

    var body: some View {
        Image(assetName)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .colorEffect(ShaderLibrary.filmGrain(.float(0.09)))   // 0.16 → 0.09(94차-2 찰칵: 프로토보다 훨씬 거칠었다)
            .scaleEffect(settled || reduceMotion ? 1.0 : 1.06)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.6)) { settled = true }
            }
    }
}
