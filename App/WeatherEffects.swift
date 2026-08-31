// 템포루틴 — 날씨 이펙트 (시안 §5.3-5·6·8·9, Phase ③ 2026-08-19 · 증강 이식 2026-08-31)
// 글로우(태양 3층·노을 2층) + 하늘 드레싱(폭풍 덮개·구름 천장·권운·노을 실루엣 띠 —
// 구름 에셋의 노이즈 윤곽을 눌러 재사용, SwiftUI에 노이즈 필터가 없다 §5.7) +
// 뭉게구름 패럴랙스 + 캔버스 파티클(비 원경 232·근경 128 / 눈 원경 66·근경 52 / 별 130 +
// 별똥별). 파티클은 자작 Canvas + TimelineView(Vortex 기각 이력). 비·눈 근경도 카드 뒤 —
// "빗줄기가 앞으로 지나가면 시야 방해"(08-31 대표님). 카드 위 이펙트(맺힘·튀김·눈 쌓임)는
// WeatherCardEffects가 카드 단위로 얹는다.

import SwiftUI

// ── 글로우(시안 §5.3-5, 증강 §5.3-9) — 태양 3층(맑음×낮) / 노을광 2층(맑음×노을) ──
struct WeatherGlow: View {
    let condition: WxCondition
    let daypart: Daypart

