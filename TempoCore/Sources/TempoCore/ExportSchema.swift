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
    /// 예민함(2026-08-04, 핸드오프 v1.5 §3-1) — 정서 계열의 두 번째 문항.
    /// ⚠ optional이 아니면 구 UserDefaults JSON이 통째로 디코딩 실패한다(키가 없어서).
    /// 읽기는 `tracksIrritability` 한 창구로 — 구 저장분은 기본 켬으로 본다.
    public var irritability: Bool?

    public var tracksIrritability: Bool { irritability ?? true }

    public init(sleep: Bool, pain: Bool, appetite: Bool, note: Bool, irritability: Bool = true) {
        self.sleep = sleep
        self.pain = pain
        self.appetite = appetite
        self.note = note
        self.irritability = irritability
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
    // v1 내 추가 필드(2026-07-22 일정 시트 개편) — optional이라 구 백업 decode 시 nil로 흡수
    public var endDate: String?         // 종료(ISO8601 instant). 종일 일정은 endDay가 정본, 이건 구 빌드 호환용 병기
    public var reminderMinutes: Int?    // nil·음수 = 알림 없음 / 0 = 정시 / N = N분 전
    /// 종일 일정의 종료 **date-only**(2026-08-20 감사 — instant만 있으면 파일 머리말의 날짜-키
    /// 규칙 위반: 시차 이동 후 재임포트·동기화에서 마지막 날이 하루 민다). 쓰기는 endDate와
    /// 병기(구 빌드는 instant를 계속 읽는다), 읽기는 이쪽 우선.
    public var endDay: String?

    public init(id: UUID, title: String, date: String, isAllDay: Bool, repeatRule: ScheduleRepeat,
                createdAt: Date, endDate: String? = nil, reminderMinutes: Int? = nil,
                endDay: String? = nil) {
        self.id = id
        self.title = title
        self.date = date
        self.isAllDay = isAllDay
        self.repeatRule = repeatRule
        self.createdAt = createdAt
        self.endDate = endDate
        self.reminderMinutes = reminderMinutes
        self.endDay = endDay
    }
}

public struct InputItemDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var category: InputCategory
    public var schedule: InputSchedule
    public var createdAt: Date
    /// 소급 기록 여부(2026-07-27, v1 내 optional 추가 — 구 봉투는 nil=false).
    /// 빠지면 복원 시 소급 .once가 "완료 전까지 이어짐"으로 되살아난다.
    public var backfilled: Bool?
    /// 하루 중 시각(자정 기준 분, 2026-08-09 — 제목 시각 파서. 같은 optional 패턴)
    public var timeMinutes: Int?
    /// 진행 방식 **정의**(2026-08-12, 같은 optional 패턴 — 구 봉투는 nil = 단순 체크).
    /// 그날의 값은 여기가 아니라 `ExportEnvelopeV1.inputProgress`에 따로 실린다.
    public var progressKind: OutputProgressKind?
    public var targetSessions: Int?
    public var targetSeconds: Int?
    /// 이름·순서만 — 완료 여부는 날짜별이라 아이템에 실을 수 없다(OutputSubtaskDTO와 다른 점)
    public var subtasks: [InputSubtaskDTO]?

    public init(id: UUID, title: String, category: InputCategory, schedule: InputSchedule,
                createdAt: Date, backfilled: Bool? = nil, timeMinutes: Int? = nil,
                progressKind: OutputProgressKind? = nil, targetSessions: Int? = nil,
                targetSeconds: Int? = nil, subtasks: [InputSubtaskDTO]? = nil) {
        self.id = id
        self.title = title
        self.category = category
        self.schedule = schedule
        self.createdAt = createdAt
        self.backfilled = backfilled
        self.timeMinutes = timeMinutes
        self.progressKind = progressKind
        self.targetSessions = targetSessions
        self.targetSeconds = targetSeconds
        self.subtasks = subtasks
    }
}

/// Input 체크리스트 항목 — 이름·순서만. isDone이 없는 게 OutputSubtaskDTO와의 차이다(2026-08-12).
public struct InputSubtaskDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var order: Int

    public init(id: UUID, title: String, order: Int) {
        self.id = id
        self.title = title
        self.order = order
    }
}

