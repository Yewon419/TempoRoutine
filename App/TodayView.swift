// 템포루틴 — 오늘 화면 (Phase 0 ②: 생리 로깅 + 단계계산, MASTER §5.9-2)
// 상태 규칙 §5.6.2: S0 콜드스타트 / S1 기록 1개(hedge) / S2 안정 / S4 overdue(diff ≥ N+GRACE).
// 카피 가드레일 §3.3: 허락 톤, 과거형·"기록상", 처방·죄책감·임신/질환 추론 금지.

import SwiftUI
import SwiftData
import TempoCore

// ── 디자인 토큰 (ui-mockup DESIGN.md — 계절 잉크·먹색·지면. 정식 미학 패스는 §5.9-8) ──
enum Ink {
    static let winter = Color(red: 0x55 / 255, green: 0x60 / 255, blue: 0x6C / 255)
    static let spring = Color(red: 0x8F / 255, green: 0x7C / 255, blue: 0x2E / 255)
    static let summer = Color(red: 0x6E / 255, green: 0x7C / 255, blue: 0x46 / 255)
    static let autumn = Color(red: 0xA8 / 255, green: 0x4B / 255, blue: 0x38 / 255)
    static let text   = Color(red: 0x2C / 255, green: 0x2B / 255, blue: 0x27 / 255)   // 먹색
    static let paper  = Color(red: 0xF2 / 255, green: 0xF3 / 255, blue: 0xF0 / 255)   // paper-frost
    static let coral  = Color(red: 0xD6 / 255, green: 0x64 / 255, blue: 0x4C / 255)
}

struct SeasonMeta {
    let name: String
    let phaseName: String
    let color: Color
    let moodline: String
}

func seasonMeta(for phase: CyclePhase) -> SeasonMeta {
    switch phase {
    case .menstrual:
        SeasonMeta(name: "겨울", phaseName: "월경기", color: Ink.winter,
                   moodline: "이번 주는 겨울이에요. 쉬어가도 괜찮아요.")
    case .follicular:
        SeasonMeta(name: "봄", phaseName: "난포기", color: Ink.spring,
                   moodline: "봄이에요. 가볍게 시작해보기 좋은 때예요.")
    case .ovulation:
        SeasonMeta(name: "여름", phaseName: "배란기", color: Ink.summer,
                   moodline: "여름이에요. 하고 싶은 만큼 빛나도 좋아요.")
    case .luteal:
        SeasonMeta(name: "가을", phaseName: "황체기", color: Ink.autumn,
                   moodline: "가을이에요. 하나씩 매듭지어도 좋은 때예요.")
    }
}

struct TodayView: View {
    /// §5.6.2 S4 배너 유예 — 예측일 경과 즉시가 아니라 +2일부터.
    static let overdueGraceDays = 2

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PeriodDay.day) private var periodDays: [PeriodDay]
    @State private var showLogSheet = false

    private var today: Date { Calendar.current.startOfDay(for: .now) }
    private var days: [Date] { periodDays.map(\.day) }
    private var starts: [Date] { PeriodMath.episodeStarts(days: days) }
    private var avgLength: Int { CyclePredictor.averageLength(startDates: starts) }

    var body: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if starts.isEmpty {
                        coldStart                                    // S0
                    } else {
                        seasonHeader
                        if overdueDiff >= avgLength + Self.overdueGraceDays {
                            overdueBanner                            // S4
                        }
                        recordSummary
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $showLogSheet) {
            PeriodLogSheet()
        }
    }

    // ── S0 콜드스타트 ──
    private var coldStart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("계절 기록 전")
                .font(.system(size: 44, weight: .bold, design: .serif))
                .foregroundStyle(Ink.text)
            Text("첫 생리일을 기록하면 계절이 시작돼요.")
                .font(.system(.body, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.7))
            Button {
                showLogSheet = true
            } label: {
                Text("첫 생리일 기록")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Ink.paper)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Ink.text, in: Capsule())
            }
            .padding(.top, 8)
        }
        .padding(.top, 48)
    }

    // ── S1/S2 계절 표제 ──
    private var seasonHeader: some View {
        let resolution = CyclePredictor.cycleDay(of: today, periodStarts: starts, averageLength: avgLength)
        let meta = resolution.map { seasonMeta(for: CyclePredictor.phaseForDay($0.day, cycleLength: avgLength)) }
        let isS1 = starts.count == 1    // 기록 1개 — hedge + 옅은 잉크 (§5.6.2)

        return VStack(alignment: .leading, spacing: 10) {
            if let meta, let resolution {
                Text(meta.name)
                    .font(.system(size: 64, weight: .bold, design: .serif))
                    .foregroundStyle(meta.color.opacity(isS1 ? 0.6 : 1.0))
                HStack(spacing: 6) {
                    if isS1 { Text("아마") }
                    Text("\(meta.phaseName) \(resolution.day)일차")
                    if resolution.projected { Text("· 예상") }
                }
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.65))
                Text(meta.moodline)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Ink.text.opacity(0.85))
                    .padding(.top, 4)
            }
        }
        .padding(.top, 32)
    }

    // ── S4 배너 (§3.3: 임신·질환 추론 절대 금지 — 사실 서술 + 허락 톤만) ──
    private var overdueDiff: Int {
        guard let last = starts.max() else { return 0 }
        return Calendar.current.dateComponents([.day], from: last, to: today).day ?? 0
    }

    private var overdueBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("기록상 예상일이 지났어요.")
                .font(.subheadline.weight(.semibold))
            Text("새로 시작했다면 기록을 추가할 수 있어요. 아니라면 그대로 두어도 괜찮아요.")
                .font(.footnote)
        }
        .foregroundStyle(Ink.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Ink.coral.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    // ── 기록 요약 + 진입 ──
    private var recordSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("생리 기록")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Ink.text)
            if let last = starts.max() {
                Text("마지막 시작일 \(last.formatted(date: .abbreviated, time: .omitted)) · 기록 \(starts.count)개 · 평균 \(avgLength)일")
                    .font(.footnote)
                    .foregroundStyle(Ink.text.opacity(0.6))
            }
            HStack(spacing: 10) {
                if !days.contains(today) {
                    Button {
                        // dedup=day: @Query 최신 상태에서 오늘 부재 확인됨 (§5.5.4)
                        modelContext.insert(PeriodDay(day: today))
                    } label: {
                        Text("오늘 기록")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Ink.paper)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Ink.text, in: Capsule())
                    }
                }
                Button {
                    showLogSheet = true
                } label: {
                    Text("기록 관리")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Ink.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .overlay(Capsule().stroke(Ink.text.opacity(0.35), lineWidth: 1))
                }
            }
        }
        .padding(.top, 8)
    }
}