    var body: some View {
        GeometryReader { _ in
            if condition == .clear, daypart == .day {
                sun
            } else if condition == .clear, daypart == .dusk {
                duskGlow
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 3층 광원(§5.3-9) — 밝은 코어 + 중간 헤일로 + 넓은 웜 워시.
    /// 단일 radial은 "빛이 있다"였지 "해가 있다"가 아니었다.
    private var sun: some View {
        let center = UnitPoint(x: 0.82, y: 0.05)
        return ZStack {
            Rectangle().fill(RadialGradient(
                stops: [
                    .init(color: Color(red: 1, green: 240 / 255, blue: 198 / 255).opacity(0.3), location: 0),
                    .init(color: Color(red: 1, green: 238 / 255, blue: 190 / 255).opacity(0.12), location: 0.55),
                    .init(color: .clear, location: 0.72),
                ],
                center: center, startRadius: 0, endRadius: 330))
            Rectangle().fill(RadialGradient(
                stops: [
                    .init(color: Color(red: 1, green: 244 / 255, blue: 206 / 255).opacity(0.55), location: 0),
                    .init(color: .clear, location: 0.7),
                ],
                center: center, startRadius: 0, endRadius: 150))
            Rectangle().fill(RadialGradient(
                stops: [
                    .init(color: Color(red: 1, green: 253 / 255, blue: 244 / 255).opacity(0.95), location: 0),
                    .init(color: Color(red: 1, green: 248 / 255, blue: 224 / 255).opacity(0.5), location: 0.58),
                    .init(color: .clear, location: 0.74),
                ],
                center: center, startRadius: 0, endRadius: 52))
        }
    }

    /// 지평선 웜 글로우 2층(§5.3-9 — 상단 잔광 추가)
    private var duskGlow: some View {
        ZStack {
            Rectangle().fill(RadialGradient(
                stops: [
                    .init(color: Color(red: 1, green: 148 / 255, blue: 88 / 255).opacity(0.22), location: 0),
                    .init(color: .clear, location: 0.75),
                ],
                center: UnitPoint(x: 0.5, y: 1.12), startRadius: 0, endRadius: 560))
            Rectangle().fill(RadialGradient(
                stops: [
                    .init(color: Color(red: 1, green: 186 / 255, blue: 120 / 255).opacity(0.6), location: 0),
                    .init(color: Color(red: 1, green: 164 / 255, blue: 96 / 255).opacity(0.2), location: 0.45),
                    .init(color: .clear, location: 0.72),
                ],
                center: UnitPoint(x: 0.5, y: 1.02), startRadius: 0, endRadius: 420))
        }
    }
}

// ── 하늘 드레싱(§5.3-8·9, 2026-08-31 이식) — 폭풍 덮개(비)·구름 천장(흐림·눈)·권운(맑음×낮)·
// 노을 실루엣 띠(맑음×노을). 시안은 radial 덩이 + feTurbulence + blur — SwiftUI엔 노이즈
// 필터가 없어 구름 에셋(노이즈 윤곽 내장)을 스케일·명도로 눌러 같은 물성을 만든다.
struct WeatherDressing: View {
    let condition: WxCondition
    let daypart: Daypart

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 10, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                switch (condition, daypart) {
                case (.rain, _): storm(in: geo.size, t: t)
                case (.cloud, _), (.snow, _): cover(in: geo.size, t: t)
                case (.clear, .day): cirrus(in: geo.size, t: t)
                case (.clear, .dusk): bands(in: geo.size, t: t)
                default: EmptyView()
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 폭풍 덮개(비) — 상단을 무겁게 누르는 어두운 비구름 천장(시안 .wx-storm). 90s 좌우 왕복.
    private func storm(in size: CGSize, t: TimeInterval) -> some View {
        let sway = CGFloat(sin(t / 90 * .pi * 2)) * size.width * 0.03
        let dim: Double = daypart == .night ? 0.35 : daypart == .dusk ? 0.6 : 1
        return ZStack(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 22 / 255, green: 32 / 255, blue: 44 / 255).opacity(0.6), location: 0),
                    .init(color: Color(red: 30 / 255, green: 42 / 255, blue: 54 / 255).opacity(0.28), location: 0.58),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top, endPoint: .bottom)
                .frame(height: size.height * 0.44)
            Image("WeatherCloud1")
                .scaleEffect(2.4)
                .brightness(-0.52).saturation(0.6)
                .position(x: size.width * 0.24 + sway, y: size.height * 0.06)
            Image("WeatherCloud2")
                .scaleEffect(2.2)
                .brightness(-0.48).saturation(0.6)
                .position(x: size.width * 0.74 + sway, y: size.height * 0.11)
        }
        .blur(radius: 9)
        .opacity(dim)
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    /// 구름 천장(흐림·눈) — 폭풍 덮개의 회백 판본(시안 .wx-cover). 하늘 전체를 덮는 층운의
    /// "덮인 기분"(종전엔 뭉게구름 2~3개가 떠 있을 뿐 하늘이 파랬다). 110s 좌우 왕복.
    private func cover(in size: CGSize, t: TimeInterval) -> some View {
        let sway = CGFloat(sin(t / 110 * .pi * 2)) * size.width * 0.03
        let dim: Double = daypart == .night ? 0.16 : daypart == .dusk ? 0.45 : 1
        return ZStack(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 218 / 255, green: 227 / 255, blue: 235 / 255).opacity(0.5), location: 0),
                    .init(color: Color(red: 210 / 255, green: 220 / 255, blue: 229 / 255).opacity(0.22), location: 0.6),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top, endPoint: .bottom)
                .frame(height: size.height * 0.52)
            Image("WeatherCloud1")
                .scaleEffect(2.4)
                .brightness(0.08).saturation(0.5)
                .position(x: size.width * 0.26 + sway, y: size.height * 0.05)
            Image("WeatherCloud2")
                .scaleEffect(2.2)
                .brightness(0.06).saturation(0.5)
                .position(x: size.width * 0.72 + sway, y: size.height * 0.1)
        }
        .blur(radius: 10)
        .opacity(dim)
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    /// 권운(맑음×낮) — 높고 얇은 새털구름 2가닥(시안 .wx-cirrus). 구름 에셋을 납작하게 눌러
    /// 깃털 결로. 매끈 타원 기각 이력(안개로 읽힘) — 노이즈 윤곽이 답이다.
    private func cirrus(in size: CGSize, t: TimeInterval) -> some View {
        ZStack {
            cirrusStrand(in: size, t: t, period: 260, delay: -70, yRatio: 0.11, scale: 1.0, opacity: 0.42)
            cirrusStrand(in: size, t: t, period: 320, delay: -190, yRatio: 0.23, scale: 0.8, opacity: 0.3)
        }
    }

    private func cirrusStrand(in size: CGSize, t: TimeInterval, period: Double, delay: Double,
                              yRatio: CGFloat, scale: CGFloat, opacity: Double) -> some View {
        let progress = ((t - delay) / period).truncatingRemainder(dividingBy: 1)
        return Image("WeatherCloud1")
            .scaleEffect(x: 1.35 * scale, y: 0.32 * scale)
            .blur(radius: 5)
            .opacity(opacity)
            .position(x: -420 + CGFloat(progress) * (size.width + 840), y: size.height * yRatio)
    }

