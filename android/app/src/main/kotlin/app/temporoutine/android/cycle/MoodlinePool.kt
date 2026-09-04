// 템포루틴 Android — 무드라인 풀 (iOS MoodlinePool.swift 이식, 카피 원문 그대로)
// 날짜 고정 픽: iOS는 참조일(2001-01-01) 기준 일수를 Int 절삭 → UInt32 × 2654435761 (mod 2^32) → % count.
// ⚠ 절삭 방식까지 같아야 같은 날 같은 문장이 나온다 — "고치지" 말 것.

package app.temporoutine.android.cycle

import app.temporoutine.core.CyclePhase
import java.time.LocalDate
import java.time.ZoneId

object MoodlinePool {

    private const val REFERENCE_EPOCH_SECONDS = 978_307_200L   // 2001-01-01T00:00:00Z
    private const val KNUTH = 2654435761u

    /** iOS `dayNumber` 동형 — 기기 시간대 자정의 Unix 초에서 참조일을 빼 86400으로 나눈 몫(0 방향 절삭). */
    internal fun dayNumber(day: LocalDate, zone: ZoneId): UInt {
        val secs = day.atStartOfDay(zone).toEpochSecond() - REFERENCE_EPOCH_SECONDS
        return (secs / 86_400).toInt().toUInt()
    }

    internal fun pick(pool: List<String>, day: LocalDate, zone: ZoneId): String {
        val seed = dayNumber(day, zone) * KNUTH
        return pool[(seed % pool.size.toUInt()).toInt()]
    }

    fun base(phase: CyclePhase, day: LocalDate, zone: ZoneId = ZoneId.systemDefault()): String =
        pick(basePool.getValue(phase), day, zone)

    fun personalized(phase: CyclePhase, level: EnergyLevel, day: LocalDate, zone: ZoneId = ZoneId.systemDefault()): String =
        pick(personalizedPool.getValue(phase to level), day, zone)

    private val basePool: Map<CyclePhase, List<String>> = mapOf(
        CyclePhase.MENSTRUAL to listOf(
            "이번 주는 겨울이에요. 조금은 쉬어가도 괜찮아요.",
            "겨울이에요. 몸이 하는 말을 먼저 들어봐요.",
            "겨울이에요. 따뜻한 것 하나면 충분한 날도 있어요.",
            "겨울이에요. 오늘은 나에게 너그러워도 좋아요.",
        ),
        CyclePhase.FOLLICULAR to listOf(
            "봄이에요. 가볍게 시작해보기 좋은 때예요.",
            "봄이에요. 작은 것부터 하나씩 깨워봐요.",
            "봄이에요. 새로 하고 싶은 게 생겼다면 그게 신호예요.",
            "봄이에요. 서두르지 않아도 어느새 자라 있을 거예요.",
        ),
        CyclePhase.OVULATION to listOf(
            "여름이에요. 하고 싶은 만큼 빛나도 좋아요.",
            "여름이에요. 오늘의 에너지를 마음껏 써봐요.",
            "여름이에요. 미뤄둔 일을 꺼내기 좋은 날이에요.",
            "여름이에요. 사람을 만나기에도 좋은 때예요.",
        ),
        CyclePhase.LUTEAL to listOf(
            "가을이에요. 스스로를 돌아보는 시간을 가져봐요.",
            "가을이에요. 하나씩 매듭지어도 좋은 때예요.",
            "가을이에요. 속도를 줄이는 것도 실력이에요.",
            "가을이에요. 오늘은 정리 하나면 충분해요.",
        ),
    )