/// Input의 그날치 진행(2026-08-12). 아이템 × 날짜 하나.
/// 실행 중인 타이머는 싣지 않는다 — 실행 상태는 이 기기 것이다(OutputItemDTO.elapsedSeconds와 같은 계약).
public struct InputProgressDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var itemID: UUID
    /// ⚠ instant — 날짜-키 규칙 위반의 잔재(구 빌드 호환 병기). 읽기는 `day` 우선.
    public var occurredOn: Date
    public var loggedSessions: Int
    public var percent: Double
    public var elapsedSeconds: Double
    public var doneSubtaskIDs: [UUID]
    /// 날짜-키 **date-only** "yyyy-MM-dd"(2026-08-20 감사 — instant만 있으면 시차 이동 시
    /// 진행이 전날/다음날 칸에 붙어 「체크는 됐는데 진행 막대는 0」이 된다).
    public var day: String?

    public init(id: UUID, itemID: UUID, occurredOn: Date, loggedSessions: Int,
                percent: Double, elapsedSeconds: Double, doneSubtaskIDs: [UUID],
                day: String? = nil) {
        self.id = id
        self.itemID = itemID
        self.occurredOn = occurredOn
        self.loggedSessions = loggedSessions
        self.percent = percent
        self.elapsedSeconds = elapsedSeconds
        self.doneSubtaskIDs = doneSubtaskIDs
        self.day = day
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
    /// 목표일(디데이, 2026-08-01 베타 피드백). Optional = 구버전 백업엔 키가 없다(자동 합성이 nil로 흡수).
    public var targetDate: Date?
    /// 타이머·스톱워치(2026-08-09, 같은 optional 패턴). elapsedSeconds = 내보내는 순간의
    /// 정지 스냅샷(실행 중 델타 접어서) — 실행 상태 자체는 이 기기 것이라 봉투에 안 싣는다.
    public var targetSeconds: Int?
    public var elapsedSeconds: Double?
    /// 하루 중 시각(자정 기준 분, 2026-08-09 — InputItemDTO와 동일 계약)
    public var timeMinutes: Int?

    public init(id: UUID, title: String, schedule: OutputSchedule, progressKind: OutputProgressKind,
                subtasks: [OutputSubtaskDTO], targetSessions: Int, loggedSessions: Int,
                percent: Double, createdAt: Date, targetDate: Date? = nil,
                targetSeconds: Int? = nil, elapsedSeconds: Double? = nil, timeMinutes: Int? = nil) {
        self.id = id
        self.title = title
        self.schedule = schedule
        self.progressKind = progressKind
        self.subtasks = subtasks
        self.targetSessions = targetSessions
        self.loggedSessions = loggedSessions
        self.percent = percent
        self.createdAt = createdAt
        self.targetDate = targetDate
        self.targetSeconds = targetSeconds
        self.elapsedSeconds = elapsedSeconds
        self.timeMinutes = timeMinutes
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
    /// 2026-08-04 추가 — 둘 다 optional/기본값이라 구 내보내기 파일도 그대로 재임포트된다
    public var irritability: Int?
    public var isBackfilled: Bool?
    /// 2026-08-09 추가(같은 optional 패턴) — 씨앗 재화 근거(체크인 최초 완성 시각).
    /// 백업·전체 삭제 undo가 이 봉투를 쓰므로 동봉하지 않으면 복원 때 씨앗이 사라진다.
    public var completedAt: Date?
    /// 2026-09-01 추가(같은 optional 패턴) — 아픈 날 증상 raw 콤마 구분("cold,muscle").
    public var symptoms: String?

    public init(id: UUID, day: String, energy: Int, mood: Int, sleep: Int?, pain: Int?,
                appetite: Int?, note: String?, createdAt: Date,
                irritability: Int? = nil, isBackfilled: Bool? = nil, completedAt: Date? = nil,
                symptoms: String? = nil) {
        self.id = id
        self.day = day
        self.energy = energy
        self.mood = mood
        self.sleep = sleep
        self.pain = pain
        self.appetite = appetite
        self.note = note
        self.createdAt = createdAt
        self.irritability = irritability
        self.isBackfilled = isBackfilled
        self.completedAt = completedAt
        self.symptoms = symptoms
    }
}

// ── 리듬 엔진 산출물 (개정 M-6c 2026-08-08 — 스펙 SSOT = 개정M_내보내기_스키마_초안.md) ──
// 목적: ① 베타 자발 공유 파일만으로 엔진 판정 재현·분석(도구가 엔진 재구현 불필요)
// ② 향후 옵트인 "연구 참여"의 전송 페이로드 미리보기 = 정확히 이 블록.
// 재임포트 시 무시(read-only) — 산출물은 원시 데이터에서 재계산이 진실. 봉투 안 원시 데이터에서
// 전부 유도 가능한 값이라 새 민감도 계층을 만들지 않는다.
public struct RhythmSummaryDTO: Codable, Equatable, Sendable {

    /// 계산에 쓰인 상수 동봉 — 상수 개정(앱 업데이트) 전후 파일이 섞여도 비교가 성립(재현성, 루프 2).
    public struct Constants: Codable, Equatable, Sendable {
        public var recentCycles: Int
        public var minCycles: Int
        public var minSamplesPerCycle: Int
        public var margin: Double
        public var lowDayFraction: Double
        public var baselineRange: Double
        public var preWindowLo: Int
        public var preWindowHi: Int

        public static var current: Constants {
            Constants(recentCycles: WindowStatsEngine.recentCycles,
                      minCycles: WindowStatsEngine.minCycles,
                      minSamplesPerCycle: WindowStatsEngine.minSamplesPerCycle,
                      margin: WindowStatsEngine.margin,
                      lowDayFraction: WindowStatsEngine.lowDayFraction,
                      baselineRange: WindowStatsEngine.baselineRange,
                      preWindowLo: WindowStatsEngine.preWindowRange.lowerBound,
                      preWindowHi: WindowStatsEngine.preWindowRange.upperBound)
        }

        public init(recentCycles: Int, minCycles: Int, minSamplesPerCycle: Int, margin: Double,
                    lowDayFraction: Double, baselineRange: Double, preWindowLo: Int, preWindowHi: Int) {
            self.recentCycles = recentCycles
            self.minCycles = minCycles
            self.minSamplesPerCycle = minSamplesPerCycle
            self.margin = margin
            self.lowDayFraction = lowDayFraction
            self.baselineRange = baselineRange
            self.preWindowLo = preWindowLo
            self.preWindowHi = preWindowHi
        }
    }

    public struct Cell: Codable, Equatable, Sendable {
        public var phase: String        // CyclePhase rawValue
        public var signal: String       // WindowSignal rawValue
        public var median: Double
        public var cyclesWithData: Int

        public init(phase: String, signal: String, median: Double, cyclesWithData: Int) {
            self.phase = phase
            self.signal = signal
            self.median = median
            self.cyclesWithData = cyclesWithData
        }
    }

    public var engineVersion: String        // "window-stats-1" — 구 푸리에 산출물과 구분
    public var computedAt: Date
    public var constants: Constants
    public var menstrualLength: Int         // §5.3 층 2 M — 계절 경계 재현에 필요(개정 M)
    public var usableCycles: Int
    public var profile: [Cell]
    public var perCycleRanges: [Double]     // A₀ 재보정 분석의 원료(§5.12 미결)
    public var preMenstrualWindow: Int?     // nil = 합의 없음(디폴트 사용 중)
    public var h1SummerMoodLift: Bool?      // nil = 불확정
    public var rhythmType: String?          // nil = 데이터 부족

    public init(engineVersion: String, computedAt: Date, constants: Constants, menstrualLength: Int,
                usableCycles: Int, profile: [Cell], perCycleRanges: [Double], preMenstrualWindow: Int?,
                h1SummerMoodLift: Bool?, rhythmType: String?) {
        self.engineVersion = engineVersion
        self.computedAt = computedAt
        self.constants = constants
        self.menstrualLength = menstrualLength
        self.usableCycles = usableCycles
        self.profile = profile
        self.perCycleRanges = perCycleRanges
        self.preMenstrualWindow = preMenstrualWindow
        self.h1SummerMoodLift = h1SummerMoodLift
        self.rhythmType = rhythmType
    }

    /// 엔진 산출 일괄 — 같은 모듈이라 내부 판정 함수(usable·perCycleRange)와 정확히 같은 기준을 쓴다.
    public static func build(cycles: [WindowCycle], menstrualLength: Int = 5,
                             computedAt: Date) -> RhythmSummaryDTO {
        let usable = WindowStatsEngine.usable(cycles)
        return RhythmSummaryDTO(
            engineVersion: "window-stats-1",
            computedAt: computedAt,
            constants: .current,
            menstrualLength: menstrualLength,
            usableCycles: usable.count,
            profile: WindowStatsEngine.profile(cycles: cycles, menstrualLength: menstrualLength).map {
                Cell(phase: $0.phase.rawValue, signal: $0.signal.rawValue,
                     median: $0.median, cyclesWithData: $0.cyclesWithData)
            },
            perCycleRanges: usable.compactMap {
                WindowStatsEngine.perCycleRange($0, menstrualLength: menstrualLength)
            },
            preMenstrualWindow: WindowStatsEngine.preMenstrualWindow(cycles: cycles),
            h1SummerMoodLift: WindowStatsEngine.h1SummerMoodLift(cycles: cycles,
                                                                 menstrualLength: menstrualLength),
            rhythmType: WindowStatsEngine.classify(cycles: cycles,
                                                   menstrualLength: menstrualLength)?.rawValue
        )
    }
}

// ── 씨앗 소비 원장 (§3.8.1, 2026-08-11) ──
// 획득은 DailyCheckIn.completedAt 파생이라 체크인을 타고 기기 간에 이어지는데, 소비는 기기마다
// 따로 놀았다(폰에서 산 테마가 패드에선 잠김). 원장을 동기·백업 대상으로 올리면서 자료형을
// **늘기만 하는 맵**으로 바꾼다 — 병합이 합집합이면 왕복 순서에 무관하게 수렴하고, 잔액이
// 음수가 되거나 같은 테마에 두 번 값을 치르는 상태 자체가 만들어지지 않는다.
// (전체 페이로드 last-writer-wins로 두면 폰 구매와 패드 공지 수령이 겹칠 때 한쪽이 통째로 날아간다.)
public struct SeedLedgerDTO: Codable, Equatable, Sendable {
    /// 보유 테마 rawValue → 그때 낸 씨앗 수. 승계분(쓰던 테마 자동 보유)은 0 — 구매분과 구분해야
    /// 병합이 승계를 유료로 오인하지 않는다.
    public var purchases: [String: Int]
    /// 수령한 공지 id → 그때 받은 씨앗 수.
    public var claims: [String: Int]
    /// 맵 원장 이전 판(UserDefaults `seedsBonus`)에서 넘어온 수령 총액. 공지별로 쪼갤 수 없어
    /// 따로 둔다 — 병합은 max(합산하면 같은 공지를 두 기기에서 받은 게 두 배가 된다).
    public var legacyBonus: Int
    /// 획득 원장(2026-08-20 사용자 결정 — 도장 불변 원칙의 원장판): 씨앗을 받은 날
    /// "yyyy-MM-dd" 집합. 체크인 행이 지워져도 획득이 남는다 — 종전엔 행 존재에서 파생해
    /// 기록 정리가 재화 회수가 됐다(철회 비대칭). optional = 구 원장 JSON 호환.
    public var earnedDays: [String]?

    public init(purchases: [String: Int] = [:], claims: [String: Int] = [:], legacyBonus: Int = 0,
                earnedDays: [String]? = nil) {
        self.purchases = purchases
        self.claims = claims
        self.legacyBonus = legacyBonus
        self.earnedDays = earnedDays
    }

    public var spent: Int { purchases.values.reduce(0, +) }
    public var bonus: Int { claims.values.reduce(0, +) + legacyBonus }
    public var ownedThemes: Set<String> { Set(purchases.keys) }

    /// 합집합 병합. 키가 겹치면 잔액이 부풀지 않는 쪽(소비는 큰 값·수령은 작은 값)을 고른다 —
    /// 전부 교환·결합·멱등이라 어느 기기에서 어떤 순서로 돌려도 같은 결과에 수렴한다.
    /// 획득 원장은 합집합(같은 날은 한 번) — 구 빌드가 이 필드를 모른 채 되올려도(nil)
    /// 로컬 원장이 보존된다.
    public func merged(with other: SeedLedgerDTO) -> SeedLedgerDTO {
        var out = self
        for (theme, paid) in other.purchases {
            out.purchases[theme] = max(out.purchases[theme] ?? paid, paid)
        }
        for (notice, seeds) in other.claims {
            out.claims[notice] = min(out.claims[notice] ?? seeds, seeds)
        }
        out.legacyBonus = max(legacyBonus, other.legacyBonus)
        if earnedDays != nil || other.earnedDays != nil {
            out.earnedDays = Array(Set(earnedDays ?? []).union(other.earnedDays ?? [])).sorted()
        }
        return out
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
    /// 개정 M-6c(2026-08-08) — v1 내 optional 추가라 구 파일 decode 무영향(backfilled 패턴).
    /// 재임포트는 이 필드를 읽지 않는다(read-only 산출물).
    public var rhythmSummary: RhythmSummaryDTO?
    /// 씨앗 소비 원장(2026-08-11, §3.8.1) — 같은 optional 추가 패턴. 획득 근거(체크인 completedAt)만
    /// 동봉하던 탓에 백업 복원·기기 이전에서 산 테마가 사라지고 씨앗만 돌아왔다. 재임포트는 이
    /// 필드를 **병합**한다(덮어쓰기 아님 — 「구매한 테마는 사라지지 않아요」).
    public var seedLedger: SeedLedgerDTO?
    /// Input 진행도(2026-08-12) — 아이템의 **정의**는 InputItemDTO에, 그날의 **값**은 여기.
    /// 빠지면 백업 복원·기기 이전에서 오늘 채운 진행이 사라진다(씨앗 원장 P-6와 같은 구멍).
    public var inputProgress: [InputProgressDTO]?
    /// 리듬 설문 응답(2026-08-20 감사 — 「모든 기록 삭제」·백업 양쪽에서 빠져 있던 유일한
    /// @Model). 같은 optional 추가 패턴. dedup = UUID.
    public var selfReports: [SelfReportDTO]?

    public init(exportedAt: Date, periodDays: [PeriodDayDTO], scheduleItems: [ScheduleItemDTO],
                inputItems: [InputItemDTO], outputItems: [OutputItemDTO],
                completions: [ItemCompletionDTO], checkIns: [DailyCheckInDTO],
                trackedSignals: TrackedSignals, rhythmSummary: RhythmSummaryDTO? = nil,
                seedLedger: SeedLedgerDTO? = nil, inputProgress: [InputProgressDTO]? = nil,
                selfReports: [SelfReportDTO]? = nil) {
        self.schemaVersion = ExportCodec.schemaVersion
        self.exportedAt = exportedAt
        self.periodDays = periodDays
        self.scheduleItems = scheduleItems
        self.inputItems = inputItems
        self.outputItems = outputItems
        self.completions = completions
        self.checkIns = checkIns
        self.trackedSignals = trackedSignals
        self.rhythmSummary = rhythmSummary
        self.seedLedger = seedLedger
        self.inputProgress = inputProgress
        self.selfReports = selfReports
    }
}

/// 리듬 설문 응답(2026-08-20) — answers = 문항 id → 선택지 문자열.
public struct SelfReportDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var answers: [String: String]
    public var completedAt: Date
    public var sharedToServer: Bool

    public init(id: UUID, answers: [String: String], completedAt: Date, sharedToServer: Bool) {
        self.id = id
        self.answers = answers
        self.completedAt = completedAt
        self.sharedToServer = sharedToServer
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
