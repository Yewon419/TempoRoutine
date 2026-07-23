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
    @Query(sort: \DailyCheckIn.day, order: .reverse) private var checkIns: [DailyCheckIn]

    private static let allPhases: [CyclePhase] = [.menstrual, .follicular, .ovulation, .luteal]

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: .now) }
    private var snapshot: CycleSnapshot { CycleSnapshot(periodDays: periodDays) }
    private var profile: EnergyProfile { EnergyProfile(checkIns: checkIns, snapshot: snapshot) }
    private var unlockedPhases: [CyclePhase] { Self.allPhases.filter { profile.level(for: $0) != nil } }

    var body: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()
            SeasonLight(phase: snapshot.phase(on: today), motif: .open)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("나의 리듬")
                        .font(.almanac(size: 44, weight: .bold))
                        .foregroundStyle(Ink.text)
                        .padding(.top, 12)
                    coldCard
                    if unlockedPhases.isEmpty {   // 패턴이 하나라도 열리면 일반론 카드는 물러남(2026-07-23)
                        meanwhileCard
                    }
                    seasonsSheet
                    diarySheet
                }
                .padding(20)
                .centeredColumn(720)   // 아이패드 중앙 조판(2026-07-23)
            }
        }
    }

    // ── 콜드스타트 카드 (§8.2.5 개정 2026-07-23 — "약 41일" 폐기) ──
    // 날짜 약속 대신 가까운 마일스톤: 이번 계절 기록 3회(EnergyProfile.minSamples) → 네 계절 채우기.
    private var progressInfo: (progress: Double, title: String, body: String, label: String) {
        if snapshot.isColdStart {
            return (0, "첫 패턴을 기다리는 중", "당신만의 패턴이 보이기 시작할 거예요.",
                    "첫 생리일을 기록하면 시작돼요")
        }
        let goal = EnergyProfile.minSamples
        let curPhase = snapshot.phase(on: today)
        let curName = curPhase.map { seasonMeta(for: $0).name } ?? "이번 계절"
        let curCount = curPhase.map { min(goal, profile.sampleCount(for: $0)) } ?? 0
        let unlocked = unlockedPhases
        if unlocked.isEmpty {
            let body = curCount == 0
                ? "\(curName)의 에너지를 세 번 기록하면, 이 계절의 첫 패턴이 보여요."
                : "\(curName)의 에너지 기록이 \(curCount)번 쌓였어요. 세 번이면 이 계절의 첫 패턴이 보여요."
            return (Double(curCount) / Double(goal), "첫 패턴을 기다리는 중", body,
                    "\(curName) 기록 \(curCount) / \(goal)")
        }
        let names = unlocked.map { seasonMeta(for: $0).name }.joined(separator: "·")
        var body = "\(names)의 패턴이 열렸어요. 네 계절이 모두 채워지면 리듬 전체가 이어져요."
        if let phase = curPhase, profile.level(for: phase) == nil {
            body += " \(curName)은 \(curCount) / \(goal)회째예요."
        }
        return (Double(unlocked.count) / 4.0, "패턴이 보이기 시작했어요", body,
                "네 계절 중 \(unlocked.count)")
    }

    private var coldCard: some View {
        let info = progressInfo
        return VStack(alignment: .leading, spacing: 10) {
            Text(info.title)
                .font(.almanac(size: 17, weight: .bold))
                .foregroundStyle(Ink.text)
            Text(info.body)
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
        .milkGlass()
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
        .milkGlass()
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
            if case .cycleAnchored(let r) = item.schedule {
                map[anchorPhase(r), default: []].append(item.title)
            }
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
        .milkGlass(radius: 18)
    }

    // ── 한 줄 일기 모음 (2026-07-22 사용자 요청 — 오늘 탭 "오늘 한 줄"의 열람 표면) ──
    // 나의 사계 낱장과 별도 카드: 사계는 공유 안전 화면(§3.5.1 메모 렌더 금지)이라 일기는 섞지 않는다.
    private var diaryEntries: [DailyCheckIn] {
        checkIns.filter { !($0.note ?? "").isEmpty }
    }

    private var diarySheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("오늘 한 줄 모음")
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Ink.text.opacity(0.5))
                    .kerning(2)
                Text("한 줄 일기")
                    .font(.almanac(size: 28, weight: .bold))
                    .foregroundStyle(Ink.text)
            }
            if diaryEntries.isEmpty {
                Text("오늘 탭에서 한 줄을 남기면 여기에 모여요.")
                    .font(.subheadline)
                    .foregroundStyle(Ink.text.opacity(0.6))
                    .padding(.vertical, 8)
            } else {
                ForEach(diaryEntries) { entry in
                    diaryRow(entry)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .milkGlass(radius: 18)
    }

    private func diaryRow(_ entry: DailyCheckIn) -> some View {
        let phase = snapshot.phase(on: entry.day)
        let meta = phase.map(seasonMeta(for:))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(entry.day.formatted(.dateTime.month().day().weekday(.abbreviated)))
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(Ink.text.opacity(0.55))
                if let meta {
                    Text(meta.name)
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(meta.color.opacity(0.85))
                }
                Spacer()
            }
            Text(entry.note ?? "")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Ink.text)
        }
        .padding(.vertical, 8)
        .almanacRule()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.day.formatted(.dateTime.month().day())), \(meta?.name ?? ""), \(entry.note ?? "")")
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
        .almanacRule()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(meta.name), \(routines.isEmpty ? "루틴 없음" : routines.joined(separator: ", "))")
    }
}
