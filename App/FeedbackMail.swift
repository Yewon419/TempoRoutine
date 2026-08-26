// 템포루틴 — 개발자에게 피드백 보내기 (2026-08-26 베타 "탭 하단부에 메세지 보내는 칸 같은거")
//
// 무서버 경계(§5.2)를 그대로 지킨다: 우리 서버로 보내는 게 아니라 **사용자의 메일 앱**을 열고,
// 보낼지 말지는 사용자가 그 화면에서 정한다. 기기에서 우리 쪽으로 자동으로 나가는 건 0이다.
// 받는 주소는 스토어 지원 연락처와 같은 주소 — 이미 공개된 창구라 새로 노출되는 정보가 없다.

import MessageUI
import SwiftUI
import UIKit

enum FeedbackMail {
    static let address = "windgarden419@gmail.com"

    static var subject: String { Loc.str("템포루틴 피드백") }

    /// 본문 = 사용자가 쓴 글 + 서명(버전·기기·OS). 서명은 재현에 필요한 최소치이고,
    /// 보내기 전 메일 화면에 그대로 보이므로 지우고 보낼 수도 있다.
    static func body(_ text: String) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let device = UIDevice.current.model
        let os = UIDevice.current.systemVersion
        return "\(text)\n\n---\n템포루틴 \(version) (\(build)) · \(device) · iOS \(os)"
    }

    /// 메일 앱을 못 쓰는 기기의 폴백 — mailto 링크
    static func mailtoURL(_ text: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body(text)),
        ]
        return components.url
    }
}

/// MFMailComposeViewController 래퍼 — 전송 여부는 완료 콜백으로만 알린다(본문은 우리가 안 읽는다).
struct FeedbackMailComposer: UIViewControllerRepresentable {
    let text: String
    let onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([FeedbackMail.address])
        controller.setSubject(FeedbackMail.subject)
        controller.setMessageBody(FeedbackMail.body(text), isHTML: false)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            onFinish(result == .sent)
        }
    }
}
