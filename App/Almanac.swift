// 템포루틴 — 미학 패스 1차 (Phase 0 ⑧-b, MASTER §4)
// 책력 표제 서체 = Gowun Batang(OFL, 번들·런타임 등록 — 실패 시 시스템 세리프 폴백)
// 계절광 = 시안 3겹 radial(§4 계절광 4세트, 다크는 감쇠)

import SwiftUI
import CoreText
import TempoCore

enum AlmanacFont {
    /// 런타임 등록(UIAppFonts 없이) — 한 번만 시도
    static let available: Bool = {
        ["GowunBatang-Regular", "GowunBatang-Bold"].allSatisfy { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { return false }
            return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
}

extension Font {
    /// 거대 표제·책력 조판 전용. 본문은 시스템 서체 유지(프로토: 표제=Gowun Batang, 본문=산세리프)
    static func almanac(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard AlmanacFont.available else {
            return .system(size: size, weight: weight, design: .serif)
        }
        return .custom(weight == .bold ? "GowunBatang-Bold" : "GowunBatang-Regular", size: size)
    }
}

// ── 재질 위계 (§4 보강 I: 크롬 유리 / 밀크 글래스 2단) ──
// 콘텐츠 카드 = 밀크 글래스(반투명 지면 + 은필 실선), 배경 계절광이 비쳐 유리감이 성립.
struct MilkGlass: ViewModifier {
    var radius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius).fill(Ink.surface)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: radius)
                            .stroke(Ink.accent.opacity(0.18), lineWidth: 1)   // 구조색 테두리(기본=은필 동값)
                    }
            }
    }
}

extension View {
    /// 콘텐츠 표면 — 카드류 전부 이 재질(§4 보강 I)
    func milkGlass(radius: CGFloat = 16) -> some View {
        modifier(MilkGlass(radius: radius))
    }

    /// 책력 괘선 — 항목 구분(§4 조판). 구조색(기본=은필 동값, 모던=흰색)
    func almanacRule(opacity: Double = 0.14) -> some View {
        overlay(alignment: .bottom) {
            Rectangle().fill(Ink.accent.opacity(opacity)).frame(height: 1)
        }
    }
}

// ── 계절 글리프 4종 (§8.1 SeasonGlyph — 색맹 담보: 색+형태 병행. 프로토 SVG path 이식) ──
struct SeasonGlyphShape: Shape {
    let phase: CyclePhase

    func path(in rect: CGRect) -> Path {
        let s = rect.width / 16
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }
        var path = Path()
        switch phase {
        case .menstrual:      // 겨울 = 눈결정 3획
            path.move(to: p(8, 2)); path.addLine(to: p(8, 14))
            path.move(to: p(2.8, 5)); path.addLine(to: p(13.2, 11))
            path.move(to: p(13.2, 5)); path.addLine(to: p(2.8, 11))
        case .follicular:     // 봄 = 새싹
            path.move(to: p(8, 14)); path.addLine(to: p(8, 6))
            path.move(to: p(8, 8))
            path.addCurve(to: p(4, 4), control1: p(8, 5.4), control2: p(6, 4))
            path.addCurve(to: p(8, 8), control1: p(4, 6.6), control2: p(6, 8))
            path.move(to: p(8, 6.6))
            path.addCurve(to: p(12, 3), control1: p(8, 4.2), control2: p(10, 3))
            path.addCurve(to: p(8, 6.6), control1: p(12, 5.4), control2: p(10, 6.6))
        case .ovulation:      // 여름 = 해
            path.addEllipse(in: CGRect(x: rect.minX + 4.8 * s, y: rect.minY + 4.8 * s,
                                       width: 6.4 * s, height: 6.4 * s))
            path.move(to: p(8, 1.5)); path.addLine(to: p(8, 3.2))
            path.move(to: p(8, 12.8)); path.addLine(to: p(8, 14.5))
            path.move(to: p(1.5, 8)); path.addLine(to: p(3.2, 8))
            path.move(to: p(12.8, 8)); path.addLine(to: p(14.5, 8))
        case .luteal:         // 가을 = 잎
            path.move(to: p(13, 3))
            path.addCurve(to: p(3, 12), control1: p(8, 3), control2: p(4, 6))
            path.addCurve(to: p(13, 3), control1: p(9, 11), control2: p(12, 8))
            path.closeSubpath()
            path.move(to: p(3, 12)); path.addLine(to: p(9, 6))
        }
        return path
    }
}

