// 템포루틴 — 나의 리듬 신호 패널 (MASTER §8.2.5 P1 / 시안 v69 6요소, 계약 §5.6.3)
// 6요소: ① 서술(과거형·"기록상") ② 미니차트(계절 막대+글리프+계절 잉크) ③ 「지금」 텍스트 태그
// ④ 하이라이트 스탯 2행 ⑤ 일관성 서술 ⑥ 근거 각주. 계산은 TempoCore(RhythmEngine), 여기는 카피·표시.
// 가드레일(§5.6.3): 전 카피 과거형·"기록상" — 운세·고정관념·미래단정·의료 해석 금지.

import SwiftUI
import TempoCore

// 신호 칩 enum은 2026-08-09 세로 나열 재편으로 폐기 — 「나의 사계」 탭이 신호 패널 전부를
// 스택으로 편다(베타 피드백 "세로로 쭉 펼쳐놓으란 뜻"). 패널이 자기 이름표를 단다.

struct SignalPanel: View {
    let signal: SignalKind
    let summaries: [PhaseSignalSummary]
    let topPhases: [CyclePhase]      // 완료 주기별 argmax(오래된 것부터) — 일관성 서술의 입력
    let completedCycles: Int
    let currentPhase: CyclePhase?
    // ── 일차 곡선 입력(2026-08-30 — 온보딩 인트로 B 곡선의 실데이터판) ──
    let dayCurve: [DayCurvePoint]
    let currentCycleDay: Int?        // 「지금」 헤어라인(범위 밖·nil이면 생략)
    let cycleLength: Int
    let menstrualLength: Int

    /// 곡선 임계 — 표본 있는 일차 3곳부터 표시, 8곳 이하는 점선(저신뢰 표기, 대표님 결정 2026-08-30)
    private static let curveMinDays = 3
    private static let curveDashedMaxDays = 8

    private var bySignal: [PhaseSignalSummary] { summaries.filter { $0.signal == signal } }
    private var narratable: Bool { RhythmEngine.narratable(summaries, signal: signal) }
    private var totalCount: Int { bySignal.reduce(0) { $0 + $1.sampleCount } }

    // ── 신호별 어휘 (에너지 높게/낮게 · 기분 밝게/잔잔하게 · 수면·식욕은 체크인 칩 어휘) ──
    /// 이름표(카드 제목) — 세로 나열 재편(2026-08-09)으로 패널이 자기 신호명을 단다.
    var titleName: String {
        switch signal {
        case .energy: Loc.str("에너지")
        case .mood: Loc.str("기분")
        case .sleep: Loc.str("수면")
        case .appetite: Loc.str("식욕")
        }
    }

    private var signalName: String {
        switch signal {
        case .energy: Loc.str("에너지")
        case .mood: Loc.str("기분")
        case .sleep: Loc.str("잠")
        case .appetite: Loc.str("식욕")
        }
    }

    private var statHighLabel: String {
        switch signal {
        case .energy: Loc.str("가장 높게")
        case .mood: Loc.str("가장 밝게")
        case .sleep: Loc.str("가장 포근하게")
        case .appetite: Loc.str("가장 좋게")
        }
    }

    private var statLowLabel: String {
        switch signal {
        case .energy: Loc.str("가장 낮게")
        case .mood: Loc.str("가장 잔잔하게")
        case .sleep: Loc.str("가장 뒤척임")
        case .appetite: Loc.str("가장 떨어짐")
        }
    }


    // ── 값 스케일: 1...5 평균 → 0~100 정수(시안 표기 — 5점 원값은 각주 몫, 2026-08-05 사용자 결정) ──
    private func scaled(_ mean: Double) -> Int {
        Int(((mean - 1) / 4 * 100).rounded())
    }

    private func summary(for phase: CyclePhase) -> PhaseSignalSummary? {
        bySignal.first { $0.phase == phase }
    }

    private var highest: PhaseSignalSummary? {
        bySignal.filter { $0.sampleCount >= RhythmEngine.minSamples }.max { $0.mean < $1.mean }
    }

