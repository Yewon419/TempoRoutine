// 템포루틴 — 나의 리듬 신호 패널 (MASTER §8.2.5 P1 / 시안 v69 6요소, 계약 §5.6.3)
// 6요소: ① 서술(과거형·"기록상") ② 미니차트(계절 막대+글리프+계절 잉크) ③ 「지금」 텍스트 태그
// ④ 하이라이트 스탯 2행 ⑤ 일관성 서술 ⑥ 근거 각주. 계산은 TempoCore(RhythmEngine), 여기는 카피·표시.
// 가드레일(§5.6.3): 전 카피 과거형·"기록상" — 운세·고정관념·미래단정·의료 해석 금지.

import SwiftUI
import TempoCore

/// 스위처 칩 순서 = 시안 v68: [에너지|기분|수면|나의 사계]. 사계는 패널이 아니라 낱장 스왑.
enum RhythmSignalTab: String, CaseIterable, Identifiable {
    case energy, mood, sleep, seasons
    var id: String { rawValue }

    var label: String {
        switch self {
        case .energy: "에너지"
        case .mood: "기분"
        case .sleep: "수면"
        case .seasons: "나의 사계"
        }
    }

    var signal: SignalKind? {
        switch self {
        case .energy: .energy
        case .mood: .mood
        case .sleep: .sleep
        case .seasons: nil
        }
    }
}

struct SignalPanel: View {
    let signal: SignalKind
    let summaries: [PhaseSignalSummary]
    let topPhases: [CyclePhase]      // 완료 주기별 argmax(오래된 것부터) — 일관성 서술의 입력
    let completedCycles: Int
    let currentPhase: CyclePhase?

    private var bySignal: [PhaseSignalSummary] { summaries.filter { $0.signal == signal } }
    private var narratable: Bool { RhythmEngine.narratable(summaries, signal: signal) }
    private var totalCount: Int { bySignal.reduce(0) { $0 + $1.sampleCount } }

    // ── 신호별 어휘 (에너지 높게/낮게 · 기분 밝게/잔잔하게 · 수면은 체크인 칩 어휘) ──
    private var signalName: String {
        switch signal {
        case .energy: "에너지"
        case .mood: "기분"
        case .sleep: "잠"
        }
    }

    /// 주어 형태 — 받침 유무로 조사가 갈려("에너지는"/"잠은") 이름과 따로 둔다.
    private var subject: String {
        switch signal {
        case .energy: "에너지는"
        case .mood: "기분은"
        case .sleep: "잠은"
        }
    }

    private var highWord: String {
        switch signal {
        case .energy: "가장 높고"
        case .mood: "가장 밝고"
        case .sleep: "가장 포근하고"
        }
    }

    private var lowWord: String {
        switch signal {
        case .energy: "가장 낮게"
        case .mood: "가장 잔잔하게"
        case .sleep: "가장 뒤척인 걸로"
        }
    }

    private var statHighLabel: String {
        switch signal {
        case .energy: "가장 높게"
        case .mood: "가장 밝게"
        case .sleep: "가장 포근하게"
        }
    }

    private var statLowLabel: String {
        switch signal {
        case .energy: "가장 낮게"
        case .mood: "가장 잔잔하게"
        case .sleep: "가장 뒤척임"
        }
    }

    private var consistencyWord: String {
        switch signal {
        case .energy: "가장 높게"
        case .mood: "가장 밝게"
        case .sleep: "가장 포근하게"
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

    private func chartColumn(phase: CyclePhase) -> some View {
        let meta = seasonMeta(for: phase)
        let value = summary(for: phase).map { scaled($0.mean) }
        let isNow = phase == currentPhase
        return VStack(spacing: 6) {
            Text(value.map(String.init) ?? "—")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Ink.text.opacity(value == nil ? 0.35 : 0.6))
            ZStack(alignment: .bottom) {
                // 표본 없는 단계 = 미표시(§5.6.3) — 트랙만 옅게 남긴다
                Capsule().fill(Ink.text.opacity(0.06))
                if let value {
                    Capsule().fill(meta.color.opacity(0.75))
                        .frame(height: max(4, 72 * Double(value) / 100))
                }
            }
            .frame(height: 72)
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
