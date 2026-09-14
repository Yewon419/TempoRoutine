// 템포루틴 Android — 렌즈 자리 (iOS TempoLens.swift LensSpot 이식)
// 컨테이너(세이프 영역) 비율 좌표. 프로토(402×874) 값을 비율로 옮겼고 지름은 세이프 높이에 비례해 줄인다(최대 1).
// 온보딩 지면이 열리는 원점(hero)·사계절 창·렌즈가 같은 좌표를 쓴다.

package app.temporoutine.android.onboarding

import androidx.compose.ui.geometry.Offset
import kotlin.math.min

data class LensSpot(val diameter: Float, val cx: Float, val cy: Float, val magnify: Float, val trailingDial: Boolean = false) {

    /** @param width·height 세이프 영역 크기(dp), column 중앙 조판 폭(dp). 반환 = 세이프 영역 기준 중심(dp)과 지름(dp). */
    fun resolve(width: Float, height: Float, column: Float): Pair<Offset, Float> {
        val x0 = (width - column) / 2
        if (trailingDial) return Offset(x0 + column - 24 - 28, 8f + 22f) to diameter
        val scale = min(1f, height / 781f)   // 프로토 세이프 높이(874 − 59 − 34)
        return Offset(x0 + column * cx, height * cy) to diameter * scale
    }

    companion object {
        val hero = LensSpot(diameter = 250f, cx = 0.5f, cy = 0.649f, magnify = 1.12f)
        val mid = LensSpot(diameter = 176f, cx = 0.5f, cy = 0.503f, magnify = 1.14f)
        val dial = LensSpot(diameter = 56f, cx = 1f, cy = 0f, magnify = 1.2f, trailingDial = true)
    }
}