    /// 노을 실루엣 띠(맑음×노을) — 역광으로 검게 눕는 낮은 구름 2줄(시안 .wx-band).
    private func bands(in size: CGSize, t: TimeInterval) -> some View {
        ZStack {
            bandStrip(in: size, t: t, period: 120, delay: 0, yRatio: 0.67, opacity: 0.5)
            bandStrip(in: size, t: t, period: 150, delay: -60, yRatio: 0.76, opacity: 0.36)
        }
    }

    private func bandStrip(in size: CGSize, t: TimeInterval, period: Double, delay: Double,
                           yRatio: CGFloat, opacity: Double) -> some View {
        let sway = CGFloat(sin((t - delay) / period * .pi * 2)) * size.width * 0.025
        return Image("WeatherCloud1")
            .scaleEffect(x: 1.6, y: 0.15)
            .brightness(-0.55).saturation(0.35)
            .blur(radius: 3)
            .opacity(opacity)
            .position(x: size.width * 0.5 + sway, y: size.height * yRatio)
    }
}

// ── 뭉게구름 패럴랙스(시안 §5.3-5) — 3장, 드리프트 110/150/130s, -420→+820pt ──
struct WeatherClouds: View {
    let condition: WxCondition
    let daypart: Daypart

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// (에셋, top 비율, 스케일, 주기 s, 딜레이 s, 조건 감쇠 전 기본 불투명도)
    private static let clouds: [(String, CGFloat, CGFloat, Double, Double, Double)] = [
        ("WeatherCloud1", 0.03, 1.0, 110, -30, 1.0),
        ("WeatherCloud2", 0.15, 0.72, 150, -95, 1.0),
        ("WeatherCloud1", 0.31, 0.85, 130, -60, 0.8),   // c3 = c1 에셋 재사용(시안 필터 동일)
    ]