    private val personalizedPool: Map<Pair<CyclePhase, EnergyLevel>, List<String>> = mapOf(
        (CyclePhase.MENSTRUAL to EnergyLevel.LOW) to listOf(
            "겨울이에요. 기록상 이맘때는 에너지가 낮았어요. 조금은 쉬어가도 좋아요.",
            "겨울이에요. 기록상 이맘때는 쉼이 먼저였어요. 오늘도 그래도 돼요.",
        ),
        (CyclePhase.MENSTRUAL to EnergyLevel.MID) to listOf(
            "겨울이에요. 기록상 이맘때의 당신은 잔잔했어요. 천천히 가도 좋아요.",
            "겨울이에요. 기록상 무리하지 않는 날이 많았어요. 그 감각을 믿어봐요.",
        ),
        (CyclePhase.MENSTRUAL to EnergyLevel.HIGH) to listOf(
            "겨울이에요. 기록상 이맘때도 에너지가 꽤 있었어요. 원하는 만큼 해보아도, 이번엔 쉬어가도 좋아요.",
            "겨울이에요. 기록상 이맘때도 힘이 남아 있었어요. 다만 무리는 말아요.",
        ),
        (CyclePhase.FOLLICULAR to EnergyLevel.LOW) to listOf(
            "봄이에요. 기록상 이맘때는 아직 잔잔했어요. 서두르지 않아도 좋아요.",
            "봄이에요. 기록상 천천히 깨어나던 때예요. 몸을 먼저 풀어봐요.",
        ),
        (CyclePhase.FOLLICULAR to EnergyLevel.MID) to listOf(
            "봄이에요. 기록상 조금씩 기지개를 켜던 때예요. 가볍게 시작해도 좋아요.",
            "봄이에요. 기록상 리듬이 올라오던 때예요. 작은 일부터 얹어봐요.",
        ),
        (CyclePhase.FOLLICULAR to EnergyLevel.HIGH) to listOf(
            "봄이에요. 기록상 이맘때 에너지가 생긴대요. 슬슬 시동을 걸어볼까요!",
            "봄이에요. 기록상 출발이 좋던 때예요. 오늘 하나 시작해봐요.",
        ),
        (CyclePhase.OVULATION to EnergyLevel.LOW) to listOf(
            "여름이에요. 기록상 이맘때는 쉼이 필요했어요. 쉬어가도 좋아요.",
            "여름이에요. 기록상 이맘때는 의외로 지치곤 했어요. 오늘은 가볍게 가요.",
        ),
        (CyclePhase.OVULATION to EnergyLevel.MID) to listOf(
            "여름이에요. 기록상 이맘때의 당신은 밝았어요. 하고 싶은 만큼 해봐요!",
            "여름이에요. 기록상 컨디션이 안정적이던 때예요. 꾸준히 가기 좋아요.",
        ),
        (CyclePhase.OVULATION to EnergyLevel.HIGH) to listOf(
            "여름이에요. 기록상 이맘때 가장 빛났어요. 마음껏 몰입해도 좋아요!",
            "여름이에요. 기록상 절정이던 때예요. 큰 일을 두기 좋은 날이에요.",
        ),
        (CyclePhase.LUTEAL to EnergyLevel.LOW) to listOf(
            "가을이에요. 기록상 이맘때는 쉽게 지치곤 했어요. 짐을 좀 덜어내도 괜찮아요.",
            "가을이에요. 기록상 기운이 내려가던 때예요. 일정을 가볍게 둬도 좋아요.",
        ),
        (CyclePhase.LUTEAL to EnergyLevel.MID) to listOf(
            "가을이에요. 기록상 하나씩 정리하던 때예요. 스스로를 돌아보는 시간을 가져봐요.",
            "가을이에요. 기록상 차분히 마무리하던 때예요. 매듭 하나면 충분해요.",
        ),
        (CyclePhase.LUTEAL to EnergyLevel.HIGH) to listOf(
            "가을이에요. 기록상 이맘때 에너지가 충분했어요. 오늘은 어떤 것에 몰입해볼까요?",
            "가을이에요. 기록상 끝심이 좋던 때예요. 미뤄둔 마무리를 해봐요.",
        ),
    )
}
