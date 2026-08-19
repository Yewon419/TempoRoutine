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

    private var bySignal: [PhaseSignalSummary] { summaries.filter { $0.signal == signal } }
    private var narratable: Bool { RhythmEngine.narratable(summaries, signal: signal) }
    private var totalCount: Int { bySignal.reduce(0) { $0 + $1.sampleCount } }

    // ── 신호별 어휘 (에너지 높게/낮게 · 기분 밝게/잔잔하게 · 수면·식욕은 체크인 칩 어휘) ──
    /// 이름표(카드 제목) — 세로 나열 재편(2026-08-09)으로 패널이 자기 신호명을 단다.
    var titleName: String {
        switch signal {
        case .energy: "에너지"
        case .mood: "기분"
        case .sleep: "수면"
        case .appetite: "식욕"
        }
    }

    private var signalName: String {
        switch signal {
        case .energy: "에너지"
        case .mood: "기분"
        case .sleep: "잠"
        case .appetite: "식욕"
        }
    }

    /// 주어 형태 — 받침 유무로 조사가 갈려("에너지는"/"잠은") 이름과 따로 둔다.
    private var subject: String {
        switch signal {
        case .energy: "에너지는"
        case .mood: "기분은"
        case .sleep: "잠은"
        case .appetite: "식욕은"
        }
    }

    private var highWord: String {
        switch signal {
        case .energy: "가장 높고"
        case .mood: "가장 밝고"
        case .sleep: "가장 포근하고"
        case .appetite: "가장 좋고"
        }
    }

    private var lowWord: String {
        switch signal {
        case .energy: "가장 낮게"
        case .mood: "가장 잔잔하게"
        case .sleep: "가장 뒤척인 걸로"
        case .appetite: "가장 떨어진 걸로"
        }
    }

    private var statHighLabel: String {
        switch signal {
        case .energy: "가장 높게"
        case .mood: "가장 밝게"
        case .sleep: "가장 포근하게"
        case .appetite: "가장 좋게"
        }
    }

    private var statLowLabel: String {
        switch signal {
        case .energy: "가장 낮게"
        case .mood: "가장 잔잔하게"
        case .sleep: "가장 뒤척임"
        case .appetite: "가장 떨어짐"
        }
    }

    private var consistencyWord: String {
        switch signal {
        case .energy: "가장 높게"
        case .mood: "가장 밝게"
        case .sleep: "가장 포근하게"
        case .appetite: "가장 좋게"
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
            return "\(signalName) 패턴은 아직 또렷하지 않아요. 기록이 더 쌓이면 여기에 담아둘게요."
        }
        let lead = completedCycles >= 1 ? "지난 \(completedCycles)주기," : "지난 기록상,"
        return "\(lead) \(subject) \(seasonMeta(for: high.phase).name)에 \(highWord) \(seasonMeta(for: low.phase).name)에 \(lowWord) 기록됐어요."
    }

    // ── ⑤ 일관성 서술 (시안 v69 — 반복성이 핵심 가치) ──
    private var consistencyLine: String? {
        guard narratable else {
            return "기록이 12회쯤 쌓이면 계절별 패턴을 여기 담아둘게요."
        }
        guard topPhases.count >= 2 else { return nil }
        // 최근 주기부터 같은 계절이 이어진 길이
        var run = 1
        let reversed = Array(topPhases.reversed())
        while run < reversed.count && reversed[run] == reversed[0] { run += 1 }
        if run >= 2 {
            return "\(run)주기 연속, \(seasonMeta(for: reversed[0]).name)이 \(consistencyWord) 기록됐어요."
        }
        // 연속이 아니면 분포 서술("2주기는 여름이, 1주기는 봄이 …")
        var counts: [CyclePhase: Int] = [:]
        for phase in topPhases { counts[phase, default: 0] += 1 }
        let parts = counts.sorted { $0.value > $1.value }
            .map { "\($0.value)주기는 \(seasonMeta(for: $0.key).name)이" }
        return "\(parts.joined(separator: ", ")) \(consistencyWord) 기록됐어요."
    }

    // ── ⑥ 근거 각주 ──
    private var footnote: String {
        guard narratable else {
            return "\(signalName) 기록 \(totalCount)회 · 패턴을 말하기엔 아직 일러요"
        }
        let cyclesPart = completedCycles >= 1 ? "지난 \(completedCycles)주기 · " : ""
        return "\(cyclesPart)\(signalName) 기록 \(totalCount)회 · 기록상 패턴이에요"
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
                Text(value.map(String.init) ?? "—")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(ringValueInk(hasValue: value != nil))
            }
            .frame(width: 54, height: 54)
            HStack(spacing: 3) {
                SeasonGlyph(phase: phase)
                Text(meta.name)
                    .font(.almanacBody(.caption, size: 12, weight: isNow ? .bold : .regular))
                    .foregroundStyle(meta.color)
            }
            // 「지금」 = 색이 아니라 텍스트 태그(시안 v69 — 색맹 담보)
            Text("지금")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Ink.text.opacity(0.55))
                .opacity(isNow ? 1 : 0)
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

    /// 링 중앙 숫자 잉크 — 레코드판은 어두운 원판 위라 흰 계열로 뒤집는다
    private func ringValueInk(hasValue: Bool) -> Color {
        if case .vinyl = ThemeStore.chrome.signalRing {
            return Color.white.opacity(hasValue ? 0.9 : 0.5)
        }
        return Ink.text.opacity(hasValue ? 0.7 : 0.35)
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
