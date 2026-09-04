// 템포루틴 Android — Room 엔티티 10종 (iOS @Model 미러, MASTER §5.5 / §5.5.2 / §5.5.3)
// iOS 규칙 승계: 전 프로퍼티 기본값, unique 제약 없음(dedup은 쓰기 경로), 연관값 enum·복합값은
// JSON 문자열 컬럼 + 계산 프로퍼티 노출(iOS `scheduleData`/`doneSubtaskData` 동형).
// 날짜: 날짜-키(day·occurredOn)는 LocalDate, 타임스탬프는 Instant.

package app.temporoutine.android.data

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import androidx.room.TypeConverter
import app.temporoutine.core.ExportCodec
import app.temporoutine.core.InputSchedule
import app.temporoutine.core.OutputProgressKind
import app.temporoutine.core.OutputSchedule
import app.temporoutine.core.ProgressGoal
import app.temporoutine.core.ProgressState
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import java.time.Instant
import java.time.LocalDate
import java.util.UUID

class Converters {
    @TypeConverter fun localDateToString(value: LocalDate?): String? = value?.toString()
    @TypeConverter fun stringToLocalDate(value: String?): LocalDate? = value?.let(LocalDate::parse)
    @TypeConverter fun instantToLong(value: Instant?): Long? = value?.toEpochMilli()
    @TypeConverter fun longToInstant(value: Long?): Instant? = value?.let(Instant::ofEpochMilli)
}

/** iOS UUID 문자열 표기(대문자)와 맞춘다 — 내보내기 봉투·재연결 키가 이 문자열이다. */
fun newId(): String = UUID.randomUUID().toString().uppercase()

/** 생리 기록 원본. iOS `PeriodDayOrigin` rawValue. */
object PeriodDayOrigin {
    const val LOCAL = "local"
    const val APP_AUTHORED = "appAuthored"
    const val HEALTH_KIT_IMPORTED = "healthKitImported"
}

/** §5.5.4 일별 생리 기록 — 하루 1개(dedup 키 = day, 쓰기 경로가 보장). */
@Entity(tableName = "period_days", indices = [Index("day")])
data class PeriodDayEntity(
    @PrimaryKey val id: String = newId(),
    val day: LocalDate,
    val origin: String = PeriodDayOrigin.LOCAL,
    val healthKitUUID: String? = null,
)

/** 아픈 날 증상 — 질병(cold·fever·stomach)은 집계 가중 0, 통증(muscle·headache)은 1. */
enum class CheckInSymptom(val rawValue: String, val isIllness: Boolean) {
    COLD("cold", true),
    FEVER("fever", true),
    STOMACH("stomach", true),
    MUSCLE("muscle", false),
    HEADACHE("headache", false);

