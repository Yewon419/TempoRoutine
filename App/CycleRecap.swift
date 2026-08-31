// 템포루틴 — 주기 리캡 카드 (2026-08-31 대표님 승인 A3)
// 한 주기가 끝나면(새 겨울 시작 = starts.last 갱신) 지난 주기를 한 장으로 돌아본다:
// 주기 길이 · 완성 체크인 수 · 에너지가 가장 높았던 계절 · 한 줄 노트 발췌.
// 나의 템포 데이터의 재조합일 뿐 새 계산 축은 없다. 노출 = 오늘 탭 상단 1회(닫으면 그 주기
// 종료), 발행 순간이 「한 바퀴」(firstCycle) 업적의 훅이다.
//
// 판정 키 = 새 주기 시작일 문자열(issuedFor). 같은 주기엔 다시 안 뜨고, 소급 기록으로
// starts가 재구성돼도 최신 시작일 기준이라 안전하다. dev 스토어는 periodDays부터 분리라 무해.

import SwiftUI
import TempoCore

struct CycleRecapData {
    let start: Date          // 지난 주기 시작
    let end: Date            // = 새 주기 시작(exclusive)
    let lengthDays: Int
    let checkInCount: Int
    let topSeason: SeasonMeta?
    let note: String?

    /// 발행 판정 — starts 2개 이상 + 이 새 주기로는 아직 발행 전일 때만.
    static func pending(snapshot: CycleSnapshot, checkIns: [DailyCheckIn]) -> CycleRecapData? {
        let starts = snapshot.starts
        guard starts.count >= 2, let newStart = starts.last else { return nil }
        guard CycleRecapStore.issuedFor != ExportCodec.dayString(newStart) else { return nil }
        let prevStart = starts[starts.count - 2]
        let cal = Calendar.current
        let length = cal.dateComponents([.day], from: prevStart, to: newStart).day ?? 0
        // 비정상 간격(중복 기록·소급 정리 중)은 발행하지 않는다 — 틀린 축하가 제일 나쁘다
        guard (15...60).contains(length) else { return nil }
        let inCycle = checkIns.filter { $0.day >= prevStart && $0.day < newStart }
        let completed = inCycle.filter { $0.completedAt != nil }
        // 에너지 최고 계절 — 계절별 평균(기록 2개 미만인 계절은 제외: 한 번의 우연을 패턴처럼 말하지 않는다)
        var byPhase: [CyclePhase: [Int]] = [:]
        for record in completed where record.energy > 0 {
            guard let phase = snapshot.phase(on: record.day) else { continue }
            byPhase[phase, default: []].append(record.energy)
        }
        let top = byPhase
            .filter { $0.value.count >= 2 }
            .max { avg($0.value) < avg($1.value) }
            .map { seasonMeta(for: $0.key) }
        let note = completed
            .sorted { $0.day > $1.day }
            .compactMap { $0.note?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return CycleRecapData(start: prevStart, end: newStart, lengthDays: length,
                              checkInCount: completed.count, topSeason: top, note: note)
    }

    private static func avg(_ values: [Int]) -> Double {
        Double(values.reduce(0, +)) / Double(max(values.count, 1))
    }
}

enum CycleRecapStore {
    private static let issuedKey = "cycleRecapIssuedFor"
    static var issuedFor: String? { UserDefaults.standard.string(forKey: issuedKey) }
    /// 닫는 순간 발행 확정 + 「한 바퀴」 업적
    @MainActor
    static func markIssued(newStart: Date) {
        UserDefaults.standard.set(ExportCodec.dayString(newStart), forKey: issuedKey)
        Achievements.shared.unlock(.firstCycle)
    }
}

/// 오늘 탭 상단 카드 — 사실만 말하고 재촉하지 않는다(§7). 닫기 = 발행 확정.
struct CycleRecapCard: View {
    let data: CycleRecapData
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("지난 주기 돌아보기")
                    .font(.almanacBody(.subheadline, size: 15, weight: .bold))
                    .foregroundStyle(Ink.text)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Ink.text.opacity(0.4))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Loc.str("닫기"))
            }
            Text(Loc.fmt("%1$@일의 주기를 한 바퀴 함께했어요.", "\(data.lengthDays)"))
                .font(.almanacBody(.footnote, size: 13))
                .foregroundStyle(Ink.text.opacity(0.75))
            if data.checkInCount > 0 {
                Text(Loc.fmt("체크인 %1$@일을 완성했어요.", "\(data.checkInCount)"))
                    .font(.almanacBody(.footnote, size: 13))
                    .foregroundStyle(Ink.text.opacity(0.75))
            }
            if let top = data.topSeason {
                HStack(spacing: 6) {
                    SeasonGlyph(phase: top.phase, size: 12)
                    Text(Loc.fmt("에너지는 %1$@에 가장 높았어요.", top.name))
                        .font(.almanacBody(.footnote, size: 13))
                        .foregroundStyle(top.color)
                }
            }
            if let note = data.note {
                Text(Loc.fmt("“%1$@”", note))
                    .font(.almanacBody(.footnote, size: 13))
                    .foregroundStyle(Ink.text.opacity(0.55))
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .milkGlass()
        .accessibilityElement(children: .combine)
    }
}
