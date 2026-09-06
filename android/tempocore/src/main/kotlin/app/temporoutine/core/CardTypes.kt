// 템포루틴 — 3카드 값 타입 (MASTER §5.5)
// iOS TempoCore/CardTypes.swift 1:1 이식. 연관값 enum은 discriminator(`type`) 커스텀 직렬화(§5.5.1).

package app.temporoutine.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.descriptors.element
import kotlinx.serialization.encoding.CompositeDecoder
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.encoding.decodeStructure
import kotlinx.serialization.encoding.encodeStructure

// ① 일정 카드 — 절대 날짜 / 연 반복 (cycle-anchored 모델 밖)
@Serializable
enum class ScheduleRepeat {
    @SerialName("none") NONE,
    @SerialName("daily") DAILY,
    @SerialName("weekly") WEEKLY,
    @SerialName("monthly") MONTHLY,
    @SerialName("yearly") YEARLY;

    val rawValue: String get() = name.lowercase()

    companion object {
        /** Swift `init?(rawValue:)` 대응 — 봉투·엔티티의 문자열 컬럼에서 되읽을 때. */
        fun fromRawValue(raw: String): ScheduleRepeat? = entries.firstOrNull { it.rawValue == raw }
    }
}

// ② Input 카드
@Serializable
enum class InputCategory {
    @SerialName("food") FOOD,
    @SerialName("exercise") EXERCISE,
    @SerialName("media") MEDIA,
    @SerialName("other") OTHER;

    val rawValue: String get() = name.lowercase()

    companion object {
        fun fromRawValue(raw: String): InputCategory? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** Input 반복. ONCE = 반복 없음(단발 체크). */
@Serializable(with = InputScheduleSerializer::class)
sealed class InputSchedule {
    data object Once : InputSchedule()
    data object Daily : InputSchedule()
    data object Weekly : InputSchedule()      // 생성일과 같은 요일
    data object Monthly : InputSchedule()     // 생성일과 같은 일, 말일 클램프
    data class CycleAnchored(val recurrence: CycleRecurrence) : InputSchedule()
}

/** Output 반복 — InputSchedule과 동형. */
@Serializable(with = OutputScheduleSerializer::class)
sealed class OutputSchedule {
    data object Once : OutputSchedule()
    data object Daily : OutputSchedule()
    data object Weekly : OutputSchedule()
    data object Monthly : OutputSchedule()
    data class CycleAnchored(val recurrence: CycleRecurrence) : OutputSchedule()
}

// ③ Output 카드 — 진행도 종류 (§5.5.2)
@Serializable
enum class OutputProgressKind {
    @SerialName("checkOnly") CHECK_ONLY,
    @SerialName("subtasks") SUBTASKS,
    @SerialName("sessions") SESSIONS,
    @SerialName("percent") PERCENT,
    @SerialName("timer") TIMER,
    @SerialName("stopwatch") STOPWATCH;

    val rawValue: String
        get() = when (this) {
            CHECK_ONLY -> "checkOnly"
            SUBTASKS -> "subtasks"
            SESSIONS -> "sessions"
            PERCENT -> "percent"
            TIMER -> "timer"
            STOPWATCH -> "stopwatch"
        }

    companion object {
        fun fromRawValue(raw: String): OutputProgressKind? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** `{ "type": "...", "recurrence": {...} }` — iOS 커스텀 Codable과 동일 키. */
private object ScheduleJson {
    fun descriptor(name: String): SerialDescriptor = buildClassSerialDescriptor(name) {
        element<String>("type")
        element<CycleRecurrence>("recurrence", isOptional = true)
    }

    fun encode(encoder: Encoder, descriptor: SerialDescriptor, kind: String, recurrence: CycleRecurrence?) {
        encoder.encodeStructure(descriptor) {
            encodeStringElement(descriptor, 0, kind)
            if (recurrence != null) encodeSerializableElement(descriptor, 1, CycleRecurrence.serializer(), recurrence)
        }
    }

    fun decode(decoder: Decoder, descriptor: SerialDescriptor): Pair<String, CycleRecurrence?> =
        decoder.decodeStructure(descriptor) {
            var kind: String? = null
            var recurrence: CycleRecurrence? = null
            while (true) {
                when (val index = decodeElementIndex(descriptor)) {
                    0 -> kind = decodeStringElement(descriptor, 0)
                    1 -> recurrence = decodeSerializableElement(descriptor, 1, CycleRecurrence.serializer())
                    CompositeDecoder.DECODE_DONE -> break
                    else -> error("unexpected index $index")
                }
            }
            (kind ?: throw SerializationException("type missing")) to recurrence
        }
}

object InputScheduleSerializer : KSerializer<InputSchedule> {
    override val descriptor: SerialDescriptor = ScheduleJson.descriptor("InputSchedule")

    override fun serialize(encoder: Encoder, value: InputSchedule) = when (value) {
        InputSchedule.Once -> ScheduleJson.encode(encoder, descriptor, "once", null)
        InputSchedule.Daily -> ScheduleJson.encode(encoder, descriptor, "daily", null)
        InputSchedule.Weekly -> ScheduleJson.encode(encoder, descriptor, "weekly", null)
        InputSchedule.Monthly -> ScheduleJson.encode(encoder, descriptor, "monthly", null)
        is InputSchedule.CycleAnchored -> ScheduleJson.encode(encoder, descriptor, "cycleAnchored", value.recurrence)
    }

    override fun deserialize(decoder: Decoder): InputSchedule {
        val (kind, recurrence) = ScheduleJson.decode(decoder, descriptor)
        return when (kind) {
            "once" -> InputSchedule.Once
            "daily" -> InputSchedule.Daily
            "weekly" -> InputSchedule.Weekly
            "monthly" -> InputSchedule.Monthly
            "cycleAnchored" -> InputSchedule.CycleAnchored(recurrence ?: throw SerializationException("recurrence missing"))
            else -> throw SerializationException("unknown InputSchedule type: $kind")
        }
    }
}

object OutputScheduleSerializer : KSerializer<OutputSchedule> {
    override val descriptor: SerialDescriptor = ScheduleJson.descriptor("OutputSchedule")

    override fun serialize(encoder: Encoder, value: OutputSchedule) = when (value) {
        OutputSchedule.Once -> ScheduleJson.encode(encoder, descriptor, "once", null)
        OutputSchedule.Daily -> ScheduleJson.encode(encoder, descriptor, "daily", null)
        OutputSchedule.Weekly -> ScheduleJson.encode(encoder, descriptor, "weekly", null)
        OutputSchedule.Monthly -> ScheduleJson.encode(encoder, descriptor, "monthly", null)
        is OutputSchedule.CycleAnchored -> ScheduleJson.encode(encoder, descriptor, "cycleAnchored", value.recurrence)
    }

    override fun deserialize(decoder: Decoder): OutputSchedule {
        val (kind, recurrence) = ScheduleJson.decode(decoder, descriptor)
        return when (kind) {
            "once" -> OutputSchedule.Once
            "daily" -> OutputSchedule.Daily
            "weekly" -> OutputSchedule.Weekly
            "monthly" -> OutputSchedule.Monthly
            "cycleAnchored" -> OutputSchedule.CycleAnchored(recurrence ?: throw SerializationException("recurrence missing"))
            else -> throw SerializationException("unknown OutputSchedule type: $kind")
        }
    }
}