    var body: some View {
        if condition != .clear {
            TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, cloud in
                        let progress = reduceMotion
                            ? (-cloud.4 / cloud.3).truncatingRemainder(dividingBy: 1)
                            : ((t - cloud.4) / cloud.3).truncatingRemainder(dividingBy: 1)
                        Image(cloud.0)
                            .scaleEffect(cloud.2)
                            .brightness(wet ? -0.18 : 0)
                            .saturation(wet ? 0.85 : 1)
                            .opacity(opacity(base: cloud.5))
                            .position(x: -420 + progress * 1240,
                                      y: geo.size.height * cloud.1 + 75)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// 비·눈 = 구름 2개(c3 제외), 구름 = 3개(시안 §5.3-5)
    private var visible: [(String, CGFloat, CGFloat, Double, Double, Double)] {
        wet ? Array(Self.clouds.prefix(2)) : Self.clouds
    }

    private var wet: Bool { condition == .rain || condition == .snow }

    /// 시간대 감쇠는 CSS 덮어쓰기 규칙 그대로 절대치(밤 .15 / 노을 .42)
    private func opacity(base: Double) -> Double {
        switch daypart {
        case .night: 0.15
        case .dusk: 0.42
        case .day: wet ? 0.62 : base
        }
    }
}

// ── 캔버스 파티클(시안 §5.3-6, 증강 §5.3-8·9) — 비·눈 2층 + 별 + 별똥별 ──
private struct WxParticle {
    var x: CGFloat
    var y: CGFloat
    var phase: CGFloat
    let size: CGFloat      // 비 = 길이, 눈·별 = 반지름
    let speed: CGFloat     // 비·눈 낙하 pt/s, 별 = 트윙클 속도
    let alpha: CGFloat
    let drift: CGFloat     // 비 = 사선 폭, 눈 = 스웨이 진폭
    let thickness: CGFloat // 비 굵기, 눈 스웨이 각속도
}

private struct WxShootingStar {
    var x: CGFloat
    var y: CGFloat
    var ux: CGFloat
    var uy: CGFloat
    var life: CGFloat
}

private final class WxParticleBank {
    var far: [WxParticle] = []    // 원경(비·눈) 또는 별
    var near: [WxParticle] = []   // 근경(비·눈)
    var seeded: WxCondition?
    var lastTime: TimeInterval?
    var shoot: WxShootingStar?
    var shootNext: TimeInterval = 0

    func seed(_ condition: WxCondition, in size: CGSize) {
        func rand(_ a: CGFloat, _ b: CGFloat) -> CGFloat { .random(in: a...b) }
        let w = size.width, h = size.height
        switch condition {
        case .rain:
            // 원경 = 가늘고 느리고 흐림 / 근경 = 길고 빠르고 밝음 — 깊이는 이 대비가 만든다(§5.3-8)
            far = (0..<232).map { _ in
                WxParticle(x: rand(-60, w + 20), y: rand(-h, h), phase: 0,
                           size: rand(8, 15), speed: rand(420, 720), alpha: rand(0.07, 0.18),
                           drift: rand(46, 92), thickness: rand(0.5, 1.0))
            }
            near = (0..<128).map { _ in
                WxParticle(x: rand(-80, w + 30), y: rand(-h, h), phase: 0,
                           size: rand(18, 34), speed: rand(920, 1450), alpha: rand(0.15, 0.30),
                           drift: rand(70, 130), thickness: rand(1.0, 1.8))
            }
        case .snow:
            far = (0..<66).map { _ in
                WxParticle(x: rand(0, w), y: rand(-h, h), phase: rand(0, .pi * 2),
                           size: rand(0.7, 1.6), speed: rand(22, 50), alpha: rand(0.3, 0.6),
                           drift: rand(8, 26), thickness: rand(0.4, 1.3))
            }
            near = (0..<52).map { _ in
                WxParticle(x: rand(0, w), y: rand(-h, h), phase: rand(0, .pi * 2),
                           size: rand(1.8, 3.4), speed: rand(46, 95), alpha: rand(0.5, 0.95),
                           drift: rand(10, 30), thickness: rand(0.5, 1.5))
            }
        default:   // 별(맑음×밤) — 상단 가중 배치
            far = (0..<130).map { _ in
                WxParticle(x: rand(0, w), y: h * rand(0, 1) * rand(0, 1), phase: rand(0, .pi * 2),
                           size: rand(0.4, 1.3), speed: rand(0.5, 2.2), alpha: rand(0.3, 1),
                           drift: 0, thickness: 0)
            }
            near = []
        }
        seeded = condition
        lastTime = nil
        shoot = nil
        shootNext = 0
    }
}

struct WeatherParticles: View {
    let condition: WxCondition
    let daypart: Daypart

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bank = WxParticleBank()

    /// 빗줄기 잉크 — 순백이 아니라 하늘 회색(08-31 교정 "너무 하얗고 세보여")
    private static let rainInk = Color(red: 205 / 255, green: 216 / 255, blue: 226 / 255)

    private var active: Bool {
        condition == .rain || condition == .snow || (condition == .clear && daypart == .night)
    }

    var body: some View {
        if active {
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                Canvas { context, size in
                    draw(in: &context, size: size, now: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, now: TimeInterval) {
        if bank.seeded != condition { bank.seed(condition, in: size) }
        let dt: CGFloat = reduceMotion ? 0
            : CGFloat(min(max(now - (bank.lastTime ?? now), 0), 0.05))
        bank.lastTime = now
        // 밤엔 빛이 없다 — 감쇠(시안 dim)
        let dim: CGFloat = daypart == .night ? 0.62 : daypart == .dusk ? 0.82 : 1
        switch condition {
        case .rain:
            // 돌풍 — 주기 다른 사인 둘의 합을 전 개체 공유(개체 사선 폭은 제각각이라
            // "일제히 흔들리는 막대밭"이 안 된다, §5.3-8)
            let wt: CGFloat = reduceMotion ? 0 : CGFloat(now)
            let wind: CGFloat = 1 + sin(wt * 0.21) * 0.3 + sin(wt * 0.067) * 0.18
            drawRain(in: &context, size: size, layer: &bank.far, dim: dim, wind: wind, dt: dt)
            drawRain(in: &context, size: size, layer: &bank.near, dim: dim, wind: wind, dt: dt)
        case .snow:
            drawSnow(in: &context, size: size, layer: &bank.far, dim: dim, dt: dt)
            drawSnow(in: &context, size: size, layer: &bank.near, dim: dim, dt: dt)
        default:
            drawStars(in: &context, now: now)
            drawShootingStar(in: &context, size: size, now: now, dt: dt)
        }
    }

    /// 빗줄기 한 층 — 꼬리 절반은 흐리게 2획(획 하나짜리 선이 주던 "막대" 인상 제거, §5.3-8)
    private func drawRain(in context: inout GraphicsContext, size: CGSize,
                          layer: inout [WxParticle], dim: CGFloat, wind: CGFloat, dt: CGFloat) {
        for i in layer.indices {
            var p = layer[i]
            let dx = p.drift * wind
            let h = (dx * dx + p.speed * p.speed).squareRoot()
            let ux = dx / h, uy = p.speed / h
            let tail = CGPoint(x: p.x, y: p.y)
            let mid = CGPoint(x: p.x + ux * p.size * 0.45, y: p.y + uy * p.size * 0.45)
            let tip = CGPoint(x: p.x + ux * p.size, y: p.y + uy * p.size)
            var full = Path()
            full.move(to: tail)
            full.addLine(to: tip)
            context.stroke(full, with: .color(Self.rainInk.opacity(p.alpha * 0.4 * dim)),
                           style: StrokeStyle(lineWidth: p.thickness, lineCap: .round))
            var head = Path()
            head.move(to: mid)
            head.addLine(to: tip)
            context.stroke(head, with: .color(Self.rainInk.opacity(p.alpha * dim)),
                           style: StrokeStyle(lineWidth: p.thickness, lineCap: .round))
            p.x += dx * dt
            p.y += p.speed * dt
            if p.y > size.height + p.size {
                p.y = -p.size - .random(in: 0...90)
                p.x = .random(in: -80...(size.width + 30))
            }
            layer[i] = p
        }
    }

    private func drawSnow(in context: inout GraphicsContext, size: CGSize,
                          layer: inout [WxParticle], dim: CGFloat, dt: CGFloat) {
        for i in layer.indices {
            var p = layer[i]
            p.phase += p.thickness * dt
            p.y += p.speed * dt
            let x = p.x + sin(p.phase) * p.drift
            let rect = CGRect(x: x - p.size, y: p.y - p.size, width: p.size * 2, height: p.size * 2)
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(p.alpha * dim)))
            if p.y > size.height + 4 {
                p.y = -4 - .random(in: 0...60)
                p.x = .random(in: 0...size.width)
            }
            layer[i] = p
        }
    }

    /// 별 — 개체별 트윙클(일제히 깜빡이지 않는다)
    private func drawStars(in context: inout GraphicsContext, now: TimeInterval) {
        let t = reduceMotion ? 0 : CGFloat(now)
        for p in bank.far {
            let a = p.alpha * (0.55 + 0.45 * sin(t * p.speed + p.phase))
            guard a > 0 else { continue }
            let rect = CGRect(x: p.x - p.size, y: p.y - p.size, width: p.size * 2, height: p.size * 2)
            context.fill(Path(ellipseIn: rect),
                         with: .color(Color(red: 240 / 255, green: 246 / 255, blue: 1).opacity(a)))
        }
    }

    /// 별똥별(§5.3-9) — 14~34s에 하나, 0.9s 궤적 페이드. reduce motion이면 없음.
    private func drawShootingStar(in context: inout GraphicsContext, size: CGSize,
                                  now: TimeInterval, dt: CGFloat) {
        guard !reduceMotion else { return }
        if bank.shootNext == 0 { bank.shootNext = now + .random(in: 8...20) }
        if bank.shoot == nil, now > bank.shootNext {
            let ux = CGFloat.random(in: 0.55...0.8) * (Bool.random() ? 1 : -1)
            bank.shoot = WxShootingStar(x: .random(in: 40...(size.width - 40)),
                                        y: .random(in: 20...(size.height * 0.28)),
                                        ux: ux, uy: (1 - ux * ux).squareRoot(), life: 0)
        }
        guard var s = bank.shoot else { return }
        s.life += dt
        let d = s.life * 520
        let head = CGPoint(x: s.x + s.ux * d, y: s.y + s.uy * d)
        let tail = CGPoint(x: head.x - s.ux * 90, y: head.y - s.uy * 90)
        let fade = max(0, 1 - s.life / 0.9)
        var path = Path()
        path.move(to: tail)
        path.addLine(to: head)
        let ink = Color(red: 240 / 255, green: 246 / 255, blue: 1)
        context.stroke(path, with: .linearGradient(
            Gradient(colors: [ink.opacity(0), ink.opacity(0.8 * Double(fade))]),
            startPoint: tail, endPoint: head),
            style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        if s.life > 0.9 {
            bank.shoot = nil
            bank.shootNext = now + .random(in: 14...34)
        } else {
            bank.shoot = s
        }
    }
}
