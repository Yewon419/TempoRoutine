// 템포루틴 — 행 길게 누르기 빠른 삭제 (2026-07-27 사용자 지시, MASTER §8.2.2·§8.2.4)
// 오늘 탭·하루 상세 공용. 행을 0.45초 누르면 하단 확인 시트가 올라오고, 확인해야 지운다(§8.2.6
// 파괴 액션 = 분리 배치 + 확인). 행은 전부 Button이라 제스처는 simultaneousGesture로 얹는다 —
// 탭(체크 토글·수정 시트)은 그대로 살아야 한다.
// ⚠ Input 삭제는 ItemCompletion을 함께 지운다: 완료 기록은 관계가 아니라 itemID 참조라
//   그냥 두면 고아 레코드가 남아 리듬 집계에 섞인다(§5.5.2). Output 서브태스크는 cascade.

import SwiftUI
import SwiftData

enum QuickDeleteTarget: Identifiable {
    case schedule(ScheduleItem)
    case input(InputItem)
    case output(OutputItem)

    var id: UUID {
        switch self {
        case .schedule(let item): item.id
        case .input(let item): item.id
        case .output(let item): item.id
        }
    }

    var title: String {
        switch self {
        case .schedule(let item): item.title
        case .input(let item): item.title
        case .output(let item): item.title
        }
    }

    var kindLabel: String {
        switch self {
        case .schedule: Loc.str("일정")
        case .input: "Input"
        case .output: "Output"
        }
    }

    func delete(from context: ModelContext, completions: [ItemCompletion]) {
        switch self {
        case .schedule(let item):
            ScheduleReminder.cancel(id: item.id)
            context.delete(item)
        case .input(let item):
            for record in completions where record.itemID == item.id {
                context.delete(record)
            }
            // 진행 레코드도 함께(2026-08-12) — itemID 참조라 관계 cascade가 닿지 않는다.
            // 남겨두면 같은 UUID가 재발급될 일은 없어도 스토어에 영영 고아로 쌓인다.
            // (InputSubtask는 관계 cascade라 아이템과 같이 지워진다)
            let progresses = (try? context.fetch(FetchDescriptor<InputProgress>())) ?? []
            for record in progresses where record.itemID == item.id {
                context.delete(record)
            }
            context.delete(item)
        case .output(let item):
            context.delete(item)
        }
    }
}

/// 행 자신에 제스처 + 확인 다이얼로그를 함께 얹는다(2026-09-01 베타 "말풍선 위치도 이상하다").
/// 종전엔 화면 루트에 한 번만 붙였는데, iOS 26 confirmationDialog가 부착 뷰를 가리키는 앵커
/// 팝오버로 떠서 말풍선이 행과 무관한 화면 상단을 가리켰다 — 행 부착이 정위치다.
private struct QuickDeletableRow: ViewModifier {
    let item: QuickDeleteTarget
    @Binding var target: QuickDeleteTarget?
    @Binding var feedback: Int
    let completions: [ItemCompletion]
    let context: ModelContext

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(quickDeleteGesture(item, into: $target, feedback: $feedback))
            .confirmationDialog(
                "\(item.kindLabel) 「\(item.title)」" as String,
                isPresented: Binding(get: { target?.id == item.id },
                                     set: { if !$0 { target = nil } }),
                titleVisibility: .visible
            ) {
                Button("삭제", role: .destructive) {
                    target?.delete(from: context, completions: completions)
                    target = nil
                }
                Button("취소", role: .cancel) { target = nil }
            } message: {
                Text("이 항목과 기록이 함께 지워져요. 되돌릴 수 없어요.")
            }
    }
}

extension View {
    /// 행마다 붙인다 — 팝오버 화살표가 그 행을 가리킨다. 표시 판정은 id 일치라 겹침 없음.
    func quickDeletable(_ item: QuickDeleteTarget,
                        target: Binding<QuickDeleteTarget?>,
                        feedback: Binding<Int>,
                        completions: [ItemCompletion],
                        context: ModelContext) -> some View {
        modifier(QuickDeletableRow(item: item, target: target, feedback: feedback,
                                   completions: completions, context: context))
    }
}

/// 행에 얹는 길게 누르기 — 확정 햅틱과 함께 확인 시트를 띄운다.
func quickDeleteGesture(_ item: QuickDeleteTarget,
                        into target: Binding<QuickDeleteTarget?>,
                        feedback: Binding<Int>) -> some Gesture {
    LongPressGesture(minimumDuration: 0.45).onEnded { _ in
        feedback.wrappedValue += 1
        target.wrappedValue = item
    }
}