    private var lowest: PhaseSignalSummary? {
        bySignal.filter { $0.sampleCount >= RhythmEngine.minSamples }.min { $0.mean < $1.mean }
    }

    // ── ① 서술 ──
    private var narration: String {
        guard narratable, let high = highest, let low = lowest else {
            return Loc.fmt("%1$@ 패턴은 아직 또렷하지 않아요. 기록이 더 쌓이면 여기에 담아둘게요.", "\(signalName)")
        }
        let lead = completedCycles >= 1
            ? Loc.fmt("지난 %lld주기,", completedCycles)
            : Loc.str("지난 기록상,")
        // 신호마다 **문장 하나가 키**다. 조각(주어·형용사)을 이어 붙이면 어순이 다른 언어에서
        // 무너진다 — 한국어에서 조사(는/은) 때문에 쪼개져 있던 것을 문장으로 되돌린 것.
        // 한국어 출력은 종전과 글자 그대로 같다.
        let key: String = switch signal {
        case .energy: "%1$@ 에너지는 %2$@에 가장 높고 %3$@에 가장 낮게 기록됐어요."
        case .mood: "%1$@ 기분은 %2$@에 가장 밝고 %3$@에 가장 잔잔하게 기록됐어요."
        case .sleep: "%1$@ 잠은 %2$@에 가장 포근하고 %3$@에 가장 뒤척인 걸로 기록됐어요."
        case .appetite: "%1$@ 식욕은 %2$@에 가장 좋고 %3$@에 가장 떨어진 걸로 기록됐어요."
        }
        return Loc.fmt(key, lead,
                       seasonMeta(for: high.phase).name, seasonMeta(for: low.phase).name)
    }

    // ── ⑤ 일관성 서술 (시안 v69 — 반복성이 핵심 가치) ──
    private var consistencyLine: String? {
        guard narratable else {
            return Loc.str("기록이 12회쯤 쌓이면 계절별 패턴을 여기 담아둘게요.")
        }
        guard topPhases.count >= 2 else { return nil }
        // 최근 주기부터 같은 계절이 이어진 길이
        var run = 1
        let reversed = Array(topPhases.reversed())
        while run < reversed.count && reversed[run] == reversed[0] { run += 1 }
        if run >= 2 {
            let runKey: String = switch signal {
            case .energy: "%1$@주기 연속, %2$@이 가장 높게 기록됐어요."
            case .mood: "%1$@주기 연속, %2$@이 가장 밝게 기록됐어요."
            case .sleep: "%1$@주기 연속, %2$@이 가장 포근하게 기록됐어요."
            case .appetite: "%1$@주기 연속, %2$@이 가장 좋게 기록됐어요."
            }
            return Loc.fmt(runKey, "\(run)", seasonMeta(for: reversed[0]).name)
        }
        // 연속이 아니면 분포 서술("2주기는 여름이, 1주기는 봄이 …")
        var counts: [CyclePhase: Int] = [:]
        for phase in topPhases { counts[phase, default: 0] += 1 }
        let parts = counts.sorted { $0.value > $1.value }
            .map { Loc.fmt("%1$@주기는 %2$@이", "\($0.value)", "\(seasonMeta(for: $0.key).name)") }
        let distKey: String = switch signal {
        case .energy: "%1$@ 가장 높게 기록됐어요."
        case .mood: "%1$@ 가장 밝게 기록됐어요."
        case .sleep: "%1$@ 가장 포근하게 기록됐어요."
        case .appetite: "%1$@ 가장 좋게 기록됐어요."
        }
        return Loc.fmt(distKey, parts.joined(separator: ", "))
    }

