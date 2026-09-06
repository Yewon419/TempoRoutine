// 템포루틴 Android — 온보딩 ③ 세 가지 카드 (iOS OnboardingFlow cardsStep 이식): 탭 진행형 3장(일정·Input·Output)
// 문안 = CardKind.info 그대로(오늘 탭 ⓘ와 같은 말). 장별 선화 = 닻(못 옮기는 날) / 찻잔(채우는 일) / 종이비행기(내보내는 일), trim 드로잉.
// Input·Output 장엔 예시 칩 — 탭하면 실제 아이템으로 담기고, 다시 탭하면 빠진다.
// ⚠ Compose PathMeasure는 첫 컨투어만 잰다(nextContour 없음) → 컨투어를 따로 만들어 누적 길이로 순차 트림한다(SwiftUI .trim 동작).

package app.temporoutine.android.onboarding

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.temporoutine.android.R
import app.temporoutine.android.theme.Fonts
import app.temporoutine.android.theme.Ink
import app.temporoutine.android.today.CardKind

@Composable
fun ColumnScope.CardsStep(page: Int, added: Set<ExampleChip>, reduceMotion: Boolean, onToggle: (ExampleChip) -> Unit) {
    val ink = Ink
    val kind = CardKind.entries[page]
    key(page) {
        val draw = rememberDrawProgress(active = true, reduceMotion = reduceMotion, durationMs = 1000, delayMs = 60)
        StepHeader(stringResource(R.string.ob_cards_eyebrow, page + 1), stringResource(kind.titleRes))
        CardSketch(kind, draw, Modifier.align(Alignment.CenterHorizontally))
    }
    Text(stringResource(kind.infoRes), style = Fonts.almanacBody(17), color = ink.text.copy(alpha = 0.78f))
    when (kind) {
        CardKind.INPUT -> ExampleBlock(
            listOf(ExampleChip.INPUT_MEDITATION to stringResource(R.string.ob_ex_meditation), ExampleChip.INPUT_TEA to stringResource(R.string.ob_ex_tea)),
            added, onToggle,
        )
        CardKind.OUTPUT -> ExampleBlock(
            listOf(ExampleChip.OUTPUT_STUDY to stringResource(R.string.ob_ex_study), ExampleChip.OUTPUT_LISTENING to stringResource(R.string.ob_ex_listening)),
            added, onToggle,
        )
        CardKind.SCHEDULE -> Unit
    }
}

