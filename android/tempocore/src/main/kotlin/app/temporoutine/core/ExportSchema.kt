// 템포루틴 — 내보내기/재임포트 직렬화 (MASTER §5.5.1 / §5.5.4 LOCKED)
// iOS TempoCore/ExportSchema.swift 1:1 이식. schemaVersion=1. 날짜-키 필드는 date-only "yyyy-MM-dd", 타임스탬프는 ISO8601(초 단위).
// 키 정렬은 iOS(sortedKeys)와 다르다 — 크로스플랫폼 동치는 바이트가 아니라 의미(파싱 트리)로 본다(계획서 「이식 함정」).

package app.temporoutine.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.time.temporal.ChronoUnit
import java.util.UUID

/** iOS `UUID` 문자열 표기(대문자)와 맞춘다. 읽기는 대소문자 무관. */
object UUIDSerializer : KSerializer<UUID> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("UUID", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: UUID) = encoder.encodeString(value.toString().uppercase())
    override fun deserialize(decoder: Decoder): UUID = try {
        UUID.fromString(decoder.decodeString())
    } catch (e: IllegalArgumentException) {
        throw SerializationException("invalid UUID", e)
    }
}

/** iOS `.iso8601` 전략(초 단위, `Z`)과 맞춘다. 읽기는 분수초·오프셋도 허용. */
object InstantSerializer : KSerializer<Instant> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("Instant", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: Instant) = encoder.encodeString(ExportCodec.instantString(value))
    override fun deserialize(decoder: Decoder): Instant =
        ExportCodec.instant(decoder.decodeString()) ?: throw SerializationException("invalid instant")
}

typealias SerialUUID = @Serializable(with = UUIDSerializer::class) UUID
typealias SerialInstant = @Serializable(with = InstantSerializer::class) Instant

// 온보딩(§3.10)서 선택하는 추적 옵션 신호 — 단일 출처는 앱 설정.
@Serializable
data class TrackedSignals(
    val sleep: Boolean,
    val pain: Boolean,
    val appetite: Boolean,
    val note: Boolean,
    /** 예민함(2026-08-04) — nullable이 아니면 구 저장분이 통째로 디코딩 실패한다. 읽기는 `tracksIrritability`. */
    val irritability: Boolean? = true,
) {
    val tracksIrritability: Boolean get() = irritability ?: true
}

// ── DTO (엔티티 평문 미러, UUID 보존) ──

@Serializable
data class PeriodDayDTO(
    val day: String,              // "yyyy-MM-dd"
    val origin: String,           // PeriodDayOrigin rawValue
    val healthKitUUID: SerialUUID? = null,
)

@Serializable
data class ScheduleItemDTO(
    val id: SerialUUID,
    val title: String,
    val date: String,             // isAllDay=true → "yyyy-MM-dd" / false → ISO8601 instant
    val isAllDay: Boolean,
    val repeatRule: ScheduleRepeat,
    val createdAt: SerialInstant,
    val endDate: String? = null,        // 종료(ISO8601 instant). 종일 일정은 endDay가 정본
    val reminderMinutes: Int? = null,   // null·음수 = 알림 없음 / 0 = 정시 / N = N분 전
    val endDay: String? = null,         // 종일 일정의 종료 date-only — 읽기는 이쪽 우선
)

@Serializable
data class InputItemDTO(
    val id: SerialUUID,
    val title: String,
    val category: InputCategory,
    val schedule: InputSchedule,
    val createdAt: SerialInstant,
    val backfilled: Boolean? = null,
    val timeMinutes: Int? = null,
    val progressKind: OutputProgressKind? = null,
    val targetSessions: Int? = null,
    val targetSeconds: Int? = null,
    val subtasks: List<InputSubtaskDTO>? = null,
)

/** Input 체크리스트 항목 — 이름·순서만. isDone이 없는 게 OutputSubtaskDTO와의 차이다. */
@Serializable
data class InputSubtaskDTO(
    val id: SerialUUID,
    val title: String,
    val order: Int,
)

/** Input의 그날치 진행. 아이템 × 날짜 하나. 실행 중인 타이머는 싣지 않는다. */
@Serializable
data class InputProgressDTO(
    val id: SerialUUID,
    val itemID: SerialUUID,
    /** ⚠ instant — 날짜-키 규칙 위반의 잔재(구 빌드 호환 병기). 읽기는 `day` 우선. */
    val occurredOn: SerialInstant,
    val loggedSessions: Int,
    val percent: Double,
    val elapsedSeconds: Double,
    val doneSubtaskIDs: List<SerialUUID>,
    val day: String? = null,
)

@Serializable
data class OutputSubtaskDTO(
    val id: SerialUUID,
    val title: String,
    val isDone: Boolean,
    val order: Int,
)

