// 템포루틴 — 생리 기록 관리 시트 (Phase 0 ②, MASTER §5.5.4)
// 데이터는 일별 PeriodDay·불연속 허용, P0 편집 UI는 연속 구간(시작~종료)만.
// 원칙 4: 미래 day 추가 금지 — 선택 범위는 오늘까지.

import SwiftUI
import SwiftData
import TempoCore

struct PeriodLogSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PeriodDay.day) private var periodDays: [PeriodDay]

    @State private var startDate = Calendar.current.startOfDay(for: .now)
    @State private var endDate = Calendar.current.startOfDay(for: .now)

    private var today: Date { Calendar.current.startOfDay(for: .now) }
    private var episodes: [[Date]] { PeriodMath.episodes(days: periodDays.map(\.day)) }

    var body: some View {
        NavigationStack {
            List {
                Section("기간 추가") {
                    DatePicker("시작일", selection: $startDate, in: ...today, displayedComponents: .date)
                    DatePicker("종료일", selection: $endDate, in: startDate...today, displayedComponents: .date)
                    Button("추가") { addRange() }
                        .disabled(startDate > endDate)
                }

                if !episodes.isEmpty {
                    Section("기록된 기간") {
                        // 최근 것부터 — 삭제는 에피소드 단위(연속 구간 편집 원칙)
                        ForEach(Array(episodes.reversed().enumerated()), id: \.offset) { _, episode in
                            if let first = episode.first, let last = episode.last {
                                HStack {
                                    Text(rangeLabel(first: first, last: last))
                                    Spacer()
                                    Text("\(episode.count)일")
                                        .foregroundStyle(.secondary)
                                }
                                .swipeActions {
                                    Button("삭제", role: .destructive) {
                                        deleteEpisode(episode)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("생리 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }

    private func rangeLabel(first: Date, last: Date) -> String {
        let f = first.formatted(date: .abbreviated, time: .omitted)
        if first == last { return f }
        return "\(f) ~ \(last.formatted(date: .abbreviated, time: .omitted))"
    }

    private func addRange() {
        let cal = Calendar.current
        let existing = Set(periodDays.map(\.day))
        var day = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)
        while day <= end {
            if day <= today && !existing.contains(day) {   // 미래 금지 + dedup=day
                modelContext.insert(PeriodDay(day: day))
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
    }

    private func deleteEpisode(_ episode: [Date]) {
        let target = Set(episode)
        for record in periodDays where target.contains(record.day) {
            modelContext.delete(record)
        }
    }
}
