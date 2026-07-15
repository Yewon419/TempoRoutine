// 템포루틴 — 주기 값 타입 (MASTER §5.5 / §5.6)
// Playground Step1(아이폰 검증 25/25) 이식본 — 알고리즘·정의 무변경, 접근 제어만 public.

import Foundation

public enum CyclePhase: String, Codable, CaseIterable, Sendable {
    case menstrual, follicular, ovulation, luteal
}

public enum CycleAnchor: Codable, Equatable, Sendable {
    case cycleStart                 // 주기 시작(생리 1일차)
    case phase(CyclePhase)          // 특정 단계 시작
}

// 연관값 enum은 auto-synthesis가 안 되거나 불안정 → discriminator('type') 커스텀 Codable (§5.5.1).
extension CycleAnchor {
    enum CodingKeys: String, CodingKey { case type, phase }
    enum Kind: String, Codable { case cycleStart, phase }
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        switch self {
        case .cycleStart:   try c.encode(Kind.cycleStart, forKey: .type)
        case .phase(let p): try c.encode(Kind.phase, forKey: .type); try c.encode(p, forKey: .phase)
        }
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .cycleStart: self = .cycleStart
        case .phase:      self = .phase(try c.decode(CyclePhase.self, forKey: .phase))
        }
    }
}

public enum OffsetOverflowRule: String, Codable, Sendable { case clamp, skip, carry }

public struct CycleRecurrence: Codable, Equatable, Sendable {
    public var anchor: CycleAnchor
    public var dayOffset: Int               // 앵커로부터 +N일 (절대 날짜 저장 X)
    public var repeatsEveryCycle: Bool      // false = 특정 주기 1회
    public var overflowRule: OffsetOverflowRule

    public init(anchor: CycleAnchor, dayOffset: Int, repeatsEveryCycle: Bool, overflowRule: OffsetOverflowRule) {
        self.anchor = anchor
        self.dayOffset = dayOffset
        self.repeatsEveryCycle = repeatsEveryCycle
        self.overflowRule = overflowRule
    }
}

public struct CyclePrediction: Sendable {
    public let lastPeriodStart: Date
    public let averageLength: Int
    public let confidence: Confidence
    public enum Confidence: Sendable { case low, medium, high }

    public init(lastPeriodStart: Date, averageLength: Int, confidence: Confidence) {
        self.lastPeriodStart = lastPeriodStart
        self.averageLength = averageLength
        self.confidence = confidence
    }
}

public struct PhaseSpan: Equatable, Sendable {
    public let phase: CyclePhase
    public let startDay: Int   // 1-indexed
    public let length: Int     // 일수

    public init(phase: CyclePhase, startDay: Int, length: Int) {
        self.phase = phase
        self.startDay = startDay
        self.length = length
    }
}

public struct DayResolution: Equatable, Sendable {
    public let day: Int        // 1-indexed day-in-cycle
    public let projected: Bool // true = 예측(실제 앵커 밖 — UI에서 faded·"예상")

    public init(day: Int, projected: Bool) {
        self.day = day
        self.projected = projected
    }
}
