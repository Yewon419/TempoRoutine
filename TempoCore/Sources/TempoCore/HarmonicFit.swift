// 템포루틴 — 푸리에 1차 조화 적합 (MASTER §5.12 ②)
//
// y(θ) ≈ c + a·cos θ + b·sin θ 를 최소제곱으로 맞춘다. 진폭 = √(a²+b²), 위상 = atan2(b, a).
//
// **편향 보정이 이 파일의 핵심이다.** 표본이 적으면 잡음이 진폭으로 새어 들어가 과대 추정된다.
// rawPower에서 잡음 기여분을 빼고 음수는 0으로 자른다. 다만 그 클리핑이 과하면
// 전원이 저진폭형이 되므로(3점 저장 시절의 실패 모드), 구현 후 분포 확인이 필요하다.

import Foundation

public enum HarmonicFit {

    /// 미지수 3개(c·a·b)라 표본이 4개는 되어야 잔차 자유도가 남는다.
    public static let minimumSamples = 4

    /// 소급 입력은 회상 기반이라 EMA와 측정 시간 척도가 다르다 — 가중치를 낮춘다(§3.4).
    public static let backfilledWeight = 0.5

    /// 한 주기의 한 계열을 적합한다. 표본이 모자라거나 위상이 한쪽에 몰리면 nil.
    public static func fit(_ samples: [(theta: Double, value: Double, weight: Double)]) -> HarmonicResult? {
        guard samples.count >= minimumSamples else { return nil }

        // 가중 최소제곱 정규방정식 (3×3 대칭)
        var sw = 0.0, sc = 0.0, ss = 0.0
        var scc = 0.0, sss = 0.0, scs = 0.0
        var sy = 0.0, syc = 0.0, sys = 0.0
        for sample in samples {
            let w = sample.weight
            let c = cos(sample.theta), s = sin(sample.theta), y = sample.value
            sw += w
            sc += w * c;      ss += w * s
            scc += w * c * c; sss += w * s * s; scs += w * c * s
            sy += w * y;      syc += w * y * c; sys += w * y * s
        }
        guard sw > 0 else { return nil }

        let matrix = [
            [sw,  sc,  ss],
            [sc,  scc, scs],
            [ss,  scs, sss],
        ]
        guard let solution = solve3x3(matrix, rhs: [sy, syc, sys]) else { return nil }
        let (c0, a, b) = (solution[0], solution[1], solution[2])

        // 잔차 분산 → 잡음 기여분. 진폭 제곱의 기대 편향 ≈ 2σ²/n (cos·sin 두 성분)
        var residualSS = 0.0
        for sample in samples {
            let predicted = c0 + a * cos(sample.theta) + b * sin(sample.theta)
            let diff = sample.value - predicted
            residualSS += sample.weight * diff * diff
        }
        let dof = sw - 3
        let noiseVariance = dof > 0 ? residualSS / dof : 0
        let rawPower = a * a + b * b
        let corrected = max(0, rawPower - 2 * noiseVariance / sw)

        return HarmonicResult(mean: c0,
                              amplitude: corrected.squareRoot(),
                              phase: atan2(b, a),
                              sampleCount: samples.count)
    }

    /// 가우스 소거 — 3×3이라 피벗만 챙기면 충분하다. 특이 행렬(위상 쏠림)이면 nil.
    private static func solve3x3(_ matrix: [[Double]], rhs: [Double]) -> [Double]? {
        var m = matrix
        var v = rhs
        for col in 0..<3 {
            var pivotRow = col
            for row in (col + 1)..<3 where abs(m[row][col]) > abs(m[pivotRow][col]) {
                pivotRow = row
            }
            guard abs(m[pivotRow][col]) > 1e-10 else { return nil }
            if pivotRow != col {
                m.swapAt(pivotRow, col)
                v.swapAt(pivotRow, col)
            }
            for row in (col + 1)..<3 {
                let factor = m[row][col] / m[col][col]
                guard factor != 0 else { continue }
                for k in col..<3 { m[row][k] -= factor * m[col][k] }
                v[row] -= factor * v[col]
            }
        }
        var solution = [0.0, 0.0, 0.0]
        for row in stride(from: 2, through: 0, by: -1) {
            var sum = v[row]
            for k in (row + 1)..<3 { sum -= m[row][k] * solution[k] }
            solution[row] = sum / m[row][row]
        }
        return solution.allSatisfy(\.isFinite) ? solution : nil
    }

    /// 한 주기의 신호 묶음에서 정서 계열을 적합한다(A축의 입력).
    public static func fitEmotional(_ signals: [DailySignal]) -> HarmonicResult? {
        fit(signals.compactMap { signal in
            signal.emotional.map {
                (signal.theta, $0, signal.isBackfilled ? backfilledWeight : 1.0)
            }
        })
    }

    public static func fitBodily(_ signals: [DailySignal]) -> HarmonicResult? {
        fit(signals.compactMap { signal in
            signal.bodily.map {
                (signal.theta, $0, signal.isBackfilled ? backfilledWeight : 1.0)
            }
        })
    }
}
