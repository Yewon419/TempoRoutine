// 템포루틴 — 계절 넘김 카드 (2026-08-31 대표님 승인 A1)
// 주기 앱만이 가진 내장 반복 이벤트: 사용자마다 계절 전환일이 주기적으로 찾아온다.
// 전환 뒤 첫 진입에 「◯◯이 시작됐어요」 카드 한 장 — 닫을 때까지 남아 전환일을 놓친
// 사람도 인사를 받는다. 사실만 말하고 재촉하지 않는다(§7).
//
// - 판정 = 마지막으로 본 계절(lastSeenPhaseRaw) ≠ 오늘 계절. 첫 실행은 조용히 채운다
//   (설치 직후 가짜 전환 방지).
// - **겨울 전환은 이 카드가 아니라 리캡(A3)이 담당** — 새 겨울 시작 = 「한 바퀴」의 순간이라
//   두 카드가 겹친다. 겨울은 건너뛰고 다음 봄 전환이 (가을→봄으로) 정상 발동한다.
// - 연출 고도화(테마별 전환 애니메이션)는 후속 — 1차는 계절색 카드 + 닫기 햅틱.

import SwiftUI
import TempoCore

enum SeasonTurnStore {
    static let lastSeenKey = "lastSeenPhaseRaw"

    /// 전환 인사 — 무드라인(§3 허락 톤)과 같은 결, 「시작」을 명시하는 짧은 한 줄
    static func greeting(for phase: CyclePhase) -> String {
        switch phase {
        case .follicular: Loc.str("봄이 시작됐어요. 조금씩 가벼워지는 때예요.")
        case .ovulation:  Loc.str("여름이 시작됐어요. 에너지가 차오르는 때예요.")
        case .luteal:     Loc.str("가을이 시작됐어요. 차분히 고르는 때예요.")
        case .menstrual:  Loc.str("겨울이 시작됐어요. 조금은 쉬어가도 좋아요.")   // 리캡 폴백용
        }
    }
}

/// 오늘 탭 상단 카드 — 계절색 헤어라인 테두리, 닫기 = lastSeen 갱신(호출부)
struct SeasonTurnCard: View {
    let meta: SeasonMeta
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SeasonGlyph(phase: meta.phase, size: 14)
                Text(Loc.fmt("%1$@이 시작됐어요", meta.name))
                    .font(.almanacBody(.subheadline, size: 15, weight: .bold))
                    .foregroundStyle(meta.color)
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
            Text(SeasonTurnStore.greeting(for: meta.phase))
                .font(.almanacBody(.footnote, size: 13))
                .foregroundStyle(Ink.text.opacity(0.75))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .milkGlass()
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(meta.color.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
