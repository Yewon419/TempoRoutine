// 템포루틴 — 앱 스위처 가림 (§5.7 P0, 2026-07-22 편입 · 2026-08-12 구현)
//
// 앱이 비활성으로 넘어갈 때 콘텐츠 위에 중립 표지를 덮는다. iOS가 그 순간 화면을 떠서 앱
// 스위처 카드로 보관하기 때문에, 가리지 않으면 계절 표제·캘린더 주기 표시가 잠금 해제도
// 없이 옆 사람에게 보인다.
//
// **왜 루트 오버레이가 아니라 별도 UIWindow인가**: `.sheet`·`.fullScreenCover`는 UIKit 표시
// 계층에서 루트 뷰보다 위에 있다. 루트에 `.overlay`를 얹으면 시트가 그 위에 남아, 체크인
// 시트나 하루 상세를 연 채 홈으로 나가면 그대로 스냅샷에 찍힌다. 앱에 시트가 열댓 개라
// 각각에 붙이는 방식은 유지가 안 된다. 창을 한 겹 더 띄우는 게 전부를 덮는 유일한 길이다.

import SwiftUI
import UIKit

@MainActor
enum PrivacyShield {
    /// 표지 창. 메인 액터 격리라 전역 가변이어도 Swift 6 동시성 경고가 없다.
    private static var window: UIWindow?

    /// 비활성 진입 — 표지를 덮는다. 이미 덮여 있으면 아무것도 하지 않는다.
    static func cover() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                  .compactMap({ $0 as? UIWindowScene })
                  .first
        else { return }

        let host = UIHostingController(rootView: PrivacyCoverView())
        // 호스팅 뷰가 기본 투명일 수 있다 — 지면색을 명시해야 아래 화면이 비치지 않는다
        host.view.backgroundColor = UIColor(Ink.paper)

        let shield = UIWindow(windowScene: scene)
        shield.windowLevel = .alert + 1      // 시트·알럿보다 위
        shield.isUserInteractionEnabled = false   // 표지는 조작 대상이 아니다
        shield.rootViewController = host
        shield.isHidden = false
        window = shield
    }

    /// 복귀 — 표지를 걷는다.
    static func uncover() {
        window?.isHidden = true
        window = nil
    }
}

/// 중립 표지 — 지면 + 브랜드 표식만. 계절·주기·기록 어느 것도 그리지 않는다(§5.7 불변식).
/// 앱의 표지처럼 보여야 가림막으로 읽히지 않는다.
private struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()
            BrandMark(diameter: 34, color: Ink.text.opacity(0.45))
        }
    }
}
