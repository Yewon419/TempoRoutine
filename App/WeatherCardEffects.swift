// 템포루틴 — 날씨 카드 이펙트 (시안 §5.3-8·9, 2026-08-31 이식)
// 비 = 카드 유리 물방울 맺힘·흘러내림 + 상단 모서리 착지 튀김(비드 + 반타원 파문) /
// 눈 = 상단 눈 쌓임(프리필 — "갑자기 쌓이면 이상해", 저주파 능선·모서리 테이퍼).
// 시안은 전면 캔버스 한 장이 카드 rect를 실측해 그렸지만, SwiftUI는 카드가 제 이펙트를
// 갖는 쪽이 동형이면서 배선이 없다(§5.3-8 매핑 각주 "카드 배경 modifier로 가도 동형") —
// 좌표가 카드 로컬이라 스크롤 추종이 공짜다. 튀김 발화는 카드별 무작위 주기(실제 낙하
// 판정과 시각적으로 구분 불가 — 근경 비 자체가 카드 뒤라 획-착지 대응이 보이지 않는다).
// 부착 = MilkGlass(skyGround + 비/눈일 때만). 하단바(UIKit)는 제외 — 시안과의 알려진 차이.

import SwiftUI

// ── 상태 은행 — 카드 인스턴스당 하나(@State 참조 유지). 좌표는 캔버스 로컬 ──
private final class WetBank {
    struct Drop {
        var x: CGFloat
        var y: CGFloat
        let r: CGFloat
        let a: CGFloat
        let ph: CGFloat
        let tw: CGFloat
    }
    struct Runner {
        var x: CGFloat
        var y: CGFloat
        var vy: CGFloat
        let r: CGFloat
        let ph: CGFloat
        var trail: [(x: CGFloat, y: CGFloat, t: TimeInterval)] = []
    }
    struct Bead {
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat
        var vy: CGFloat
        let r: CGFloat
        let a: CGFloat
        var life: CGFloat
    }
    struct Ripple {
        let x: CGFloat
        let y: CGFloat
        var life: CGFloat
    }

    var drops: [Drop] = []
    var seededSize: CGSize = .zero
    var runner: Runner?
    var nextRun: TimeInterval = 0
    var beads: [Bead] = []
    var ripples: [Ripple] = []
    var nextSplash: TimeInterval = 0
    var rim: (h: CGFloat, bumps: [CGFloat])?
    var lastTime: TimeInterval?

    func seedIfNeeded(_ size: CGSize) {
        guard size != seededSize, size.width > 40 else { return }
        func rand(_ a: CGFloat, _ b: CGFloat) -> CGFloat { .random(in: a...b) }
        let n = max(24, min(72, Int(size.width * size.height / 2600)))
        drops = (0..<n).map { _ in
            Drop(x: rand(3, size.width - 3), y: rand(3, size.height - 3), r: rand(0.5, 2.4),
                 a: rand(0.25, 0.85), ph: rand(0, .pi * 2), tw: rand(0.04, 0.22))
        }
        // 능선 프로파일 = 저주파 사인 2개 합성 + 미세 노이즈(0.12~1) — 순수 랜덤 고주파는
        // "빛나는 테두리 선"으로 읽힘(시안 기각 이력). 프리필 4.2~5.4pt.
        let count = Int(ceil(size.width / 6)) + 1
        let f1 = rand(1.5, 2.5) * .pi * 2 / CGFloat(count), p1 = rand(0, 9)
        let f2 = rand(4, 7) * .pi * 2 / CGFloat(count), p2 = rand(0, 9)
        let bumps: [CGFloat] = (0..<count).map { k in
            let v = 0.62 + 0.3 * sin(CGFloat(k) * f1 + p1) + 0.18 * sin(CGFloat(k) * f2 + p2)
                + rand(-0.05, 0.05)
            return max(0.12, min(1, v))
        }
        rim = (h: rand(4.2, 5.4), bumps: bumps)
        seededSize = size
        runner = nil
        nextRun = 0
        beads = []
        ripples = []
        nextSplash = 0
    }
}

/// 카드 위 젖음 층 — MilkGlass overlay(비 = 맺힘·튀김 / 눈 = 쌓임). 터치 통과.
struct WeatherCardWetLayer: View {
    let radius: CGFloat
    let condition: WxCondition

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bank = WetBank()

