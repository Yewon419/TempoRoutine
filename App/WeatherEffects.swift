// 템포루틴 — 날씨 이펙트 (시안 §5.3-5·6, Phase ③ 2026-08-19)
// 글로우(맑음 낮·노을) + 뭉게구름 패럴랙스(에셋 2장 — 시안 feDisplacementMap 렌더를
// Playwright로 추출, SwiftUI에 노이즈 필터가 없다 §5.7) + 캔버스 파티클(비 110·눈 90·별 130).
// 파티클은 자작 Canvas + TimelineView(2026-08-19 확정 — Vortex 기각: 의존성·깜깜이 API).
// 개체별 랜덤(속도·크기·위상·흔들림·트윙클)이 핵심 — CSS 타일 기각("너무 일정")의 답.

import SwiftUI

// ── 글로우(시안 §5.3-5) — 태양광(맑음×낮) 우상단 / 노을광(맑음×노을) 지평선 ──
struct WeatherGlow: View {
    let condition: WxCondition
    let daypart: Daypart

    var body: some View {
        GeometryReader { geo in
            if condition == .clear, daypart == .day {
                Rectangle().fill(RadialGradient(
                    stops: [
                        .init(color: Color(red: 1, green: 246 / 255, blue: 216 / 255).opacity(0.85), location: 0),
                        .init(color: Color(red: 1, green: 238 / 255, blue: 190 / 255).opacity(0.22), location: 0.42),
                        .init(color: .clear, location: 0.7),
                    ],
                    center: UnitPoint(x: 0.82, y: 0.04), startRadius: 0, endRadius: 300))
            } else if condition == .clear, daypart == .dusk {
                Rectangle().fill(RadialGradient(
                    stops: [
                        .init(color: Color(red: 1, green: 186 / 255, blue: 120 / 255).opacity(0.55), location: 0),
                        .init(color: Color(red: 1, green: 164 / 255, blue: 96 / 255).opacity(0.18), location: 0.45),
                        .init(color: .clear, location: 0.72),
                    ],
                    center: UnitPoint(x: 0.5, y: 1.02), startRadius: 0, endRadius: 420))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

// ── 캔버스 파티클(시안 §5.3-6) — 비·눈·별(맑음×밤만). 시안 JS 엔진 파라미터 동값 ──
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

private final class WxParticleBank {
    var particles: [WxParticle] = []
    var seeded: WxCondition?
    var lastTime: TimeInterval?

    func seed(_ condition: WxCondition, in size: CGSize) {
        func rand(_ a: CGFloat, _ b: CGFloat) -> CGFloat { .random(in: a...b) }
        let w = size.width, h = size.height
        switch condition {
        case .rain:
            particles = (0..<110).map { _ in
                WxParticle(x: rand(-60, w + 20), y: rand(-h, h), phase: 0,
                           size: rand(10, 22), speed: rand(620, 1080), alpha: rand(0.16, 0.42),
                           drift: rand(60, 115), thickness: rand(0.7, 1.6))
            }
        case .snow:
            particles = (0..<90).map { _ in
                WxParticle(x: rand(0, w), y: rand(-h, h), phase: rand(0, .pi * 2),
                           size: rand(0.9, 2.7), speed: rand(26, 84), alpha: rand(0.4, 0.95),
                           drift: rand(8, 26), thickness: rand(0.4, 1.3))
            }
        default:   // 별(맑음×밤) — 상단 가중 배치
            particles = (0..<130).map { _ in
                WxParticle(x: rand(0, w), y: h * rand(0, 1) * rand(0, 1), phase: rand(0, .pi * 2),
                           size: rand(0.4, 1.3), speed: rand(0.5, 2.2), alpha: rand(0.3, 1),
                           drift: 0, thickness: 0)
            }
        }
        seeded = condition
        lastTime = nil
    }
}

struct WeatherParticles: View {
    let condition: WxCondition
    let daypart: Daypart

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bank = WxParticleBank()

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
            for i in bank.particles.indices {
                var p = bank.particles[i]
                let h = (p.drift * p.drift + p.speed * p.speed).squareRoot()
                let ux = p.drift / h, uy = p.speed / h
                var path = Path()
                path.move(to: CGPoint(x: p.x, y: p.y))
                path.addLine(to: CGPoint(x: p.x + ux * p.size, y: p.y + uy * p.size))
                context.stroke(path, with: .color(.white.opacity(p.alpha * dim)),
                               style: StrokeStyle(lineWidth: p.thickness, lineCap: .round))
                p.x += p.drift * dt
                p.y += p.speed * dt
                if p.y > size.height + p.size {
                    p.y = -p.size - .random(in: 0...90)
                    p.x = .random(in: -60...(size.width + 20))
                }
                bank.particles[i] = p
            }
        case .snow:
            for i in bank.particles.indices {
                var p = bank.particles[i]
                p.phase += p.thickness * dt
                p.y += p.speed * dt
                let x = p.x + sin(p.phase) * p.drift
                let rect = CGRect(x: x - p.size, y: p.y - p.size, width: p.size * 2, height: p.size * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(p.alpha * dim)))
                if p.y > size.height + 4 {
                    p.y = -4 - .random(in: 0...60)
                    p.x = .random(in: 0...size.width)
                }
                bank.particles[i] = p
            }
        default:   // 별 — 개체별 트윙클(일제히 깜빡이지 않는다)
            let t = reduceMotion ? 0 : CGFloat(now)
            for p in bank.particles {
                let a = p.alpha * (0.55 + 0.45 * sin(t * p.speed + p.phase))
                guard a > 0 else { continue }
                let rect = CGRect(x: p.x - p.size, y: p.y - p.size, width: p.size * 2, height: p.size * 2)
                context.fill(Path(ellipseIn: rect),
                             with: .color(Color(red: 240 / 255, green: 246 / 255, blue: 1).opacity(a)))
            }
        }
    }
}
