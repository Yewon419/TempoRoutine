// 템포루틴 — Input 진행 컨트롤 (2026-08-12 사용자 지시, MASTER §5.5.2 개정)
//
// Output의 SessionProgressControl을 재사용하지 않는 이유: 그건 OutputItem에 직결돼 값을 직접
// 쓴다(item.loggedSessions = n). Input의 값은 아이템이 아니라 **그날의 InputProgress**에 있다.
// 일반화하려면 Output 호출부까지 손대야 해서, 값+콜백 기반으로 따로 뒀다.
//
// 레코드 생성은 **첫 조작 때** 한다(ensureProgress) — 뷰를 그리는 중에 insert하면 그 삽입이
// 다시 렌더를 부른다. 안 만지는 날은 레코드도 안 생긴다.

import SwiftUI
import TempoCore

struct InputProgressControl: View {
    let goal: InputProgressGoal
    let subtasks: [InputSubtask]
    let progress: InputProgress?
    /// 첫 조작 때 그날 레코드를 만들어 돌려준다
    let ensureProgress: () -> InputProgress
    /// 값이 바뀐 뒤 호출 — 인자는 "그날 목표에 닿았는가"(자동 체크 판정)
    let onChange: (Bool) -> Void

    private var state: InputProgressState { progress?.state() ?? InputProgressState() }

    var body: some View {
        switch goal.kind {
        case .subtasks: subtaskRows
        case .sessions: sessionRow
        case .percent:  percentRow
        case .timer, .stopwatch: EmptyView()   // 3b에서
        }
    }

    /// 값 변경 공통 경로 — 레코드를 확보하고, 바꾸고, 자동 체크를 판정해 올린다
    private func mutate(_ change: (InputProgress) -> Void) {
        let record = progress ?? ensureProgress()
        change(record)
        onChange(InputProgressRule.isFulfilled(goal: goal, state: record.state()))
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

    // ── 세션 ── 목표 1~8은 점 행, 그 밖은 카운터(점 9개+는 §8.1 44pt를 못 지킨다 — Output과 같은 규칙)
    @ViewBuilder
    private var sessionRow: some View {
        if (1...8).contains(goal.targetSessions) {
            sessionDots
        } else {
            sessionCounter
        }
    }

    private var sessionDots: some View {
        HStack(spacing: 4) {
            ForEach(1...max(1, goal.targetSessions), id: \.self) { index in
                Button {
                    // 지금 수를 다시 누르면 하나 되돌린다(체크인 3탭과 같은 문법)
                    let next = state.loggedSessions == index ? index - 1 : index
                    mutate { $0.loggedSessions = next }
                } label: {
                    ZStack {
                        Circle().stroke(Ink.text.opacity(0.3), lineWidth: 1.5)
                        if index <= state.loggedSessions { Circle().fill(Ink.text) }
                    }
                    .frame(width: 18, height: 18)
                    .frame(width: 32, height: 36)   // 터치 타깃(§8.1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("\(state.loggedSessions) / \(goal.targetSessions)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Ink.text.opacity(0.55))
                .padding(.leading, 4)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("진행")
        .accessibilityValue("\(state.loggedSessions) / \(goal.targetSessions)회")
    }

    private var sessionCounter: some View {
        HStack(spacing: 12) {
            stepButton("minus", enabled: state.loggedSessions > 0) {
                mutate { $0.loggedSessions = max(0, state.loggedSessions - 1) }
            }
            Text(goal.targetSessions > 0
                 ? "\(state.loggedSessions) / \(goal.targetSessions)"
                 : "\(state.loggedSessions)회")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Ink.text.opacity(0.7))
            stepButton("plus", enabled: true) {
                mutate { $0.loggedSessions = state.loggedSessions + 1 }
            }
            Spacer(minLength: 0)
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(enabled ? Ink.text.opacity(0.7) : Ink.text.opacity(0.25))
                .frame(width: 32, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // ── 퍼센트 ── 연속 조정이라 햅틱은 붙이지 않는다(§8.1 "과용 여지가 큰 연속 조정은 제외")
    private var percentRow: some View {
        HStack(spacing: 10) {
            Slider(value: Binding(
                get: { state.percent / 100 },
                set: { value in mutate { $0.percent = value * 100 } }
            ), in: 0...1)
            .tint(Ink.text)
            Text((state.percent / 100).formatted(.percent.precision(.fractionLength(0))))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Ink.text.opacity(0.7))
                .frame(width: 40, alignment: .trailing)
        }
    }
}
