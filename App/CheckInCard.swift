// 템포루틴 — 데일리 체크인 카드 (MASTER §3.4 / §8.2.2 / §8.2.4)
// 오늘 탭·하루 상세 공용. 날짜만 다르고 문법은 같다 — 뒤늦은 기록·자정 넘겨 마무리하는 하루를
// 위해 지난 날짜에도 쓸 수 있어야 한다(2026-07-26 사용자 지적: "어제 기록할 방법이 없었다").
// 미래는 기록하지 않는다 — 생리 기록과 같은 원칙(§5.5.4 기록≠예측).
// 저장 조건 = 필수 2신호(energy·mood) 또는 노트(§5.5 — 한 줄 일기 단독 저장 허용).
// 스트릭·연속 표시 금지(§3.4), 전부 해제하면 기록 철회(스킵 무벌점).

import SwiftUI
import SwiftData

struct CheckInCard: View {
    let day: Date

    @Environment(\.modelContext) private var modelContext
    @Query private var checkIns: [DailyCheckIn]

    @State private var draftEnergy = 0
    @State private var draftMood = 0
    @State private var draftSleep = 0
    @State private var draftNote = ""
    @State private var draftLoaded = false
    @FocusState private var noteFocused: Bool   // 키보드 닫기 경로(베타 피드백 2026-07-22)

    private var cal: Calendar { Calendar.current }
    private var normalizedDay: Date { cal.startOfDay(for: day) }
    private var isToday: Bool { normalizedDay == cal.startOfDay(for: .now) }
    private var record: DailyCheckIn? { checkIns.first { $0.day == normalizedDay } }

    private var title: String { isToday ? "오늘의 체크인" : "이날의 체크인" }
    private var noteLabel: String { isToday ? "오늘 한 줄" : "그날 한 줄" }
    private var confirmLine: String {
        isToday ? "오늘 기록이 나의 리듬에 담겼어요." : "이날 기록이 나의 리듬에 담겼어요."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.almanac(size: 17, weight: .bold))
                .foregroundStyle(Ink.text)
            checkInRow(label: "에너지는", options: ["낮음", "보통", "높음"], value: $draftEnergy)
            checkInRow(label: "기분은", options: ["흐림", "보통", "맑음"], value: $draftMood)
            checkInRow(label: "지난밤 잠은", options: ["뒤척임", "보통", "푹 잤어요"], value: $draftSleep)
            VStack(alignment: .leading, spacing: 6) {
                Text(noteLabel).font(.caption).foregroundStyle(Ink.text.opacity(0.5))
                TextField("남기고 싶은 만큼만, 짧게.", text: $draftNote, axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(Ink.text)
                    .focused($noteFocused)
                    .onChange(of: draftNote) { persistDraft() }
            }
            if draftEnergy > 0 && draftMood > 0 {
                Text(confirmLine)
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Ink.text.opacity(0.6))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .milkGlass()
        .onAppear(perform: loadDraft)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("완료") { noteFocused = false }.foregroundStyle(Ink.text)
            }
        }
    }

    private func checkInRow(label: String, options: [String], value: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Ink.text.opacity(0.75))
                .frame(width: 88, alignment: .leading)
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let mapped = index * 2 + 1   // 3탭 = 1·3·5
                let selected = value.wrappedValue == mapped
                Button {
                    value.wrappedValue = selected ? 0 : mapped
                    persistDraft()
                } label: {
                    Text(option)
                        .font(.caption)
                        .foregroundStyle(selected ? Ink.paper : Ink.text.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(selected ? AnyShapeStyle(Ink.text) : AnyShapeStyle(Ink.text.opacity(0.08)),
                                    in: Capsule())
                }
                .accessibilityLabel("\(label) \(option)")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
    }

    private func loadDraft() {
        guard !draftLoaded else { return }
        draftLoaded = true
        if let existing = record {
            draftEnergy = existing.energy
            draftMood = existing.mood
            draftSleep = existing.sleep ?? 0
            draftNote = existing.note ?? ""
        }
    }

    /// 저장 조건 = 필수 2신호(energy·mood) 또는 노트(§5.5 개정 2026-07-22 — 노트 단독 저장 허용,
    /// 한 줄 일기 유실 방지). 리듬 집계는 energy·mood 둘 다 1...5인 행만 쓴다(§5.6.3).
    private func persistDraft() {
        let hasSignals = draftEnergy > 0 && draftMood > 0
        let hasNote = !draftNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if let existing = record {
            if hasSignals || hasNote {
                existing.energy = draftEnergy
                existing.mood = draftMood
                existing.sleep = draftSleep > 0 ? draftSleep : nil
                existing.note = hasNote ? draftNote : nil
            } else {
                modelContext.delete(existing)   // 전부 해제 = 기록 철회(스킵 무벌점)
            }
        } else if hasSignals || hasNote {
            let created = DailyCheckIn(day: normalizedDay, energy: draftEnergy, mood: draftMood)
            created.sleep = draftSleep > 0 ? draftSleep : nil
            created.note = hasNote ? draftNote : nil
            modelContext.insert(created)
        }
    }
}
