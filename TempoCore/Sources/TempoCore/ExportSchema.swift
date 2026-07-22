// 템포루틴 — 내보내기/재임포트 직렬화 (MASTER §5.5.1 / §5.5.4 갱신 LOCKED)
// @Model ↔ DTO 분리. schemaVersion=1 (PeriodDay 일별 기록 정의 — 미출시라 v1 자체 교체).
// 날짜-키 필드(day·occurredOn·종일 일정 date)는 date-only "yyyy-MM-dd" — instant 인코딩은
// 타임존 이동 후 재임포트에서 날짜-키 dedup을 파괴(§5.5.1 G 정정). 타임스탬프는 ISO8601.

import Foundation

// 온보딩(§3.10)서 선택하는 추적 옵션 신호 — 단일 출처는 앱 설정.
public struct TrackedSignals: Codable, Equatable, Sendable {
    public var sleep: Bool
    public var pain: Bool
    public var appetite: Bool
    public var note: Bool

    public init(sleep: Bool, pain: Bool, appetite: Bool, note: Bool) {
        self.sleep = sleep
        self.pain = pain
        self.appetite = appetite
        self.note = note
    }
}

// ── DTO (@Model 평문 미러, UUID 보존 — ItemCompletion·OutputSubtask 재연결용) ──

public struct PeriodDayDTO: Codable, Equatable, Sendable {
    public var day: String              // "yyyy-MM-dd"
    public var origin: String           // PeriodDayOrigin rawValue
    public var healthKitUUID: UUID?

    public init(day: String, origin: String, healthKitUUID: UUID?) {
        self.day = day
        self.origin = origin
        self.healthKitUUID = healthKitUUID
    }
}

public struct ScheduleItemDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var date: String             // isAllDay=true → "yyyy-MM-dd" / false → ISO8601 instant
    public var isAllDay: Bool
    public var repeatRule: ScheduleRepeat
    public var createdAt: Date

    public init(id: UUID, title: String, date: String, isAllDay: Bool, repeatRule: ScheduleRepeat, createdAt: Date) {
        self.id = id
        self.title = title
        self.date = date
        self.isAllDay = isAllDay
        self.repeatRule = repeatRule
        self.createdAt = createdAt
    }
}

public struct InputItemDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var category: InputCategory
    public var schedule: InputSchedule
    public var createdAt: Date

    public init(id: UUID, title: String, category: InputCategory, schedule: InputSchedule, createdAt: Date) {
        self.id = id
        self.title = title
        self.category = category
        self.schedule = schedule
        self.createdAt = createdAt
    }
}

public struct OutputSubtaskDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var isDone: Bool
    public var order: Int

    public init(id: UUID, title: String, isDone: Bool, order: Int) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.order = order
    }
}

public struct OutputItemDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var schedule: OutputSchedule
    public var progressKind: OutputProgressKind
    public var subtasks: [OutputSubtaskDTO]
    public var targetSessions: Int
    public var loggedSessions: Int
    public var percent: Double
    public var createdAt: Date

    public init(id: UUID, title: String, schedule: OutputSchedule, progressKind: OutputProgressKind,
                subtasks: [OutputSubtaskDTO], targetSessions: Int, loggedSessions: Int,
                percent: Double, createdAt: Date) {
        self.id = id
        self.title = title
        self.schedule = schedule
        self.progressKind = progressKind
        self.subtasks = subtasks
        self.targetSessions = targetSessions
        self.loggedSessions = loggedSessions
        self.percent = percent
        self.createdAt = createdAt
    }
}

public struct ItemCompletionDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var itemID: UUID
    public var occurredOn: String       // "yyyy-MM-dd"
    public var completedAt: Date

    public init(id: UUID, itemID: UUID, occurredOn: String, completedAt: Date) {
        self.id = id
        self.itemID = itemID
        self.occurredOn = occurredOn
        self.completedAt = completedAt
    }
}

public struct DailyCheckInDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var day: String              // "yyyy-MM-dd" (dedup 키)
    public var energy: Int
    public var mood: Int
    public var sleep: Int?
    public var pain: Int?
    public var appetite: Int?
    public var note: String?
    public var createdAt: Date

    public init(id: UUID, day: String, energy: Int, mood: Int, sleep: Int?, pain: Int?,
                appetite: Int?, note: String?, createdAt: Date) {
        self.id = id
        self.day = day
        self.energy = energy
        self.mood = mood
        self.sleep = sleep
        self.pain = pain
        self.appetite = appetite
        self.note = note
        self.createdAt = createdAt
    }
}

// ── 봉투 ──
public struct ExportEnvelopeV1: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var exportedAt: Date
    public var periodDays: [PeriodDayDTO]          // §5.5.4: periodLogs → periodDays
    public var scheduleItems: [ScheduleItemDTO]
    public var inputItems: [InputItemDTO]
    public var outputItems: [OutputItemDTO]
    public var completions: [ItemCompletionDTO]
    public var checkIns: [DailyCheckInDTO]
    public var trackedSignals: TrackedSignals

    public init(exportedAt: Date, periodDays: [PeriodDayDTO], scheduleItems: [ScheduleItemDTO],
                inputItems: [InputItemDTO], outputItems: [OutputItemDTO],
                completions: [ItemCompletionDTO], checkIns: [DailyCheckInDTO],
                trackedSignals: TrackedSignals) {
        self.schemaVersion = ExportCodec.schemaVersion
        self.exportedAt = exportedAt
        self.periodDays = periodDays
        self.scheduleItems = scheduleItems
        self.inputItems = inputItems
        self.outputItems = outputItems
        self.completions = completions
        self.checkIns = checkIns
        self.trackedSignals = trackedSignals
    }
}

// ── 코덱 ──
public enum ExportCodec {
    public static let schemaVersion = 1

    public enum CodecError: Error, Equatable {
        case newerVersion(Int)   // 백업이 앱보다 최신 → 거부(§5.5.1)
        case corrupt
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let isoFormatter = ISO8601DateFormatter()

    public static func dayString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// "yyyy-MM-dd" → 현재 캘린더 start-of-day (§5.5.1 재임포트 규칙)
    public static func day(from string: String) -> Date? {
        dayFormatter.date(from: string).map { Calendar.current.startOfDay(for: $0) }
    }

    public static func instantString(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    public static func instant(from string: String) -> Date? {
        isoFormatter.date(from: string)
    }

    public static func encode(_ envelope: ExportEnvelopeV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    public static func decode(_ data: Data) throws -> ExportEnvelopeV1 {
        struct VersionProbe: Codable { var schemaVersion: Int }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let probe = try? decoder.decode(VersionProbe.self, from: data) else {
            throw CodecError.corrupt
        }
        if probe.schemaVersion > schemaVersion {
            throw CodecError.newerVersion(probe.schemaVersion)
        }
        do {
            return try decoder.decode(ExportEnvelopeV1.self, from: data)
        } catch {
            throw CodecError.corrupt
        }
    }
}
