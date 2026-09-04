// 템포루틴 — 직렬화 테스트 (MASTER §5.5.1, T40~)
// iOS TempoCoreTests/ExportSchemaTests.swift 1:1 이식.

package app.temporoutine.core

import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ExportSchemaTests {

    private fun sampleEnvelope(): ExportEnvelopeV1 {
        val r = CycleRecurrence(CycleAnchor.Phase(CyclePhase.LUTEAL), 2, true, OffsetOverflowRule.CLAMP)
        val itemID = UUID.randomUUID()
        return ExportEnvelopeV1(
            exportedAt = Instant.ofEpochSecond(1_800_000_000),
            periodDays = listOf(PeriodDayDTO("2026-07-01", "local", null)),
            scheduleItems = listOf(ScheduleItemDTO(UUID.randomUUID(), "병원 예약", "2026-07-15",
                isAllDay = true, repeatRule = ScheduleRepeat.NONE, createdAt = Instant.ofEpochSecond(1_799_000_000))),
            inputItems = listOf(InputItemDTO(itemID, "가볍게 걷기", InputCategory.EXERCISE,
                InputSchedule.CycleAnchored(r), Instant.ofEpochSecond(1_799_000_000))),
            outputItems = listOf(OutputItemDTO(UUID.randomUUID(), "자격증 공부", OutputSchedule.CycleAnchored(r), OutputProgressKind.SUBTASKS,
                subtasks = listOf(OutputSubtaskDTO(UUID.randomUUID(), "1챕터", true, 0)),
                targetSessions = 0, loggedSessions = 0, percent = 0.0,
                createdAt = Instant.ofEpochSecond(1_799_000_000))),
            completions = listOf(ItemCompletionDTO(UUID.randomUUID(), itemID, "2026-07-02", Instant.ofEpochSecond(1_799_100_000))),
            checkIns = listOf(DailyCheckInDTO(UUID.randomUUID(), "2026-07-02", energy = 3, mood = 5,
                sleep = 1, pain = null, appetite = null, note = "짧게", createdAt = Instant.ofEpochSecond(1_799_100_000))),
            trackedSignals = TrackedSignals(sleep = true, pain = false, appetite = false, note = true),
        )
    }

    // T40: 봉투 왕복 — DTO 전 필드 보존
    @Test fun testT40_envelopeRoundTrip() {
        val original = sampleEnvelope()
        val text = ExportCodec.encode(original)
        val decoded = ExportCodec.decode(text)
        assertEquals(original, decoded)
        assertEquals(1, decoded.schemaVersion)
    }

    // T41: date-only 왕복
    @Test fun testT41_dayStringRoundTrip() {
        val today = LocalDate.now()
        val s = ExportCodec.dayString(today)
        assertTrue(Regex("""^\d{4}-\d{2}-\d{2}$""").matches(s))
        assertEquals(today, ExportCodec.day(s))
    }

    // T42: 더 최신 백업 거부(§5.5.1 버전 규칙)
    @Test fun testT42_newerVersionRejected() {
        val envelope = sampleEnvelope()
        envelope.schemaVersion = 2
        val text = Json { encodeDefaults = true; explicitNulls = false }.encodeToString(ExportEnvelopeV1.serializer(), envelope)
        val error = assertFailsWith<ExportCodec.CodecError> { ExportCodec.decode(text) }
        assertEquals(ExportCodec.CodecError.NewerVersion(2), error)
    }

    // T43: 손상 파일 → corrupt
    @Test fun testT43_corruptRejected() {
        val error = assertFailsWith<ExportCodec.CodecError> { ExportCodec.decode("{}") }
        assertEquals(ExportCodec.CodecError.Corrupt, error)
        assertFailsWith<ExportCodec.CodecError> { ExportCodec.decode("생리") }
    }

    // T44: 시간 지정 일정 instant 왕복
    @Test fun testT44_instantRoundTrip() {
        val now = Instant.ofEpochSecond(1_800_000_123)
        val s = ExportCodec.instantString(now)
        assertEquals(now, ExportCodec.instant(s))
    }

    // T45: rhythmSummary 왕복 + 구 파일 호환
    @Test fun testT45_rhythmSummaryRoundTrip() {
        val old = ExportCodec.encode(sampleEnvelope())
        assertNull(ExportCodec.decode(old).rhythmSummary)

        val swing = WindowCycle(28, (1..28).map { d ->
            WindowDaySample(d, 28 - d + 1, energy = if (d > 24) 2 else 4, mood = if (d <= 5) 2 else 4)
        })
        val summary = RhythmSummaryDTO.build(listOf(swing, swing, swing), computedAt = Instant.ofEpochSecond(1_800_000_000))
        val envelope = sampleEnvelope().copy(rhythmSummary = summary)
        val decoded = ExportCodec.decode(ExportCodec.encode(envelope))
        assertEquals(summary, decoded.rhythmSummary)

        assertEquals("window-stats-1", summary.engineVersion)
        assertEquals(5, summary.menstrualLength, "T45 M 디폴트 동봉(개정 M)")
        assertEquals(3, summary.usableCycles)
        assertEquals("vivace", summary.rhythmType)
        assertEquals(5, summary.preMenstrualWindow)
        assertEquals(listOf(2.0, 2.0, 2.0), summary.perCycleRanges)
        assertEquals(RhythmSummaryDTO.Constants.current, summary.constants)
    }

    // T46: 씨앗 원장 — 구 봉투 호환 + 왕복
    @Test fun testT46_seedLedgerEnvelopeRoundTrip() {
        assertNull(ExportCodec.decode(ExportCodec.encode(sampleEnvelope())).seedLedger)

        val ledger = SeedLedgerDTO(purchases = mapOf("modern" to 7), claims = mapOf("notice-1" to 7), legacyBonus = 3)
        val envelope = sampleEnvelope().copy(seedLedger = ledger)
        assertEquals(ledger, ExportCodec.decode(ExportCodec.encode(envelope)).seedLedger)
    }

    // T47: 잔액 셈
    @Test fun testT47_seedLedgerTotals() {
        val ledger = SeedLedgerDTO(purchases = mapOf("modern" to 7, "letterpress" to 0),
            claims = mapOf("notice-1" to 7, "notice-2" to 2), legacyBonus = 3)
        assertEquals(7, ledger.spent, "승계분(0)은 소비에 안 잡힌다")
        assertEquals(12, ledger.bonus)
        assertEquals(setOf("modern", "letterpress"), ledger.ownedThemes)
    }

    // T48: 병합 = 합집합
    @Test fun testT48_seedLedgerMergeIsUnion() {
        val phone = SeedLedgerDTO(purchases = mapOf("modern" to 7))
        val pad = SeedLedgerDTO(claims = mapOf("notice-1" to 7))
        val merged = phone.merged(pad)
        assertEquals(mapOf("modern" to 7), merged.purchases)
        assertEquals(mapOf("notice-1" to 7), merged.claims)
        assertEquals(7, merged.spent)
        assertEquals(7, merged.bonus)
    }

    // T49: 교환·결합·멱등
    @Test fun testT49_seedLedgerMergeConverges() {
        val a = SeedLedgerDTO(mapOf("modern" to 7), mapOf("n1" to 7), 3)
        val b = SeedLedgerDTO(mapOf("letterpress" to 5), mapOf("n2" to 2), 0)
        val c = SeedLedgerDTO(mapOf("modern" to 0), mapOf("n1" to 7), 9)

        assertEquals(b.merged(a), a.merged(b), "교환")
        assertEquals(a.merged(b.merged(c)), a.merged(b).merged(c), "결합")
        assertEquals(a, a.merged(a), "멱등")
        assertEquals(7, a.merged(c).purchases["modern"])
        assertEquals(9, a.merged(c).legacyBonus, "구판 잔재는 합산 아닌 max")
    }

    // T50: 같은 공지를 두 기기가 따로 받아도 한 번으로 접힌다
    @Test fun testT50_seedLedgerClaimCountsOnce() {
        val phone = SeedLedgerDTO(claims = mapOf("notice-1" to 7))
        val pad = SeedLedgerDTO(claims = mapOf("notice-1" to 7))
        assertEquals(7, phone.merged(pad).bonus)
    }

    // (Android 추가) UUID 표기 — iOS와 같은 대문자로 쓰고, 소문자도 읽는다
    @Test fun testUUIDCaseCompat() {
        val id = UUID.fromString("e621e1f8-c36c-495a-93fc-0c247a3e6e5f")
        val dto = InputSubtaskDTO(id, "x", 0)
        val text = ExportCodec.json.encodeToString(InputSubtaskDTO.serializer(), dto)
        assertTrue(text.contains("E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        assertEquals(dto, ExportCodec.json.decodeFromString(InputSubtaskDTO.serializer(),
            """{"id":"e621e1f8-c36c-495a-93fc-0c247a3e6e5f","title":"x","order":0}"""))
        assertNotNull(ExportCodec.instant("2027-01-15T08:00:00.123Z"), "분수초도 읽는다")
        assertNotNull(ExportCodec.instant("2027-01-15T17:00:00+09:00"), "오프셋도 읽는다")
    }
}
