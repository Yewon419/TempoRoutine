// 템포루틴 — 주기 값 타입 (MASTER §5.5 / §5.6)
// iOS TempoCore/CycleTypes.swift 1:1 이식 — 알고리즘·정의 무변경. 날짜는 LocalDate(date-only).

package app.temporoutine.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.descriptors.element
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.encoding.decodeStructure
import kotlinx.serialization.encoding.encodeStructure
import java.time.LocalDate

@Serializable
enum class CyclePhase {
    @SerialName("menstrual") MENSTRUAL,
    @SerialName("follicular") FOLLICULAR,
    @SerialName("ovulation") OVULATION,
    @SerialName("luteal") LUTEAL;

    /** iOS `rawValue` — 저장·식별 키. 표시에 쓰지 않는다. */
    val rawValue: String get() = name.lowercase()

    companion object {
        fun fromRawValue(raw: String): CyclePhase? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** 앵커 — discriminator(`type`) 커스텀 직렬화(§5.5.1). */
@Serializable(with = CycleAnchorSerializer::class)
sealed class CycleAnchor {
    /** 주기 시작(생리 1일차) */
    data object CycleStart : CycleAnchor()

    /** 특정 단계 시작 */
    data class Phase(val phase: CyclePhase) : CycleAnchor()
}

object CycleAnchorSerializer : KSerializer<CycleAnchor> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("CycleAnchor") {
        element<String>("type")
        element<CyclePhase>("phase", isOptional = true)
    }

    override fun serialize(encoder: Encoder, value: CycleAnchor) {
        encoder.encodeStructure(descriptor) {
            when (value) {
                CycleAnchor.CycleStart -> encodeStringElement(descriptor, 0, "cycleStart")
                is CycleAnchor.Phase -> {
                    encodeStringElement(descriptor, 0, "phase")
                    encodeSerializableElement(descriptor, 1, CyclePhase.serializer(), value.phase)
                }
            }
        }
    }

    override fun deserialize(decoder: Decoder): CycleAnchor = decoder.decodeStructure(descriptor) {
        var type: String? = null
        var phase: CyclePhase? = null
        while (true) {
            when (val index = decodeElementIndex(descriptor)) {
                0 -> type = decodeStringElement(descriptor, 0)
                1 -> phase = decodeSerializableElement(descriptor, 1, CyclePhase.serializer())
                kotlinx.serialization.encoding.CompositeDecoder.DECODE_DONE -> break
                else -> error("unexpected index $index")
            }
        }
        when (type) {
            "cycleStart" -> CycleAnchor.CycleStart
            "phase" -> CycleAnchor.Phase(phase ?: throw kotlinx.serialization.SerializationException("phase missing"))
            else -> throw kotlinx.serialization.SerializationException("unknown anchor type: $type")
        }
    }
}

@Serializable
enum class OffsetOverflowRule {
    @SerialName("clamp") CLAMP,
    @SerialName("skip") SKIP,
    @SerialName("carry") CARRY;

    val rawValue: String get() = name.lowercase()
}

@Serializable
data class CycleRecurrence(
    val anchor: CycleAnchor,
    val dayOffset: Int,               // 앵커로부터 +N일 (절대 날짜 저장 X)
    val repeatsEveryCycle: Boolean,   // false = 특정 주기 1회
    val overflowRule: OffsetOverflowRule,
    /** 계절 전체 모드(2026-08-01). true = 앵커 계절의 모든 날 — dayOffset 무시. `.phase` 앵커에서만 의미.
     *  nullable인 이유: 기존 저장분에 이 키가 없다 — 키 부재를 null로 흡수해야 하위 호환. 읽기는 `spansWholePhase`. */
    val wholePhase: Boolean? = null,
) {
    /** 계절 전체인가 — 저장 표현과 무관하게 계산 경로가 쓰는 단일 창구 */
    val spansWholePhase: Boolean get() = wholePhase == true
}

data class CyclePrediction(
    val lastPeriodStart: LocalDate,
    val averageLength: Int,
    val confidence: Confidence,
) {
    enum class Confidence { LOW, MEDIUM, HIGH }
}

data class PhaseSpan(
    val phase: CyclePhase,
    val startDay: Int,   // 1-indexed
    val length: Int,     // 일수
)

data class DayResolution(
    val day: Int,           // 1-indexed day-in-cycle
    val projected: Boolean, // true = 예측(실제 앵커 밖 — UI에서 faded·"예상")
)
