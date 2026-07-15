// 템포루틴 — CyclePredictor 테스트 (MASTER §5.6.1, T1~T16 = 25 assertions)
// Playground Step1(아이폰 검증 25/25) 하니스의 XCTest 이식본 — 케이스·기대값 무변경.

import XCTest
@testable import TempoCore

final class CyclePredictorTests: XCTestCase {

    let cal = Calendar.current
    lazy var base: Date = cal.date(from: DateComponents(year: 2025, month: 1, day: 1))!
    func d(_ off: Int) -> Date { cal.date(byAdding: .day, value: off, to: base)! }
    var pred28: CyclePrediction { CyclePrediction(lastPeriodStart: d(0), averageLength: 28, confidence: .high) }

    // T1 averageLength
    func testT1AverageLength() {
        XCTAssertEqual(CyclePredictor.averageLength(startDates: [d(0), d(28)]), 28, "T1 avg 28")
        XCTAssertEqual(CyclePredictor.averageLength(startDates: [d(0)]), 28, "T1 avg <2 → 28")
        XCTAssertEqual(CyclePredictor.averageLength(startDates: [d(0), d(60)]), 35, "T1 avg clamp 35")
        XCTAssertEqual(CyclePredictor.averageLength(startDates: [d(0), d(10)]), 21, "T1 avg clamp 21")
    }

    // T2 phaseSpans(28)
    func testT2PhaseSpans28() {
        XCTAssertEqual(CyclePredictor.phaseSpans(cycleLength: 28), [
            PhaseSpan(phase: .menstrual,  startDay: 1,  length: 5),
            PhaseSpan(phase: .follicular, startDay: 6,  length: 9),
            PhaseSpan(phase: .ovulation,  startDay: 15, length: 3),
            PhaseSpan(phase: .luteal,     startDay: 18, length: 11),
        ], "T2 spans28")
    }

    // T3 phaseSpans(35) — 봄만 늘어남
    func testT3PhaseSpans35() {
        XCTAssertEqual(CyclePredictor.phaseSpans(cycleLength: 35)[1],
                       PhaseSpan(phase: .follicular, startDay: 6, length: 16),
                       "T3 spans35 follicular 6·16")
    }

    // T4 phaseSpans(21)
    func testT4PhaseSpans21() {
        let s21 = CyclePredictor.phaseSpans(cycleLength: 21)
        XCTAssertEqual(s21.reduce(0) { $0 + $1.length }, 21, "T4 spans21 sum=21")
        XCTAssertEqual(s21[1], PhaseSpan(phase: .follicular, startDay: 6, length: 2), "T4 spans21 follicular 6·2")
    }

    // T5 phaseForDay(28)
    func testT5PhaseForDay() {
        XCTAssertEqual(CyclePredictor.phaseForDay(1,  cycleLength: 28), .menstrual, "T5 day1 menstrual")
        XCTAssertEqual(CyclePredictor.phaseForDay(15, cycleLength: 28), .ovulation, "T5 day15 ovulation")
        XCTAssertEqual(CyclePredictor.phaseForDay(28, cycleLength: 28), .luteal, "T5 day28 luteal")
    }

    // T6 resolve 정상: luteal(start18) + 2 = day20
    func testT6ResolveLutealOffset() {
        let r = CycleRecurrence(anchor: .phase(.luteal), dayOffset: 2, repeatsEveryCycle: true, overflowRule: .clamp)
        XCTAssertEqual(CyclePredictor.resolveDate(recurrence: r, cycleStart: d(0), prediction: pred28), d(19), "T6 luteal+2 → day20")
    }

    // T7 overflow clamp: ovulation(len3) +5 → 마지막 day17
    func testT7OverflowClamp() {
        let r = CycleRecurrence(anchor: .phase(.ovulation), dayOffset: 5, repeatsEveryCycle: true, overflowRule: .clamp)
        XCTAssertEqual(CyclePredictor.resolveDate(recurrence: r, cycleStart: d(0), prediction: pred28), d(16), "T7 clamp → day17")
    }

    // T8 overflow skip → nil
    func testT8OverflowSkip() {
        let r = CycleRecurrence(anchor: .phase(.ovulation), dayOffset: 5, repeatsEveryCycle: true, overflowRule: .skip)
        XCTAssertNil(CyclePredictor.resolveDate(recurrence: r, cycleStart: d(0), prediction: pred28), "T8 skip → nil")
    }

    // T9 overflow carry: 15+5 = day20 (황체로 이월)
    func testT9OverflowCarry() {
        let r = CycleRecurrence(anchor: .phase(.ovulation), dayOffset: 5, repeatsEveryCycle: true, overflowRule: .carry)
        XCTAssertEqual(CyclePredictor.resolveDate(recurrence: r, cycleStart: d(0), prediction: pred28), d(19), "T9 carry → day20")
    }

    // T10 cycleStart +0 → cycleStart
    func testT10CycleStartZero() {
        let r = CycleRecurrence(anchor: .cycleStart, dayOffset: 0, repeatsEveryCycle: true, overflowRule: .clamp)
        XCTAssertEqual(CyclePredictor.resolveDate(recurrence: r, cycleStart: d(0), prediction: pred28), d(0), "T10 cycleStart+0 → day1")
    }

    // T11 carry 주기초과 → day28 클램프
    func testT11CarryPastCycle() {
        let r = CycleRecurrence(anchor: .cycleStart, dayOffset: 40, repeatsEveryCycle: true, overflowRule: .carry)
        XCTAssertEqual(CyclePredictor.resolveDate(recurrence: r, cycleStart: d(0), prediction: pred28), d(27), "T11 carry past N → day28")
    }

    // T12 cycleDay 과거 실주기: [d0, d0+33], date d0+30 → day31, projected=false
    func testT12PastRealCycle() {
        XCTAssertEqual(CyclePredictor.cycleDay(of: d(30), periodStarts: [d(0), d(33)], averageLength: 28),
                       DayResolution(day: 31, projected: false),
                       "T12 past real cycle → day31 projected=false")
    }

    // T13 cycleDay 미래 투영: [d0], date d0+31 → day4, projected=true
    func testT13FutureProjection() {
        XCTAssertEqual(CyclePredictor.cycleDay(of: d(31), periodStarts: [d(0)], averageLength: 28),
                       DayResolution(day: 4, projected: true),
                       "T13 future projection → day4 projected=true")
    }

    // T14 isOverdue
    func testT14Overdue() {
        XCTAssertTrue(CyclePredictor.isOverdue(on: d(30), periodStarts: [d(0)], averageLength: 28), "T14 overdue true")
        XCTAssertFalse(CyclePredictor.isOverdue(on: d(20), periodStarts: [d(0)], averageLength: 28), "T14 not overdue")
    }

    // T15 S0 콜드스타트 → nil
    func testT15ColdStart() {
        XCTAssertNil(CyclePredictor.phase(on: d(5), periodStarts: [], averageLength: 28), "T15 cold start → nil")
    }

    // T16 confidence
    func testT16Confidence() {
        XCTAssertEqual(CyclePredictor.confidence(periodStarts: [d(0), d(28), d(56), d(84)]), .high, "T16 conf high (regular 4)")
        XCTAssertEqual(CyclePredictor.confidence(periodStarts: [d(0), d(25), d(61)]), .low, "T16 conf low (spread>7)")
        XCTAssertEqual(CyclePredictor.confidence(periodStarts: [d(0), d(28)]), .medium, "T16 conf medium (2 logs)")
    }
}
