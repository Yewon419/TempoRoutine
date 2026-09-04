// 템포루틴 Android — 서체 (iOS Almanac.swift Font.almanac / almanacBody, notoSerif 분기 이식)
// 은필 표제(`almanac`)는 weight 인자를 무시하고 항상 NotoSerifKR Light — iOS 실장 그대로.
// 본문(`almanacBody`)만 bold → Medium. 시스템 세리프는 한글 글리프가 없으니 번들 서체를 명시한다.

package app.temporoutine.android.theme

import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.unit.sp
import app.temporoutine.android.R

object Fonts {
    val notoSerifKR: FontFamily = FontFamily(
        Font(R.font.notoserifkr_variable, weight = FontWeight.Light, variationSettings = FontVariation.Settings(FontVariation.weight(300))),
        Font(R.font.notoserifkr_variable, weight = FontWeight.Medium, variationSettings = FontVariation.Settings(FontVariation.weight(500))),
    )

    private val platform = PlatformTextStyle(includeFontPadding = false)
    private val trim = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.None)

    /** 표제 전용(고정 크기, Dynamic Type 미추종) — 58·44·28·22·17. */
    fun almanac(size: Int): TextStyle = TextStyle(
        fontFamily = notoSerifKR,
        fontWeight = FontWeight.Light,
        fontSize = size.sp,
        lineHeight = (size * 1.2f).sp,
        platformStyle = platform,
        lineHeightStyle = trim,
    )

    /** 본문급 — bold면 Medium. sp라 시스템 글꼴 크기 추종(iOS relativeTo 대응). */
    fun almanacBody(size: Int, bold: Boolean = false): TextStyle = TextStyle(
        fontFamily = notoSerifKR,
        fontWeight = if (bold) FontWeight.Medium else FontWeight.Light,
        fontSize = size.sp,
        lineHeight = (size * 1.45f).sp,
        platformStyle = platform,
        lineHeightStyle = trim,
    )

    /** iOS 시스템 서체 자리(.footnote·.caption 등) — Android 기본 산세리프. */
    fun system(size: Int, weight: FontWeight = FontWeight.Normal): TextStyle = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = weight,
        fontSize = size.sp,
        lineHeight = (size * 1.35f).sp,
        platformStyle = platform,
        lineHeightStyle = trim,
    )
}
