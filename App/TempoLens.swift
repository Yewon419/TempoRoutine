// 템포루틴 — 온보딩 「템포 렌즈」 부품 (2026-09-07 대표님 컨셉 승인, ui-mockup/onboarding-v2 이식)
// 유리 렌즈 하나가 온보딩 전 단계를 관통한다: 지면을 배율 m으로 재합성해 원으로 자르고(굴절은 Metal
// distortionEffect, LensWarp.metal), 서리 층·림 스펙큘러·안쪽 그림자를 얹는다. 시스템 glassEffect는
// 실기기 2회 기각(Almanac.swift:314) — 자체 공식만 쓴다. 유리는 이 렌즈 하나뿐, 컨트롤은 무광
// (스위치 = MatteToggleStyle, 엄지·원반 = 지면색, 채움 = 먹 번짐).

import SwiftUI
import TempoCore

// ── 렌즈 자리 ──────────────────────────────────────────────
/// 컨테이너(세이프 영역) 비율 좌표. 프로토(402×874) 값을 비율로 옮겼고 지름은 화면 높이에 비례해 줄인다(최대 1).
struct LensSpot: Equatable {
    var diameter: CGFloat
    var cx: CGFloat        // 컬럼 폭 비율(0~1)
    var cy: CGFloat        // 컨테이너 높이 비율
    var magnify: CGFloat
    var trailingDial = false   // 우상단 진행 다이얼 — 컬럼 트레일링 24 안쪽, 상단바 높이 중심

    static let hero = LensSpot(diameter: 250, cx: 0.5, cy: 0.649, magnify: 1.12)
    static let mid = LensSpot(diameter: 176, cx: 0.5, cy: 0.503, magnify: 1.14)
    static let top = LensSpot(diameter: 150, cx: 0.5, cy: 0.362, magnify: 1.12)
    static let dial = LensSpot(diameter: 56, cx: 1, cy: 0, magnify: 1.2, trailingDial: true)

    func resolve(in size: CGSize, column: CGFloat) -> (center: CGPoint, diameter: CGFloat) {
        let x0 = (size.width - column) / 2
        if trailingDial {
            return (CGPoint(x: x0 + column - 24 - 28, y: 8 + 22), diameter)
        }
        let scale = min(1, size.height / 781)   // 프로토 세이프 높이(874 − 59 − 34)
        return (CGPoint(x: x0 + column * cx, y: size.height * cy), diameter * scale)
    }
}

/// 렌즈 안에 보이는 것 — 단계가 고른다. 숫자·호·눈금은 값이 자주 바뀌므로 드로잉 트리거(introKey)에서 뺀다.
struct LensContent: Equatable {
    var ring = false
    var drawsRing = false       // 브랜드 장면 = 원이 그려진다(1.5s, 0.9s 지연)
    var nodes = false           // 4계절 노드(글리프 + 라벨)
    var orbit = false
    var wave = false
    var sketch: CardKind? = nil
    var number: Int? = nil      // 큰 숫자(지속일·주기)
    var arcFraction: Double? = nil   // 겨울 호 = 지속일 / 주기
    var ticks: Int? = nil       // 눈금 수 = 주기
    var progress: Double? = nil      // 진행(0~1)

    var focus: Bool { number != nil || sketch != nil }
    var introKey: String {
        "\(ring)\(drawsRing)\(nodes)\(orbit)\(wave)\(sketch?.rawValue ?? "-")"
    }
}

/// 제네릭 뷰는 static 저장 프로퍼티를 못 가진다 — 렌즈 상수는 여기(2026-09-07 CI 실측).
enum LensSpec {
    static let shade = Color(red: 60 / 255, green: 75 / 255, blue: 90 / 255)
    static let nodePhases: [(phase: CyclePhase, deg: Double)] =
        [(.menstrual, -90), (.follicular, 0), (.ovulation, 90), (.luteal, 180)]
    static let waveNodes: [(phase: CyclePhase, x: CGFloat, y: CGFloat)] =
        [(.menstrual, 30, 158), (.follicular, 72, 81), (.ovulation, 100, 53), (.luteal, 172, 138)]
}

// ── 렌즈 ──────────────────────────────────────────────────
struct TempoLens<Ground: View>: View {
    let center: CGPoint
    let diameter: CGFloat
    let magnify: CGFloat
    let containerSize: CGSize
    let content: LensContent
    let flat: Bool              // 심플 지면 = 평면색, 굴절 없음
    let reduceMotion: Bool
    @ViewBuilder let ground: () -> Ground