@Serializable
data class OutputItemDTO(
    val id: SerialUUID,
    val title: String,
    val schedule: OutputSchedule,
    val progressKind: OutputProgressKind,
    val subtasks: List<OutputSubtaskDTO>,
    val targetSessions: Int,
    val loggedSessions: Int,
    val percent: Double,
    val createdAt: SerialInstant,
    val targetDate: SerialInstant? = null,
    val targetSeconds: Int? = null,
    val elapsedSeconds: Double? = null,
    val timeMinutes: Int? = null,
)

@Serializable
data class ItemCompletionDTO(
    val id: SerialUUID,
    val itemID: SerialUUID,
    val occurredOn: String,       // "yyyy-MM-dd"
    val completedAt: SerialInstant,
)

@Serializable
data class DailyCheckInDTO(
    val id: SerialUUID,
    val day: String,              // "yyyy-MM-dd" (dedup 키)
    val energy: Int,
    val mood: Int,
    val sleep: Int? = null,
    val pain: Int? = null,
    val appetite: Int? = null,
    val note: String? = null,
    val createdAt: SerialInstant,
    val irritability: Int? = null,
    val isBackfilled: Boolean? = null,
    val completedAt: SerialInstant? = null,
    val symptoms: String? = null,
)

// ── 리듬 엔진 산출물 (개정 M-6c) — 재임포트 시 무시(read-only) ──
@Serializable
data class RhythmSummaryDTO(
    val engineVersion: String,        // "window-stats-1"
    val computedAt: SerialInstant,
    val constants: Constants,
    val menstrualLength: Int,
    val usableCycles: Int,
    val profile: List<Cell>,
    val perCycleRanges: List<Double>,
    val preMenstrualWindow: Int? = null,
    val h1SummerMoodLift: Boolean? = null,
    val rhythmType: String? = null,
) {
    /** 계산에 쓰인 상수 동봉 — 상수 개정 전후 파일이 섞여도 비교가 성립(재현성). */
    @Serializable
    data class Constants(
        val recentCycles: Int,
        val minCycles: Int,
        val minSamplesPerCycle: Int,
        val margin: Double,
        val lowDayFraction: Double,
        val baselineRange: Double,
        val preWindowLo: Int,
        val preWindowHi: Int,
    ) {
        companion object {
            val current: Constants
                get() = Constants(
                    recentCycles = WindowStatsEngine.RECENT_CYCLES,
                    minCycles = WindowStatsEngine.MIN_CYCLES,
                    minSamplesPerCycle = WindowStatsEngine.MIN_SAMPLES_PER_CYCLE,
                    margin = WindowStatsEngine.MARGIN,
                    lowDayFraction = WindowStatsEngine.LOW_DAY_FRACTION,
                    baselineRange = WindowStatsEngine.BASELINE_RANGE,
                    preWindowLo = WindowStatsEngine.PRE_WINDOW_RANGE.first,
                    preWindowHi = WindowStatsEngine.PRE_WINDOW_RANGE.last,
                )
        }
    }

    @Serializable
    data class Cell(
        val phase: String,        // CyclePhase rawValue
        val signal: String,       // WindowSignal rawValue
        val median: Double,
        val cyclesWithData: Int,
    )

    companion object {
        /** 엔진 산출 일괄 — 같은 모듈이라 내부 판정 함수와 정확히 같은 기준을 쓴다. */
        fun build(cycles: List<WindowCycle>, menstrualLength: Int = 5, computedAt: Instant): RhythmSummaryDTO {
            val usable = WindowStatsEngine.usable(cycles)
            return RhythmSummaryDTO(
                engineVersion = "window-stats-1",
                computedAt = computedAt,
                constants = Constants.current,
                menstrualLength = menstrualLength,
                usableCycles = usable.size,
                profile = WindowStatsEngine.profile(cycles, menstrualLength).map {
                    Cell(it.phase.rawValue, it.signal.rawValue, it.median, it.cyclesWithData)
                },
                perCycleRanges = usable.mapNotNull { WindowStatsEngine.perCycleRange(it, menstrualLength = menstrualLength) },
                preMenstrualWindow = WindowStatsEngine.preMenstrualWindow(cycles),
                h1SummerMoodLift = WindowStatsEngine.h1SummerMoodLift(cycles, menstrualLength),
                rhythmType = WindowStatsEngine.classify(cycles, menstrualLength)?.rawValue,
            )
        }
    }
}

