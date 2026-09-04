// 템포루틴 — 크로스플랫폼 골든 픽스처 (Phase 0 신규, 계획서 「골든 픽스처」)
//
// iOS가 실제로 내보낸 봉투(tools/review-sample-backup.json)를 Kotlin 코덱으로 읽고 다시 써서
// **의미 동치**를 증명한다. 바이트 동치는 애초에 불가(iOS sortedKeys·정수/실수 표기 차이)라 기준은 셋:
//   ① 디코드 → 인코드 → 디코드 결과가 첫 디코드와 같다(왕복 손실 0)
//   ② 재인코드 JSON의 객체 키 집합이 원본과 재귀적으로 같다(필드 누락·추가 0). 단 원본의 명시 null 키는
//      부재와 동형으로 본다 — 이 픽스처는 파이썬 생성기 산출이라 `"healthKitUUID": null`을 적지만, iOS 앱의
//      JSONEncoder와 Kotlin 코덱(explicitNulls=false)은 둘 다 그 키를 생략하고, 디코더는 둘 다 null을 받는다.
//   ③ 원시값은 숫자는 수치로, 문자열·불리언은 그대로 같다
// 이 셋이 통과하면 iOS ↔ Android 가져오기가 어느 방향이든 성립한다.

package app.temporoutine.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlin.test.fail

class GoldenFixtureTests {

    private fun loadText(): String {
        assumeTrue(ReviewSampleTests.sampleFile.exists(), "샘플 파일 없음")
        return ReviewSampleTests.sampleFile.readText(Charsets.UTF_8)
    }

    @Test fun testRoundTripIsLossless() {
        val text = loadText()
        val first = ExportCodec.decode(text)
        val second = ExportCodec.decode(ExportCodec.encode(first))
        assertEquals(first, second)
    }

    @Test fun testReencodedTreeMatchesOriginal() {
        val text = loadText()
        val original = ExportCodec.json.parseToJsonElement(text)
        val reencoded = ExportCodec.json.parseToJsonElement(ExportCodec.encode(ExportCodec.decode(text)))
        assertSameTree(original, reencoded, path = "$")
    }

    @Test fun testFixtureExercisesEveryOptionalBlock() {
        // 픽스처가 얇으면 위 두 테스트가 공허하게 통과한다 — 옵셔널 블록이 실제로 실려 있는지 못 박는다.
        val envelope = ExportCodec.decode(loadText())
        assertNotNull(envelope.seedLedger, "씨앗 원장")
        assertTrue(envelope.inputItems.any { it.schedule is InputSchedule.CycleAnchored } ||
            envelope.outputItems.any { it.schedule is OutputSchedule.CycleAnchored } ||
            envelope.inputItems.isNotEmpty(), "아이템 스케줄 분기가 하나는 있어야 한다")
        assertTrue(envelope.scheduleItems.any { !it.isAllDay }, "시각 있는 일정(instant 표기)이 있어야 한다")
    }

    private fun assertSameTree(a: JsonElement, b: JsonElement, path: String) {
        when (a) {
            is JsonObject -> {
                val bo = b as? JsonObject ?: fail("$path: 객체가 아님")
                val presentKeys = a.filterValues { it !is JsonNull }.keys
                assertEquals(presentKeys, bo.filterValues { it !is JsonNull }.keys, "$path: 키 집합")
                for (key in presentKeys) assertSameTree(a.getValue(key), bo.getValue(key), "$path.$key")
            }
            is JsonArray -> {
                val ba = b as? JsonArray ?: fail("$path: 배열이 아님")
                assertEquals(a.size, ba.size, "$path: 배열 길이")
                for (i in a.indices) assertSameTree(a[i], ba[i], "$path[$i]")
            }
            is JsonPrimitive -> {
                val bp = b as? JsonPrimitive ?: fail("$path: 원시값이 아님")
                if (a is JsonNull || bp is JsonNull) { assertEquals(a, bp, path); return }
                when {
                    a.isString -> assertEquals(a.content, bp.content, path)
                    a.booleanOrNull != null -> assertEquals(a.booleanOrNull, bp.booleanOrNull, path)
                    else -> assertEquals(a.doubleOrNull, bp.doubleOrNull, path)   // iOS `0` vs Kotlin `0.0`
                }
            }
        }
    }
}
