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

/// 일정 한 줄 — 오늘 일정 위젯용(Phase 2)
struct WidgetScheduleLine: Codable {
    let time: String       // "종일" / "저녁 7:00"
    let title: String      // 여러 날이면 "제주 여행 · 2/3일차"로 앱이 합성
}

/// Input 한 줄 — 오늘 카드 위젯용(2026-07-27 개편)
struct WidgetCheckLine: Codable {
    let title: String
    let done: Bool
    /// 항목 식별자(2026-08-02 A단계) — B단계 체크 큐가 어떤 항목인지 지목하려면 필수.
    /// optional = 구 스냅샷 JSON 호환(계약 규칙: 추가만, 변경 금지)
    var id: UUID?
}

/// Output 한 줄 — 진행 라벨은 앱이 합성("60%" / "2/3")
struct WidgetProgressLine: Codable {
    let title: String
    let label: String
    let fraction: Double   // 0...1
    var id: UUID?
    /// 진행 방식 — OutputProgressKind rawValue("percent"/"sessions"/"subtasks").
    /// 위젯은 이걸로 표기만 가른다(주기 로직 없음 원칙 유지). B단계 인터랙션 분기도 여기서.
    var kind: String?
    /// 목표일 배지 문구 — "D-3"/"D-DAY"/"D+2". 계산은 앱이 한다(§8.2.8 문구 드리프트 방지).
    /// 기준일 = 그 엔트리의 날짜(앱 DDayBadge와 동형: 하루 상세에서 과거를 보면 그날 기준)
    var dday: String?
}

/// 하루치 표시 내용 — 위젯은 이 문자열들을 그대로 그린다.
/// Phase 2 추가 필드는 전부 optional — 구 스냅샷 JSON도 그대로 디코드된다(추가만, 변경 금지).
struct WidgetDay: Codable {
    let day: Date          // startOfDay
    let season: String?    // winter/spring/summer/autumn — 글리프·잉크색 키. nil = 계절 없음
    let title: String      // "겨울" / S0 "템포루틴"
    let sub: String        // "월경기 3일차 · 예상" / S0 "기록하면 계절이 채워져요"
    let inline: String     // 잠금화면 inline 한 줄 — "겨울 3일차" / "템포루틴"
    let mood: String?      // 무드라인(소형 위젯 하단)
    let projected: Bool    // 예상 = faded(§8.1 상태 어휘)
    var recorded: Bool?    // 생리 기록일 = 코랄 형광펜(주간 스트립, Phase 2)
    var predicted: Bool?   // 예상 생리일 = 회색 형광펜(미래만 — §5.6.2 소급 투영 금지)
    var schedules: [WidgetScheduleLine]?   // 그날 일정(로컬만 — EventKit 오버레이는 런타임 전용이라 제외)
    var inputs: [WidgetCheckLine]?         // 그날 Input(오늘 카드, 2026-07-27)
    var outputs: [WidgetProgressLine]?     // 그날 Output
    // 총계(2026-08-02 A단계) — 위 배열은 위젯 예산 때문에 잘려 있다. 카운터·잠금화면 요약이
    // 잘린 배열을 세면 "다 챙겼어요"가 거짓이 된다(5번째가 미완인데 상위 4개만 완료인 날).
    var inputTotal: Int?
    var inputDone: Int?
    var outputTotal: Int?
    /// 주기 진행 0...1(플레이리스트 미니 시크바, 2026-08-19). optional 추가만 — 계약 규칙.
    var cycleProgress: Double?
}

struct WidgetSnapshot: Codable {
    let generatedAt: Date
    let days: [WidgetDay]
    /// 테마 키(2026-07-29 테마 시스템 Phase 5) — "standard"/"modern". optional 추가만(계약 규칙)
    var theme: String? = nil
    /// 포인트컬러의 선택 색(2026-08-17) — "vermilion"/"skyBlue"/… . 다른 테마에서는 안 읽힌다.
    /// 테마 키와 따로 싣는 이유: 색은 테마 안의 선택지라 theme 문자열에 섞으면
    /// 기존 설치의 스냅샷("modern")을 못 읽게 된다. optional 추가만 — 계약 규칙.
    var pointColor: String? = nil

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