struct SeasonGlyph: View {
    let phase: CyclePhase
    var size: CGFloat = 13
    var color: Color?

    var body: some View {
        SeasonGlyphShape(phase: phase)
            .stroke(color ?? seasonMeta(for: phase).color,
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)   // 계절명 텍스트가 라벨 담당
    }
}

/// 모던 전용 지면 질감 — 22pt 간격 1pt 도트(시안 §1.3-1, --dot rgba(233,231,240,.05)).
/// 정적 콘텐츠(상태 의존 없음) — 드래그 프레임 재계산 함정과 무관(repo CLAUDE.md).
struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 22
            let dot = Color(red: 233 / 255, green: 231 / 255, blue: 240 / 255).opacity(0.05)
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)),
                                 with: .color(dot))
                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 은필 선화 텍스처 노출 방식(§4 보강 I) — 카드류 뒤=전면, 개방 구간=중단부 마스크(v42), 온보딩=전면 감쇠(v63)
enum MotifStyle: Equatable { case card, open, onboarding }

/// 계절광 — 시안 .season-light 3겹 radial 이식. 지면(paper) 위에 얹는 상단 빛.
struct SeasonLight: View {
    let phase: CyclePhase?   // nil = 콜드(겨울 광)
    var motif: MotifStyle = .card

    @Environment(\.colorScheme) private var colorScheme

    private var lights: (a: Color, b: Color, c: Color) { Self.lightColors(for: phase) }

    /// 계절광 3겹 색 — 캘린더 상단 글로우(2026-07-28 시안 결정)도 같은 원색을 쓴다.
    /// 모던 = 계절 불문 무채 3단(시안 §1.3-5 — 하루 상세 포함, 유채 계절광으로 덮지 않는다)
    static func lightColors(for phase: CyclePhase?) -> (a: Color, b: Color, c: Color) {
        if ThemeStore.current == .modern {
            return (Color.white.opacity(0.12),
                    Color(red: 190 / 255, green: 192 / 255, blue: 198 / 255).opacity(0.07),
                    Color(red: 150 / 255, green: 152 / 255, blue: 158 / 255).opacity(0.09))
        }
        return switch phase {
        case .follicular:
            (Color(red: 216 / 255, green: 196 / 255, blue: 132 / 255).opacity(0.55),
             Color(red: 228 / 255, green: 214 / 255, blue: 164 / 255).opacity(0.38),
             Color(red: 208 / 255, green: 190 / 255, blue: 138 / 255).opacity(0.42))
        case .ovulation:   // 연두 보정(채도↓명도↑, 2026-07-21 사용자 결정)
            (Color(red: 207 / 255, green: 221 / 255, blue: 179 / 255).opacity(0.55),
             Color(red: 231 / 255, green: 237 / 255, blue: 214 / 255).opacity(0.38),
             Color(red: 198 / 255, green: 214 / 255, blue: 172 / 255).opacity(0.42))
        case .luteal:
            (Color(red: 206 / 255, green: 158 / 255, blue: 132 / 255).opacity(0.52),
             Color(red: 219 / 255, green: 184 / 255, blue: 162 / 255).opacity(0.36),
             Color(red: 198 / 255, green: 152 / 255, blue: 128 / 255).opacity(0.40))
        default:   // menstrual·콜드 = 겨울
            (Color(red: 148 / 255, green: 172 / 255, blue: 192 / 255).opacity(0.72),
             Color(red: 185 / 255, green: 199 / 255, blue: 209 / 255).opacity(0.42),
             Color(red: 160 / 255, green: 182 / 255, blue: 199 / 255).opacity(0.52))
        }
    }

