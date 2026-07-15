// 템포루틴 — Phase 0 ① 예측 엔진 (resolveDate + overflow). MASTER.md §5.6 / §5.6.1 / §5.6.2.
// 순수 로직(Foundation만). SwiftData·UI 의존 없음 → Swift Playgrounds(아이폰)에서 paste & Run.
// 기대 출력: "— 25 passed, 0 failed —"
//
// ⚠️ 이 파일은 step1 검증용 단일 산출물(엔진 + 테스트) — 역사 보존용.
//    2026-07-15 빌드 1에서 TempoCore SPM 패키지로 이식 완료(엔진=Sources/TempoCore,
//    테스트=Tests/TempoCoreTests XCTest 25케이스). 이제 진실은 TempoCore — 이 파일은 수정하지 않는다.

import Foundation

// MARK: - 값 타입 (§5.5 / §5.6)

enum CyclePhase: String, Codable, CaseIterable { case menstrual, follicular, ovulation, luteal }

enum CycleAnchor: Codable, Equatable {
    case cycleStart                 // 주기 시작(생리 1일차)
    case phase(CyclePhase)          // 특정 단계 시작
}

// 연관값 enum은 auto-synthesis가 안 되거나 불안정 → discriminator('type') 커스텀 Codable (§5.5.1).
extension CycleAnchor {
    enum CodingKeys: String, CodingKey { case type, phase }
    enum Kind: String, Codable { case cycleStart, phase }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        switch self {
        case .cycleStart:   try c.encode(Kind.cycleStart, forKey: .type)
        case .phase(let p): try c.encode(Kind.phase, forKey: .type); try c.encode(p, forKey: .phase)
        }
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .cycleStart: self = .cycleStart
        case .phase:      self = .phase(try c.decode(CyclePhase.self, forKey: .phase))
        }
    }
}

enum OffsetOverflowRule: String, Codable { case clamp, skip, carry }

struct CycleRecurrence: Codable, Equatable {
    var anchor: CycleAnchor
    var dayOffset: Int               // 앵커로부터 +N일 (절대 날짜 저장 X)
    var repeatsEveryCycle: Bool      // false = 특정 주기 1회
    var overflowRule: OffsetOverflowRule
}

struct CyclePrediction {
    let lastPeriodStart: Date
    let averageLength: Int
    let confidence: Confidence
    enum Confidence { case low, medium, high }
}

struct PhaseSpan: Equatable {
    let phase: CyclePhase
    let startDay: Int   // 1-indexed
    let length: Int     // 일수
}

struct DayResolution: Equatable {
    let day: Int        // 1-indexed day-in-cycle
    let projected: Bool // true = 예측(실제 앵커 밖 — UI에서 faded·"예상")
}

// MARK: - 예측 엔진 (§5.6)

enum CyclePredictor {

    /// 평균 주기 길이. 기록<2개면 28, [21,35] 클램프.
    static func averageLength(startDates: [Date]) -> Int {
        let sorted = startDates.sorted()
        guard sorted.count >= 2 else { return 28 }
        let gaps = zip(sorted, sorted.dropFirst())
            .map { Calendar.current.dateComponents([.day], from: $0, to: $1).day ?? 28 }
        return max(21, min(35, gaps.reduce(0, +) / gaps.count))
    }

