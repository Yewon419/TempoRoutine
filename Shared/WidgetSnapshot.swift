// 템포루틴 — 앱 ↔ 위젯 스냅샷 계약 (위젯 Phase 1, 2026-07-27)
// 위젯은 SwiftData를 읽지 않는다 — 앱이 App Group에 쓰는 이 JSON이 유일한 데이터 통로.
// (스토어를 App Group으로 옮기는 안은 기각: 2026-07-24 split-brain 이력 — 스토어 위치 변경 금지)
// 문구·계산은 전부 앱이 한다 — 위젯엔 주기 로직이 없어야 문구 드리프트가 없다.
// 이 파일은 앱·위젯 두 타깃에 같이 컴파일된다(project.yml sources: Shared).

import Foundation

enum WidgetShared {
    static let appGroupID = "group.app.temporoutine.TempoRoutine"
    static let snapshotFilename = "widget-snapshot.json"

    static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(snapshotFilename)
    }
}

/// 하루치 표시 내용 — 위젯은 이 문자열들을 그대로 그린다
struct WidgetDay: Codable {
    let day: Date          // startOfDay
    let season: String?    // winter/spring/summer/autumn — 글리프·잉크색 키. nil = 계절 없음
    let title: String      // "겨울" / S0 "템포루틴"
    let sub: String        // "월경기 3일차 · 예상" / S0 "기록하면 계절이 채워져요"
    let inline: String     // 잠금화면 inline 한 줄 — "겨울 3일차" / "템포루틴"
    let mood: String?      // 무드라인(소형 위젯 하단)
    let projected: Bool    // 예상 = faded(§8.1 상태 어휘)
}

struct WidgetSnapshot: Codable {
    let generatedAt: Date
    let days: [WidgetDay]

    func entry(for date: Date, calendar: Calendar = .current) -> WidgetDay? {
        let target = calendar.startOfDay(for: date)
        return days.first { calendar.isDate($0.day, inSameDayAs: target) }
    }

    static func load() -> WidgetSnapshot? {
        guard let url = WidgetShared.snapshotURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