    /// 튀김 비드·눈 능선이 카드 위로 넘치는 몫 — 캔버스를 위로 이만큼 키운다
    private static let headroom: CGFloat = 30

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                Canvas { context, size in
                    draw(in: &context, size: size,
                         now: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height + Self.headroom)
            .offset(y: -Self.headroom)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, now: TimeInterval) {
        // 캔버스 좌표: 카드 상단 = headroom, 카드 rect = (0, headroom, w, h)
        let card = CGSize(width: size.width, height: size.height - Self.headroom)
        bank.seedIfNeeded(card)
        let dt: CGFloat = reduceMotion ? 0
            : CGFloat(min(max(now - (bank.lastTime ?? now), 0), 0.05))
        bank.lastTime = now
        let dim: CGFloat = WxState.daypart == .night ? 0.62 : WxState.daypart == .dusk ? 0.82 : 1
        switch condition {
        case .rain:
            drawDrops(in: &context, card: card, now: now, dt: dt, dim: dim)
            drawSplashes(in: &context, card: card, now: now, dt: dt, dim: dim)
        case .snow:
            drawRim(in: &context, card: card, dt: dt, dim: dim)
        default:
            break
        }
    }

    // ── 맺힘 + 흘러내림(§5.3-8) — 카드 라운드로 클립, 개체별 숨쉬기, 큰 방울만 광점 ──
    private func drawDrops(in context: inout GraphicsContext, card: CGSize,
                           now: TimeInterval, dt: CGFloat, dim: CGFloat) {
        let top = Self.headroom
        var clipped = context
        clipped.clip(to: Path(roundedRect: CGRect(x: 0, y: top, width: card.width, height: card.height),
                              cornerRadius: radius))
        let t: CGFloat = reduceMotion ? 0 : CGFloat(now)
        let ink = Color(red: 235 / 255, green: 243 / 255, blue: 250 / 255)
        for d in bank.drops {
            // .20 = 시안 08-31 교정("좀 더 투명하게") — 맺힘은 있는 듯 없는 듯이 맞다
            let a = d.a * (0.45 + 0.55 * sin(t * d.tw + d.ph)) * 0.20 * dim
            guard a > 0.01 else { continue }
            let rect = CGRect(x: d.x - d.r, y: top + d.y - d.r, width: d.r * 2, height: d.r * 2)
            clipped.fill(Path(ellipseIn: rect), with: .color(ink.opacity(a)))
            if d.r > 1.1 {
                let hi = CGRect(x: d.x - d.r * 0.3 - d.r * 0.3, y: top + d.y - d.r * 0.35 - d.r * 0.3,
                                width: d.r * 0.6, height: d.r * 0.6)
                clipped.fill(Path(ellipseIn: hi), with: .color(.white.opacity(min(a * 1.4, 0.5))))
            }
        }
        guard !reduceMotion else { return }
        // 이따금 한 방울이 무거워져 흘러내린다 — 1.1s 자국, 바닥에서 소멸
        if bank.nextRun == 0 { bank.nextRun = now + .random(in: 2...7) }
        if bank.runner == nil, now > bank.nextRun {
            bank.runner = WetBank.Runner(x: .random(in: card.width * 0.12...card.width * 0.88),
                                         y: .random(in: 2...card.height * 0.3),
                                         vy: .random(in: 14...30), r: .random(in: 1.4...2.2),
                                         ph: .random(in: 0...9))
        }
        if var r = bank.runner {
            r.vy = min(r.vy + 46 * dt, 130)
            r.y += r.vy * dt
            r.x += sin(r.y * 0.12 + r.ph) * 14 * dt
            r.trail.append((r.x, r.y, now))
            while let first = r.trail.first, now - first.t > 1.1 { r.trail.removeFirst() }
            for i in 1..<max(r.trail.count, 1) {
                let p0 = r.trail[i - 1], p1 = r.trail[i]
                let ta = (1 - CGFloat(now - p1.t) / 1.1) * 0.10 * dim
                var seg = Path()
                seg.move(to: CGPoint(x: p0.x, y: top + p0.y))
                seg.addLine(to: CGPoint(x: p1.x, y: top + p1.y))
                clipped.stroke(seg, with: .color(ink.opacity(ta)),
                               style: StrokeStyle(lineWidth: r.r * 0.8, lineCap: .round))
            }
            let head = CGRect(x: r.x - r.r, y: top + r.y - r.r, width: r.r * 2, height: r.r * 2)
            clipped.fill(Path(ellipseIn: head),
                         with: .color(Color(red: 245 / 255, green: 250 / 255, blue: 1).opacity(0.34 * dim)))
            if r.y > card.height + 4 {
                bank.runner = nil
                bank.nextRun = now + .random(in: 3.5...9)
            } else {
                bank.runner = r
            }
        }
    }