    /// 계절 연동 배경 모티프(v30 — 겨울=마른 가지 은필화, 그 외 계절 대응 선화)
    private var motifImage: Image {
        switch phase {
        case .follicular: Image("MotifSpring")
        case .ovulation:  Image("MotifSummer")
        case .luteal:     Image("MotifAutumn")
        default:          Image("MotifWinter")   // menstrual · 콜드(nil) · 온보딩 고정
        }
    }

    var body: some View {
        let l = lights
        ZStack {
            Rectangle().fill(RadialGradient(colors: [l.a, .clear],
                                            center: UnitPoint(x: 0.18, y: -0.08),
                                            startRadius: 0, endRadius: 430))
            Rectangle().fill(RadialGradient(colors: [l.b, .clear],
                                            center: UnitPoint(x: 0.88, y: 0.22),
                                            startRadius: 0, endRadius: 340))
            Rectangle().fill(RadialGradient(colors: [l.c, .clear],
                                            center: UnitPoint(x: 0.5, y: 1.08),
                                            startRadius: 0, endRadius: 420))
            if ThemeStore.current == .modern {
                DotGrid()   // 모던 질감 = 도트 그리드(시안 §1.3-1, 은필 선화 대체)
            } else {
                motifLayer
            }
        }
        // 모던 = 항상 다크 단일 외관(시안 --light-dim 1) — 시스템 다크 감쇠 미적용
        .opacity(ThemeStore.current == .modern ? 1.0 : (colorScheme == .dark ? 0.35 : 1.0))
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 은필 선화 텍스처 — 시안 `.season-light::after` 이식(v30 계절 연동·v42 개방구간 마스크·v63 온보딩 감쇠).
    /// 대비 낮춘 두 겹(상단좌측·하단우측, background-size 175%/240% 근사) + multiply — 피사체 아닌 질감.
    private var motifLayer: some View {
        ZStack {
            motifTile(scale: 1.75, alignment: .topLeading)
            motifTile(scale: 2.40, alignment: .bottomTrailing)
        }
        .compositingGroup()
        .blendMode(.multiply)
        .contrast(motif == .onboarding ? 0.88 : 0.95)
        .opacity(motif == .onboarding ? 0.11 : 0.30)
        .mask(motifMask)
    }

    private func motifTile(scale: CGFloat, alignment: Alignment) -> some View {
        GeometryReader { geo in
            // 타일 기준 폭은 아이폰 폭 수준으로 캡핑(2026-07-23) — 아이패드에서 폭 비례로 키우면
            // 타일이 화면보다 훨씬 커져 그림 본체가 밖으로 밀리고 소스 여백만 보인다.
            let base = min(geo.size.width, 430)
            motifImage
                .resizable()
                .frame(width: base * scale, height: base * scale)
                .frame(width: geo.size.width, height: geo.size.height, alignment: alignment)
                .clipped()
        }
    }

    /// 개방 구간(캘린더·나의 리듬·설정) = 표제·탭바 뒤만 노출, 본문 중단부는 마스크(v42/v63 확장).
    /// 그 외(카드류·온보딩)는 전면 노출 — 온보딩은 opacity 자체가 낮아 별도 마스크 불필요(v63).
    @ViewBuilder
    private var motifMask: some View {
        if motif == .open {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black, location: 0.20),
                    .init(color: .clear, location: 0.30),
                    .init(color: .clear, location: 0.78),
                    .init(color: .black, location: 0.90),
                    .init(color: .black, location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
        } else {
            Rectangle().fill(Color.black)
        }
    }
}
