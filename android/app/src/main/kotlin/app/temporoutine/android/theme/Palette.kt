// 템포루틴 Android — 은필(standard) 팔레트 20토큰 (iOS Theme.swift:149-173 이식) + Ink 접근자.
// 테마 시스템은 iOS ThemePalette/ThemeChrome 구조를 데이터로 두되, Phase 1은 은필 1종만 값을 채운다.

package app.temporoutine.android.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import app.temporoutine.core.CyclePhase

data class Palette(
    val winter: Color,
    val spring: Color,
    val summer: Color,
    val autumn: Color,
    val text: Color,
    val paper: Color,
    val record: Color,
    val danger: Color,
    val dim: Color,
    val oxide: Color,
    val holiday: Color,
    val saturday: Color,
    val frost: Color,
    val glowWinter: Color,
    val glowSpring: Color,
    val glowSummer: Color,
    val glowAutumn: Color,
    val surface: Color,
    val accent: Color,
) {
    fun season(phase: CyclePhase): Color = when (phase) {
        CyclePhase.MENSTRUAL -> winter
        CyclePhase.FOLLICULAR -> spring
        CyclePhase.OVULATION -> summer
        CyclePhase.LUTEAL -> autumn
    }

    fun glow(phase: CyclePhase): Color = when (phase) {
        CyclePhase.MENSTRUAL -> glowWinter
        CyclePhase.FOLLICULAR -> glowSpring
        CyclePhase.OVULATION -> glowSummer
        CyclePhase.LUTEAL -> glowAutumn
    }
}

/** 색 아닌 테마 결정(iOS ThemeChrome 축) — 은필 값. 다른 테마 추가 시 여기만 데이터로 늘린다. */
data class Chrome(
    val showsSeasonLight: Boolean,
    val motifTexture: Boolean,
    val dimsInDarkMode: Boolean,
    val boostsContrast: Boolean,
)

object StandardTheme {
    val light = Palette(
        winter = Color(0xFF55606C), spring = Color(0xFF8F7C2E), summer = Color(0xFF6E7C46), autumn = Color(0xFFA84B38),
        text = Color(0xFF2C2B27), paper = Color(0xFFF0F0ED), record = Color(0xFF5B626B), danger = Color(0xFFB23A30),
        dim = Color(0xFF2C2B27).copy(alpha = 0.55f), oxide = Color(0xFF8B6F55), holiday = Color(0xFFC2453C),
        saturday = Color(0xFF3D6BC4), frost = Color(0xFFF2F3F0),
        glowWinter = Color(0xFF96AECA), glowSpring = Color(0xFFF4DCA9), glowSummer = Color(0xFFBDD085), glowAutumn = Color(0xFFD08C86),
        surface = Color.White.copy(alpha = 0.55f), accent = Color(0xFF55606C),
    )
    val dark = Palette(
        winter = Color(0xFF98A6B4), spring = Color(0xFFC2AC52), summer = Color(0xFFA3B378), autumn = Color(0xFFD6826B),
        text = Color(0xFFE8E6E1), paper = Color(0xFF1C1B19), record = Color(0xFFA9B0B8), danger = Color(0xFFD0685E),
        dim = Color(0xFFE8E6E1).copy(alpha = 0.5f), oxide = Color(0xFFB29477), holiday = Color(0xFFE07A70),
        saturday = Color(0xFF7FA4E8), frost = Color(0xFF1A1B1B),
        glowWinter = Color(0xFFA6BAD2), glowSpring = Color(0xFFF6E1B6), glowSummer = Color(0xFFC7D797), glowAutumn = Color(0xFFD79D98),
        surface = Color.White.copy(alpha = 0.07f), accent = Color(0xFF98A6B4),
    )
    val chrome = Chrome(showsSeasonLight = true, motifTexture = true, dimsInDarkMode = true, boostsContrast = false)
}

val LocalInk = staticCompositionLocalOf { StandardTheme.light }
val LocalChrome = staticCompositionLocalOf { StandardTheme.chrome }
/** 다크 외관 여부 — 계절광 감쇠 등 색 아닌 분기가 본다. 시스템값 대신 이걸 보는 이유 = 온보딩 라이트 고정(LightAppearance). */
val LocalDarkAppearance = staticCompositionLocalOf { false }

/** iOS `Ink.*` 대응 — 콜사이트는 이것만 본다. */
val Ink: Palette
    @Composable get() = LocalInk.current

@Composable
fun TempoTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    CompositionLocalProvider(
        LocalInk provides if (dark) StandardTheme.dark else StandardTheme.light,
        LocalChrome provides StandardTheme.chrome,
        LocalDarkAppearance provides dark,
        content = content,
    )
}

/** 온보딩 라이트 고정(iOS `.preferredColorScheme(.light)`, 2026-09-04) — 팔레트·계절광 감쇠 둘 다 라이트로. */
@Composable
fun LightAppearance(content: @Composable () -> Unit) {
    CompositionLocalProvider(
        LocalInk provides StandardTheme.light,
        LocalDarkAppearance provides false,
        content = content,
    )
}
