// 템포루틴 Android — 반경 스케일 (iOS TodayView.swift `Radius`, 79차 2026-09-09 이식).
// 카드·시트·큰 표면 = card / 사진·미니 카드·칩·입력 = inner / 띠·게이지·작은 마커 = small /
// 폭 4 이하 극세(눈금·조각) = hairline. 이 넷 + 캡슐(CircleShape)만 쓴다.
// ⚠ iOS는 전부 `.continuous`(스쿼클)이지만 Compose RoundedCornerShape는 원호 모서리다 — 근사.

package app.temporoutine.android.theme

import androidx.compose.ui.unit.dp

object Radius {
    val card = 16.dp
    val inner = 10.dp
    val small = 4.dp
    val hairline = 2.dp
}
