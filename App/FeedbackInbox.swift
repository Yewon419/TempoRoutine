// 템포루틴 — 피드백 직송(2026-08-31 대표님 지시 "메일 말고 바로 메세지처럼 보내지게")
//
// §5.2 무서버 경계의 명시적 개정: 소식란 피드백 한 경로에 한해 CloudKit **공개 DB**로
// 직접 저장한다. 별도 서버·키·비용 0 — 개발자는 CloudKit Dashboard(Public Database >
// Feedback 레코드)에서 읽는다. 나가는 것 = 사용자가 쓴 글 + 재현 서명(버전·기기·OS·언어·
// 테마)뿐, 식별자·기록 데이터는 싣지 않는다.
//
// ⚠ 공개 DB 쓰기도 iCloud 로그인이 필요하다 — 비로그인·네트워크 실패는 기존 메일 경로로
// 폴백한다(호출부). ⚠ 레코드 타입 `Feedback`은 **콘솔 스키마 프로덕션 배포가 선행**
// (repo CLAUDE.md — PlannerSync TRItem 오류 12 전례. JIT 생성은 개발 환경 전용).
// 사람 단계: Dashboard > Schema > Record Types에 Feedback(text/version/build/device/os/
// locale/theme: String) 생성 후 Deploy to Production.

import CloudKit
import SwiftUI
import UIKit

enum FeedbackInbox {
    private static let containerID = "iCloud.app.temporoutine.TempoRoutine"

    enum SendError: Error {
        case notSignedIn      // iCloud 비로그인 — 메일 폴백 대상
        case underlying(Error)
    }

    /// 공개 DB에 피드백 레코드 하나 저장. 성공 = 그대로 끝(개발자가 대시보드에서 읽는다).
    /// @MainActor — UIDevice.current(메인 격리) 서명 때문. 대기는 전부 await라 블로킹 없음.
    @MainActor
    static func send(_ text: String) async throws(SendError) {
        let container = CKContainer(identifier: containerID)
        let status = (try? await container.accountStatus()) ?? .couldNotDetermine
        guard status == .available else { throw .notSignedIn }

        let record = CKRecord(recordType: "Feedback")
        let info = Bundle.main.infoDictionary
        record["text"] = text
        record["version"] = info?["CFBundleShortVersionString"] as? String ?? "?"
        record["build"] = info?["CFBundleVersion"] as? String ?? "?"
        record["device"] = UIDevice.current.model
        record["os"] = UIDevice.current.systemVersion
        record["locale"] = Locale.current.identifier
        record["theme"] = ThemeStore.current.rawValue
        do {
            _ = try await container.publicCloudDatabase.save(record)
        } catch {
            throw .underlying(error)
        }
    }
}
