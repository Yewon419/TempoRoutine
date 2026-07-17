// 템포루틴 — 앱 엔트리 (빌드 2 최소 타깃: TempoCore 링크 증명용 플레이스홀더)
// Phase 0 ②(생리 로깅+단계계산 UI)는 다음 빌드에서 — 여기는 파이프라인 검증이 목적.

import SwiftUI
import TempoCore

@main
struct TempoRoutineApp: App {
    var body: some Scene {
        WindowGroup {
            TodayPlaceholderView()
        }
    }
}

/// 오늘 화면 자리 — TempoCore 호출로 링크·동작을 실기기에서 증명한다.
struct TodayPlaceholderView: View {
    private var seasonLabel: String {
        // 데모: 기록 1개(21일 전 시작) 가정 → 오늘의 단계
        let start = Calendar.current.date(byAdding: .day, value: -21, to: .now) ?? .now
        guard let r = CyclePredictor.phase(on: .now, periodStarts: [start], averageLength: 28) else {
            return "계절 기록 전"
        }
        let name: String
        switch r.phase {
        case .menstrual:  name = "겨울"
        case .follicular: name = "봄"
        case .ovulation:  name = "여름"
        case .luteal:     name = "가을"
        }
        return r.projected ? "\(name) · 예상" : name
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(seasonLabel)
                .font(.system(size: 56, weight: .bold, design: .serif))
            Text("당신 몸의 템포에 맞게.")
                .font(.system(.body, design: .serif))
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
