// 템포루틴 — 축 엔진의 앱측 접합부 (MASTER §3.11 / §5.12)
// CycleSnapshot이 주기 스냅샷의 접합부이듯, 여기는 체크인 → 축 추정의 접합부다.
// 계산 자체는 TempoCore(AxisEstimator)에 있고 이 파일은 데이터를 모아 넘기기만 한다.

import Foundation
import TempoCore

struct AxisProfile {
    let state: AxisState?

    /// M축 서술이 갈리는 임계 — 계열 값 범위가 1...5라 차이의 반 칸(0.5)을 기준으로 둔다.
    /// ⚠ 설문의 M 임계(M_raw ∈ [-3,3]에서 1)와 척도가 달라 값이 다르다. 같은 상수로 묶지 말 것.
    static let modalityThreshold = 0.5

    /// 한 주기에 최소 이만큼은 기록돼야 적합에 넣는다(§5.12 — 미지수 3개라 4개 필요).
    static let minSamplesPerCycle = HarmonicFit.minimumSamples

    init(checkIns: [DailyCheckIn], snapshot: CycleSnapshot) {
        self.state = AxisEstimator.estimate(cycles: Self.groupIntoCycles(checkIns, snapshot: snapshot))
    }

    /// 완료된 주기만 묶는다. 진행 중인 주기는 표본이 앞부분에 몰려 있어 진폭이 왜곡된다.
    private static func groupIntoCycles(_ checkIns: [DailyCheckIn],
                                        snapshot: CycleSnapshot) -> [[DailySignal]] {
        let starts = snapshot.starts.sorted()
        guard starts.count >= 2 else { return [] }
        let cal = Calendar.current

        var cycles: [[DailySignal]] = []
        for (index, start) in starts.enumerated() where index < starts.count - 1 {
            let end = starts[index + 1]
            let length = cal.dateComponents([.day], from: start, to: end).day ?? snapshot.averageLength
            guard length > 0 else { continue }

            let signals: [DailySignal] = checkIns.compactMap { entry in
                let day = cal.startOfDay(for: entry.day)
                guard day >= start, day < end else { return nil }
                let offset = (cal.dateComponents([.day], from: start, to: day).day ?? 0) + 1
                let emotional = SignalConversion.emotional(mood: entry.mood,
                                                           irritability: entry.irritability)
                let bodily = SignalConversion.bodily(pain: entry.pain)
                guard emotional != nil || bodily != nil else { return nil }
                return DailySignal(cycleDay: offset, cycleLength: length,
                                   emotional: emotional, bodily: bodily,
                                   isBackfilled: entry.isBackfilled)
            }
            guard signals.count >= minSamplesPerCycle else { continue }
            cycles.append(signals)
        }
        return cycles
    }

    var type: RhythmType? { state.map { AxisEstimator.classify($0) } }

    /// A축 = 유형 이름. 표시는 §3.11 — 이름은 A축만 쓴다.
    var typeName: String? { type?.displayName }

    /// A축 한 줄 — 응답이 아니라 그 사람 로그의 관찰이라 "기록됐어요" 어투다(§7 관찰형 강제).
    var amplitudeLine: String? {
        switch type {
        case .vivace:  "지난 주기들, 오르내림이 큰 편으로 기록됐어요."
        case .andante: "지난 주기들, 잔잔한 편으로 기록됐어요."
        case .rubato:  "아직은 주기마다 달라서, 조금 더 지켜보고 있어요."
        case nil:      nil
        }
    }

    /// M축 = 라벨이 아니라 한 줄 서술(§3.11). D1 판정에서 붕괴하면 이 줄만 감춘다.
    var modalityLine: String? {
        guard let state, type != nil else { return nil }
        if state.modality >= Self.modalityThreshold {
            return "마음 쪽 신호가 먼저 오는 편이에요."
        }
        if state.modality <= -Self.modalityThreshold {
            return "몸 쪽 신호가 먼저 오는 편이에요."
        }
        return "마음과 몸이 비슷하게 움직여요."
    }

    /// 로그가 없으면 말하지 않는다(§3.11) — 이 값이 false면 화면에 카드를 올리지 않는다.
    var hasEnoughData: Bool { state != nil }
}
