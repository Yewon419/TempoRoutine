// 템포루틴 — 미학 패스 1차 (Phase 0 ⑧-b, MASTER §4)
// 책력 표제 서체 = Gowun Batang(OFL, 번들·런타임 등록 — 실패 시 시스템 세리프 폴백)
// 계절광 = 시안 3겹 radial(§4 계절광 4세트, 다크는 감쇠)

import SwiftUI
import CoreText
import TempoCore
import UIKit

/// 확정 햅틱(§4 토큰: 확정 = medium) — 시트 저장처럼 **뷰가 곧바로 사라지는 지점용**.
/// `.sensoryFeedback`은 상태 변화 관측 기반이라 dismiss와 같은 틱이면 씹힐 수 있다(2026-08-09).
/// 화면에 남는 뷰의 햅틱은 종전대로 `.sensoryFeedback` 토큰을 쓴다.
@MainActor
func confirmHaptic() {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
}

enum AlmanacFont {
    /// 런타임 등록(UIAppFonts 없이) — 한 번만 시도
    static let available: Bool = {
        ["GowunBatang-Regular", "GowunBatang-Bold"].allSatisfy { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { return false }
            return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
}

/// 활판 서체(시안 §2.3-2) — Bodoni Moda(라틴 숫자) + Noto Serif KR(한글), 둘 다 OFL variable ttf.
/// variable 등록 시 named instance가 별도 PostScript 이름으로 노출되는 것에 기댄다
/// (NotoSerifKR-Light 등). ⚠ 실기기에서 이름 매칭이 어긋나면 폴백(시스템 세리프)으로 떨어진다 —
/// 그때는 정적 웨이트 ttf로 교체가 정석이다.
enum LetterpressFont {
    static let available: Bool = {
        ["NotoSerifKR-Variable", "BodoniModa-Variable"].allSatisfy { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { return false }
            return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
}

/// 모던 표제·숫자 서체 — Pretendard(SIL OFL, App/Fonts 번들) 3웨이트 런타임 등록
enum ThemeFont {
    static let available: Bool = {
        ["Pretendard-Regular", "Pretendard-Medium", "Pretendard-SemiBold"].allSatisfy { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "otf") else { return false }
            return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
}

extension Font {
    /// 거대 표제·책력 조판 전용. 본문은 시스템 서체 유지(프로토: 표제=Gowun Batang, 본문=산세리프).
    /// 모던 = Pretendard(표제 600, 시안 §1.3-3 — Gowun 세리프 대체), 등록 실패 시 시스템 폴백
    static func almanac(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch ThemeStore.chrome.typeFace {
        case .notoSerif:
            // 활판 표제(시안 §2.3-12): 한글 = Noto Serif KR 300(200은 음각 선이 계절광에 묻힌다).
            // variable ttf의 named instance로 로드 — 실패 시 시스템 세리프 폴백.
            guard LetterpressFont.available else {
                return .system(size: size, weight: .light, design: .serif)
            }
            return .custom("NotoSerifKR-Light", size: size)
        case .pretendard:
            guard ThemeFont.available else {
                return .system(size: size, weight: weight == .bold ? .semibold : .medium)
            }
            return .custom(weight == .bold ? "Pretendard-SemiBold" : "Pretendard-Medium", size: size)
        case .gowun:
            guard AlmanacFont.available else {
                return .system(size: size, weight: weight, design: .serif)
            }
            return .custom(weight == .bold ? "GowunBatang-Bold" : "GowunBatang-Regular", size: size)
        case .system:
            return .system(size: size, weight: weight)
        }
    }

    /// 본문급 책력 표기 — Dynamic Type을 따라가는 상대 크기(`relativeTo:`).
    /// 시스템 세리프(New York)는 **한글 글리프가 없어** 한글만 고딕으로 폴백된다 — 영문만 세리프로
    /// 렌더돼 한 줄 안에서 결이 어긋난다(2026-08-01 베타 피드백: 계절 라벨·한 줄 일기).
    /// 그래서 한글이 섞이는 세리프 표기는 시스템 대신 번들 서체를 명시한다.
    static func almanacBody(_ style: Font.TextStyle, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch ThemeStore.chrome.typeFace {
        case .notoSerif:
            guard LetterpressFont.available else {
                return .system(style, design: .serif).weight(weight)
            }
            return .custom(weight == .bold ? "NotoSerifKR-Medium" : "NotoSerifKR-Light",
                           size: size, relativeTo: style)
        case .pretendard:
            guard ThemeFont.available else { return .system(style).weight(weight) }
            return .custom(weight == .bold ? "Pretendard-SemiBold" : "Pretendard-Regular",
                           size: size, relativeTo: style)
        case .gowun:
            guard AlmanacFont.available else { return .system(style, design: .serif).weight(weight) }
            return .custom(weight == .bold ? "GowunBatang-Bold" : "GowunBatang-Regular",
                           size: size, relativeTo: style)
        case .system:
            return .system(style).weight(weight)
        }
    }
}

// ── 모던 거대 표제 = 아웃라인 타이포 (시안 §1.3-2, Phase 4 스파이크) ──
// CSS `paint-order: stroke fill` 등가: 결합 글리프 패스에 스트로크(잉크)를 먼저 긋고
// 채움(지면색)을 위에 얹는다 — 획 내부 경계가 가려져 바깥 외곽선만 남는다
// (단순 텍스트 스트로크는 획 겹침으로 시안 단계에서 기각된 이력).
// 실기기 시각 확정 전까지 스파이크 — 실패 시 almanacDisplay의 분기만 걷어내면 솔리드 복귀.
struct OutlineText: View {
    let text: String
    let size: CGFloat
    var stroke: CGFloat = 1.2   // 바깥으로 보이는 두께(중심 스트로크라 2배로 긋는다)

    private struct Metrics {
        let path: Path
        let width: CGFloat
        let ascent: CGFloat
        let descent: CGFloat
    }

    private var metrics: Metrics {
        let ctFont = CTFontCreateWithName("Pretendard-SemiBold" as CFString, size, nil)
        let attributed = NSAttributedString(string: text, attributes: [.font: ctFont])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let combined = CGMutablePath()
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        for run in runs {
            let attrs = CTRunGetAttributes(run) as! [CFString: Any]
            let runFont = attrs[kCTFontAttributeName] as! CTFont
            for i in 0..<CTRunGetGlyphCount(run) {
                var glyph = CGGlyph()
                var position = CGPoint()
                CTRunGetGlyphs(run, CFRange(location: i, length: 1), &glyph)
                CTRunGetPositions(run, CFRange(location: i, length: 1), &position)
                guard let glyphPath = CTFontCreatePathForGlyph(runFont, glyph, nil) else { continue }
                combined.addPath(glyphPath,
                                 transform: CGAffineTransform(translationX: position.x, y: position.y))
            }
        }
        // CoreText 좌표(베이스라인 원점, y 위로) → SwiftUI(좌상단 원점, y 아래로) + 스트로크 여백
        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: stroke, ty: ascent + stroke)
        let flipped = combined.copy(using: &flip) ?? combined
        return Metrics(path: Path(flipped), width: width, ascent: ascent, descent: descent)
    }

    var body: some View {
        let m = metrics
        Canvas { context, _ in
            context.stroke(m.path, with: .color(Ink.text),
                           style: StrokeStyle(lineWidth: stroke * 2, lineJoin: .round))
            context.fill(m.path, with: .color(Ink.paper))
        }
        .frame(width: m.width + stroke * 2, height: m.ascent + m.descent + stroke * 2)
        // 이웃 텍스트와 베이스라인 정렬(표제 HStack들이 .firstTextBaseline 정렬)
        .alignmentGuide(.firstTextBaseline) { _ in m.ascent + stroke }
        .accessibilityLabel(Text(text))
    }
}

/// 거대 표제 공용 진입점 — 모던 = 아웃라인, 그 외(및 폰트 미등록) = 솔리드 almanac
@ViewBuilder
func almanacDisplay(_ text: String, size: CGFloat, color: Color) -> some View {
    if ThemeStore.chrome.debossDisplay {
        // 활판 음각(시안 §2.3-1): 잉크 없는 종이색 활자 + 극세 그림자 2겹.
        // 어두운 선은 상좌(그늘진 벽), 흰 선은 하우(빛 받는 벽) — 원본 실측이 음각이다.
        // 한글은 어두운 광을 .52로 올린다(§2.3-12 — 획이 얇아 .44로는 밝은 구간에 잠긴다).
        Text(text)
            .font(.almanac(size: size, weight: .regular))
            .foregroundStyle(Ink.paper)
            .shadow(color: Color(red: 90 / 255, green: 84 / 255, blue: 72 / 255).opacity(0.52),
                    radius: 0.7, x: -1, y: -1)
            .shadow(color: .white, radius: 0.8, x: 1, y: 1.2)
    } else if ThemeStore.chrome.outlineDisplay, ThemeFont.available {
        OutlineText(text: text, size: size)
    } else {
        Text(text)
            .font(.almanac(size: size, weight: .bold))
            .foregroundStyle(color)
            // 날씨 = 하늘 위 가독 그림자(시안 §5.3-4, 애플 날씨 문법). 다른 테마는 무그림자
            .shadow(color: ThemeStore.chrome.skyGround
                    ? Color(red: 4 / 255, green: 14 / 255, blue: 28 / 255).opacity(0.35) : .clear,
                    radius: 7, y: 1)
    }
}

extension View {
    /// 하늘 지면 위 보조 활자 가독 그림자(2026-08-20 베타 피드백 "가독성 떨어진다" —
    /// 흰 구름 위 흰 날짜·무드라인이 잠긴다). 표제 그림자(almanacDisplay)와 같은 색,
    /// 작은 활자라 반경만 줄임. 다른 테마는 무영향(.clear).
    func skyInkShadow() -> some View {
        shadow(color: ThemeStore.chrome.skyGround
               ? Color(red: 4 / 255, green: 14 / 255, blue: 28 / 255).opacity(0.4) : .clear,
               radius: 4, y: 1)
    }
}

// ── 재질 위계 (§4 보강 I: 크롬 유리 / 밀크 글래스 2단) ──
// 콘텐츠 카드 = 밀크 글래스(반투명 지면 + 은필 실선), 배경 계절광이 비쳐 유리감이 성립.
struct MilkGlass: ViewModifier {
    var radius: CGFloat = 16
    /// 티켓 테마에서 스텁에 세울 «핵심 값 하나»(시각·진행률·일차). nil = 스텁 없는 카드.
    /// 다른 테마에서는 무시된다 — 값을 넘겨도 렌더에 영향이 없다.
    var stub: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if ThemeStore.chrome.ticketChrome, let stub {
            // 발권물(시안 §3.3-②) — 스텁 자리를 본문에서 비우고, 윤곽을 V홈까지 도려낸다.
            // 하단 18pt = 카드 간격을 시안 34로(컨테이너 spacing 16과 합산, 2026-08-14 실측 —
            // 16 간격에서는 위 카드의 아래 V홈과 아래 카드의 위 V홈이 마주 봐 하나로 뭉친다).
            content
                .padding(.trailing, TicketSpec.stubWidth + 8)
                .background(TicketSpec.ticketPaper)
                .overlay(alignment: .trailing) { TicketCardStub(value: stub) }
                .clipShape(TicketCardShape())
                .padding(.bottom, 18)
        } else if ThemeStore.chrome.ticketChrome {
            // 스텁 없는 카드도 발권 지면(시안 .card 기본 — radius 4·그림자·유리 재질 없음).
            // 종전엔 둥근 유리 카드가 발권물과 섞여 지면이 두 문법으로 갈렸다(2026-08-17 피드백).
            content.background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(TicketSpec.ticketPaper)
                    .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
            }
        } else if ThemeStore.chrome.liquidGlassCards {
            // 플레이리스트(시안 §4.4 ⑥) — iOS 26 시스템 리퀴드 글래스. 시안의 커스텀 공식
            // (사선 그라데이션 + 4방 림 스펙큘러)은 이 재질의 근사였다 — 본물을 쓴다.
            // 라운드는 시안 20(기본 16만 승격, 명시 radius는 존중).
            // 틴트 = 흰 20%(시안 --glass 그라데이션 10~30%의 평균). 종전 55%는 다크
            // colorScheme발 검정 폴백 시절 응급값 — 근본 수정(forcesLightAppearance,
            // 2026-08-19) 후 "틴트가 세서 유리가 아니라 면으로 보인다" 베타 피드백로 복귀.
            // 0으로 다 걷지 않는 이유 = 시안도 흰 기운을 남긴다("흰 계열" §4.4 ⑥).
            // .clear 변형(2026-08-20) — .regular는 무틴트여도 재질 자체가 뿌옇다(베타 피드백
            // "여전히 안투명", 틴트 0.2로도 재현). .clear가 미디어 지면용 고투명 유리.
            content.glassEffect(.clear,
                                in: RoundedRectangle(cornerRadius: radius == 16 ? 20 : radius))
        } else if ThemeStore.chrome.engravedCards {
            // 활판(시안 §2.3-7-1) — 배경 없음. **눌린 것은 카드가 아니라 선 하나**다:
            // 어두운 윤곽선 위에 흰 윤곽선을 (1, 1.2) 어긋나게 얹는다(표제 음각과 같은 기법).
            // ⚠ inset 그림자 방식은 기각 이력 — 면 전체가 눌린 것처럼 보인다(§2.6).
            content.background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(Color.white, lineWidth: 1)
                        .offset(x: 1, y: 1.2)
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(Color(red: 90 / 255, green: 84 / 255, blue: 72 / 255).opacity(0.34),
                                lineWidth: 1)
                }
            }
        } else {
            content.background { surface }
        }
    }