    // ── 착지 튀김(§5.3-8) — 비드 2~4알(포물선) + 상단 모서리 반타원 파문. 과하면 소음이라 잘게 ──
    private func drawSplashes(in context: inout GraphicsContext, card: CGSize,
                              now: TimeInterval, dt: CGFloat, dim: CGFloat) {
        guard !reduceMotion else { return }
        let top = Self.headroom
        if bank.nextSplash == 0 { bank.nextSplash = now + .random(in: 0.2...0.8) }
        if now > bank.nextSplash {
            let x = CGFloat.random(in: 8...(card.width - 8))
            for _ in 0..<Int.random(in: 2...4) {
                bank.beads.append(WetBank.Bead(x: x, y: top, vx: .random(in: -90...90),
                                               vy: .random(in: -240 ... -70), r: .random(in: 0.5...1.3),
                                               a: .random(in: 0.3...0.6), life: 0))
            }
            bank.ripples.append(WetBank.Ripple(x: x, y: top, life: 0))
            bank.nextSplash = now + .random(in: 0.25...0.8)
        }
        let ink = Color(red: 205 / 255, green: 216 / 255, blue: 226 / 255)   // 빗줄기와 같은 잉크
        bank.beads = bank.beads.filter { $0.life < 0.5 }
        for i in bank.beads.indices {
            var b = bank.beads[i]
            b.life += dt
            b.vy += 1500 * dt
            b.x += b.vx * dt
            b.y += b.vy * dt
            let rect = CGRect(x: b.x - b.r, y: b.y - b.r, width: b.r * 2, height: b.r * 2)
            context.fill(Path(ellipseIn: rect),
                         with: .color(ink.opacity(b.a * (1 - b.life / 0.5) * dim)))
            bank.beads[i] = b
        }
        bank.ripples = bank.ripples.filter { $0.life < 0.34 }
        for i in bank.ripples.indices {
            bank.ripples[i].life += dt
            let r = bank.ripples[i]
            let k = r.life / 0.34
            let rx = 2 + 9 * k, ry = rx * 0.32
            // 면 위 반타원 — 전체 타원을 위쪽 절반 클립으로 잘라 그린다(시안 ellipse π→2π 동형)
            let ellipse = Path(ellipseIn: CGRect(x: r.x - rx, y: r.y - ry, width: rx * 2, height: ry * 2))
            var upper = context
            upper.clip(to: Path(CGRect(x: r.x - rx - 1, y: r.y - ry - 1, width: rx * 2 + 2, height: ry + 1)))
            upper.stroke(ellipse, with: .color(.white.opacity(0.32 * Double(1 - k) * Double(dim))),
                         style: StrokeStyle(lineWidth: 0.8))
        }
    }

    // ── 눈 쌓임(§5.3-9) — 프리필 둔덕, 능선·바닥 동시 테이퍼 + 라운드 안쪽 8pt 인셋 ──
    private func drawRim(in context: inout GraphicsContext, card: CGSize, dt: CGFloat, dim: CGFloat) {
        guard var rim = bank.rim else { return }
        rim.h = min(rim.h + dt * 0.03, 6.5)   // 내리는 동안 아주 천천히 두꺼워진다
        bank.rim = rim
        let top = Self.headroom
        let glow = max(dim, 0.75)   // 눈은 빛을 되쏘므로 밤에도 덜 죽는다
        var pts: [(x: CGFloat, top: CGFloat, bot: CGFloat)] = []
        for k in 0..<rim.bumps.count {
            let x = min(8 + CGFloat(k) * 6, card.width - 8)
            let edge = min(x - 8, (card.width - 8) - x)
            let taper = min(1, edge / 22)
            pts.append((x, top - rim.h * rim.bumps[k] * taper, top + 2.5 * taper))
        }
        guard pts.count > 2 else { return }
        var path = Path()
        path.move(to: CGPoint(x: pts[0].x, y: pts[0].bot))
        for k in 1..<pts.count {
            let mx = (pts[k - 1].x + pts[k].x) / 2, my = (pts[k - 1].top + pts[k].top) / 2
            path.addQuadCurve(to: CGPoint(x: mx, y: my),
                              control: CGPoint(x: pts[k - 1].x, y: pts[k - 1].top))
        }
        path.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: pts[pts.count - 1].bot))
        for k in stride(from: pts.count - 2, through: 0, by: -1) {
            path.addLine(to: CGPoint(x: pts[k].x, y: pts[k].bot))
        }
        path.closeSubpath()
        context.fill(path, with: .color(
            Color(red: 246 / 255, green: 250 / 255, blue: 253 / 255).opacity(0.92 * glow)))
    }
}
