// 템포루틴 — Input 진행 컨트롤 (2026-08-12 사용자 지시, MASTER §5.5.2 개정)
//
// 세션·타이머는 **Output과 같은 컨트롤을 쓴다**(2026-08-13 통일) — 여기는 그날 레코드를
// 확보해 넘기는 얇은 층이다. 체크리스트만 자체 구현: Input은 완료 여부가 날짜별이라
// 항목(InputSubtask)에 isDone이 없고, Output(OutputSubtask.isDone)과 조작 대상이 다르다.
//
// 레코드 생성은 **첫 조작 때** 한다(ensureProgress) — 뷰를 그리는 중에 insert하면 그 삽입이
// 다시 렌더를 부른다. 안 만지는 날은 레코드도 안 생긴다.

import SwiftUI
import TempoCore

struct InputProgressControl: View {
    let goal: ProgressGoal
    /// Live Activity·자동 체크가 가리키는 대상 = **아이템**(그날 레코드가 아니다)
    let itemID: UUID
    let itemTitle: String
    let subtasks: [InputSubtask]
    let progress: InputProgress?
    /// 첫 조작 때 그날 레코드를 만들어 돌려준다
    let ensureProgress: () -> InputProgress
    /// 값이 바뀐 뒤 호출 — 인자는 "그날 목표에 닿았는가"(자동 체크 판정)
    let onChange: (Bool) -> Void

    private var state: ProgressState { progress?.state() ?? ProgressState() }

    var body: some View {
        content
            .onAppear {
                // 타이머는 @Bindable을 걸 대상이 있어야 해서 레코드를 미리 확보한다.
                // onAppear인 이유 = 뷰를 그리는 중에 insert하면 그 삽입이 다시 렌더를 부른다.
                // 값이 0뿐인 레코드는 내보내기에서 걸러지므로 백업이 지저분해지지 않는다.
                if goal.kind == .timer || goal.kind == .stopwatch, progress == nil {
                    _ = ensureProgress()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch goal.kind {
        case .subtasks:
            subtaskRows
        case .sessions:
            SessionProgressControl(logged: state.loggedSessions, target: goal.targetSessions) { next, _ in
                mutate { $0.loggedSessions = next }
            }
        case .percent:
            percentRow
        case .timer, .stopwatch:
            if let record = progress {
                TimerProgressControl(backing: record, activityID: itemID, activityTitle: itemTitle,
                                     isTimer: goal.kind == .timer,
                                     targetSeconds: goal.targetSeconds ?? 0,
                                     isInput: true) { _ in
                    onChange(ProgressRule.isFulfilled(goal: goal, state: record.state()))
                }
            }
        }
    }

    /// 값 변경 공통 경로 — 레코드를 확보하고, 바꾸고, 자동 체크를 판정해 올린다
    private func mutate(_ change: (InputProgress) -> Void) {
        let record = progress ?? ensureProgress()
        change(record)
        onChange(ProgressRule.isFulfilled(goal: goal, state: record.state()))
    }

    // ── 체크리스트 ──
    private var subtaskRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(subtasks.sorted { $0.order < $1.order }) { sub in
                let done = state.doneSubtasks > 0 && (progress?.doneSubtaskIDs.contains(sub.id) ?? false)
                Button {
                    mutate { record in
                        var ids = record.doneSubtaskIDs
                        if ids.contains(sub.id) { ids.remove(sub.id) } else { ids.insert(sub.id) }
                        // 지워진 항목의 id가 남아 있으면 "다 했다"가 거짓으로 참이 된다 — 매번 걸러낸다
                        record.doneSubtaskIDs = ids.intersection(Set(subtasks.map(\.id)))
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .font(.caption)
                            .foregroundStyle(done ? Ink.text : Ink.text.opacity(0.3))
                        Text(sub.title)
                            .font(.footnote)
                            .foregroundStyle(Ink.text.opacity(done ? 0.5 : 0.8))
                            .strikethrough(done, color: Ink.dim)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(done ? [.isSelected] : [])
            }
        }
    }

    // ── 퍼센트 ── 연속 조정이라 햅틱은 붙이지 않는다(§8.1 "과용 여지가 큰 연속 조정은 제외")
    private var percentRow: some View {
        HStack(spacing: 10) {
            Slider(value: Binding(
                get: { state.percent },
                set: { value in mutate { $0.percent = value } }
            ), in: 0...1)
            .tint(Ink.text)
            Text(state.percent.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Ink.text.opacity(0.7))
                .frame(width: 40, alignment: .trailing)
        }
    }
}
