// 템포루틴 — 아이패드 적응 레이아웃 헬퍼 (2026-07-23 사용자 지시: 아이패드 전용 UI·가로모드)
// 원칙: 아이폰(§8 스펙)은 무변경. regular 폭에서만 중앙 조판·2열·분할 뷰가 발동한다.
// compact 기기에선 maxWidth 제한이 화면 폭보다 커서 자연히 무영향(사이즈클래스 분기 불필요).

import SwiftUI

extension View {
    /// 책력 중앙 조판 — 콘텐츠 최대 폭 제한 + 중앙 정렬. 아이패드 전폭 늘어짐 방지.
    func centeredColumn(_ maxWidth: CGFloat = 720) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}