// ── 씨앗 소비 원장 (§3.8.1) — 늘기만 하는 맵, 병합은 합집합 ──
@Serializable
data class SeedLedgerDTO(
    /** 보유 테마 rawValue → 그때 낸 씨앗 수. 승계분은 0. */
    val purchases: Map<String, Int> = emptyMap(),
    /** 수령한 공지 id → 그때 받은 씨앗 수. */
    val claims: Map<String, Int> = emptyMap(),
    /** 맵 원장 이전 판에서 넘어온 수령 총액 — 병합은 max. */
    val legacyBonus: Int = 0,
    /** 획득 원장 — 씨앗을 받은 날 "yyyy-MM-dd" 집합. nullable = 구 원장 JSON 호환. */
    val earnedDays: List<String>? = null,
) {
    val spent: Int get() = purchases.values.sum()
    val bonus: Int get() = claims.values.sum() + legacyBonus
    val ownedThemes: Set<String> get() = purchases.keys

    /** 합집합 병합. 키가 겹치면 잔액이 부풀지 않는 쪽(소비는 큰 값·수령은 작은 값). 교환·결합·멱등. */
    fun merged(with: SeedLedgerDTO): SeedLedgerDTO {
        val other = with
        val purchasesOut = purchases.toMutableMap()
        for ((theme, paid) in other.purchases) purchasesOut[theme] = maxOf(purchasesOut[theme] ?: paid, paid)
        val claimsOut = claims.toMutableMap()
        for ((notice, seeds) in other.claims) claimsOut[notice] = minOf(claimsOut[notice] ?: seeds, seeds)
        val earned = if (earnedDays != null || other.earnedDays != null) {
            (earnedDays.orEmpty().toSet() + other.earnedDays.orEmpty().toSet()).sorted()
        } else null
        return SeedLedgerDTO(purchasesOut, claimsOut, maxOf(legacyBonus, other.legacyBonus), earned)
    }
}

/** 리듬 설문 응답 — answers = 문항 id → 선택지 문자열. */
@Serializable
data class SelfReportDTO(
    val id: SerialUUID,
    val answers: Map<String, String>,
    val completedAt: SerialInstant,
    val sharedToServer: Boolean,
)

// ── 봉투 ──
@Serializable
data class ExportEnvelopeV1(
    var schemaVersion: Int = ExportCodec.SCHEMA_VERSION,
    val exportedAt: SerialInstant,
    val periodDays: List<PeriodDayDTO>,
    val scheduleItems: List<ScheduleItemDTO>,
    val inputItems: List<InputItemDTO>,
    val outputItems: List<OutputItemDTO>,
    val completions: List<ItemCompletionDTO>,
    val checkIns: List<DailyCheckInDTO>,
    val trackedSignals: TrackedSignals,
    /** 재임포트는 읽지 않는다(read-only 산출물). */
    val rhythmSummary: RhythmSummaryDTO? = null,
    /** 재임포트는 이 필드를 병합한다(덮어쓰기 아님). */
    val seedLedger: SeedLedgerDTO? = null,
    val inputProgress: List<InputProgressDTO>? = null,
    val selfReports: List<SelfReportDTO>? = null,
)

// ── 코덱 ──
object ExportCodec {
    const val SCHEMA_VERSION = 1

    sealed class CodecError(message: String) : Exception(message) {
        /** 백업이 앱보다 최신 → 거부(§5.5.1) */
        data class NewerVersion(val version: Int) : CodecError("newer schema version $version")
        data object Corrupt : CodecError("corrupt export file") {
            private fun readResolve(): Any = Corrupt
        }
    }

    /** iOS JSONDecoder처럼 모르는 키는 무시(전방 호환). null 옵셔널은 키 자체를 생략(iOS 동형). */
    val json: Json = Json {
        prettyPrint = true
        encodeDefaults = true
        explicitNulls = false
        ignoreUnknownKeys = true
    }

    fun dayString(date: LocalDate): String = date.format(DateTimeFormatter.ISO_LOCAL_DATE)

    /** "yyyy-MM-dd" → LocalDate (§5.5.1 재임포트 규칙) */
    fun day(from: String): LocalDate? = try {
        LocalDate.parse(from, DateTimeFormatter.ISO_LOCAL_DATE)
    } catch (e: DateTimeParseException) {
        null
    }

    fun instantString(date: Instant): String =
        DateTimeFormatter.ISO_INSTANT.format(date.truncatedTo(ChronoUnit.SECONDS))

    fun instant(from: String): Instant? = try {
        Instant.parse(from)
    } catch (e: DateTimeParseException) {
        try {
            OffsetDateTime.parse(from).toInstant()
        } catch (e2: DateTimeParseException) {
            null
        }
    }

    fun encode(envelope: ExportEnvelopeV1): String = json.encodeToString(ExportEnvelopeV1.serializer(), envelope)

    fun decode(text: String): ExportEnvelopeV1 {
        val probe = try {
            json.parseToJsonElement(text) as? JsonObject
        } catch (e: SerializationException) {
            null
        } ?: throw CodecError.Corrupt
        val version = (probe["schemaVersion"] as? JsonPrimitive)?.intOrNull ?: throw CodecError.Corrupt
        if (version > SCHEMA_VERSION) throw CodecError.NewerVersion(version)
        return try {
            json.decodeFromString(ExportEnvelopeV1.serializer(), text)
        } catch (e: SerializationException) {
            throw CodecError.Corrupt
        } catch (e: IllegalArgumentException) {
            throw CodecError.Corrupt
        }
    }
}
