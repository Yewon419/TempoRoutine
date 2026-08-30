// 템포루틴 — CyclePredictor 테스트 (MASTER §5.6.1, T1~T16 = 25 assertions + T17~T18 백테스트)
// Playground Step1(아이폰 검증 25/25) 하니스의 XCTest 이식본 — 케이스·기대값 무변경.

import XCTest
@testable import TempoCore

final class CyclePredictorTests: XCTestCase {

    let cal = Calendar.current
    lazy var base: Date = cal.date(from: DateComponents(year: 2025, month: 1, day: 1))!
    func d(_ off: Int) -> Date { cal.date(byAdding: .day, value: off, to: base)! }
    var pred28: CyclePrediction { CyclePrediction(lastPeriodStart: d(0), averageLength: 28, confidence: .high) }

    // T1 averageLength (§5.6 개정 2026-07-31: 유효 gap [21,35] 필터 + 최근 5개 + 반올림)
    func testT1AverageLength() {
        XCTAssertEqual(CyclePredictor.averageLength(startDates: [d(0), d(28)]), 28, "T1 avg 28")
        XCTAssertEqual(CyclePredictor.averageLength(startDates: [d(0)]), 28, "T1 avg <2 → 28")
        // 이상치 gap 단독 = 유효 gap 0개 → 폴백 28 (구 계약: 클램프 35/21 — 개정으로 교체)
        XCTAssertEqual(CyclePredictor.averageLength(startDates: [d(0), d(60)]), 28, "T1 outlier-only long → 28")
        XCTAssertEqual(CyclePredictor.averageLength(startDates: [d(0), d(10)]), 28, "T1 outlier-only short → 28")
        // 기록 공백(56일 gap)은 평균에서 배제 — [28, 56, 28] → 유효 [28, 28] → 28
        XCTAssertEqual(CyclePredictor.averageLength(startDates: [d(0), d(28), d(84), d(112)]), 28,
                       "T1 공백 gap 배제")
        // 최근성 — 유효 gap 7개 [21×4, 30×3] 중 최근 5개 [21,21,30,30,30] → 26.4 → 26
        // (전 기간 평균이면 24.86 → 25로 갈라짐 — suffix(5) 적용을 고정하는 조합)
        XCTAssertEqual(CyclePredictor.averageLength(
            startDates: [d(0), d(21), d(42), d(63), d(84), d(114), d(144), d(174)]), 26, "T1 최근 5개 평균")
        // 반올림 — gaps [28, 29] → 28.5 → 29 (구 계약: 정수 절사 28)
        XCTAssertEqual(CyclePredictor.averageLength(startDates: [d(0), d(28), d(57)]), 29, "T1 반올림")
    }

    // T1b prior (개정 M 2026-08-08 — 온보딩 ②-4 보고값. 실측 gap 없을 때만, 실측이 생기면 무시)
    func testT1bPriorLength() {
        XCTAssertEqual(CyclePredictor.averageLength(startDates: [], priorLength: 30), 30, "T1b 기록 0 → prior")
        XCTAssertEqual(CyclePredictor.averageLength(startDates: [d(0)], priorLength: 30), 30, "T1b 기록 1 → prior")
        XCTAssertEqual(CyclePredictor.averageLength(startDates: [d(0), d(60)], priorLength: 30), 30,
                       "T1b 유효 gap 0 → prior")
        XCTAssertEqual(CyclePredictor.averageLength(startDates: [d(0), d(26)], priorLength: 30), 26,
                       "T1b 실측 gap 있으면 prior 무시")
        XCTAssertEqual(CyclePredictor.averageLength(startDates: [], priorLength: 40), 35, "T1b prior 클램프 상한")
        XCTAssertEqual(CyclePredictor.averageLength(startDates: [], priorLength: 10), 21, "T1b prior 클램프 하한")
        XCTAssertEqual(CyclePredictor.averageLength(startDates: []), 28, "T1b prior 없음 → 28 불변")
    }

    // T17 predictionErrors — 백테스트(2026-08-18 예측 오차 자가 표시). 산식 = analyze_export.py §2.
    func testT17PredictionErrors() {
        // [28, 29, 27] gap: k=2 예측 28 vs 실제 29 → +1 / k=3 예측 29(28.5 반올림) vs 27 → −2
        XCTAssertEqual(CyclePredictor.predictionErrors(startDates: [d(0), d(28), d(57), d(84)]),
                       [1, -2], "T17 기본 백테스트")
        // 무효 gap(60)은 표본 제외 — 예측은 하되 실제가 [21,35] 밖이면 안 센다
        XCTAssertEqual(CyclePredictor.predictionErrors(startDates: [d(0), d(28), d(88), d(116)]),
                       [0], "T17 무효 gap 배제")
        // 표본 부족 — 시작일 <3이면 빈 배열
        XCTAssertEqual(CyclePredictor.predictionErrors(startDates: [d(0), d(28)]), [], "T17 표본 부족")
        XCTAssertEqual(CyclePredictor.predictionErrors(startDates: []), [], "T17 기록 0")
        // 최근 5개 윈도 — 유효 오차 8개 [0,0,0,+7,+6,+4,+3,+1] → 뒤 5개만
        XCTAssertEqual(CyclePredictor.predictionErrors(
            startDates: [d(0), d(21), d(42), d(63), d(84), d(112), d(140), d(168), d(196), d(224)]),
                       [7, 6, 4, 3, 1], "T17 최근 5개 윈도")
    }