    private var surface: some View {
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

extension View {
    /// 콘텐츠 표면 — 카드류 전부 이 재질(§4 보강 I).
    /// `stub`을 주면 티켓 테마에서만 발권물 문법(우측 스텁·V홈)으로 갈아탄다(시안 §3.3-②).
    func milkGlass(radius: CGFloat = 16, stub: String? = nil) -> some View {
        modifier(MilkGlass(radius: radius, stub: stub))
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
            // 모던이 시스템을 따라가면서(2026-08-12) 도트도 지면 대비로 뒤집어야 한다 —
            // 흰 도트는 밝은 지면에서 안 보인다.
            let dot = Color(uiColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 233 / 255, green: 231 / 255, blue: 240 / 255, alpha: 0.05)
                    : UIColor(red: 16 / 255, green: 16 / 255, blue: 20 / 255, alpha: 0.06)
            })
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
extension CyclePhase {
    /// 계절 **표시** 순서 = 봄→여름→가을→겨울 (베타 피드백 2026-07-29 사용자 지시,
    /// "모든 탭에서"). 데이터·엔진 순서(월경기=겨울이 주기 시작)와는 별개 — 나열 UI 전용.
    /// 온보딩은 예외: 기준일=겨울 시작 서사에 묶여 있어 겨울 선두 유지.
    static let displayOrder: [CyclePhase] = [.follicular, .ovulation, .luteal, .menstrual]
}

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
        if ThemeStore.chrome.saturatedSeasonLight {
            // 플레이리스트(시안 §4.4 ⑨) — 커버 계절을 잇는 진한 파스텔. 다른 테마보다
            // 진하게(α .68까지) 잡는다: 글래스는 뒤로 색이 지나갈 때만 유리로 읽힌다.
            return switch phase {
            case .follicular:
                (Color(red: 232 / 255, green: 168 / 255, blue: 184 / 255).opacity(0.68),
                 Color(red: 186 / 255, green: 218 / 255, blue: 178 / 255).opacity(0.50),
                 Color(red: 236 / 255, green: 198 / 255, blue: 208 / 255).opacity(0.52))
            case .ovulation:
                (Color(red: 126 / 255, green: 190 / 255, blue: 224 / 255).opacity(0.68),
                 Color(red: 158 / 255, green: 214 / 255, blue: 212 / 255).opacity(0.50),
                 Color(red: 146 / 255, green: 198 / 255, blue: 228 / 255).opacity(0.52))
            case .luteal:
                (Color(red: 216 / 255, green: 158 / 255, blue: 100 / 255).opacity(0.68),
                 Color(red: 198 / 255, green: 170 / 255, blue: 134 / 255).opacity(0.48),
                 Color(red: 222 / 255, green: 182 / 255, blue: 132 / 255).opacity(0.52))
            default:   // menstrual·콜드 = 겨울(라벤더·블루)
                (Color(red: 170 / 255, green: 186 / 255, blue: 224 / 255).opacity(0.68),
                 Color(red: 198 / 255, green: 208 / 255, blue: 232 / 255).opacity(0.48),
                 Color(red: 184 / 255, green: 198 / 255, blue: 226 / 255).opacity(0.52))
            }
        }
        if ThemeStore.chrome.neutralSeasonLight {
            // 시안 수치(.12/.07/.09)가 실기기 OLED에선 거의 안 보임(베타 피드백 2026-07-29
            // "뒤쪽에 은은한 빛 깔린 것처럼") — 50% 상향. 실기기 재확인 항목.
            // 라이트에선 흰 빛이 안 보인다 — 지면 대비로 뒤집어 어두운 쪽으로(2026-08-12)
            func neutral(_ darkAlpha: Double, _ lightAlpha: Double) -> Color {
                Color(uiColor: UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor(white: 1, alpha: darkAlpha)
                        : UIColor(white: 0, alpha: lightAlpha)
                })
            }
            return (neutral(0.18, 0.05), neutral(0.11, 0.03), neutral(0.13, 0.04))
        }
        return switch phase {
        case .follicular:   // 베이지 전환(2026-08-09 사용자 지시 "노랑이 구려" — 같은 날 파스텔 옐로도 폐기)
            (Color(red: 226 / 255, green: 211 / 255, blue: 186 / 255).opacity(0.55),
             Color(red: 238 / 255, green: 227 / 255, blue: 206 / 255).opacity(0.38),
             Color(red: 219 / 255, green: 203 / 255, blue: 176 / 255).opacity(0.42))
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
            // 계절광을 끄는 테마(기본)는 3겹 radial을 아예 안 그린다 — 지면만 남는다.
            // ⚠ 계절 밴드 색(팔레트 glow*)과는 별개다. 저쪽은 정보 구조라 끄지 않는다.
            if ThemeStore.chrome.showsSeasonLight {
                Rectangle().fill(RadialGradient(colors: [l.a, .clear],
                                                center: UnitPoint(x: 0.18, y: -0.08),
                                                startRadius: 0, endRadius: 430))
                Rectangle().fill(RadialGradient(colors: [l.b, .clear],
                                                center: UnitPoint(x: 0.88, y: 0.22),
                                                startRadius: 0, endRadius: 340))
                Rectangle().fill(RadialGradient(colors: [l.c, .clear],
                                                center: UnitPoint(x: 0.5, y: 1.08),
                                                startRadius: 0, endRadius: 420))
            }
            switch ThemeStore.chrome.texture {
            case .dotGrid: DotGrid()   // 모던 질감 = 도트 그리드(시안 §1.3-1, 은필 선화 대체)
            case .motif:   motifLayer
            case .grain:   grainLayer  // 활판 = 종이 그레인 타일(시안 §2.3-7)
            case .none:    EmptyView()
            }
        }
        // 모던 = 항상 다크 단일 외관(시안 --light-dim 1) — 시스템 다크 감쇠 미적용
        .opacity(ThemeStore.chrome.dimsInDarkMode && colorScheme == .dark ? 0.35 : 1.0)
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
        // 블러 제거(2026-08-16 베타 피드백 "배경 블러 다 제거") — 2026-08-10에 넣었던 1.4pt를 걷는다.
        // ⚠ motifTile의 마스크 블러는 남긴다: 그건 배경 흐림이 아니라 타일 경계 페더링이고,
        //   걷으면 "그림 살짝 잘린다"(2026-08-10 피드백)로 되돌아간다.
        // 0.30 → 0.46 상향(2026-08-09 사용자 "기본 테마에서 그림이 빠졌던데") — 봄 모티프처럼
        // 잉크가 옅은 판이 밝은 계절광(베이지) 위 multiply에서 안 읽히던 것. 코드 회귀 아님.
        .opacity(motif == .onboarding ? 0.14 : 0.46)
        .mask(motifMask)
    }

    /// 활판 종이 그레인(시안 §2.2 --grain) — 120px 노이즈 타일 반복. feTurbulence 근사 에셋.
    private var grainLayer: some View {
        Image("GrainTile")
            .resizable(resizingMode: .tile)
            .accessibilityHidden(true)
    }

    private func motifTile(scale: CGFloat, alignment: Alignment) -> some View {
        GeometryReader { geo in
            // 타일 기준 폭은 아이폰 폭 수준으로 캡핑(2026-07-23) — 아이패드에서 폭 비례로 키우면
            // 타일이 화면보다 훨씬 커져 그림 본체가 밖으로 밀리고 소스 여백만 보인다.
            let base = min(geo.size.width, 430)
            let side = base * scale
            motifImage
                .resizable()
                .frame(width: side, height: side)
                // 타일 이미지 경계 페더링(2026-08-10 베타 피드백 "그림 살짝 잘린다") —
                // 가지가 이미지 가장자리에서 하드 컷되던 것을 사방 ~5% 페이드로 스러지게.
                .mask {
                    Rectangle()
                        .padding(side * 0.05)
                        .blur(radius: side * 0.05)
                }
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
