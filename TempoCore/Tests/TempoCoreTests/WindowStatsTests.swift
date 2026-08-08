// 리듬 엔진(윈도우 통계) 테스트 — MASTER §5.12 개정 M (2026-08-08 전면 대체).
// 표 기반 결정론 케이스. 특히 세 가지를 못 지나가게 막는다:
// ① 빈 윈도우·표본 미달 = 침묵(nil) ② 합의 임계 없이 말하기 ③ 안단테 도달 불가(구 엔진 결함 재발).
//
// SignalConversionTests는 구 AxisEngineTests에서 승계 — 변환은 사분면 커버 리마인더가 계속 쓴다.

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
        XCTAssertEqual(SignalConversion.bodily(pain: 1), 5)
        XCTAssertEqual(SignalConversion.bodily(pain: 5), 1)
    }

    func testUnrecordedIsNil() {
        XCTAssertNil(SignalConversion.emotional(mood: 0, irritability: 0))
        XCTAssertNil(SignalConversion.emotional(mood: nil, irritability: nil))
        XCTAssertNil(SignalConversion.bodily(pain: 0))
        XCTAssertNil(SignalConversion.bodily(pain: 9))
    }
}

final class WindowStatsTests: XCTestCase {

    /// 매일 기록된 완료 주기 하나. r = length − d + 1.
    private func cycle(length: Int = 28,
                       energy: (Int) -> Int? = { _ in nil },
                       mood: (Int) -> Int? = { _ in nil }) -> WindowCycle {
        WindowCycle(length: length, samples: (1...length).map { d in
            WindowDaySample(daysFromStart: d, daysUntilNext: length - d + 1,
                            energy: energy(d), mood: mood(d))
        })
    }

    /// 생리 전 dipDays일 energy 2, 나머지 4 (28일 주기 → dip = day 29−dipDays부터).
    private func dipCycle(dipDays: Int) -> WindowCycle {
        cycle(energy: { d in d > 28 - dipDays ? 2 : 4 })
    }

    // ── 기초 통계

    func testMedian() {
        XCTAssertNil(WindowStatsEngine.median([]))
        XCTAssertEqual(WindowStatsEngine.median([3]), 3)
        XCTAssertEqual(WindowStatsEngine.median([4, 1, 2]), 2)
        XCTAssertEqual(WindowStatsEngine.median([4, 1, 2, 3]), 2.5)
    }

    func testBaselineAndSuffixMedian() {
        let c = dipCycle(dipDays: 4)
        XCTAssertEqual(WindowStatsEngine.baseline(c, signal: .energy), 4)
        XCTAssertEqual(WindowStatsEngine.suffixMedian(c, signal: .energy, p: 4), 2)
        // p=6이면 정상일 2일이 섞여도 중앙값은 아직 2 — 중앙값이 경계 탐지에 못 쓰이는 이유.
        XCTAssertEqual(WindowStatsEngine.suffixMedian(c, signal: .energy, p: 6), 2)
        // 신호가 없으면 침묵.
        XCTAssertNil(WindowStatsEngine.baseline(c, signal: .mood))
    }

    /// 계절 윈도우 경계는 실측 주기 길이를 따른다 — 35일 주기의 여름은 22~24일차(§5.3 뒤앵커).
    func testPhaseMedianRespectsCycleLength() {
        let c = cycle(length: 35, mood: { d in (22...24).contains(d) ? 5 : 3 })
        XCTAssertEqual(WindowStatsEngine.phaseMedian(c, signal: .mood, phase: .ovulation), 5)
        XCTAssertEqual(WindowStatsEngine.phaseMedian(c, signal: .mood, phase: .follicular), 3)
    }

