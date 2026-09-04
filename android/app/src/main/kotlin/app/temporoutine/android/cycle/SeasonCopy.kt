// 템포루틴 Android — 계절 카피 (iOS TodayView.swift seasonMeta 이식). 색은 테마 층(Palette)이 든다.
// ⚠ 의학 단계명 필드를 두지 않는다(§1 개정 M) — 사용자 표면은 계절+컨디션 언어만. 비교는 phase로.

package app.temporoutine.android.cycle

import app.temporoutine.core.CyclePhase

data class SeasonCopy(val phase: CyclePhase, val name: String, val moodline: String, val lever: String)

fun seasonCopy(phase: CyclePhase): SeasonCopy = when (phase) {
    CyclePhase.MENSTRUAL -> SeasonCopy(phase, "겨울", "이번 주는 겨울이에요. 조금은 쉬어가도 괜찮아요.", "오늘은 천천히 이어가볼까요?")
    CyclePhase.FOLLICULAR -> SeasonCopy(phase, "봄", "봄이에요. 가볍게 시작해보기 좋은 때예요.", "시동 거는 주기예요. 가볍게 시작해도 좋아요.")
    CyclePhase.OVULATION -> SeasonCopy(phase, "여름", "여름이에요. 하고 싶은 만큼 빛나도 좋아요.", "마음껏 몰입해도 좋아요.")
    CyclePhase.LUTEAL -> SeasonCopy(phase, "가을", "가을이에요. 스스로를 돌아보는 시간을 가져봐요.", "조금 더 해볼 수 있나요? 무리하지는 말아요.")
}

/** 표시 순서(봄→여름→가을→겨울). 엔진 순서(겨울 먼저)와 별개. */
val CyclePhase.Companion.displayOrder: List<CyclePhase>
    get() = listOf(CyclePhase.FOLLICULAR, CyclePhase.OVULATION, CyclePhase.LUTEAL, CyclePhase.MENSTRUAL)
