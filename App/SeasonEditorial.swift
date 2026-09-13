// 템포루틴 — 온보딩 사계절 장 편집 조판 「J2」 (2026-09-13 대표님 확정)
// 프로토 ui-mockup/onboarding-v2 ?variant=j 를 옮긴 것. 화면이 세 층으로 읽힌다:
//   좌상단 호수 숫자 「01」 아웃라인 148 + 「/ 04」 → 우중단 계절 글리프 라인 176 → 좌하단 킥커 → 표제 96 → 덱 → 크레딧.
//   오른쪽 가장자리엔 「한 달 안의 사계절」 세로쓰기. 활자는 전부 지면색(흰), 사진 위 먹 그라데이션은 SeasonWindow가 깐다.
// 등장 연출(대표님 "전환 애니메이션도 예쁘게"): 숫자는 왼쪽에서 밀려 들어오고, 글리프는 선이 그려지듯(trim),
//   킥커·표제·덱·크레딧은 70ms 간격으로 올라온다. `revealed`를 바깥(OnboardingFlow)이 장마다 false→true로 튕긴다.
//   Reduce Motion = 전부 페이드만.

import CoreText
import SwiftUI
import TempoCore

/// 문자열의 글리프 외곽선 — 아웃라인 활자(SwiftUI Text는 stroke가 없다). CoreText 글리프 경로를 모아
/// rect의 좌상단에 맞춰 놓는다(경계 상자 기준이라 프레임은 그릇일 뿐).
struct TextOutline: Shape {
    let text: String
    let fontName: String?
    let size: CGFloat

    func path(in rect: CGRect) -> Path {
        let uiFont: UIFont = fontName.flatMap { UIFont(name: $0, size: size) }
            ?? UIFont.systemFont(ofSize: size, weight: .bold)
        let ctFont = CTFontCreateWithName(uiFont.fontName as CFString, size, nil)
        let attributed = NSAttributedString(string: text, attributes: [.font: uiFont])
        let line = CTLineCreateWithAttributedString(attributed)
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return Path() }
        let combined = CGMutablePath()
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for i in 0..<count {
                var transform = CGAffineTransform(translationX: positions[i].x, y: positions[i].y)
                if let glyphPath = CTFontCreatePathForGlyph(ctFont, glyphs[i], &transform) {
                    combined.addPath(glyphPath)
                }
            }
        }
        // CoreText는 y-up — 뒤집은 뒤 경계 상자를 rect 좌상단에 맞춘다
        var flip = CGAffineTransform(scaleX: 1, y: -1)
        guard let flipped = combined.copy(using: &flip) else { return Path() }
        let box = flipped.boundingBoxOfPath
        var move = CGAffineTransform(translationX: rect.minX - box.minX, y: rect.minY - box.minY)
        guard let placed = flipped.copy(using: &move) else { return Path() }
        return Path(placed)
    }
}

struct SeasonEditorial: View {
    let phase: CyclePhase
    let index: Int              // 0~3 → 「01」~「04」
    let title: String           // 계절명
    let kicker: String          // seasonMeta.plain — 「생리 중」
    let deck: String            // 본문 두 줄을 한 문장으로
    let tag: String             // 크레딧 왼쪽 — 「주기의 시작」
    let fine: String?           // 마지막 장(가을)만 — 「처방하지 않는다」 고지(89차 결정 유지)
    let revealed: Bool
    let reduceMotion: Bool

    private static let paper = Ink.frost
    private var folio: String { String(format: "%02d", index + 1) }
    private var serifName: String? { AlmanacFont.available ? "GowunBatang-Bold" : nil }