    /// §5.3 LOCKED 경계(황체기 고정·양방향 앵커). 합은 항상 n. M=5/B=14/O=3.
    static func phaseSpans(cycleLength n: Int) -> [PhaseSpan] {
        let m = 5, b = 14, o = 3
        var menLen = m
        var folLen = (n - b) - m       // N−B−M (탄력)
        var ovuLen = o
        var lutLen = b - o             // B−O
        // 짧은 주기 클램프: 난포기 <1이면 후반부(황체→배란→월경 순) 1일씩 양보. 디폴트+[21,35]에선 미발동.
        while folLen < 1 {
            if lutLen > 1 { lutLen -= 1; folLen += 1 }
            else if ovuLen > 1 { ovuLen -= 1; folLen += 1 }
            else if menLen > 1 { menLen -= 1; folLen += 1 }
            else { break }
        }
        let menStart = 1
        let folStart = menStart + menLen
        let ovuStart = folStart + folLen
        let lutStart = ovuStart + ovuLen
        return [
            PhaseSpan(phase: .menstrual,  startDay: menStart, length: menLen),
            PhaseSpan(phase: .follicular, startDay: folStart, length: folLen),
            PhaseSpan(phase: .ovulation,  startDay: ovuStart, length: ovuLen),
            PhaseSpan(phase: .luteal,     startDay: lutStart, length: lutLen),
        ]
    }

    /// 주기 기준 반복을 특정 주기(cycleStart=1일차)에서 절대 날짜로 resolve. ← 제품의 심장.
    static func resolveDate(recurrence r: CycleRecurrence, cycleStart: Date, prediction p: CyclePrediction) -> Date? {
        let n = p.averageLength
        // 1. 앵커 span(시작일 1-indexed, 길이)
        let span: (start: Int, length: Int)
        switch r.anchor {
        case .cycleStart:
            span = (1, n)
        case .phase(let ph):
            guard let s = phaseSpans(cycleLength: n).first(where: { $0.phase == ph }) else { return nil }
            span = (s.startDay, s.length)
        }
        // 2. dayOffset + overflow
        let offset = max(0, r.dayOffset)
        var targetDay: Int
        if offset >= span.length {                       // overflow
            switch r.overflowRule {
            case .skip:  return nil                       // 이번 주기 미발생
            case .clamp: targetDay = span.start + span.length - 1   // span 마지막 날
            case .carry: targetDay = span.start + offset            // 다음 단계로 이월(같은 주기 내)
            }
        } else {
            targetDay = span.start + offset
        }
        // 3. 주기 경계로 가둠 (carry가 주기 밖이면 day n; .cycleStart에선 carry≡clamp)
        targetDay = min(max(targetDay, 1), n)
        // 4. 절대 날짜 = cycleStart + (targetDay-1)일
        return Calendar.current.date(byAdding: .day, value: targetDay - 1, to: cycleStart)
    }

    /// 날짜의 단계 + projected 플래그. 기록 0개면 nil(S0).
    static func phase(on date: Date, periodStarts: [Date], averageLength n: Int) -> (phase: CyclePhase, projected: Bool)? {
        guard let r = cycleDay(of: date, periodStarts: periodStarts, averageLength: n) else { return nil }
        return (phaseForDay(r.day, cycleLength: n), r.projected)
    }

    /// 기록 규칙성으로 신뢰도. <2 low / spread>7일 low / 4+개 & spread≤3일 high / 그 외 medium.
    static func confidence(periodStarts: [Date]) -> CyclePrediction.Confidence {
        let sorted = periodStarts.sorted()
        guard sorted.count >= 2 else { return .low }
        let gaps = zip(sorted, sorted.dropFirst())
            .map { Calendar.current.dateComponents([.day], from: $0, to: $1).day ?? 28 }
        let spread = (gaps.max() ?? 0) - (gaps.min() ?? 0)
        if sorted.count >= 4 && spread <= 3 { return .high }
        if spread <= 7 { return .medium }
        return .low
    }

    /// 예측 다음 생리일(마지막 기록 + 예측길이) 경과인데 새 기록 없음 = overdue.
    static func isOverdue(on date: Date, periodStarts: [Date], averageLength n: Int) -> Bool {
        guard let last = periodStarts.max() else { return false }
        let diff = Calendar.current.dateComponents([.day], from: last, to: date).day ?? 0
        return diff >= n
    }