    @State private var ringDraw: CGFloat = 0
    @State private var nodesIn = false
    @State private var orbitOn = false
    @State private var orbitAngle: Double = 0
    @State private var waveDraw: CGFloat = 0
    @State private var sketchDraw: CGFloat = 0

    var body: some View {
        ZStack {
            glass
            frostLayer
            overlays
            sheen
            rim
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .shadow(color: LensSpec.shade.opacity(0.18), radius: 20, y: 18)
        .shadow(color: LensSpec.shade.opacity(0.10), radius: 3, y: 2)
        .position(center)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: content.introKey) { await runIntro() }
    }

    // 지면 재합성 — 렌즈 중심을 기준으로 배율 m, 렌즈 프레임 중심으로 옮겨 원으로 자른다
    private var glass: some View {
        let w = max(containerSize.width, 1)
        let h = max(containerSize.height, 1)
        return ZStack {
            if flat {
                Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
            } else {
                ground()
                    .frame(width: w, height: h)
                    .scaleEffect(magnify, anchor: UnitPoint(x: center.x / w, y: center.y / h))
                    .offset(x: w / 2 - center.x, y: h / 2 - center.y)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .distortionEffect(ShaderLibrary.lensWarp(.float2(CGSize(width: diameter, height: diameter)),
                                                  .float(0.10)),
                          maxSampleOffset: CGSize(width: diameter * 0.06, height: diameter * 0.06),
                          isEnabled: !flat && !reduceMotion)
        .saturation(0.75)
        .contrast(1.05)
    }

    /// 서리 층 — 기본 .5, 숫자·선화 단계는 중앙 방사형(.78 → .5)으로 가독을 올린다(2026-09-07 디테일 ③)
    private var frostLayer: some View {
        let base = Color(red: 238 / 255, green: 241 / 255, blue: 242 / 255)
        return ZStack {
            base.opacity(0.5)
            if content.focus {
                RadialGradient(stops: [.init(color: Ink.frost.opacity(0.78), location: 0),
                                       .init(color: Ink.frost.opacity(0.5), location: 0.7),
                                       .init(color: Ink.frost.opacity(0.5), location: 1)],
                               center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: diameter * 0.55)
            }
        }
    }

    private var sheen: some View {
        ZStack {
            Ellipse()
                .fill(RadialGradient(colors: [Color.white.opacity(0.55), .clear],
                                     center: .center, startRadius: 0, endRadius: diameter * 0.3))
                .frame(width: diameter * 0.6, height: diameter * 0.4)
                .position(x: diameter * 0.3, y: diameter * 0.22)
            Ellipse()
                .fill(RadialGradient(colors: [Color(red: 120 / 255, green: 140 / 255, blue: 160 / 255).opacity(0.14), .clear],
                                     center: .center, startRadius: 0, endRadius: diameter * 0.4))
                .frame(width: diameter * 0.8, height: diameter * 0.6)
                .position(x: diameter * 0.7, y: diameter * 0.9)
        }
    }

    /// 림 — 흰 1px 테 + 상좌 안쪽 광(inset 2 3 8 white) + 하우 안쪽 그림자(inset −6 −10 22 shade)
    private var rim: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.55), lineWidth: 6).blur(radius: 6).offset(x: 2, y: 3)
            Circle().stroke(LensSpec.shade.opacity(0.14), lineWidth: 22).blur(radius: 11).offset(x: -6, y: -10)
            Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
        }
    }

    // ── 렌즈 속 그림(설계 공간 200 → 지름 비례) ──
    private var overlays: some View {
        let s = diameter / 200
        return ZStack {
            if content.ring { ringView(s) }
            if let f = content.arcFraction { arcView(s, fraction: f) }
            if let n = content.ticks { TickRing(count: n).stroke(Ink.winter.opacity(0.55), lineWidth: 1.2) }
            if content.nodes { nodesView(s) }
            if content.orbit && !reduceMotion { orbitView(s) }
            if content.wave { waveView(s) }
            if let kind = content.sketch { sketchView(s, kind) }
            if let n = content.number { numberView(s, n) }
            if let p = content.progress { progressView(s, p) }
        }
        .frame(width: diameter, height: diameter)
    }

    private func ringView(_ s: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: content.drawsRing ? ringDraw : 1)
            .stroke(Ink.winter.opacity(0.9), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: 172 * s, height: 172 * s)
    }

    private func arcView(_ s: CGFloat, fraction: Double) -> some View {
        Circle()
            .trim(from: 0, to: fraction)
            .stroke(Ink.winter, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: 172 * s, height: 172 * s)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: fraction)
    }

    private func progressView(_ s: CGFloat, _ p: Double) -> some View {
        Circle()
            .trim(from: 0, to: p)
            .stroke(Ink.text.opacity(0.85), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: 172 * s, height: 172 * s)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.7), value: p)
    }

    private func nodesView(_ s: CGFloat) -> some View {
        ForEach(Array(LensSpec.nodePhases.enumerated()), id: \.offset) { index, node in
            let a = node.deg * .pi / 180
            let meta = seasonMeta(for: node.phase)
            let labelDX: CGFloat = node.deg == 0 ? -24 : node.deg == 180 ? 24 : 0
            let labelDY: CGFloat = node.deg == -90 ? 28 : node.deg == 90 ? -18 : 0
            ZStack {
                Circle().fill(Ink.frost).frame(width: 22 * s, height: 22 * s)
                SeasonGlyph(phase: node.phase, size: 16 * s)
                haloText(meta.name, size: 11, color: meta.color)
                    .offset(x: labelDX * s, y: labelDY * s)
            }
            .opacity(nodesIn ? 1 : 0)
            .offset(x: 86 * s * cos(a), y: 86 * s * sin(a) + (nodesIn ? 0 : 3))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(1.36 + Double(index) * 0.36), value: nodesIn)
        }
    }

    private func orbitView(_ s: CGFloat) -> some View {
        Circle()
            .fill(Ink.winter)
            .frame(width: 5.2 * s, height: 5.2 * s)
            .offset(y: -86 * s)
            .rotationEffect(.degrees(orbitAngle))
            .opacity(orbitOn ? 1 : 0)
            .animation(.easeOut(duration: 0.6), value: orbitOn)
    }

    /// 곡선 장면 — 계절 라벨은 글리프만(2026-09-07 대표님 "글씨 말고 아이콘만")
    private func waveView(_ s: CGFloat) -> some View {
        ZStack {
            LensWaveShape()
                .trim(from: 0, to: waveDraw)
                .stroke(Ink.winter.opacity(0.9), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            ForEach(Array(LensSpec.waveNodes.enumerated()), id: \.offset) { index, node in
                ZStack {
                    Circle().fill(Ink.frost.opacity(0.9)).frame(width: 20 * s, height: 20 * s)
                    SeasonGlyph(phase: node.phase, size: 16 * s)
                }
                .position(x: node.x * s, y: node.y * s)
                .opacity(nodesIn ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(0.5 + Double(index) * 0.3), value: nodesIn)
            }
        }
    }

    private func sketchView(_ s: CGFloat, _ kind: CardKind) -> some View {
        let style = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
        let ink = Ink.text.opacity(0.8)
        return Group {
            switch kind {
            case .schedule: AnchorSketch().trim(from: 0, to: sketchDraw).stroke(ink, style: style)
            case .input: TeacupSketch().trim(from: 0, to: sketchDraw).stroke(ink, style: style)
            case .output: PaperPlaneSketch().trim(from: 0, to: sketchDraw).stroke(ink, style: style)
            }
        }
        .frame(width: 112 * s, height: 96 * s)
    }

    private func numberView(_ s: CGFloat, _ n: Int) -> some View {
        VStack(spacing: 2 * s) {
            haloText("\(n)", size: 40 * s, color: Ink.text, serif: true)
                .contentTransition(.numericText(value: Double(n)))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: n)
            haloText(Loc.str("일"), size: 12 * s, color: Ink.text.opacity(0.6), weight: .medium)
        }
        .offset(y: 4 * s)
    }

    /// 지면색 헤일로 활자 — 프로토 paint-order:stroke 대역(렌즈 속 가독, 2026-09-07 디테일 ③)
    private func haloText(_ text: String, size: CGFloat, color: Color, serif: Bool = false,
                          weight: Font.Weight = .regular) -> some View {
        let font: Font = serif ? .almanac(size: size, weight: .bold) : .almanacBody(.caption2, size: size, weight: weight)
        return Text(text)
            .font(font)
            .foregroundStyle(color)
            .background {
                Text(text).font(font).foregroundStyle(Ink.frost).blur(radius: 2.5)
                    .overlay { Text(text).font(font).foregroundStyle(Ink.frost).blur(radius: 1) }
            }
    }

    private func runIntro() async {
        ringDraw = content.drawsRing ? 0 : 1
        nodesIn = false
        orbitOn = false
        orbitAngle = 0
        waveDraw = 0
        sketchDraw = 0
        if reduceMotion {
            ringDraw = 1; nodesIn = true; waveDraw = 1; sketchDraw = 1
            return
        }
        try? await Task.sleep(nanoseconds: 30_000_000)   // 상태 변화가 관측되도록 한 틱 양보
        guard !Task.isCancelled else { return }
        nodesIn = true
        if content.drawsRing { withAnimation(.easeOut(duration: 1.5).delay(0.9)) { ringDraw = 1 } }
        if content.wave { withAnimation(.easeOut(duration: 1.3).delay(0.35)) { waveDraw = 1 } }
        if content.sketch != nil { withAnimation(.easeOut(duration: 1.1).delay(0.25)) { sketchDraw = 1 } }
        guard content.orbit else { return }
        try? await Task.sleep(nanoseconds: 3_100_000_000)   // 원 완성 뒤 궤도 시작(프로토 3.1s)
        guard !Task.isCancelled else { return }
        orbitOn = true
        withAnimation(.linear(duration: 26).repeatForever(autoreverses: false)) { orbitAngle = 360 }
    }
}

