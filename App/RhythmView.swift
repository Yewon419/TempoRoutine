// 템포루틴 — 나의 리듬 탭 (MASTER §8.2.5 P0 표면: 콜드스타트 + 나의 사계 낱장 기본 노출)
// 신호 패널·집계 서술은 P1 로직(§5.6.3 — P0는 데이터 형태만 락). 카피 = 프로토 v77 전사.
// 나의 사계(§3.5.1 공유 안전 화면): 렌더 금지 = 날짜·주기 시점·체크인·메모·진행도 — 루틴 이름만.

import SwiftUI
import SwiftData
import TempoCore

struct RhythmView: View {
    @Query(sort: \PeriodDay.day) private var periodDays: [PeriodDay]
    @Query(sort: \InputItem.createdAt) private var inputs: [InputItem]
    @Query(sort: \OutputItem.createdAt) private var outputs: [OutputItem]

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: .now) }
    private var snapshot: CycleSnapshot { CycleSnapshot(periodDays: periodDays) }

    var body: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()
            SeasonLight(phase: snapshot.phase(on: today))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("나의 리듬")
                        .font(.almanac(size: 44, weight: .bold))
                        .foregroundStyle(Ink.text)
                        .padding(.top, 12)
                    coldCard
                    meanwhileCard
                    seasonsSheet
                }
                .padding(20)
            }
        }
    }

    // ── 콜드스타트 카드 (§8.2.5 P0) — 목표 = 2주기 완주 근사, 진행은 정보성 ──
    private var progressInfo: (progress: Double, remaining: Int, label: String) {
        guard let first = snapshot.starts.first, let last = snapshot.starts.last else {
            return (0, 0, "첫 생리일을 기록하면 시작돼요")
        }
        let avg = snapshot.averageLength
        let total = avg * 2
        let done = cal.dateComponents([.day], from: first, to: today).day ?? 0
        let progress = min(1.0, Double(done) / Double(total))
        let remaining = max(0, total - done)
        let dayInCycle = (cal.dateComponents([.day], from: last, to: today).day ?? 0) + 1
        return (progress, remaining, "\(snapshot.starts.count)주기차 · \(min(dayInCycle, avg))일째 기록 중")
    }

    private var coldCard: some View {
        let info = progressInfo
        return VStack(alignment: .leading, spacing: 10) {
            Text("첫 패턴을 기다리는 중")
                .font(.almanac(size: 17, weight: .bold))
                .foregroundStyle(Ink.text)
            Text(info.remaining > 0 && !snapshot.isColdStart
                 ? "앞으로 약 \(info.remaining)일이면 당신만의 패턴이 보이기 시작해요."
                 : "당신만의 패턴이 보이기 시작할 거예요.")
                .font(.subheadline)
                .foregroundStyle(Ink.text.opacity(0.75))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.text.opacity(0.08))
                    Capsule().fill(Ink.text.opacity(0.55))
                        .frame(width: max(6, geo.size.width * info.progress))
                }
            }
            .frame(height: 6)
            .accessibilityLabel("패턴 수집 진행")
            .accessibilityValue(info.progress.formatted(.percent.precision(.fractionLength(0))))
            Text(info.label)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Ink.text.opacity(0.5))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var meanwhileCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("그동안은")
                .font(.almanac(size: 17, weight: .bold))
                .foregroundStyle(Ink.text)
            Text("많은 사람이 월경기엔 에너지가 낮아진다고 느껴요. 당신의 리듬은 곧 여기에 쌓입니다.")
                .font(.subheadline)
                .foregroundStyle(Ink.text.opacity(0.75))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    // ── 나의 사계 낱장 (§3.5.1 — 기본 노출, 개방형 4단 책력) ──
    private var routinesBySeason: [CyclePhase: [String]] {
        var map: [CyclePhase: [String]] = [:]
        for item in inputs {
            if case .cycleAnchored(let r) = item.schedule {
                map[anchorPhase(r), default: []].append(item.title)
            }
        }
        for item in outputs {
            map[anchorPhase(item.recurrence), default: []].append(item.title)
        }
        return map
    }

    private func anchorPhase(_ r: CycleRecurrence) -> CyclePhase {
        switch r.anchor {
        case .cycleStart: .menstrual
        case .phase(let p): p
        }
    }

    private var seasonsSheet: some View {
        let routines = routinesBySeason
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("계절별 루틴")
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Ink.text.opacity(0.5))
                    .kerning(2)
                Text("나의 사계")
                    .font(.almanac(size: 28, weight: .bold))
                    .foregroundStyle(Ink.text)
            }
            ForEach([CyclePhase.menstrual, .follicular, .ovulation, .luteal], id: \.self) { phase in
                seasonRow(phase: phase, routines: routines[phase] ?? [])
            }
            Text("템포루틴 · 당신 몸의 템포에 맞게")
                .font(.system(.caption, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.45))
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func seasonRow(phase: CyclePhase, routines: [String]) -> some View {
        let meta = seasonMeta(for: phase)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SeasonGlyph(phase: phase)
                Text(meta.name)
                    .font(.system(.subheadline, design: .serif).weight(.bold))
                    .foregroundStyle(meta.color)
                Spacer()
            }
            if routines.isEmpty {
                // 빈 계절 = 밑줄 괘선(빈 낱장도 캡처물 성립 — §3.5.1)
                Rectangle().fill(Ink.winter.opacity(0.18)).frame(height: 1)
                    .padding(.vertical, 8)
            } else {
                ForEach(routines, id: \.self) { name in
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(Ink.text)
                }
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.winter.opacity(0.14)).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(meta.name), \(routines.isEmpty ? "루틴 없음" : routines.joined(separator: ", "))")
    }
}