    /// 날짜 → day-in-cycle(1-indexed) + projected. 과거=포함 실주기 앵커, 미래/overdue=예측 투영.
    /// internal(테스트 접근용 — private 아님). §5.6.2 정정: 모듈로 단일투영의 과거 오류 제거.
    static func cycleDay(of date: Date, periodStarts: [Date], averageLength n: Int) -> DayResolution? {
        let sorted = periodStarts.sorted()
        guard let first = sorted.first else { return nil }            // 기록 0개(S0)
        guard let base = sorted.last(where: { $0 <= date }) else {    // 첫 기록 이전 → 역투영
            let diff = Calendar.current.dateComponents([.day], from: first, to: date).day ?? 0
            return DayResolution(day: ((diff % n) + n) % n + 1, projected: true)
        }
        let diff = Calendar.current.dateComponents([.day], from: base, to: date).day ?? 0
        if base == sorted.last && diff >= n {                          // 마지막 앵커+예측 초과 = 예측/overdue
            return DayResolution(day: diff % n + 1, projected: true)
        }
        return DayResolution(day: diff + 1, projected: false)          // 실제 주기 내
    }

    /// day-in-cycle → 단계. internal(테스트 접근용).
    static func phaseForDay(_ day: Int, cycleLength n: Int) -> CyclePhase {
        let d = min(max(day, 1), n)
        for s in phaseSpans(cycleLength: n) where d >= s.startDay && d < s.startDay + s.length {
            return s.phase
        }
        return .luteal
    }
}

// MARK: - 테스트 하니스 (XCTest 없이 Playgrounds/CLI 실행)

var passed = 0, failed = 0
func check(_ name: String, _ ok: Bool) {
    if ok { passed += 1; print("✅ \(name)") } else { failed += 1; print("❌ \(name)") }
}

let cal = Calendar.current
let base = cal.date(from: DateComponents(year: 2025, month: 1, day: 1))!
func d(_ off: Int) -> Date { cal.date(byAdding: .day, value: off, to: base)! }
let pred28 = CyclePrediction(lastPeriodStart: d(0), averageLength: 28, confidence: .high)