    // T18 predictionErrors + prior — 유효 gap 0 구간의 예측은 prior를 쓴다(T1b 경로 동일)
    func testT18PredictionErrorsPrior() {
        // history [0,60] = 유효 gap 0 → prior 30으로 예측 vs 실제 28 → −2
        XCTAssertEqual(CyclePredictor.predictionErrors(startDates: [d(0), d(60), d(88)], priorLength: 30),
                       [-2], "T18 prior 예측")
        XCTAssertEqual(CyclePredictor.predictionErrors(startDates: [d(0), d(60), d(88)]),
                       [0], "T18 prior 없음 → 28")
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

    // T2b 층 2 M 파라미터(개정 M) — M=7·N=28: 겨울 1~7, 봄이 남은 날을 흡수해 6~14 → 7~14
    func testT2b_menstrualLengthParameter() {
        let spans = CyclePredictor.phaseSpans(cycleLength: 28, menstrualLength: 7)
        XCTAssertEqual(spans[0], PhaseSpan(phase: .menstrual, startDay: 1, length: 7), "T2b 겨울 7일")
        XCTAssertEqual(spans[1], PhaseSpan(phase: .follicular, startDay: 8, length: 7), "T2b 봄 축소")
        XCTAssertEqual(spans[2], PhaseSpan(phase: .ovulation, startDay: 15, length: 3), "T2b 여름 불변")
        XCTAssertEqual(spans[3], PhaseSpan(phase: .luteal, startDay: 18, length: 11), "T2b 가을 불변")
        XCTAssertEqual(spans.map(\.length).reduce(0, +), 28, "T2b 합 = N")
        // 단계 판정도 같은 경계를 쓴다
        XCTAssertEqual(CyclePredictor.phaseForDay(6, cycleLength: 28, menstrualLength: 7), .menstrual)
        XCTAssertEqual(CyclePredictor.phaseForDay(6, cycleLength: 28), .follicular, "T2b 디폴트 5 불변")
        // 범위 밖 입력은 클램프(온보딩 입력 범위 [1,10])
        XCTAssertEqual(CyclePredictor.phaseSpans(cycleLength: 28, menstrualLength: 99)[0].length, 10)
    }

    // T2c 계절 일수 조정 전 그리드(2026-08-30) — n 15...40 × m 0...12(338조합) 불변식 5종.
    // 파이썬 미러 검사와 동일: ① 합 == n ② 전 구간 ≥1일 ③ 연속(간극·겹침 없음)
    // ④ 겨울 = 클램프된 m(짧은 주기 양보 미발동 시) ⑤ 매 일차가 정확히 1구간에 배정.
    func testT2c_phaseSpanGridInvariants() {
        for n in 15...40 {
            for mRaw in 0...12 {
                let spans = CyclePredictor.phaseSpans(cycleLength: n, menstrualLength: mRaw)
                XCTAssertEqual(spans.map(\.length).reduce(0, +), n, "n=\(n) m=\(mRaw) 합")
                XCTAssertTrue(spans.allSatisfy { $0.length >= 1 }, "n=\(n) m=\(mRaw) 0일 구간")
                var cursor = 1
                for span in spans {
                    XCTAssertEqual(span.startDay, cursor, "n=\(n) m=\(mRaw) \(span.phase) 연속성")
                    cursor = span.startDay + span.length
                }
                let mClamped = min(max(mRaw, 1), 10)
                if (n - 14) - mClamped >= 1 {   // 짧은 주기 양보 미발동 조건
                    XCTAssertEqual(spans[0].length, mClamped, "n=\(n) m=\(mRaw) 겨울 = m")
                }
                for d in 1...n {
                    let hits = spans.filter { d >= $0.startDay && d < $0.startDay + $0.length }
                    XCTAssertEqual(hits.count, 1, "n=\(n) m=\(mRaw) d=\(d) 배정")
                    XCTAssertEqual(CyclePredictor.phaseForDay(d, cycleLength: n, menstrualLength: mRaw),
                                   hits.first?.phase, "n=\(n) m=\(mRaw) d=\(d) phaseForDay 정합")
                }
            }
        }
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
