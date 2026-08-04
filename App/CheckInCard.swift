// 템포루틴 — 데일리 체크인 카드 (MASTER §3.4 / §8.2.2 / §8.2.4)
// 오늘 탭·하루 상세 공용. 날짜만 다르고 문법은 같다 — 뒤늦은 기록·자정 넘겨 마무리하는 하루를
// 위해 지난 날짜에도 쓸 수 있어야 한다(2026-07-26 사용자 지적: "어제 기록할 방법이 없었다").
// 미래는 기록하지 않는다 — 생리 기록과 같은 원칙(§5.5.4 기록≠예측).
// 저장 조건 = 필수 2신호(energy·mood) 또는 노트(§5.5 — 한 줄 일기 단독 저장 허용).
// 스트릭·연속 표시 금지(§3.4), 전부 해제하면 기록 철회(스킵 무벌점).

import SwiftUI
import SwiftData
import TempoCore   // TrackedSignals

struct CheckInCard: View {
    let day: Date

    @Environment(\.modelContext) private var modelContext
    @Query private var checkIns: [DailyCheckIn]

    @State private var draftEnergy = 0
    @State private var draftMood = 0
    @State private var draftSleep = 0
    @State private var draftIrritability = 0
    @State private var draftPain = 0
    @State private var draftAppetite = 0
    @State private var draftNote = ""
    @State private var draftLoaded = false

    /// 어떤 행을 보여줄지는 온보딩·설정에서 고른 추적 항목이 정한다(§3.10).
    /// ⚠ 종전에는 이 배선이 없어 통증·식욕을 켜도 카드에 나오지 않았다(2026-08-04 발견).
    private var signals: TrackedSignals { AppSettings.trackedSignals }
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
            // 정서 계열(기분·예민함) → 신체 계열(몸) 순. M축은 이 둘의 차로 정의된다(v1.5 §2-3).
            checkInRow(label: "에너지는", options: ["낮음", "보통", "높음"], value: $draftEnergy)
            checkInRow(label: "기분은", options: ["흐림", "보통", "맑음"], value: $draftMood)
            if signals.tracksIrritability {
                checkInRow(label: "예민함은", options: ["잔잔함", "보통", "날카로움"], value: $draftIrritability)
            }
            if signals.pain {
                checkInRow(label: "몸은", options: ["불편해요", "보통", "괜찮아요"], value: $draftPain)
            }
            if signals.sleep {
                checkInRow(label: "지난밤 잠은", options: ["뒤척임", "보통", "푹 잤어요"], value: $draftSleep)
            }
            if signals.appetite {
                checkInRow(label: "식욕은", options: ["없음", "보통", "좋음"], value: $draftAppetite)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(noteLabel).font(.caption).foregroundStyle(Ink.text.opacity(0.5))
                TextField("", text: $draftNote, axis: .vertical)   // placeholder 제거(2026-07-31 사용자 지시)
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
        // 날짜가 바뀌면 그날 것으로 다시 읽는다(2026-08-03 베타 피드백 "어제 저장한 게 오늘까지 표시").
        // onAppear 한 번만 로드하면, 앱을 백그라운드에 둔 채 자정을 넘겼을 때 day는 오늘로 바뀌는데
        // 초안은 어제 값이 남아 칩·확인 문구가 어제 상태로 보이고, 손대는 순간 오늘로 복사된다.
        .onChange(of: normalizedDay) { _, _ in reloadDraft() }
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
                let current = value.wrappedValue
                let selected = current == mapped
                // 중간값(2·4)은 양옆 두 칩이 함께 옅게 찬다 — 3버튼 UI를 유지하면서
                // 저장은 5점으로 받는다(v1.5 §3-2: 3점 척도는 진폭 추정 정보량이 부족).
                let half = current > 0 && (current == mapped - 1 || current == mapped + 1)
                Button {
                    value.wrappedValue = selected ? 0 : mapped
                    persistDraft()
                } label: {
                    Text(option)
                        .font(.caption)
                        .foregroundStyle(selected ? Ink.paper : Ink.text.opacity(half ? 0.9 : 0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(chipFill(selected: selected, half: half), in: Capsule())
                }
                // 왼쪽 칩과의 사이값 = mapped-1. 첫 칩은 왼쪽이 없어 중간값이 없다.
                .onLongPressGesture {
                    guard mapped > 1 else { return }
                    value.wrappedValue = current == mapped - 1 ? 0 : mapped - 1
                    persistDraft()
                }
                .accessibilityLabel("\(label) \(option)")
                .accessibilityValue(half ? "이전 항목과의 중간" : "")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                // 롱프레스는 VoiceOver로 닿기 어렵다 — 같은 동작을 명시 액션으로도 연다
                .accessibilityAction(named: "중간값으로") {
                    guard mapped > 1 else { return }
                    value.wrappedValue = mapped - 1
                    persistDraft()
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// SwiftUI 뷰 한 식에 조건 분기를 몰면 타입체크가 터진다 — 배경만 떼어 낸다(CLAUDE.md 실측)
    private func chipFill(selected: Bool, half: Bool) -> AnyShapeStyle {
        if selected { return AnyShapeStyle(Ink.text) }
        if half { return AnyShapeStyle(Ink.text.opacity(0.35)) }
        return AnyShapeStyle(Ink.text.opacity(0.08))
    }

    /// 신호를 먼저 비우고 노트를 마지막에 비운다 — 노트의 onChange가 persistDraft를 부르는데,
    /// 그 시점에 신호가 남아 있으면 새 날짜에 어제 값이 저장된다.
    private func reloadDraft() {
        draftEnergy = 0
        draftMood = 0
        draftSleep = 0
        draftIrritability = 0
        draftPain = 0
        draftAppetite = 0
        draftNote = ""
        draftLoaded = false
        loadDraft()
    }

    private func loadDraft() {
        guard !draftLoaded else { return }
        draftLoaded = true
        if let existing = record {
            draftEnergy = existing.energy
            draftMood = existing.mood
            draftSleep = existing.sleep ?? 0
            draftIrritability = existing.irritability ?? 0
            draftPain = existing.pain ?? 0
            draftAppetite = existing.appetite ?? 0
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
                existing.irritability = draftIrritability > 0 ? draftIrritability : nil
                existing.pain = draftPain > 0 ? draftPain : nil
                existing.appetite = draftAppetite > 0 ? draftAppetite : nil
                existing.note = hasNote ? draftNote : nil
            } else {
                modelContext.delete(existing)   // 전부 해제 = 기록 철회(스킵 무벌점)
            }
        } else if hasSignals || hasNote {
            // 지난 날짜에 쓰는 기록 = 회상 기반이라 적합 가중치가 다르다(v1.5 §3-4).
            // 판정 기준은 "카드가 보고 있는 날 ≠ 오늘" — 자정 넘겨 마무리하는 하루도 여기 걸린다.
            let created = DailyCheckIn(day: normalizedDay, energy: draftEnergy, mood: draftMood,
                                       isBackfilled: !isToday)
            created.sleep = draftSleep > 0 ? draftSleep : nil
            created.irritability = draftIrritability > 0 ? draftIrritability : nil
            created.pain = draftPain > 0 ? draftPain : nil
            created.appetite = draftAppetite > 0 ? draftAppetite : nil
            created.note = hasNote ? draftNote : nil
            modelContext.insert(created)
        }
    }
}