func runStep1Tests() {
    // T1 averageLength
    check("T1 avg 28",        CyclePredictor.averageLength(startDates: [d(0), d(28)]) == 28)
    check("T1 avg <2 → 28",   CyclePredictor.averageLength(startDates: [d(0)]) == 28)
    check("T1 avg clamp 35",  CyclePredictor.averageLength(startDates: [d(0), d(60)]) == 35)
    check("T1 avg clamp 21",  CyclePredictor.averageLength(startDates: [d(0), d(10)]) == 21)

    // T2 phaseSpans(28)
    check("T2 spans28", CyclePredictor.phaseSpans(cycleLength: 28) == [
        PhaseSpan(phase: .menstrual,  startDay: 1,  length: 5),
        PhaseSpan(phase: .follicular, startDay: 6,  length: 9),
        PhaseSpan(phase: .ovulation,  startDay: 15, length: 3),
        PhaseSpan(phase: .luteal,     startDay: 18, length: 11),
    ])
    // T3 phaseSpans(35) — 봄만 늘어남
    check("T3 spans35 follicular 6·16",
          CyclePredictor.phaseSpans(cycleLength: 35)[1] == PhaseSpan(phase: .follicular, startDay: 6, length: 16))
    // T4 phaseSpans(21)
    let s21 = CyclePredictor.phaseSpans(cycleLength: 21)
    check("T4 spans21 sum=21",          s21.reduce(0) { $0 + $1.length } == 21)
    check("T4 spans21 follicular 6·2",  s21[1] == PhaseSpan(phase: .follicular, startDay: 6, length: 2))

    // T5 phaseForDay(28)
    check("T5 day1 menstrual",   CyclePredictor.phaseForDay(1,  cycleLength: 28) == .menstrual)
    check("T5 day15 ovulation",  CyclePredictor.phaseForDay(15, cycleLength: 28) == .ovulation)
    check("T5 day28 luteal",     CyclePredictor.phaseForDay(28, cycleLength: 28) == .luteal)

    // T6 resolve 정상: luteal(start18) + 2 = day20
    let rLuteal2 = CycleRecurrence(anchor: .phase(.luteal), dayOffset: 2, repeatsEveryCycle: true, overflowRule: .clamp)
    check("T6 luteal+2 → day20", CyclePredictor.resolveDate(recurrence: rLuteal2, cycleStart: d(0), prediction: pred28) == d(19))

    // T7 overflow clamp: ovulation(len3) +5 → 마지막 day17
    let rOvuClamp = CycleRecurrence(anchor: .phase(.ovulation), dayOffset: 5, repeatsEveryCycle: true, overflowRule: .clamp)
    check("T7 clamp → day17", CyclePredictor.resolveDate(recurrence: rOvuClamp, cycleStart: d(0), prediction: pred28) == d(16))
    // T8 overflow skip → nil
    let rOvuSkip = CycleRecurrence(anchor: .phase(.ovulation), dayOffset: 5, repeatsEveryCycle: true, overflowRule: .skip)
    check("T8 skip → nil", CyclePredictor.resolveDate(recurrence: rOvuSkip, cycleStart: d(0), prediction: pred28) == nil)
    // T9 overflow carry: 15+5 = day20 (황체로 이월)
    let rOvuCarry = CycleRecurrence(anchor: .phase(.ovulation), dayOffset: 5, repeatsEveryCycle: true, overflowRule: .carry)
    check("T9 carry → day20", CyclePredictor.resolveDate(recurrence: rOvuCarry, cycleStart: d(0), prediction: pred28) == d(19))

    // T10 cycleStart +0 → cycleStart
    let rCS0 = CycleRecurrence(anchor: .cycleStart, dayOffset: 0, repeatsEveryCycle: true, overflowRule: .clamp)
    check("T10 cycleStart+0 → day1", CyclePredictor.resolveDate(recurrence: rCS0, cycleStart: d(0), prediction: pred28) == d(0))
    // T11 carry 주기초과 → day28 클램프
    let rCS40 = CycleRecurrence(anchor: .cycleStart, dayOffset: 40, repeatsEveryCycle: true, overflowRule: .carry)
    check("T11 carry past N → day28", CyclePredictor.resolveDate(recurrence: rCS40, cycleStart: d(0), prediction: pred28) == d(27))

    // T12 cycleDay 과거 실주기: [d0, d0+33], date d0+30 → day31, projected=false
    check("T12 past real cycle → day31 projected=false",
          CyclePredictor.cycleDay(of: d(30), periodStarts: [d(0), d(33)], averageLength: 28) == DayResolution(day: 31, projected: false))
    // T13 cycleDay 미래 투영: [d0], date d0+31 → day4, projected=true
    check("T13 future projection → day4 projected=true",
          CyclePredictor.cycleDay(of: d(31), periodStarts: [d(0)], averageLength: 28) == DayResolution(day: 4, projected: true))
    // T14 isOverdue
    check("T14 overdue true",  CyclePredictor.isOverdue(on: d(30), periodStarts: [d(0)], averageLength: 28) == true)
    check("T14 not overdue",   CyclePredictor.isOverdue(on: d(20), periodStarts: [d(0)], averageLength: 28) == false)
    // T15 S0 콜드스타트 → nil
    check("T15 cold start → nil", CyclePredictor.phase(on: d(5), periodStarts: [], averageLength: 28) == nil)
    // T16 confidence
    check("T16 conf high (regular 4)",    CyclePredictor.confidence(periodStarts: [d(0), d(28), d(56), d(84)]) == .high)
    check("T16 conf low (spread>7)",      CyclePredictor.confidence(periodStarts: [d(0), d(25), d(61)]) == .low)
    check("T16 conf medium (2 logs)",     CyclePredictor.confidence(periodStarts: [d(0), d(28)]) == .medium)

    print("\n— \(passed) passed, \(failed) failed —")
}

runStep1Tests()
