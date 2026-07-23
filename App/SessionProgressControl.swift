// 템포루틴 — Output 세션 진행 컨트롤 (2026-07-23 베타 피드백 개선, §8.1 ProgressControl)
// 목표 1~8세션 = 먹색 점 행(탭 = 그 수만큼, 현재 수 재탭 = 하나 되돌리기 — 체크인 3탭과 같은 문법).
// 목표 없음·9+ = 카운터 + 진행 바 폴백(점 9개+는 터치 타깃이 §8.1 44pt를 못 지킴).
// 먹색 채움 통일(§8.1 정정 노트): 채운 점 = --ink. 오늘 탭·하루 상세 공용.

import SwiftUI

struct SessionProgressControl: View {
    let item: OutputItem
    /// 조정 순간 호출 — completed=true는 목표 도달(확정 햅틱), 그 외 작은 햅틱(§8.1 2단 체계)
    let onAdjust: (_ completed: Bool) -> Void

    private var target: Int { item.targetSessions }
    private var logged: Int { item.loggedSessions }

    var body: some View {
        if (1...8).contains(target) {
            dotsRow
        } else {
            counterRow
        }
    }

    // ── 점 행 (목표 1~8) ──
    private var dotsRow: some View {
        HStack(spacing: 4) {
            ForEach(1...target, id: \.self) { index in
                let filled = index <= logged
                Button {
                    let next = logged == index ? index - 1 : index
                    onAdjust(next >= target)
                    item.loggedSessions = next
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Ink.text.opacity(0.3), lineWidth: 1.5)
                        if filled {
                            Circle().fill(Ink.text)
                        }
                    }
                    .frame(width: 20, height: 20)
                    .frame(width: 36, height: 40)   // 터치 타깃(§8.1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("\(logged) / \(target)")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Ink.text.opacity(0.55))
                .padding(.leading, 6)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("세션 진행")
        .accessibilityValue("\(logged) / \(target) 세션")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment where logged < target:
                onAdjust(logged + 1 >= target)
                item.loggedSessions = logged + 1
            case .decrement where logged > 0:
                onAdjust(false)
                item.loggedSessions = logged - 1
            default:
                break
            }
        }
    }

    // ── 카운터 + 진행 바 (목표 없음 또는 9+) ──
    private var counterRow: some View {
        HStack(spacing: 12) {
            Text(target > 0 ? "\(logged) / \(target) 세션" : "\(logged) 세션")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Ink.text.opacity(0.7))
            if target > 0 {
                Capsule()
                    .fill(Ink.text.opacity(0.08))
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule()
                                .fill(Ink.text.opacity(0.55))
                                .frame(width: max(logged > 0 ? 6 : 0,
                                                  geo.size.width * min(1, Double(logged) / Double(target))))
                        }
                    }
                    .frame(height: 5)
                    .clipShape(Capsule())
            } else {
                Spacer(minLength: 0)
            }
            Button {
                guard logged > 0 else { return }
                onAdjust(false)
                item.loggedSessions = logged - 1
            } label: {
                Image(systemName: "minus.circle")
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                onAdjust(target > 0 && logged + 1 >= target)
                item.loggedSessions = logged + 1
            } label: {
                Image(systemName: "plus.circle")
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Ink.text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("세션 진행")
        .accessibilityValue(target > 0 ? "\(logged) / \(target) 세션" : "\(logged) 세션")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                onAdjust(target > 0 && logged + 1 >= target)
                item.loggedSessions = logged + 1
            case .decrement where logged > 0:
                onAdjust(false)
                item.loggedSessions = logged - 1
            default:
                break
            }
        }
    }
}
