// 템포루틴 Android — 단계별 에너지 프로파일 (iOS EnergyProfile.swift 이식)
// 개인화 무드라인의 입력: (단계 × energy) 가중 평균. projected 날·질병 가중 0 행은 제외. 표본 <3이면 침묵.

package app.temporoutine.android.cycle

import app.temporoutine.core.CyclePhase
import java.time.LocalDate
import kotlin.math.floor

enum class EnergyLevel { LOW, MID, HIGH }

/** 체크인 한 행의 집계 입력 — 앱 엔티티에서 변환해 넘긴다. */
data class EnergySample(val day: LocalDate, val energy: Int, val weight: Double)

class EnergyProfile(samples: List<EnergySample>, snapshot: CycleSnapshot) {

    private data class Acc(var sum: Double = 0.0, var weight: Double = 0.0)

    private val stats: Map<CyclePhase, Acc>

    init {
        val acc = mutableMapOf<CyclePhase, Acc>()
        for (s in samples) {
            if (s.energy !in 1..5 || s.weight <= 0) continue
            val info = snapshot.phaseInfo(s.day) ?: continue
            if (info.projected) continue
            val a = acc.getOrPut(info.phase) { Acc() }
            a.sum += s.energy * s.weight
            a.weight += s.weight
        }
        stats = acc
    }

    fun sampleCount(phase: CyclePhase): Int = stats[phase]?.let { floor(it.weight).toInt() } ?: 0

    /** null = 표본 미달(기본 카피로 폴백). 경계 = 평균 ≤2.5 low / ≥3.5 high. */
    fun level(phase: CyclePhase): EnergyLevel? {
        val s = stats[phase] ?: return null
        if (s.weight < MIN_SAMPLES) return null
        val mean = s.sum / s.weight
        return when {
            mean <= 2.5 -> EnergyLevel.LOW
            mean >= 3.5 -> EnergyLevel.HIGH
            else -> EnergyLevel.MID
        }
    }

    companion object {
        const val MIN_SAMPLES = 3.0
    }
}
