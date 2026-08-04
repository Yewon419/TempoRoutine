// 템포루틴 — 축 추정 (MASTER §5.12 ③④)
//
// 주기별 진폭 추정치를 칼만 1D로 평활하고 유형을 배정한다.
//
// **분산 하한이 이 파일의 존재 이유다.** 하한이 없으면 한 주기 내내 같은 값을 찍은 순간
// σ̂²=0 → r=0 → K=1 → σ²=0 이 되어 "진폭 0, 확신도 100%"로 굳고 이후 관측을 전부 무시한다.
// 온디바이스에서 벌어지므로 서버 후처리로 거를 수 없다 — 사용자 수와 무관하게 필요하다.

import Foundation

public enum AxisEstimator {

    /// 관측 노이즈 분산 하한. 6점 척도 양자화 오차 분산 1/12 ≈ 0.083.
    public static let minObservationVariance = 1.0 / 12.0
    /// 상태 분산 하한 — 같은 근거의 절반. 0이 되면 갱신이 멈춘다.
    public static let minStateVariance = 1.0 / 24.0
    /// 프로세스 노이즈. 유형은 "서서히 드리프트"라 작게 잡는다(§3.11 은유 층위).
    public static let processVariance = 0.02

    /// 루바토 구간 — Φ((A − A₀)/σ) ∈ [0.5, 0.85). 아직 어느 쪽이라 말할 확신이 없는 구간.
    public static let rubatoLowerBound = 0.5
    public static let rubatoUpperBound = 0.85

    /// 판정 기준 진폭 A₀ — "변동이 있다"고 부를 최소치.
    /// ⚠ 핸드오프 스펙은 Φ(μ/σ)라고만 썼는데, 진폭은 √이라 음수가 될 수 없어
    /// 그대로 구현하면 Φ ≥ 0.5가 항상 참이 되고 **안단테가 영원히 나오지 않는다**(2026-08-04 실측).
    /// 기준을 빼야 "기준보다 유의하게 큰가"라는 검정이 성립한다.
    /// 값 근거: 진폭 0.5 = peak-to-peak 1.0 = 5점 척도에서 한 칸. 파일럿 후 조정 대상.
    public static let baselineAmplitude = 0.5

    /// 주기 하나를 관측해 상태를 갱신한다. 첫 관측이면 prior 없이 시작한다.
    public static func update(state: AxisState?, cycle signals: [DailySignal]) -> AxisState? {
        guard let emotional = HarmonicFit.fitEmotional(signals) else { return state }
        let bodily = HarmonicFit.fitBodily(signals)

        // A축 관측 = 두 계열 진폭 중 큰 쪽이 아니라 정서 진폭을 쓴다.
        // 신체는 M축(방향)에만 쓰인다 — 진폭의 정의를 한 계열에 고정해야 주기 간 비교가 성립한다.
        let observation = emotional.amplitude
        // 표본이 적을수록 관측을 덜 믿는다. 하한이 걸려 있어 0으로 내려가지 않는다.
        let observationVariance = max(minObservationVariance,
                                      1.0 / Double(max(1, emotional.sampleCount)))

        let modality = (emotional.mean) - (bodily?.mean ?? emotional.mean)

        guard let previous = state else {
            return AxisState(amplitude: observation,
                             variance: max(minStateVariance, observationVariance),
                             modality: modality,
                             observedCycles: 1)
        }

        // 예측 → 갱신
        let predictedVariance = max(minStateVariance, previous.variance + processVariance)
        let gain = predictedVariance / (predictedVariance + observationVariance)
        let amplitude = previous.amplitude + gain * (observation - previous.amplitude)
        let variance = max(minStateVariance, (1 - gain) * predictedVariance)

        let n = Double(previous.observedCycles)
        let blendedModality = (previous.modality * n + modality) / (n + 1)

        return AxisState(amplitude: amplitude,
                         variance: variance,
                         modality: blendedModality,
                         observedCycles: previous.observedCycles + 1)
    }

    /// 여러 주기를 순서대로 흘려 최종 상태를 얻는다.
    public static func estimate(cycles: [[DailySignal]]) -> AxisState? {
        cycles.reduce(nil) { update(state: $0, cycle: $1) }
    }

    /// Φ((A − A₀)/σ) — 진폭이 기준보다 유의하게 큰지에 대한 확신도.
    public static func confidence(_ state: AxisState) -> Double {
        let sigma = state.variance.squareRoot()
        let margin = state.amplitude - baselineAmplitude
        guard sigma > 0 else { return margin > 0 ? 1 : 0 }
        return normalCDF(margin / sigma)
    }

    /// 유형 배정 — 루바토를 먼저 거른다(§3.11).
    /// ⚠ 사전 설문의 루바토와 산출 경로가 다르다. 같은 필드에 담지 말 것.
    public static func classify(_ state: AxisState) -> RhythmType {
        let phi = confidence(state)
        if phi < rubatoLowerBound { return .andante }
        if phi < rubatoUpperBound { return .rubato }
        return .vivace
    }

    /// 표준정규 CDF — erf 기반. 플랫폼 math의 erf를 쓴다(Darwin·Glibc 공통).
    static func normalCDF(_ x: Double) -> Double {
        0.5 * (1 + erf(x / 2.0.squareRoot()))
    }
}