/// 주기 눈금 — 바깥 86에서 안쪽 79(7의 배수 = 74)로. 설계 공간 200 기준을 rect에 비례.
struct TickRing: Shape {
    let count: Int
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard count > 0 else { return p }
        let s = min(rect.width, rect.height) / 200
        let c = CGPoint(x: rect.midX, y: rect.midY)
        for i in 0..<count {
            let a = -CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / CGFloat(count)
            let r1: CGFloat = 86 * s
            let r2: CGFloat = (i % 7 == 0 ? 74 : 79) * s
            p.move(to: CGPoint(x: c.x + r1 * cos(a), y: c.y + r1 * sin(a)))
            p.addLine(to: CGPoint(x: c.x + r2 * cos(a), y: c.y + r2 * sin(a)))
        }
        return p
    }
}

/// 렌즈 속 에너지 곡선 — 프로토 200×200 좌표(M30 140 C 56 140 72 80 100 68 C 128 56 148 110 172 120)
struct LensWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 200
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var p = Path()
        p.move(to: pt(30, 140))
        p.addCurve(to: pt(100, 68), control1: pt(56, 140), control2: pt(72, 80))
        p.addCurve(to: pt(172, 120), control1: pt(128, 56), control2: pt(148, 110))
        return p
    }
}

