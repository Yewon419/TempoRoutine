// 축 엔진 테스트 (MASTER §5.12) — 이식본이 아니라 신규 구현이라 처음부터 붙인다.
// 특히 두 가지를 못 지나가게 막는다: ① 계열 방향 뒤집기 ② 칼만 분산이 0으로 굳는 것.

import XCTest
@testable import TempoCore

final class SignalConversionTests: XCTestCase {

    /// mood는 "높을수록 좋음"이라 뒤집혀야 한다 — 흐림(1)이 가장 힘든 값(5)이 된다.
    func testMoodIsFlipped() {
        XCTAssertEqual(SignalConversion.emotional(mood: 1, irritability: nil), 5)
        XCTAssertEqual(SignalConversion.emotional(mood: 5, irritability: nil), 1)
    }

    /// irritability는 "높을수록 나쁨"이라 그대로 간다 — 뒤집으면 부호가 반대가 된다.
    func testIrritabilityIsNotFlipped() {
        XCTAssertEqual(SignalConversion.emotional(mood: nil, irritability: 5), 5)
        XCTAssertEqual(SignalConversion.emotional(mood: nil, irritability: 1), 1)
    }

    /// 둘 다 있으면 평균 — 흐림(1→5)과 날카로움(5)이면 둘 다 힘든 쪽이라 5여야 한다.
    func testEmotionalAveragesBothItems() {
        XCTAssertEqual(SignalConversion.emotional(mood: 1, irritability: 5), 5)
        XCTAssertEqual(SignalConversion.emotional(mood: 5, irritability: 1), 1)
        XCTAssertEqual(SignalConversion.emotional(mood: 3, irritability: 3), 3)
    }

    /// pain UI는 "불편해요(1) ~ 괜찮아요(5)" — 불편감은 역방향이다.
    func testBodilyIsFlipped() {
        XCTAssertEqual(SignalConversion.bodily(pain: 1), 5)   // 불편해요 → 가장 힘듦
        XCTAssertEqual(SignalConversion.bodily(pain: 5), 1)   // 괜찮아요 → 가장 안 힘듦
    }

    func testUnrecordedIsNil() {
        XCTAssertNil(SignalConversion.emotional(mood: 0, irritability: 0))
        XCTAssertNil(SignalConversion.emotional(mood: nil, irritability: nil))
        XCTAssertNil(SignalConversion.bodily(pain: 0))
        XCTAssertNil(SignalConversion.bodily(pain: 9))
    }
}

final class HarmonicFitTests: XCTestCase {

    private func cycle(length: Int, value: (Int) -> Double) -> [DailySignal] {
        (1...length).map { day in
            DailySignal(cycleDay: day, cycleLength: length,
                        emotional: value(day), bodily: nil)
        }
    }

    /// 알려진 사인파를 넣으면 진폭이 복원돼야 한다. 잡음이 없어 보정도 거의 안 깎는다.
    func testRecoversKnownAmplitude() throws {
        let length = 28
        let signals = cycle(length: length) { day in
            let theta = 2 * Double.pi * Double(day - 1) / Double(length)
            return 3.0 + 1.5 * cos(theta)
        }
        let result = try XCTUnwrap(HarmonicFit.fitEmotional(signals))
        XCTAssertEqual(result.mean, 3.0, accuracy: 0.01)
        XCTAssertEqual(result.amplitude, 1.5, accuracy: 0.01)
        XCTAssertEqual(result.phase, 0, accuracy: 0.01)
    }

    /// 상수 입력 = 변동 없음 → 진폭 0. 여기서 분산이 0이 되는 게 칼만 붕괴의 입구다.
    func testConstantInputGivesZeroAmplitude() throws {
        let signals = cycle(length: 28) { _ in 3.0 }
        let result = try XCTUnwrap(HarmonicFit.fitEmotional(signals))
        XCTAssertEqual(result.amplitude, 0, accuracy: 1e-9)
    }

    /// 표본이 모자라면 적합하지 않는다 — 억지로 맞추면 진폭이 과대 추정된다.
    func testTooFewSamplesReturnsNil() {
        let signals = (1...3).map {
            DailySignal(cycleDay: $0, cycleLength: 28, emotional: Double($0), bodily: nil)
        }
        XCTAssertNil(HarmonicFit.fitEmotional(signals))
    }

    /// 편향 보정 — 순수 잡음만 넣으면 진폭이 0으로 깎여야 한다(과대 추정 방지).
    func testNoiseOnlyIsCorrectedDown() throws {
        let length = 28
        // 결정론적 의사잡음(테스트 재현성). 주기 성분이 없다.
        let signals = cycle(length: length) { day in
            3.0 + (Double((day * 7919) % 13) - 6) * 0.05
        }
        let result = try XCTUnwrap(HarmonicFit.fitEmotional(signals))
        XCTAssertLessThan(result.amplitude, 0.2)
    }

    /// 소급 입력은 가중치가 낮다 — 같은 날 값을 흔들어도 적합이 덜 끌려간다.
    func testBackfilledSamplesWeighLess() throws {
        let length = 28
        func build(backfilledOutlier: Bool) -> [DailySignal] {
            (1...length).map { day in
                let theta = 2 * Double.pi * Double(day - 1) / Double(length)
                let base = 3.0 + 1.0 * cos(theta)
                let isOutlier = day == 14
                return DailySignal(cycleDay: day, cycleLength: length,
                                   emotional: isOutlier ? base + 4 : base, bodily: nil,
                                   isBackfilled: isOutlier && backfilledOutlier)
            }
        }
        let weighted = try XCTUnwrap(HarmonicFit.fitEmotional(build(backfilledOutlier: true)))
        let full = try XCTUnwrap(HarmonicFit.fitEmotional(build(backfilledOutlier: false)))
        // 이상치가 평균을 끌어올리는데, 소급이면 덜 끌어올려야 한다
        XCTAssertLessThan(weighted.mean, full.mean)
    }
}

