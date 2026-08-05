// 리듬 집계 엔진 테스트 (MASTER §5.6.3)
// 막아야 할 것: ① 노트 단독 행(energy·mood=0)이 평균에 새는 것 ② projected 표본이 집계에 드는 것
// ③ 옵션 신호(sleep) nil이 0으로 세어지는 것 ④ 일관성 argmax가 예측 길이로 도출되는 것(과거는 실측)

import XCTest
@testable import TempoCore

final class RhythmEngineTests: XCTestCase {

    private let cal = Calendar.current

    private func day(_ base: Date, _ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: base)!
    }

    private var base: Date {
        cal.startOfDay(for: cal.date(from: DateComponents(year: 2026, month: 1, day: 5))!)
    }

    /// 28일 주기 2개 + 진행 중 1개 — starts = 0, 28, 56일차.
    private var starts: [Date] { [base, day(base, 28), day(base, 56)] }

    func testBucketsMeanBySignalAndPhase() {
        // §5.3 경계(n=28): 겨울 1~5 / 봄 6~14 / 여름 15~17 / 가을 18~28일차.
        // 겨울(1·2일차)에 에너지 2·2, 여름(16일차)에 4.
        let samples = [
            SignalSample(day: day(base, 0), energy: 2, mood: 3, sleep: nil),
            SignalSample(day: day(base, 1), energy: 2, mood: 3, sleep: nil),
            SignalSample(day: day(base, 15), energy: 4, mood: 5, sleep: 2),
        ]
        let result = RhythmEngine.summaries(samples: samples, periodStarts: starts, averageLength: 28)

        let menstrualEnergy = result.first { $0.phase == .menstrual && $0.signal == .energy }
        XCTAssertEqual(menstrualEnergy?.mean, 2.0)
        XCTAssertEqual(menstrualEnergy?.sampleCount, 2)

        // sleep은 non-nil 행만 — 겨울 버킷에 sleep 요약이 없어야 한다
        XCTAssertNil(result.first { $0.phase == .menstrual && $0.signal == .sleep })
        XCTAssertEqual(result.first { $0.signal == .sleep }?.sampleCount, 1)
    }

    /// 노트 단독 행(energy·mood 0)은 §5.5 규약상 유효 체크인이지만 집계엔 못 들어간다.
    func testNoteOnlyRowsAreExcluded() {
        let samples = [
            SignalSample(day: day(base, 0), energy: 0, mood: 0, sleep: 5),
            SignalSample(day: day(base, 1), energy: 3, mood: 0, sleep: nil),
        ]
        XCTAssertTrue(RhythmEngine.summaries(samples: samples, periodStarts: starts,
                                             averageLength: 28).isEmpty)
    }

    /// 마지막 앵커 + 예측 길이를 넘어선 날짜(projected)는 제외 — 추정 위에 추정을 쌓지 않는다.
    func testProjectedDaysAreExcluded() {
        let samples = [SignalSample(day: day(base, 56 + 30), energy: 5, mood: 5, sleep: nil)]
        XCTAssertTrue(RhythmEngine.summaries(samples: samples, periodStarts: starts,
                                             averageLength: 28).isEmpty)
    }

    func testNarratableRequiresTwoPhasesAtThreshold() {
        // 겨울 3개 — 단계 1개만 임계 도달 → 비교 불가
        var samples = (0...2).map { SignalSample(day: day(base, $0), energy: 2, mood: 3, sleep: nil) }
        var result = RhythmEngine.summaries(samples: samples, periodStarts: starts, averageLength: 28)
        XCTAssertFalse(RhythmEngine.narratable(result, signal: .energy))

        // 봄(7~9일차) 3개 추가 → 두 단계 도달
        samples += (6...8).map { SignalSample(day: day(base, $0), energy: 4, mood: 4, sleep: nil) }
        result = RhythmEngine.summaries(samples: samples, periodStarts: starts, averageLength: 28)
        XCTAssertTrue(RhythmEngine.narratable(result, signal: .energy))
        // sleep은 여전히 표본 0 — 신호별로 따로 판정돼야 한다
        XCTAssertFalse(RhythmEngine.narratable(result, signal: .sleep))
    }

    /// 주기마다 겨울 낮음·여름(16일차) 높음이면 topPhase는 두 주기 모두 ovulation.
    func testPerCycleTopPhases() {
        var samples: [SignalSample] = []
        for cycleStart in [0, 28] {
            samples.append(SignalSample(day: day(base, cycleStart + 1), energy: 2, mood: 3, sleep: nil))
            samples.append(SignalSample(day: day(base, cycleStart + 15), energy: 5, mood: 4, sleep: nil))
        }
        let tops = RhythmEngine.perCycleTopPhases(signal: .energy, samples: samples, periodStarts: starts)
        XCTAssertEqual(tops, [.ovulation, .ovulation])
    }

    /// 단계가 하나뿐인 주기는 건너뛴다 — 비교가 성립하지 않는다.
    func testCycleWithSinglePhaseIsSkipped() {
        let samples = [
            SignalSample(day: day(base, 1), energy: 2, mood: 3, sleep: nil),      // 1주기: 겨울만
            SignalSample(day: day(base, 28 + 1), energy: 2, mood: 3, sleep: nil), // 2주기: 겨울+여름
            SignalSample(day: day(base, 28 + 15), energy: 5, mood: 4, sleep: nil),
        ]
        let tops = RhythmEngine.perCycleTopPhases(signal: .energy, samples: samples, periodStarts: starts)
        XCTAssertEqual(tops, [.ovulation])
    }

    /// 완료 주기가 없으면(시작일 1개) 빈 배열.
    func testNoCompletedCycles() {
        let samples = [SignalSample(day: day(base, 1), energy: 3, mood: 3, sleep: nil)]
        XCTAssertTrue(RhythmEngine.perCycleTopPhases(signal: .energy, samples: samples,
                                                     periodStarts: [base]).isEmpty)
    }
}