// ── 유리 시트 (앱 공식: 반투명 흰 그라데이션 + 림 스펙큘러, 블러 없음) ──
struct GlassSheet: ViewModifier {
    let bare: Bool
    func body(content: Content) -> some View {
        content.background {
            if !bare {
                let shape = UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30)
                shape
                    .fill(LinearGradient(colors: [Color.white.opacity(0.62), Color.white.opacity(0.34)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.white.opacity(0.85)).frame(height: 1).padding(.horizontal, 30)
                    }
                    .shadow(color: Color(red: 60 / 255, green: 75 / 255, blue: 90 / 255).opacity(0.08), radius: 15, y: -10)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

// ── 컨트롤 (2026-09-07 컨트롤 언어: 채움 = 먹 번짐, 엄지·원반 = 무광 지면) ──

/// 주 행동 — 먹 캡슐 52. 누르면 흰 먹이 중심에서 번진다(inkBleed).
struct InkCapsuleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Ink.paper)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Ink.text, in: Capsule())
            .overlay {
                Circle()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 20, height: 20)
                    .scaleEffect(configuration.isPressed ? 24 : 0.01)
                    .opacity(configuration.isPressed ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.55), value: configuration.isPressed)
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            .shadow(color: Ink.text.opacity(0.18), radius: 10, y: 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 보조 행동 — 활자 + 은필 손그림 밑줄(누르면 그어진다)
struct GhostUnderlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15))
            .foregroundStyle(Ink.text.opacity(0.7))
            .overlay(alignment: .bottom) {
                HandUnderline()
                    .trim(from: 0, to: configuration.isPressed ? 1 : 0)
                    .stroke(Ink.winter, lineWidth: 1.2)
                    .frame(height: 6)
                    .offset(y: 4)
                    .animation(.easeOut(duration: 0.28), value: configuration.isPressed)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
    }
}

