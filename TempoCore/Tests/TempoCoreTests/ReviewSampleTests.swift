// 템포루틴 — 심사용 샘플 백업 검증 (2026-08-24)
//
// 왜 있나: `tools/review-sample-backup.json`은 App Review 심사자가 「설정 > 백업 가져오기」로
// 불러 화면을 채우는 파일이다(심사준비 §7). 이 파일의 스키마가 어긋나 있으면 심사자가
// 가져오기에 실패하고, 그건 Guideline 2.1(기능을 확인할 수 없음)로 직결된다.
//
// 원래는 실기기에서 한 번 가져와 보는 게 확인 절차였는데, 가져오기는 **덮어쓰기가 아니라
// 병합**이라(`ExportImport.merge`) 실사용 기기에 합성 생리·체크인이 섞이고 체크인은
// 동기화까지 타고 넘어간다. 그래서 기기 대신 여기서 검증한다 — 진짜 위험은 파일 쪽
// 스키마고, 파일 선택기 경로는 기존 백업 가져오기 기능과 같은 코드다.
//
// 건수를 정확히 박지 않고 하한만 본다 — 생성기를 다른 시드·기준일로 다시 돌려도 「심사자
// 화면이 채워진다」는 성질은 그대로여야 한다.

import XCTest
@testable import TempoCore

final class ReviewSampleTests: XCTestCase {

    /// 리포 루트의 tools/review-sample-backup.json
    private func sampleURL() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }   // …/TempoCoreTests → Tests → TempoCore → 루트
        return url.appendingPathComponent("tools/review-sample-backup.json")
    }

    private func loadSample() throws -> ExportEnvelopeV1 {
        let url = sampleURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("샘플 파일 없음: \(url.path)")
        }
        return try ExportCodec.decode(try Data(contentsOf: url))
    }

    // 앱과 같은 디코더로 실제로 읽힌다
    func testSampleDecodes() throws {
        let envelope = try loadSample()
        XCTAssertEqual(envelope.schemaVersion, 1)
    }

    // 인사이트 화면(나의 템포·예측)이 켜질 만큼의 표본
    func testSampleFillsInsightScreens() throws {
        let envelope = try loadSample()
        XCTAssertGreaterThanOrEqual(envelope.periodDays.count, 15,
                                    "주기가 여러 번 있어야 사계·예측이 켜진다")
        XCTAssertGreaterThanOrEqual(envelope.checkIns.count, 60,
                                    "체크인이 얇으면 「패턴은 아직 또렷하지 않아요」로 떨어진다")
        // 날짜 키가 전부 파싱돼야 한다 — 하나라도 어긋나면 그 기록은 조용히 버려진다
        for day in envelope.periodDays {
            XCTAssertNotNil(ExportCodec.day(from: day.day), "생리 기록 날짜 파싱 실패: \(day.day)")
        }
        for checkIn in envelope.checkIns {
            XCTAssertNotNil(ExportCodec.day(from: checkIn.day), "체크인 날짜 파싱 실패: \(checkIn.day)")
        }
    }

    // 오늘 탭(스토어 프레이밍의 리드 = 플래너)이 비지 않는다
    func testSampleFillsPlanner() throws {
        let envelope = try loadSample()
        XCTAssertGreaterThanOrEqual(envelope.scheduleItems.count, 3)
        XCTAssertGreaterThanOrEqual(envelope.inputItems.count, 3)
        XCTAssertGreaterThanOrEqual(envelope.outputItems.count, 3)
        XCTAssertGreaterThanOrEqual(envelope.completions.count, 20,
                                    "루틴 체크가 있어야 캘린더 완료 표시가 뜬다")

        // 심사 시점이 언제든 보이려면 반복 항목이 있어야 한다(단발만 있으면 지나간다)
        let repeating = envelope.scheduleItems.contains { $0.repeatRule != ScheduleRepeat.none }
        XCTAssertTrue(repeating, "반복 일정이 없으면 심사일에 오늘 탭이 빈다")
        let dailyInput = envelope.inputItems.contains { $0.schedule == .daily }
        XCTAssertTrue(dailyInput, "매일 루틴이 없으면 심사일에 오늘 탭이 빈다")
        let openGoal = envelope.outputItems.contains { $0.schedule == .once }
        XCTAssertTrue(openGoal, "`.once` 목표는 완료까지 계속 표시된다 — 날짜와 무관한 표면")

        // 날짜 표기 규칙(§5.5): 종일은 "yyyy-MM-dd", 시각 있는 건 ISO8601 instant
        for item in envelope.scheduleItems {
            if item.isAllDay {
                XCTAssertNotNil(ExportCodec.day(from: item.date), "종일 일정 날짜 파싱 실패: \(item.date)")
            } else {
                XCTAssertNotNil(ExportCodec.instant(from: item.date), "일정 시각 파싱 실패: \(item.date)")
            }
        }

        // 진행도가 눈에 보이는 항목이 있어야 「쓰고 있는 앱」으로 읽힌다
        let inProgress = envelope.outputItems.contains {
            $0.percent > 0 || $0.loggedSessions > 0 || $0.subtasks.contains(where: \.isDone)
        }
        XCTAssertTrue(inProgress, "진행 중인 목표가 하나도 없으면 전부 시작 전으로 보인다")
    }

    // 씨앗 → 테마 구매 흐름을 심사자가 직접 눌러볼 수 있다
    func testSampleLetsReviewerBuyATheme() throws {
        let envelope = try loadSample()
        let ledger = try XCTUnwrap(envelope.seedLedger, "씨앗 원장이 없으면 테마 구매를 못 본다")
        XCTAssertGreaterThanOrEqual(ledger.earnedDays?.count ?? 0, 7,
                                    "테마 한 벌 값(씨앗 7개)보다 많아야 한다")
        XCTAssertTrue(ledger.purchases.isEmpty,
                      "이미 사둔 상태로 주면 구매를 눌러볼 수 없다")
    }

    // 대표님 실제 기록이 섞여 들어가지 않았다 — 이 파일은 심사자에게 나간다
    func testSampleCarriesNoNotes() throws {
        let envelope = try loadSample()
        for checkIn in envelope.checkIns {
            XCTAssertNil(checkIn.note, "합성 표본에 한 줄 기록이 있으면 실제 기록이 섞인 것이다")
        }
        XCTAssertTrue((envelope.selfReports ?? []).isEmpty,
                      "설문 응답은 합성 대상이 아니다 — 들어 있으면 실제 응답이다")
    }
}