    /// 개정 M — M 파라미터가 계절 윈도우 경계를 움직인다. M=7이면 6·7일차가 겨울로 들어온다.
    func testPhaseMedianRespectsMenstrualLength() {
        let c = cycle(mood: { d in d <= 7 ? 2 : 4 })
        XCTAssertEqual(WindowStatsEngine.phaseMedian(c, signal: .mood, phase: .menstrual,
                                                     menstrualLength: 7), 2)
        XCTAssertEqual(WindowStatsEngine.phaseMedian(c, signal: .mood, phase: .follicular,
                                                     menstrualLength: 7), 4)
        // 디폴트 5면 6·7일차의 2가 봄에 섞인다 — [2,2,4,4,4,4,4,4,4] 중앙값 4
        XCTAssertEqual(WindowStatsEngine.phaseMedian(c, signal: .mood, phase: .follicular), 4)
    }

    // ── P 저컨디션 윈도우

    /// dip 4일 → P=5. 저컨디션 비율 0.75 규칙은 경계를 최대 +1일 과대 추정한다
    /// (suffix 5일 중 4일 저컨디션 = 0.8 ≥ 0.75). 방향이 안전하고(자기돌봄이 하루 일찍),
    /// lowDayFraction은 파일럿 조정 대상(§5.12 루프 2).
    func testPreMenstrualWindowDetected() {
        let cycles = [dipCycle(dipDays: 4), dipCycle(dipDays: 4), dipCycle(dipDays: 4)]
        XCTAssertEqual(WindowStatsEngine.preMenstrualWindow(cycles: cycles), 5)
    }

    func testPreMenstrualWindowSilentWhenFlat() {
        let flat = cycle(energy: { _ in 4 })
        XCTAssertNil(WindowStatsEngine.preMenstrualWindow(cycles: [flat, flat, flat]))
    }

    func testPreMenstrualWindowNeedsThreeCycles() {
        let cycles = [dipCycle(dipDays: 4), dipCycle(dipDays: 4)]
        XCTAssertNil(WindowStatsEngine.preMenstrualWindow(cycles: cycles))
    }

    /// energy가 아예 없으면(기분만 기록) P는 침묵한다 — 다른 신호로 대충 때우지 않는다.
    func testEnergyMissingSilencesPreWindow() {
        let moodOnly = cycle(mood: { _ in 3 })
        XCTAssertNil(WindowStatsEngine.preMenstrualWindow(cycles: [moodOnly, moodOnly, moodOnly]))
    }

    // ── 홀드아웃 채택 게이트 (§5.3 ③ — 개정 M)

    /// F1 산식 — dip 4일 주기에서 p=4는 완전 일치(1.0), p=5는 정상일 하나가 섞여 감점.
    func testHoldoutScore() throws {
        let c = dipCycle(dipDays: 4)
        XCTAssertEqual(WindowStatsEngine.holdoutScore(c, p: 4), 1.0)
        let p5 = try XCTUnwrap(WindowStatsEngine.holdoutScore(c, p: 5))
        XCTAssertLessThan(p5, 1.0)
        // 기록 없는 주기는 판정 불능
        XCTAssertNil(WindowStatsEngine.holdoutScore(cycle(), p: 5))
    }

    /// dip 6일 → 학습 P=7(0.75 규칙), 홀드아웃에서도 7이 디폴트 5보다 나음 → 채택.
    func testAdoptedPreWindowWhenBetter() {
        let cycles = Array(repeating: dipCycle(dipDays: 6), count: 4)   // 학습 3 + 홀드아웃 1
        XCTAssertEqual(WindowStatsEngine.adoptedPreWindow(cycles: cycles), 7)
    }

    /// 홀드아웃 주기의 실제 패턴(dip 4일)에선 디폴트 5가 학습값 7보다 나음 → 기각(nil).
    func testAdoptedPreWindowRejectedWhenDefaultBetter() {
        let cycles = Array(repeating: dipCycle(dipDays: 6), count: 3) + [dipCycle(dipDays: 4)]
        XCTAssertNil(WindowStatsEngine.adoptedPreWindow(cycles: cycles))
    }