/// 손그림 밑줄 — 프로토 100×6 path
struct HandUnderline: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 100 * rect.width, y: rect.minY + y / 6 * rect.height)
        }
        var p = Path()
        p.move(to: pt(1, 4))
        p.addCurve(to: pt(60, 3), control1: pt(20, 2), control2: pt(40, 5))
        p.addCurve(to: pt(99, 3.5), control1: pt(80, 1), control2: pt(90, 2))
        return p
    }
}

/// 잉크 방울 라디오 — 은필 테, 고르면 먹 방울이 overshoot로 맺힌다
struct InkRadio: View {
    let on: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? Ink.text : Ink.winter.opacity(0.55), lineWidth: 1.2)
            Circle().fill(Ink.text).padding(4).scaleEffect(on ? 1 : 0.01)
        }
        .frame(width: 22, height: 22)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.6), value: on)
        .accessibilityHidden(true)
    }
}

/// 예시 칩 — 은필 윤곽, 담으면 먹 도장(−2.5° 스탬프 스프링). 높이 44(탭 타깃).
struct StampChip: View {
    let label: String
    let on: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: on ? "checkmark" : "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .rotationEffect(.degrees(on ? -12 : 0))
                    .scaleEffect(on ? 1.15 : 1)
                Text(label).font(.system(size: 15))
            }
            .foregroundStyle(on ? Ink.paper : Ink.text)
            .padding(.leading, 14).padding(.trailing, 16)
            .frame(height: 44)
            .background(on ? Ink.text : Color(red: 250 / 255, green: 250 / 255, blue: 248 / 255).opacity(0.6), in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Color.white.opacity(0.12) : Ink.winter.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.62), value: on)
        .accessibilityValue(on ? Loc.str("담김") : "")
    }
}

/// 자(ruler) 입력 — 먹 채움 트랙 + 눈금 + 무광 지면 엄지 44. 값이 렌즈 숫자·호·눈금에 그대로 비친다.
struct RulerSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String
    let onChange: () -> Void

    private var count: Int { range.upperBound - range.lowerBound }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                let usable = max(w - 44, 1)
                let t = CGFloat(value - range.lowerBound) / CGFloat(max(count, 1))
                let x = 22 + usable * t
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.text.opacity(0.18)).frame(height: 2)
                        .padding(.horizontal, 22)
                    Capsule().fill(Ink.text).frame(width: max(0, x - 22), height: 2)
                        .padding(.leading, 22)
                    HStack(spacing: 0) {
                        ForEach(0...count, id: \.self) { i in
                            Rectangle().fill(Ink.text.opacity(0.35))
                                .frame(width: 1, height: i % 5 == 0 ? 16 : 10)
                            if i < count { Spacer(minLength: 0) }
                        }
                    }
                    .padding(.horizontal, 22)
                    .offset(y: -4)
                    Circle()
                        .fill(Ink.frost)
                        .overlay(Circle().strokeBorder(Ink.winter.opacity(0.6), lineWidth: 1.2))
                        .shadow(color: Color(red: 60 / 255, green: 75 / 255, blue: 90 / 255).opacity(0.16), radius: 5, y: 4)
                        .frame(width: 44, height: 44)
                        .offset(x: x - 22)
                        .animation(.easeOut(duration: 0.12), value: value)
                }
                .frame(height: 64)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    let raw = (g.location.x - 22) / usable * CGFloat(count)
                    let next = range.lowerBound + Int((raw).rounded())
                    let clamped = min(range.upperBound, max(range.lowerBound, next))
                    if clamped != value { value = clamped; onChange() }
                })
            }
            .frame(height: 64)
            HStack {
                Text(Loc.fmt("%lld일", range.lowerBound))
                Spacer()
                Text(Loc.fmt("%lld일", range.upperBound))
            }
            .font(.system(size: 12))
            .foregroundStyle(Ink.text.opacity(0.45))
            .padding(.horizontal, 20)
        }
        .accessibilityRepresentation {
            Stepper(value: $value, in: range) { Text("\(value)\(unit)") }
        }
    }
}
