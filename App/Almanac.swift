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

/// 계절광 — 시안 .season-light 3겹 radial 이식. 지면(paper) 위에 얹는 상단 빛.
struct SeasonLight: View {
    let phase: CyclePhase?   // nil = 콜드(겨울 광)

    @Environment(\.colorScheme) private var colorScheme

    private var lights: (a: Color, b: Color, c: Color) {
        switch phase {
        case .follicular:
            (Color(red: 216 / 255, green: 196 / 255, blue: 132 / 255).opacity(0.55),
             Color(red: 228 / 255, green: 214 / 255, blue: 164 / 255).opacity(0.38),
             Color(red: 208 / 255, green: 190 / 255, blue: 138 / 255).opacity(0.42))
        case .ovulation:
            (Color(red: 178 / 255, green: 200 / 255, blue: 142 / 255).opacity(0.55),
             Color(red: 200 / 255, green: 214 / 255, blue: 166 / 255).opacity(0.38),
             Color(red: 168 / 255, green: 194 / 255, blue: 140 / 255).opacity(0.42))
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
        }
        .opacity(colorScheme == .dark ? 0.35 : 1.0)   // 다크 = 감쇠(먹지 위 은은한 빛)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
