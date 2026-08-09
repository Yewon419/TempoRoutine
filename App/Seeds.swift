// 템포루틴 — 씨앗 (테마 재화, 2026-08-09 사용자 결정)
// 하루 체크인을 다 적으면(오늘 한 줄 제외) 씨앗 1개. 당일 작성이 원칙, 다음날 작성까지 인정.
// 별도 원장 모델을 두지 않고 DailyCheckIn.completedAt에서 파생한다(§5.5 파생 우선 철학) —
// 기록 철회(삭제)면 그 씨앗도 사라진다. 소비(테마 구매)가 붙는 시점에 잔액 하한을 함께 설계.
// 스트릭·연속 표시 금지(§3.4)는 그대로다 — 씨앗은 개수만 말하고 연속을 말하지 않는다.

import SwiftUI
import TempoCore

enum Seeds {
    /// 완료 판정 — 필수 2신호 + 켜져 있는 추적 신호 전부. 오늘 한 줄은 제외(사용자 규칙).
    /// 판정은 저장 순간의 추적 설정 기준 — 나중에 항목을 켜고 꺼도 이미 찍힌 도장은 불변.
    static func isComplete(energy: Int, mood: Int, sleep: Int?, appetite: Int?,
                           signals: TrackedSignals) -> Bool {
        guard energy > 0, mood > 0 else { return false }
        if signals.sleep && (sleep ?? 0) == 0 { return false }
        if signals.appetite && (appetite ?? 0) == 0 { return false }
        return true
    }

    /// 완료 도장 — 처음 완성된 순간에만 찍는다(이후 수정해도 최초 시각 유지 = 중복 지급 없음).
    static func stampCompletion(_ record: DailyCheckIn, signals: TrackedSignals) {
        guard record.completedAt == nil,
              isComplete(energy: record.energy, mood: record.mood,
                         sleep: record.sleep, appetite: record.appetite, signals: signals)
        else { return }
        record.completedAt = .now
    }

    /// 지급 판정 — 그날 또는 다음날 안에 완성된 기록만(마감 = day+2일 0시).
    static func isAwarded(_ record: DailyCheckIn) -> Bool {
        guard let stamped = record.completedAt else { return false }
        guard let deadline = Calendar.current.date(byAdding: .day, value: 2, to: record.day) else {
            return false
        }
        return stamped < deadline
    }

    static func balance(_ checkIns: [DailyCheckIn]) -> Int {
        checkIns.filter { isAwarded($0) }.count
    }

    static func awardedDays(_ checkIns: [DailyCheckIn]) -> Set<Date> {
        Set(checkIns.filter { isAwarded($0) }.map(\.day))
    }
}

/// 씨앗 글리프 — 위가 살짝 뾰족한 물방울꼴. 은필 선화 모티프와 같은 단색 계열(§4).
struct SeedGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.5, y: 0))
        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h),
                       control: CGPoint(x: w * 1.12, y: h * 0.68))
        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: 0),
                       control: CGPoint(x: -w * 0.12, y: h * 0.68))
        return p
    }
}

/// 오늘 탭 우상단 잔액 배지. 돈 문법(코인·금액) 금지 — 씨앗 글리프 + 개수만.
struct SeedBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            SeedGlyph()
                .fill(Ink.text.opacity(0.75))
                .frame(width: 9, height: 12)
                .rotationEffect(.degrees(16))
            Text("\(count)")
                .font(.almanacBody(.footnote, size: 13))
                .monospacedDigit()
                .foregroundStyle(Ink.text.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Ink.surface, in: Capsule())
        .overlay(Capsule().stroke(Ink.text.opacity(0.15), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("씨앗 \(count)개")
    }
}