    /// 홀드아웃까지 4주기가 안 되면 게이트 자체가 침묵.
    func testAdoptedPreWindowNeedsFourCycles() {
        let cycles = Array(repeating: dipCycle(dipDays: 6), count: 3)
        XCTAssertNil(WindowStatsEngine.adoptedPreWindow(cycles: cycles))
    }

    // ── H1 배란 주변 기분 상승

    func testH1ConfirmedWhenSummerLifts() {
        let lift = cycle(mood: { d in (15...17).contains(d) ? 5 : 3 })
        XCTAssertEqual(WindowStatsEngine.h1SummerMoodLift(cycles: [lift, lift, lift]), true)
    }

    func testH1RefutedWhenFlat() {
        let flat = cycle(mood: { _ in 3 })
        XCTAssertEqual(WindowStatsEngine.h1SummerMoodLift(cycles: [flat, flat, flat]), false)
    }

    func testH1SilentUnderThreeCycles() {
        let lift = cycle(mood: { d in (15...17).contains(d) ? 5 : 3 })
        XCTAssertNil(WindowStatsEngine.h1SummerMoodLift(cycles: [lift, lift]))
    }

    // ── A축 유형

    private var swingCycle: WindowCycle {   // 겨울 2, 나머지 4 → range 2
        cycle(mood: { d in d <= 5 ? 2 : 4 })
    }
    private var flatCycle: WindowCycle {    // range 0
        cycle(mood: { _ in 3 })
    }

    func testClassifyVivace() {
        XCTAssertEqual(WindowStatsEngine.classify(cycles: [swingCycle, swingCycle, swingCycle]),
                       .vivace)
    }

    /// ★ 안단테 도달 가능 — 기준(baselineRange) 비교가 빠지면 이 유형이 영영 안 나온다
    /// (구 엔진 2026-08-04 실측 결함의 재발 방지).
    func testClassifyAndante() {
        XCTAssertEqual(WindowStatsEngine.classify(cycles: [flatCycle, flatCycle, flatCycle]),
                       .andante)
    }

    /// 주기 간 불일치 = 루바토 — 표본은 충분한데 어느 쪽으로도 합의가 안 선다.
    func testClassifyRubatoOnDisagreement() {
        let cycles = [swingCycle, swingCycle, flatCycle, flatCycle]  // n=4, 임계 3, 2:2
        XCTAssertEqual(WindowStatsEngine.classify(cycles: cycles), .rubato)
    }

    func testClassifyNilUnderThreeCycles() {
        XCTAssertNil(WindowStatsEngine.classify(cycles: [swingCycle, swingCycle]))
    }

    /// 기록 일수 미달 주기는 판정에 안 들어간다 — 값이 있어도 4일 미만이면 제외.
    func testSparseCyclesAreExcluded() {
        let sparse = WindowCycle(length: 28, samples: (1...3).map { d in
            WindowDaySample(daysFromStart: d, daysUntilNext: 28 - d + 1, energy: nil, mood: 2)
        })
        XCTAssertNil(WindowStatsEngine.classify(cycles: [sparse, sparse, sparse]))
    }

    /// 최근 K주기만 본다 — 6주기 중 첫 주기(변동 큼)는 창 밖이라 판정에 안 낀다.
    func testOnlyRecentCyclesAreUsed() {
        let cycles = [swingCycle] + Array(repeating: flatCycle, count: 5)
        XCTAssertEqual(WindowStatsEngine.classify(cycles: cycles), .andante)
    }

    // ── 프로파일

    func testProfileSummaries() {
        let cycles = [swingCycle, swingCycle, swingCycle]
        let profile = WindowStatsEngine.profile(cycles: cycles)
        let winterMood = profile.first { $0.phase == .menstrual && $0.signal == .mood }
        XCTAssertEqual(winterMood?.median, 2)
        XCTAssertEqual(winterMood?.cyclesWithData, 3)
        // energy는 기록이 없으므로 요약 자체가 없어야 한다(침묵).
        XCTAssertFalse(profile.contains { $0.signal == .energy })
    }
}