@Composable
private fun ExampleBlock(chips: List<Pair<ExampleChip, String>>, added: Set<ExampleChip>, onToggle: (ExampleChip) -> Unit) {
    val ink = Ink
    Column(Modifier.padding(top = 6.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        // 빠지는 법은 눌러 보면 알게 되는 동작이라 첫 안내에서 뺀다(2026-08-12 베타 피드백)
        Text(stringResource(R.string.ob_ex_hint), style = Fonts.system(12), color = ink.text.copy(alpha = 0.5f))
        for ((chip, label) in chips) {
            ExampleChipView(label, added = chip in added) { onToggle(chip) }
        }
    }
}

@Composable
private fun ExampleChipView(label: String, added: Boolean, onClick: () -> Unit) {
    val ink = Ink
    val addedLabel = stringResource(R.string.ob_ex_added)
    Row(
        Modifier
            .semantics { if (added) stateDescription = addedLabel }
            .background(ink.text.copy(alpha = if (added) 0.04f else 0.08f), CircleShape)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        val color = ink.text.copy(alpha = if (added) 0.55f else 1f)
        Canvas(Modifier.size(10.dp)) {
            val s = Stroke(width = 1.8.dp.toPx(), cap = StrokeCap.Round)
            if (added) {
                val p = Path().apply { moveTo(size.width * 0.05f, size.height * 0.55f); lineTo(size.width * 0.4f, size.height * 0.9f); lineTo(size.width * 0.95f, size.height * 0.15f) }
                drawPath(p, color, style = s)
            } else {
                drawLine(color, Offset(size.width / 2, 0f), Offset(size.width / 2, size.height), s.width, StrokeCap.Round)
                drawLine(color, Offset(0f, size.height / 2), Offset(size.width, size.height / 2), s.width, StrokeCap.Round)
            }
        }
        Text(label, style = Fonts.system(13, FontWeight.Medium), color = color)
    }
}

// ── 장별 선화 ──

@Composable
private fun CardSketch(kind: CardKind, progress: Float, modifier: Modifier) {
    val ink = Ink
    Box(modifier.padding(vertical = 8.dp).clearAndSetSemantics { }) {
        Canvas(Modifier.size(128.dp, 108.dp)) {
            val stroke = Stroke(width = 1.6.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round)
            val rect = Rect(Offset.Zero, size)
            val contours = when (kind) {
                CardKind.SCHEDULE -> anchorContours(rect)
                CardKind.INPUT -> teacupContours(rect)
                CardKind.OUTPUT -> paperPlaneContours(rect)
            }
            drawTrimmedContours(contours, progress, ink.text.copy(alpha = 0.65f), stroke)
        }
    }
}

/** 여러 컨투어를 하나의 경로처럼 순차 트림한다(누적 길이 기준). */
fun DrawScope.drawTrimmedContours(contours: List<Path>, progress: Float, color: Color, stroke: Stroke) {
    if (progress <= 0f) return
    val measure = PathMeasure()
    val lengths = contours.map { measure.setPath(it, false); measure.length }
    val total = lengths.sum()
    var consumed = 0f
    for ((i, path) in contours.withIndex()) {
        val len = lengths[i]
        val local = if (len <= 0f) 1f else ((progress * total - consumed) / len).coerceIn(0f, 1f)
        drawTrimmed(path, local, color, stroke)
        consumed += len
    }
}

private fun Rect.pt(x: Float, y: Float) = Offset(left + x * width, top + y * height)

/** 닻 — 일정 장 */
private fun anchorContours(r: Rect): List<Path> = listOf(
    Path().apply { addOval(Rect(Offset(r.left + 0.43f * r.width, r.top + 0.02f * r.height), Size(0.14f * r.width, 0.13f * r.height))) },
    line(r.pt(0.5f, 0.15f), r.pt(0.5f, 0.82f)),
    line(r.pt(0.34f, 0.30f), r.pt(0.66f, 0.30f)),
    Path().apply { val a = r.pt(0.5f, 0.82f); moveTo(a.x, a.y); val c = r.pt(0.26f, 0.84f); val b = r.pt(0.20f, 0.58f); quadraticTo(c.x, c.y, b.x, b.y) },
    Path().apply { val a = r.pt(0.5f, 0.82f); moveTo(a.x, a.y); val c = r.pt(0.74f, 0.84f); val b = r.pt(0.80f, 0.58f); quadraticTo(c.x, c.y, b.x, b.y) },
    line(r.pt(0.20f, 0.58f), r.pt(0.29f, 0.61f)),
    line(r.pt(0.80f, 0.58f), r.pt(0.71f, 0.61f)),
)

/** 찻잔 — Input 장 (예시 "잠들기 전 차 한 잔"과 이어지는 그림) */
private fun teacupContours(r: Rect): List<Path> = listOf(
    Path().apply {
        val a = r.pt(0.22f, 0.50f); moveTo(a.x, a.y)
        val b = r.pt(0.27f, 0.74f); lineTo(b.x, b.y)
        val c = r.pt(0.42f, 0.85f); val d = r.pt(0.57f, 0.74f); quadraticTo(c.x, c.y, d.x, d.y)
        val e = r.pt(0.62f, 0.50f); lineTo(e.x, e.y)
    },
    line(r.pt(0.22f, 0.50f), r.pt(0.62f, 0.50f)),
    Path().apply { val a = r.pt(0.62f, 0.55f); moveTo(a.x, a.y); val c = r.pt(0.79f, 0.62f); val b = r.pt(0.62f, 0.69f); quadraticTo(c.x, c.y, b.x, b.y) },
    line(r.pt(0.16f, 0.85f), r.pt(0.68f, 0.85f)),
    Path().apply { val a = r.pt(0.35f, 0.41f); moveTo(a.x, a.y); val c = r.pt(0.28f, 0.32f); val b = r.pt(0.39f, 0.24f); quadraticTo(c.x, c.y, b.x, b.y) },
    Path().apply { val a = r.pt(0.50f, 0.41f); moveTo(a.x, a.y); val c = r.pt(0.43f, 0.32f); val b = r.pt(0.54f, 0.24f); quadraticTo(c.x, c.y, b.x, b.y) },
)

/** 종이비행기 — Output 장 */
private fun paperPlaneContours(r: Rect): List<Path> {
    val nose = r.pt(0.86f, 0.26f)
    return listOf(
        Path().apply { moveTo(nose.x, nose.y); val a = r.pt(0.10f, 0.52f); lineTo(a.x, a.y); val b = r.pt(0.47f, 0.59f); lineTo(b.x, b.y); lineTo(nose.x, nose.y) },
        Path().apply { val a = r.pt(0.47f, 0.59f); moveTo(a.x, a.y); val b = r.pt(0.40f, 0.80f); lineTo(b.x, b.y); lineTo(nose.x, nose.y) },
    )
}

private fun line(a: Offset, b: Offset): Path = Path().apply { moveTo(a.x, a.y); lineTo(b.x, b.y) }
