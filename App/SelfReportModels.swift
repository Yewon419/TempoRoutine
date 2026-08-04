// 템포루틴 — 앱 내 자기보고 설문 응답 저장 (v1.6 §4)
//
// **로컬 저장이 기본, 서버 전송은 별도 옵트인.** 기증 페이로드(주기당 충분통계량)와는
// 다른 종류의 데이터라 자동으로 포함되지 않는다.
// ⚠ 새 @Model이므로 TempoRoutineApp의 .modelContainer(for:) 배열에 등록돼 있어야 한다 —
// 빠뜨리면 컴파일은 통과하고 실기기에서 insert/@Query가 조용히 실패한다(repo CLAUDE.md).

import Foundation
import SwiftData
import TempoCore

@Model
final class SelfReportRecord {
    var id: UUID = UUID()
    /// [String: String] JSON. 복합 Codable을 저장 프로퍼티로 직접 두면 SwiftData가 깨진다(CLAUDE.md)
    var answersData: Data = Data()
    var completedAt: Date = Date()
    /// 서버 전송 옵트인 여부 — 기본 false. 켜기 전까지 응답은 기기 밖으로 나가지 않는다.
    var sharedToServer: Bool = false

    init(answers: [String: String]) {
        self.id = UUID()
        self.answersData = (try? JSONEncoder().encode(answers)) ?? Data()
        self.completedAt = .now
        self.sharedToServer = false
    }

    var answers: [String: String] {
        get { (try? JSONDecoder().decode([String: String].self, from: answersData)) ?? [:] }
        set { answersData = (try? JSONEncoder().encode(newValue)) ?? answersData }
    }

    var result: SelfReportResult { SelfReportScoring.score(answers) }
}

enum SelfReportStore {
    private static let promptedKey = "selfReportPrompted"

    /// 첫 주기 완료 시 1회만 제안한다(v1.6 §4) — 두 번 권하지 않는다.
    static var hasPrompted: Bool {
        get { UserDefaults.standard.bool(forKey: promptedKey) }
        set { UserDefaults.standard.set(newValue, forKey: promptedKey) }
    }

    /// 제안 조건: 주기를 한 번 이상 완주했고, 아직 답한 적 없고, 권한 적 없다.
    /// 첫 주기를 다 기록한 사람은 이탈 위험이 낮고, 침묵하는 문구의 이유를 이미 체감했다.
    static func shouldPrompt(snapshot: CycleSnapshot, records: [SelfReportRecord]) -> Bool {
        !hasPrompted && records.isEmpty && snapshot.starts.count >= 2
    }
}