    var body: some View {
        ZStack(alignment: .topLeading) {
            numeral
            verticalLabel
            glyph
            block
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // ── 등장 ──
    private func rise(_ order: Int) -> Animation? {
        if reduceMotion { return .easeOut(duration: 0.3) }
        return .easeOut(duration: 0.55).delay(0.08 + Double(order) * 0.07)
    }

    private func risen<V: View>(_ view: V, order: Int) -> some View {
        view
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : 14)
            .animation(rise(order), value: revealed)
    }

    // ── 좌상단 호수 숫자 ──
    private var numeral: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextOutline(text: folio, fontName: serifName, size: 148)
                .stroke(Self.paper.opacity(0.62), lineWidth: 1.2)
                .frame(width: 200, height: 150, alignment: .topLeading)
            Text(verbatim: "/ 04")
                .font(LensSpec.serif(14, bold: false))
                .kerning(3)
                .foregroundStyle(Self.paper.opacity(0.7))
                .padding(.leading, 6)
        }
        .padding(.top, 8)
        .padding(.leading, -4)
        .opacity(revealed ? 1 : 0)
        .offset(x: revealed || reduceMotion ? 0 : -18)
        .animation(reduceMotion ? .easeOut(duration: 0.3) : .easeOut(duration: 0.7), value: revealed)
        .accessibilityElement()
        .accessibilityLabel(Loc.fmt("한 달 안의 사계절 %1$lld / 4", index + 1))
    }

    // ── 오른쪽 세로쓰기 ──
    private var verticalLabel: some View {
        VStack(spacing: 7) {
            ForEach(Array(Loc.str("한 달 안의 사계절").enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .font(LensSpec.serif(12, bold: false))
            }
        }
        .foregroundStyle(Self.paper.opacity(0.55))
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 4)
        .opacity(revealed ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.3) : .easeOut(duration: 0.8).delay(0.2), value: revealed)
        .accessibilityHidden(true)   // 숫자 라벨이 같은 정보를 읽는다
    }

    // ── 우중단 글리프 — 선이 그려지듯 ──
    private var glyph: some View {
        SeasonGlyphShape(phase: phase)
            .trim(from: 0, to: revealed || reduceMotion ? 1 : 0)
            .stroke(Self.paper.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(width: 176, height: 176)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 246)
            .padding(.trailing, -4)
            .opacity(revealed ? 1 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.3) : .easeOut(duration: 0.9).delay(0.25), value: revealed)
            .accessibilityHidden(true)
    }

    // ── 좌하단 카피 블록 ──
    private var block: some View {
        VStack(alignment: .leading, spacing: 0) {
            risen(kickerRow, order: 0)
            risen(Text(title)
                    .font(LensSpec.serif(96))
                    .foregroundStyle(Self.paper)
                    .padding(.leading, -5)
                    .padding(.top, 10)
                    .padding(.bottom, 14), order: 1)
            risen(Text(deck)
                    .font(.system(size: 15))
                    .lineSpacing(6)
                    .foregroundStyle(Self.paper.opacity(0.8))
                    .frame(maxWidth: 290, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true), order: 2)
            if let fine {
                risen(Text(fine)
                        .font(.system(size: 10.5))
                        .lineSpacing(3)
                        .foregroundStyle(Self.paper.opacity(0.5))
                        .padding(.top, 10)
                        .fixedSize(horizontal: false, vertical: true), order: 3)
            }
            risen(credit, order: fine == nil ? 3 : 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private var kickerRow: some View {
        HStack(spacing: 8) {
            SeasonGlyph(phase: phase, size: 12, color: seasonMeta(for: phase).color.mix(with: .white, by: 0.55))
            Text(kicker)
                .font(.system(size: 12))
                .kerning(3)
        }
        .foregroundStyle(Self.paper.opacity(0.82))
    }

    private var credit: some View {
        HStack {
            Text(tag)
            Spacer(minLength: 0)
            Text(verbatim: "STILL \(folio)")
        }
        .font(.system(size: 10.5))
        .kerning(1.8)
        .foregroundStyle(Self.paper.opacity(0.58))
        .padding(.top, 10)
        .overlay(alignment: .top) { Rectangle().fill(Self.paper.opacity(0.28)).frame(height: 1) }
        .padding(.top, 20)
    }
}
