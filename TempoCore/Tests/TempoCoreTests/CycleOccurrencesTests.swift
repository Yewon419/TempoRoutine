// 템포루틴 — occurrence 열거 테스트 (MASTER §5.6.4·§5.5.3, T30~)

import XCTest
@testable import TempoCore

final class CycleOccurrencesTests: XCTestCase {

    private let cal = Calendar.current

    private func day(_ offset: Int) -> Date {
        cal.startOfDay(for: cal.date(byAdding: .day, value: offset, to: Date())!)
    }

    // T30: 기록 0개 → 창·occurrence 없음
    func testT30_emptyStarts() {
        XCTAssertEqual(CycleOccurrences.cycleWindows(periodStarts: [], averageLength: 28, horizonCycles: 2), [])
        let r = CycleRecurrence(anchor: .cycleStart, dayOffset: 0, repeatsEveryCycle: true, overflowRule: .clamp)
        XCTAssertEqual(CycleOccurrences.occurrences(of: r, createdAt: day(0), periodStarts: [],
                                                    averageLength: 28, horizonCycles: 2), [])
    }

    // T31: 창 열거 — 과거=실측(27·29), 현재=N, 미래 k≤지평(projected)
    func testT31_windowEnumeration() {
        let starts = [day(0), day(27), day(56)]   // 실측 갭 27, 29
        let windows = CycleOccurrences.cycleWindows(periodStarts: starts, averageLength: 28, horizonCycles: 2)
        XCTAssertEqual(windows.count, 5)
        XCTAssertEqual(windows[0], CycleWindow(start: day(0), length: 27, projected: false))
        XCTAssertEqual(windows[1], CycleWindow(start: day(27), length: 29, projected: false))
        XCTAssertEqual(windows[2], CycleWindow(start: day(56), length: 28, projected: false))
        XCTAssertEqual(windows[3], CycleWindow(start: day(84), length: 28, projected: true))
        XCTAssertEqual(windows[4], CycleWindow(start: day(112), length: 28, projected: true))
    }

    // T32: 매 주기 반복 — 창마다 시작+offset, 과거는 실측 길이 기준, 미래만 projected
    func testT32_repeatingOccurrences() {
        let starts = [day(0), day(27)]
        let r = CycleRecurrence(anchor: .cycleStart, dayOffset: 2, repeatsEveryCycle: true, overflowRule: .clamp)
        let occ = CycleOccurrences.occurrences(of: r, createdAt: day(0), periodStarts: starts,
                                               averageLength: 28, horizonCycles: 1)
        XCTAssertEqual(occ.map(\.date), [day(2), day(29), day(57)])
        XCTAssertEqual(occ.map(\.projected), [false, false, true])
    }

    // T33: overflow .skip — 배란기(3일) 밖 offset은 그 주기 미발생 → occurrence 0
    func testT33_skipDropsOccurrence() {
        let starts = [day(0)]
        let r = CycleRecurrence(anchor: .phase(.ovulation), dayOffset: 5, repeatsEveryCycle: true, overflowRule: .skip)
        let occ = CycleOccurrences.occurrences(of: r, createdAt: day(0), periodStarts: starts,
                                               averageLength: 28, horizonCycles: 1)
        XCTAssertEqual(occ, [])
    }

    // T34: one-shot 바인딩(§5.5.3) — createdAt 주기에서 resolve일이 이미 지났으면 다음 주기로 1회 이월
    func testT34_oneShotRollsToNextCycle() {
        let starts = [day(0)]
        let r = CycleRecurrence(anchor: .cycleStart, dayOffset: 2, repeatsEveryCycle: false, overflowRule: .clamp)
        let occ = CycleOccurrences.occurrences(of: r, createdAt: day(10), periodStarts: starts,
                                               averageLength: 28, horizonCycles: 2)
        XCTAssertEqual(occ.count, 1)
        XCTAssertEqual(occ[0].date, day(30))          // day(2)는 createdAt(10) 이전 → 다음 주기 28+2
        XCTAssertTrue(occ[0].projected)
    }

    // T34b: one-shot — resolve일이 createdAt 이후면 바인딩 주기 그대로
    func testT34b_oneShotStaysInBindingCycle() {
        let starts = [day(0)]
        let r = CycleRecurrence(anchor: .cycleStart, dayOffset: 20, repeatsEveryCycle: false, overflowRule: .clamp)
        let occ = CycleOccurrences.occurrences(of: r, createdAt: day(10), periodStarts: starts,
                                               averageLength: 28, horizonCycles: 2)
        XCTAssertEqual(occ.count, 1)
        XCTAssertEqual(occ[0].date, day(20))
        XCTAssertFalse(occ[0].projected)
    }

    // T35: one-shot의 .skip은 clamp로 해석(§5.5.3) — 배란기 밖 offset이 span 마지막 날로
    func testT35_oneShotSkipReadAsClamp() {
        let starts = [day(0)]
        let r = CycleRecurrence(anchor: .phase(.ovulation), dayOffset: 10, repeatsEveryCycle: false, overflowRule: .skip)
        let occ = CycleOccurrences.occurrences(of: r, createdAt: day(0), periodStarts: starts,
                                               averageLength: 28, horizonCycles: 1)
        XCTAssertEqual(occ.count, 1)
        // n=28: 배란기 = 15~17일차 → clamp = 17일차 = day(16)
        XCTAssertEqual(occ[0].date, day(16))
    }

    // T36: InputSchedule 커스텀 Codable 왕복 (§5.5.1 discriminator)
    func testT36_inputScheduleCodableRoundTrip() throws {
        let r = CycleRecurrence(anchor: .phase(.luteal), dayOffset: 3, repeatsEveryCycle: true, overflowRule: .carry)
        for original in [InputSchedule.daily, .weekly, .monthly, .cycleAnchored(r)] {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(InputSchedule.self, from: data)
            XCTAssertEqual(decoded, original)
        }
    }
}