    companion object {
        fun fromRaw(raw: String): CheckInSymptom? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** §3.4 데일리 체크인 — day 기준 upsert(하루 1개). 단계는 저장하지 않는다(집계 시 도출). */
@Entity(tableName = "daily_check_ins", indices = [Index("day")])
data class DailyCheckInEntity(
    @PrimaryKey val id: String = newId(),
    val day: LocalDate,
    val energy: Int = 0,            // 1...5 (UI 3탭 = 1·3·5), 0 = 미기록
    val mood: Int = 0,              // 1...5, 0 = 미기록
    val sleep: Int? = null,
    val pain: Int? = null,
    val appetite: Int? = null,
    val irritability: Int? = null,
    val note: String? = null,
    val createdAt: Instant = Instant.now(),
    val isBackfilled: Boolean = false,
    /** 체크인이 처음 완성된 시각(씨앗 근거). null = 미완성. 한 번 찍히면 되돌리지 않는다. */
    val completedAt: Instant? = null,
    /** 증상 raw 콤마 구분("cold,muscle"), 정렬 저장. */
    val symptoms: String = "",
) {
    val symptomSet: Set<CheckInSymptom>
        get() = symptoms.split(",").mapNotNull { CheckInSymptom.fromRaw(it) }.toSet()

    /** 집계 가중 — 질병 0(완전 제외) / 그 외 1. */
    val aggregationWeight: Double get() = if (symptomSet.any { it.isIllness }) 0.0 else 1.0

    companion object {
        fun joinSymptoms(set: Set<CheckInSymptom>): String = set.map { it.rawValue }.sorted().joinToString(",")
    }
}

/** ① 일정 카드 — 절대 날짜 / 연 반복. 계절 레버 없음. */
@Entity(tableName = "schedule_items")
data class ScheduleItemEntity(
    @PrimaryKey val id: String = newId(),
    val title: String = "",
    val date: Instant,                       // 시작(절대). 종일이면 그날 자정(기기 시간대)
    val endDate: Instant? = null,            // 시간 지정=종료 시각 / 종일=종료 날짜. null = 하루짜리
    val isAllDay: Boolean = true,
    val repeatRule: String = "none",         // ScheduleRepeat rawValue
    val reminderMinutes: Int = -1,           // -1 없음 / 0 정시 / N분 전
    val createdAt: Instant = Instant.now(),
)

/** ② Input 카드 — 채움. 진행 방식은 정의만, 그날의 값은 InputProgress. */
@Entity(tableName = "input_items")
data class InputItemEntity(
    @PrimaryKey val id: String = newId(),
    val title: String = "",
    val category: String = "other",          // InputCategory rawValue
    val progressKindRaw: String = "",        // "" = 단순 체크
    val targetSessions: Int = 0,
    val targetSeconds: Int? = null,
    val scheduleJson: String = "",           // InputSchedule JSON. 빈 문자열 = daily 폴백
    val createdAt: Instant = Instant.now(),
    /** 지난 날짜에 소급해 적은 기록인가 — .once의 "완료 전까지 이어짐"을 끈다. */
    val backfilled: Boolean = false,
    val timeMinutes: Int? = null,            // 자정 기준 분
) {
    val schedule: InputSchedule
        get() = decodeOrNull(scheduleJson, InputSchedule.serializer()) ?: InputSchedule.Daily

    /** null = 단순 체크 */
    val progressKind: OutputProgressKind? get() = OutputProgressKind.fromRawValue(progressKindRaw)

    fun progressGoal(subtaskCount: Int): ProgressGoal? =
        progressKind?.let { ProgressGoal(it, targetSessions, targetSeconds, subtaskCount) }

    companion object {
        fun encodeSchedule(schedule: InputSchedule): String =
            ExportCodec.json.encodeToString(InputSchedule.serializer(), schedule)
    }
}

/** Input 서브태스크 — 이름·순서만(완료 여부는 날짜별이라 InputProgress가 갖는다). */
@Entity(tableName = "input_subtasks", indices = [Index("ownerId")])
data class InputSubtaskEntity(
    @PrimaryKey val id: String = newId(),
    val ownerId: String,
    val title: String = "",
    @ColumnInfo(name = "sort_order") val order: Int = 0,
)

/** Input의 그날치 진행. 한 아이템 × 한 날짜에 하나. 완료는 ItemCompletion이 맡는다. */
@Entity(tableName = "input_progress", indices = [Index("itemId"), Index("occurredOn")])
data class InputProgressEntity(
    @PrimaryKey val id: String = newId(),
    val itemId: String,
    val occurredOn: LocalDate,
    val loggedSessions: Int = 0,
    val percent: Double = 0.0,               // 0~1
    val elapsedAccumSeconds: Double = 0.0,
    val timerStartedAt: Instant? = null,     // 진행 중 시작 앵커 — null = 멈춤
    val doneSubtaskJson: String = "",        // [UUID] JSON
) : TimerBacking {
    val doneSubtaskIds: Set<String>
        get() = decodeOrNull(doneSubtaskJson, ListSerializer(String.serializer()))?.map { it.uppercase() }?.toSet() ?: emptySet()

    fun withDoneSubtaskIds(ids: Set<String>): InputProgressEntity =
        copy(doneSubtaskJson = ExportCodec.json.encodeToString(ListSerializer(String.serializer()), ids.sorted()))

    override val accumSeconds: Double get() = elapsedAccumSeconds
    override val startedAt: Instant? get() = timerStartedAt

    fun state(now: Instant = Instant.now()): ProgressState =
        ProgressState(loggedSessions, percent, elapsedSeconds(now), doneSubtaskIds.size)
}

/** 발생 완료 — 상대 저장이라 완료는 절대 날짜로. Input 전용(§5.5.2). 레코드 존재 = 완료. */
@Entity(tableName = "item_completions", indices = [Index("itemId"), Index("occurredOn")])
data class ItemCompletionEntity(
    @PrimaryKey val id: String = newId(),
    val itemId: String,
    val occurredOn: LocalDate,
    val completedAt: Instant = Instant.now(),
)

/** ③ Output 카드 — 내보냄. 진행도는 아이템 수명 누적, 완료는 파생(§5.5.2). */
@Entity(tableName = "output_items")
data class OutputItemEntity(
    @PrimaryKey val id: String = newId(),
    val title: String = "",
    val scheduleJson: String = "",           // OutputSchedule JSON. 빈 문자열 = daily 폴백
    val progressKind: String = "percent",    // OutputProgressKind rawValue
    val targetSessions: Int = 0,
    val loggedSessions: Int = 0,
    val percent: Double = 0.0,
    val createdAt: Instant = Instant.now(),
    val targetDate: Instant? = null,         // 디데이
    val targetSeconds: Int? = null,
    val elapsedAccumSeconds: Double = 0.0,
    val timerStartedAt: Instant? = null,
    val timeMinutes: Int? = null,
) : TimerBacking {
    val schedule: OutputSchedule
        get() = decodeOrNull(scheduleJson, OutputSchedule.serializer()) ?: OutputSchedule.Daily

    val kind: OutputProgressKind get() = OutputProgressKind.fromRawValue(progressKind) ?: OutputProgressKind.PERCENT

    override val accumSeconds: Double get() = elapsedAccumSeconds
    override val startedAt: Instant? get() = timerStartedAt

    fun progressGoal(subtaskCount: Int): ProgressGoal = ProgressGoal(kind, targetSessions, targetSeconds, subtaskCount)

    fun progressState(doneSubtasks: Int, now: Instant = Instant.now()): ProgressState =
        ProgressState(loggedSessions, percent, elapsedSeconds(now), doneSubtasks)

    companion object {
        fun encodeSchedule(schedule: OutputSchedule): String =
            ExportCodec.json.encodeToString(OutputSchedule.serializer(), schedule)
    }
}

@Entity(tableName = "output_subtasks", indices = [Index("ownerId")])
data class OutputSubtaskEntity(
    @PrimaryKey val id: String = newId(),
    val ownerId: String,
    val title: String = "",
    val isDone: Boolean = false,
    @ColumnInfo(name = "sort_order") val order: Int = 0,
)

/** 앱 내 자기보고 설문 응답(v1.6 §4). Phase 1엔 화면이 없지만 스키마 v1에 포함(마이그레이션 회피). */
@Entity(tableName = "self_reports")
data class SelfReportEntity(
    @PrimaryKey val id: String = newId(),
    val answersJson: String = "{}",
    val completedAt: Instant = Instant.now(),
    val sharedToServer: Boolean = false,
) {
    val answers: Map<String, String>
        get() = decodeOrNull(answersJson, MapSerializer(String.serializer(), String.serializer())) ?: emptyMap()
}

/** 타이머 저장처 통일 — 컨트롤은 이 계약만 알고 어느 카드인지 모른다. */
interface TimerBacking {
    val accumSeconds: Double
    val startedAt: Instant?
    val isTimerRunning: Boolean get() = startedAt != null

    /** 현재 경과(초) — 누적 + 진행 중 델타 */
    fun elapsedSeconds(now: Instant = Instant.now()): Double =
        accumSeconds + (startedAt?.let { maxOf(0.0, (now.toEpochMilli() - it.toEpochMilli()) / 1000.0) } ?: 0.0)
}

private fun <T> decodeOrNull(json: String, serializer: kotlinx.serialization.KSerializer<T>): T? {
    if (json.isBlank()) return null
    return try {
        ExportCodec.json.decodeFromString(serializer, json)
    } catch (e: SerializationException) {
        null
    } catch (e: IllegalArgumentException) {
        null
    }
}
