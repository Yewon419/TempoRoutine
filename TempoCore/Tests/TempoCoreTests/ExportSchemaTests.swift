// 템포루틴 — 직렬화 테스트 (MASTER §5.5.1, T40~)

import XCTest
@testable import TempoCore

final class ExportSchemaTests: XCTestCase {

    private func sampleEnvelope() -> ExportEnvelopeV1 {
        let r = CycleRecurrence(anchor: .phase(.luteal), dayOffset: 2, repeatsEveryCycle: true, overflowRule: .clamp)
        let itemID = UUID()
        return ExportEnvelopeV1(
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000),
            periodDays: [PeriodDayDTO(day: "2026-07-01", origin: "local", healthKitUUID: nil)],
            scheduleItems: [ScheduleItemDTO(id: UUID(), title: "병원 예약", date: "2026-07-15",
                                            isAllDay: true, repeatRule: .none,
                                            createdAt: Date(timeIntervalSince1970: 1_799_000_000))],
            inputItems: [InputItemDTO(id: itemID, title: "가볍게 걷기", category: .exercise,
                                      schedule: .cycleAnchored(r),
                                      createdAt: Date(timeIntervalSince1970: 1_799_000_000))],
            outputItems: [OutputItemDTO(id: UUID(), title: "자격증 공부", recurrence: r, progressKind: .subtasks,
                                        subtasks: [OutputSubtaskDTO(id: UUID(), title: "1챕터", isDone: true, order: 0)],
                                        targetSessions: 0, loggedSessions: 0, percent: 0,
                                        createdAt: Date(timeIntervalSince1970: 1_799_000_000))],
            completions: [ItemCompletionDTO(id: UUID(), itemID: itemID, occurredOn: "2026-07-02",
                                            completedAt: Date(timeIntervalSince1970: 1_799_100_000))],
            checkIns: [DailyCheckInDTO(id: UUID(), day: "2026-07-02", energy: 3, mood: 5,
                                       sleep: 1, pain: nil, appetite: nil, note: "짧게",
                                       createdAt: Date(timeIntervalSince1970: 1_799_100_000))],
            trackedSignals: TrackedSignals(sleep: true, pain: false, appetite: false, note: true)
        )
    }

    // T40: 봉투 왕복 — DTO 전 필드 보존 (UUID·연관값 enum 포함)
    func testT40_envelopeRoundTrip() throws {
        let original = sampleEnvelope()
        let data = try ExportCodec.encode(original)
        let decoded = try ExportCodec.decode(data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.schemaVersion, 1)
    }

    // T41: date-only 왕복 — dayString → day 복원이 start-of-day로 안정
    func testT41_dayStringRoundTrip() {
        let today = Calendar.current.startOfDay(for: .now)
        let s = ExportCodec.dayString(today)
        XCTAssertTrue(s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil)
        XCTAssertEqual(ExportCodec.day(from: s), today)
    }

    // T42: 더 최신 백업 거부(§5.5.1 버전 규칙)
    func testT42_newerVersionRejected() throws {
        var envelope = sampleEnvelope()
        envelope.schemaVersion = 2
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)
        XCTAssertThrowsError(try ExportCodec.decode(data)) { error in
            XCTAssertEqual(error as? ExportCodec.CodecError, .newerVersion(2))
        }
    }

    // T43: 손상 파일 → corrupt
    func testT43_corruptRejected() {
        XCTAssertThrowsError(try ExportCodec.decode(Data("{}".utf8))) { error in
            XCTAssertEqual(error as? ExportCodec.CodecError, .corrupt)
        }
        XCTAssertThrowsError(try ExportCodec.decode(Data("생리".utf8)))
    }

    // T44: 시간 지정 일정 instant 왕복
    func testT44_instantRoundTrip() {
        let now = Date(timeIntervalSince1970: 1_800_000_123)
        let s = ExportCodec.instantString(now)
        XCTAssertEqual(ExportCodec.instant(from: s), now)
    }
}
