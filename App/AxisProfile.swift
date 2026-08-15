// 템포루틴 — 리듬 엔진의 앱측 접합부 (MASTER §3.11 / §5.12 개정 M)
// CycleSnapshot이 주기 스냅샷의 접합부이듯, 여기는 체크인 → 윈도우 통계의 접합부다.
// 계산 자체는 TempoCore(WindowStatsEngine)에 있고 이 파일은 데이터를 모아 넘기기만 한다.

import Foundation
import TempoCore

struct AxisProfile {
    let cycles: [WindowCycle]
    let menstrualLength: Int   // §5.3 층 2 M — 계절 윈도우 경계에 필요(개정 M)

    init(checkIns: [DailyCheckIn], snapshot: CycleSnapshot) {
        self.cycles = Self.groupIntoCycles(checkIns, snapshot: snapshot)
        self.menstrualLength = snapshot.menstrualLength
    }

    /// 완료된 주기만 묶는다 — 실측 앵커라 r(다음 시작까지 남은 일수)도 실측이고 projected가 없다.
    /// §5.12 ②: 비백필만 — 소급 입력은 회상 기반이라 제외한다(구 엔진의 가중 0.5에서 제외로 강화).
    private static func groupIntoCycles(_ checkIns: [DailyCheckIn],
                                        snapshot: CycleSnapshot) -> [WindowCycle] {
        let starts = snapshot.starts.sorted()
        guard starts.count >= 2 else { return [] }
        let cal = Calendar.current

        var cycles: [WindowCycle] = []
        for (index, start) in starts.enumerated() where index < starts.count - 1 {
            let end = starts[index + 1]
            guard let length = cal.dateComponents([.day], from: start, to: end).day,
                  length > 0 else { continue }

            let samples: [WindowDaySample] = checkIns.compactMap { entry in
                guard !entry.isBackfilled else { return nil }
                let day = cal.startOfDay(for: entry.day)
                guard day >= start, day < end,
                      let offset = cal.dateComponents([.day], from: start, to: day).day
                else { return nil }
                // 0 = 미기록은 엔진의 value(of:)가 거른다 — 여기서 이중 필터를 두면 기준이 갈라진다.
                return WindowDaySample(daysFromStart: offset + 1,
                                       daysUntilNext: length - offset,
                                       energy: entry.energy, mood: entry.mood)
            }
            cycles.append(WindowCycle(length: length, samples: samples))
        }
        return cycles
    }

    var type: RhythmType? { WindowStatsEngine.classify(cycles: cycles, menstrualLength: menstrualLength) }

    // ⚠ `typeName`·`amplitudeLine` 삭제(2026-08-15 사용자 지시 "안 쓰는 건 다 삭제").
    // 2026-08-09에 유형 카드를 UI에서 내리면서 소비처가 0이 된 채 카피만 남아 있었다.
    // §3.11이 남기라고 한 것은 **엔진 산출**(위 `type`·WindowStats·내보내기)이지 문구가 아니다.
    // 유형 서술을 되살릴 땐 그때의 톤으로 다시 쓴다(§7 관찰형 — "기록됐어요" 어투).

    /// ~~M축 한 줄 서술~~ — **폐기(2026-08-05 사용자 결정)**: 체크인 병합으로 몸(pain) 입력
    /// 행이 사라져 신체 계열이 더는 쌓이지 않는다. 분모 없는 M축을 계속 말하면
    /// "마음과 몸이 비슷하게 움직여요"가 데이터 없이 항상 뜨는 거짓 서술이 된다.
    /// 개정 M에서 엔진의 modality 계산 자체도 폐기됐다 — UI 자리는 재도입 대비로 남긴다.
    var modalityLine: String? { nil }

    /// 로그가 없으면 말하지 않는다(§3.11) — 이 값이 false면 화면에 카드를 올리지 않는다.
    /// ⚠ 개정 M: 발화 게이트가 1주기 → 유효 3주기(§5.3 학습 계약)로 강화됐다.
    var hasEnoughData: Bool { type != nil }

    /// §5.3 층 2 `P` — 원시 학습값. 분석·내보내기용(소비처는 adoptedPreWindow).
    var preMenstrualWindow: Int? { WindowStatsEngine.preMenstrualWindow(cycles: cycles) }

    /// 소비처용 `P` — 홀드아웃 채택 게이트(§5.3 ③) 통과분, 못 넘으면 디폴트 5.
    var adoptedPreWindow: Int {
        WindowStatsEngine.adoptedPreWindow(cycles: cycles) ?? WindowStatsEngine.defaultPreWindow
    }

    /// §2.3 H1 — 배란 주변 기분 상승. true일 때만 여름 상승 서사 발화 허용.
    var h1SummerMoodLift: Bool? {
        WindowStatsEngine.h1SummerMoodLift(cycles: cycles, menstrualLength: menstrualLength)
    }
}