    // ── ⑥ 근거 각주 ──
    private var footnote: String {
        guard narratable else {
            return Loc.fmt("%1$@ 기록 %2$lld회 · 패턴을 말하기엔 아직 일러요", signalName, totalCount)
        }
        let cyclesPart = completedCycles >= 1 ? Loc.fmt("지난 %lld주기 · ", completedCycles) : ""
        return Loc.fmt("%1$@%2$@ 기록 %3$@회 · 기록상 패턴이에요", "\(cyclesPart)", "\(signalName)", "\(totalCount)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 이름표 — 세로 나열에서 어느 신호의 패널인지(2026-08-09)
            Text(titleName)
                .font(.almanac(size: 17, weight: .bold))
                .foregroundStyle(Ink.text)
            Text(narration)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)

            if narratable {
                chart
                stats
            }

            // 일차 곡선 — narratable과 별개 게이트(계절 비교는 안 돼도 일차 3곳이면 선은 그린다)
            if dayCurve.count >= Self.curveMinDays {
                curveSection
            }

            if let consistencyLine {
                Text(consistencyLine)
                    .font(.footnote)
                    .foregroundStyle(Ink.text.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(footnote)
                .font(.caption)
                .foregroundStyle(Ink.text.opacity(0.5))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .milkGlass()
    }

    // ── ②③ 미니차트 + 「지금」 마커 ──
    private var chart: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ForEach(CyclePhase.displayOrder, id: \.self) { phase in
                chartColumn(phase: phase)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(narration)
    }

    // 막대 → 원형 링 게이지(2026-08-05 베타 피드백 "원 모양으로 차게" — 배경 원·계절 원 문법과 통일).
    // 종전 캡슐 막대는 열 폭이 넓어 원형 덩어리로 오독됐다(실기기 스크린샷).
    // 트랙·채움은 테마 분기(2026-08-20 시안 — 티켓 절취 천공·활판 음각 홈·플레이리스트 레코드판).
    private func chartColumn(phase: CyclePhase) -> some View {
        let meta = seasonMeta(for: phase)
        let value = summary(for: phase).map { scaled($0.mean) }
        let isNow = phase == currentPhase
        return VStack(spacing: 8) {
            ZStack {
                // 표본 없는 단계 = 트랙만 옅게(§5.6.3 미표시 원칙)
                ringTrack(seasonColor: meta.color)
                if let value {
                    ringFill(color: meta.color, progress: Double(value) / 100)
                }
                // 레코드판은 중앙 숫자 없음(2026-08-20 베타 피드백 — 원판 위 숫자가 은유를 깬다.
                // 시안 §4.4-⑩도 무숫자). 값은 아래 스탯 2행이 담당, VoiceOver는 서술 라벨 담당.
                if ThemeStore.chrome.signalRing != .vinyl {
                    // 현재 계절 = 원 안 숫자를 계절색·볼드로(2026-08-22 베타 — 「지금」 텍스트 태그 대체).
                    // 값 없음(「—」)은 현재 계절이어도 옅게 둔다.
                    Text(value.map(String.init) ?? "—")
                        .font(.caption.weight(isNow && value != nil ? .bold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(isNow && value != nil ? meta.color : Ink.text.opacity(value == nil ? 0.35 : 0.7))
                }
            }
            .frame(width: 54, height: 54)
            HStack(spacing: 3) {
                SeasonGlyph(phase: phase)
                Text(meta.name)
                    .font(.almanacBody(.caption, size: 12, weight: isNow ? .bold : .regular))
                    .foregroundStyle(meta.color)
            }
            // 「지금」 텍스트 태그는 제거(2026-08-22 베타) — 현재 계절은 원 안 숫자 색·볼드 + 계절명 볼드로.
            // (시안 v69의 색맹 담보는 숫자 볼드·계절명 볼드가 이어받는다 — 색만으로 구분하지 않는다)
        }
        .frame(maxWidth: .infinity)
    }

    // ── 링 트랙·채움 테마 분기(시안: 티켓 §3.3-⑧ / 활판 §2.3-14 / 플레이리스트 §4.4-⑩,
    //    치수는 시안 링 지름 38 → 앱 54 비례 환산) ──
    @ViewBuilder
    private func ringTrack(seasonColor: Color) -> some View {
        switch ThemeStore.chrome.signalRing {
        case .plain:
            Circle().stroke(Ink.text.opacity(0.08), lineWidth: 5)
        case .perforated:
            // 절취 천공 24개 균등 배치(round cap 점). 납작 대시는 기각 — 주기가 원주에
            // 정수로 안 떨어져 시작점이 어긋나고 파편이 채움 호와 섞여 보풀로 읽힌다(시안).
            let gap: CGFloat = .pi * 54 / 24 - 0.1
            Circle().stroke(Ink.text.opacity(0.26),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [0.1, gap]))
        case .engraved:
            // 카드 윤곽과 같은 음각 2겹 — 어두운 선 1px + 흰 광 우하 (1, 1.2)(시안 §2.3-14)
            Circle().stroke(Color.flatRGB(0x5A, 0x54, 0x48).opacity(0.34), lineWidth: 1)
                .shadow(color: .white, radius: 0, x: 1, y: 1.2)
        case .vinyl:
            // 레코드판 — 어두운 원판 + 동심 그루브 2줄 + 계절색 스핀들, 진행 링은 바깥 테
            let groove: Color = Color.white.opacity(0.16)
            ZStack {
                Circle().fill(Color.flatRGB(0x24, 0x31, 0x3D)).frame(width: 45, height: 45)
                Circle().stroke(groove, lineWidth: 1.1).frame(width: 35, height: 35)
                Circle().stroke(groove, lineWidth: 1.1).frame(width: 25, height: 25)
                Circle().fill(seasonColor).frame(width: 6, height: 6)
                Circle().stroke(Ink.text.opacity(0.14), lineWidth: 4)
            }
        }
    }

    private func ringFill(color: Color, progress: Double) -> some View {
        // 채움 굵기·끝맺음도 트랙과 짝(활판 = 계절 잉크 헤어라인·butt, 티켓·레코드판 = 실선 4)
        let style: StrokeStyle
        let opacity: Double
        switch ThemeStore.chrome.signalRing {
        case .plain:
            style = StrokeStyle(lineWidth: 5, lineCap: .round)
            opacity = 0.8
        case .perforated:
            style = StrokeStyle(lineWidth: 4, lineCap: .round)
            opacity = 0.9
        case .engraved:
            style = StrokeStyle(lineWidth: 1.5, lineCap: .butt)
            opacity = 0.95
        case .vinyl:
            style = StrokeStyle(lineWidth: 4, lineCap: .round)
            opacity = 0.8
        }
        return Circle()
            .trim(from: 0, to: max(0.02, progress))   // 0이어도 씨앗만큼은 보이게
            .stroke(color.opacity(opacity), style: style)
            .rotationEffect(.degrees(-90))   // 12시부터 차오른다
    }

    // ── 일차 곡선 (2026-08-30 — 주기 일차 축 실데이터 곡선, 온보딩 EnergyWave의 실측판) ──
    // 표본 있는 일차끼리만 직선 연결 + 점 — 없는 일차를 보간해 그리면 없는 데이터를 단정한다.
    // 8곳 이하 = 점선(저신뢰), 9곳부터 실선. 바닥에 계절 밑줄 띠(캘린더 밑줄 문법)와
    // 오늘 일차 헤어라인. 추세 서술 카피는 두지 않는다(§7 — 선은 기록, 해석은 사용자 몫).
    private var curveSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            curveCanvas
                .frame(height: 96)
            HStack {
                Text(Loc.fmt("%lld일차", 1))
                Spacer()
                Text(Loc.fmt("%lld일차", cycleLength))
            }
            .font(.caption2)
            .foregroundStyle(Ink.text.opacity(0.4))
            Text(Loc.str("주기 일차별 평균 · 기록상 패턴이에요"))
                .font(.caption)
                .foregroundStyle(Ink.text.opacity(0.5))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Loc.fmt("%1$@ 주기 일차별 평균 곡선 · 일차 %2$@곳 기록",
                                    "\(titleName)", "\(dayCurve.count)"))
    }

    private var curveCanvas: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let plotBottom = h - 10       // 아래 10pt = 계절 띠 몫
            let inset: CGFloat = 4        // 곡선 상하 숨통
            ZStack(alignment: .topLeading) {
                seasonBand(width: w, y: h - 2)
                nowHairline(width: w, bottom: plotBottom)
                curvePath(width: w, top: inset, bottom: plotBottom - inset)
                curveDots(width: w, top: inset, bottom: plotBottom - inset)
            }
        }
    }

    private func curveX(_ day: Int, width: CGFloat) -> CGFloat {
        (CGFloat(day) - 0.5) / CGFloat(max(cycleLength, 1)) * width
    }

    private func curveY(_ mean: Double, top: CGFloat, bottom: CGFloat) -> CGFloat {
        top + CGFloat((5 - mean) / 4) * (bottom - top)   // 1...5 → bottom...top
    }

    @ViewBuilder
    private func curvePath(width: CGFloat, top: CGFloat, bottom: CGFloat) -> some View {
        let dashed = dayCurve.count <= Self.curveDashedMaxDays
        let style = StrokeStyle(lineWidth: 1.4, lineCap: .round,
                                dash: dashed ? [4, 4] : [])
        Path { p in
            for (i, point) in dayCurve.enumerated() {
                let at = CGPoint(x: curveX(point.day, width: width),
                                 y: curveY(point.mean, top: top, bottom: bottom))
                if i == 0 { p.move(to: at) } else { p.addLine(to: at) }
            }
        }
        .stroke(Ink.text.opacity(0.75), style: style)
    }

    @ViewBuilder
    private func curveDots(width: CGFloat, top: CGFloat, bottom: CGFloat) -> some View {
        let r: CGFloat = 2
        Path { p in
            for point in dayCurve {
                let at = CGPoint(x: curveX(point.day, width: width),
                                 y: curveY(point.mean, top: top, bottom: bottom))
                p.addEllipse(in: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2))
            }
        }
        .fill(Ink.text.opacity(0.85))
    }

    /// 계절 밑줄 띠 — 캘린더의 숫자 아래 직각 밑줄 문법(§8.1)을 x축에 눕힌 것
    @ViewBuilder
    private func seasonBand(width: CGFloat, y: CGFloat) -> some View {
        let spans = CyclePredictor.phaseSpans(cycleLength: cycleLength,
                                              menstrualLength: menstrualLength)
        ForEach(spans, id: \.startDay) { span in
            let x0 = (CGFloat(span.startDay) - 1) / CGFloat(max(cycleLength, 1)) * width
            let bw = CGFloat(span.length) / CGFloat(max(cycleLength, 1)) * width
            Rectangle()
                .fill(seasonMeta(for: span.phase).color.opacity(0.75))
                .frame(width: max(bw - 1, 0), height: 3)
                .position(x: x0 + bw / 2, y: y)
        }
    }

    @ViewBuilder
    private func nowHairline(width: CGFloat, bottom: CGFloat) -> some View {
        if let d = currentCycleDay, (1...cycleLength).contains(d) {
            Rectangle()
                .fill(Ink.text.opacity(0.18))
                .frame(width: 1, height: bottom)
                .position(x: curveX(d, width: width), y: bottom / 2)
        }
    }

    // ── ④ 하이라이트 스탯 2행 ──
    @ViewBuilder
    private var stats: some View {
        if let high = highest, let low = lowest {
            VStack(spacing: 0) {
                statRow(label: statHighLabel, summary: high)
                statRow(label: statLowLabel, summary: low)
            }
        }
    }

    private func statRow(label: String, summary: PhaseSignalSummary) -> some View {
        let meta = seasonMeta(for: summary.phase)
        return HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Ink.text.opacity(0.55))
            Text(meta.name)
                .font(.almanacBody(.subheadline, size: 15, weight: .bold))
                .foregroundStyle(meta.color)
            Spacer()
            Text("\(scaled(summary.mean))")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Ink.text.opacity(0.75))
        }
        .padding(.vertical, 8)
        .almanacRule()
        .accessibilityElement(children: .combine)
    }
}