final class AxisEstimatorTests: XCTestCase {

    private func cycle(length: Int = 28, amplitude: Double, bodilyMean: Double? = nil) -> [DailySignal] {
        (1...length).map { day in
            let theta = 2 * Double.pi * Double(day - 1) / Double(length)
            return DailySignal(cycleDay: day, cycleLength: length,
                               emotional: 3.0 + amplitude * cos(theta),
                               bodily: bodilyMean.map { $0 + amplitude * 0.2 * cos(theta) })
        }
    }

    /// ★ 칼만 붕괴 방지 — 상수 입력(진폭 0)을 아무리 많이 넣어도 분산이 0이 되면 안 된다.
    /// 0이 되는 순간 K=1로 굳어 이후 관측을 전부 무시한다.
    func testVarianceNeverCollapsesToZero() throws {
        let flat = (1...28).map {
            DailySignal(cycleDay: $0, cycleLength: 28, emotional: 3.0, bodily: nil)
        }
        var state: AxisState?
        for _ in 0..<12 {
            state = AxisEstimator.update(state: state, cycle: flat)
        }
        let final = try XCTUnwrap(state)
        XCTAssertGreaterThanOrEqual(final.variance, AxisEstimator.minStateVariance)
        XCTAssertGreaterThan(final.variance, 0)
        XCTAssertEqual(final.observedCycles, 12)
    }

    /// 상태가 굳지 않았다는 증거 — 평탄한 주기를 12번 본 뒤에도 큰 진폭 관측을 반영해야 한다.
    func testStillRespondsAfterManyFlatCycles() throws {
        let flat = (1...28).map {
            DailySignal(cycleDay: $0, cycleLength: 28, emotional: 3.0, bodily: nil)
        }
        var state: AxisState?
        for _ in 0..<12 { state = AxisEstimator.update(state: state, cycle: flat) }
        let before = try XCTUnwrap(state).amplitude
        state = AxisEstimator.update(state: state, cycle: cycle(amplitude: 2.0))
        XCTAssertGreaterThan(try XCTUnwrap(state).amplitude, before)
    }

    /// 큰 진폭이 반복되면 비바체로 수렴한다.
    func testLargeAmplitudeConvergesToVivace() throws {
        var state: AxisState?
        for _ in 0..<6 { state = AxisEstimator.update(state: state, cycle: cycle(amplitude: 2.0)) }
        XCTAssertEqual(AxisEstimator.classify(try XCTUnwrap(state)), .vivace)
    }

    /// 진폭이 사실상 0이면 안단테 — Φ(0/σ)=0.5 미만 쪽으로 떨어진다.
    func testFlatConvergesToAndante() throws {
        let flat = (1...28).map {
            DailySignal(cycleDay: $0, cycleLength: 28, emotional: 3.0, bodily: nil)
        }
        var state: AxisState?
        for _ in 0..<6 { state = AxisEstimator.update(state: state, cycle: flat) }
        XCTAssertEqual(AxisEstimator.classify(try XCTUnwrap(state)), .andante)
    }

    /// 루바토 경계 — Φ가 [0.5, 0.85)면 아직 정하지 않는다.
    func testRubatoBand() {
        let borderline = AxisState(amplitude: 0.35, variance: 0.5, modality: 0, observedCycles: 3)
        let phi = AxisEstimator.confidence(borderline)
        XCTAssertGreaterThanOrEqual(phi, AxisEstimator.rubatoLowerBound)
        XCTAssertLessThan(phi, AxisEstimator.rubatoUpperBound)
        XCTAssertEqual(AxisEstimator.classify(borderline), .rubato)
    }

    /// M축 부호 — 정서가 신체보다 힘들면 양수(마음이 먼저 신호를 보내는 편).
    func testModalitySign() throws {
        let emotionalHeavy = (1...28).map {
            DailySignal(cycleDay: $0, cycleLength: 28, emotional: 4.0, bodily: 2.0)
        }
        let state = try XCTUnwrap(AxisEstimator.update(state: nil, cycle: emotionalHeavy))
        XCTAssertGreaterThan(state.modality, 0)

        let bodilyHeavy = (1...28).map {
            DailySignal(cycleDay: $0, cycleLength: 28, emotional: 2.0, bodily: 4.0)
        }
        let state2 = try XCTUnwrap(AxisEstimator.update(state: nil, cycle: bodilyHeavy))
        XCTAssertLessThan(state2.modality, 0)
    }

    /// 표본이 모자란 주기는 상태를 망가뜨리지 않고 그대로 통과시킨다.
    func testInsufficientCycleKeepsPreviousState() throws {
        var state = AxisEstimator.update(state: nil, cycle: cycle(amplitude: 1.5))
        let before = try XCTUnwrap(state)
        let sparse = [DailySignal(cycleDay: 1, cycleLength: 28, emotional: 3, bodily: nil)]
        state = AxisEstimator.update(state: state, cycle: sparse)
        XCTAssertEqual(try XCTUnwrap(state), before)
    }

    func testNormalCDFKnownValues() {
        XCTAssertEqual(AxisEstimator.normalCDF(0), 0.5, accuracy: 1e-9)
        XCTAssertEqual(AxisEstimator.normalCDF(1.96), 0.975, accuracy: 1e-3)
        XCTAssertEqual(AxisEstimator.normalCDF(-1.96), 0.025, accuracy: 1e-3)
    }
}
