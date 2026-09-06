// 봉투 왕복·병합 규칙 — iOS ExportImport 계약(날짜 dedup·UUID dedup·아이템×날짜 dedup·노트/증상 단독 보존·씨앗 합집합)을 고정.

package app.temporoutine.android.data

import app.temporoutine.core.ExportCodec
import app.temporoutine.core.InputSchedule
import app.temporoutine.core.OutputProgressKind
import app.temporoutine.core.OutputSchedule
import app.temporoutine.core.SeedLedgerDTO
import app.temporoutine.core.TrackedSignals
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ExportImportTests {

    private val zone: ZoneId = ZoneId.of("Asia/Seoul")
    private val day = LocalDate.of(2026, 9, 3)
    private val now: Instant = day.atStartOfDay(zone).toInstant()
    private val signals = TrackedSignals(sleep = true, pain = false, appetite = true, note = true, irritability = false)
    private fun id() = UUID.randomUUID().toString().uppercase()

    private fun sample(): StoreSnapshot {
        val inputId = id()
        val outputId = id()
        val subtaskId = id()
        return StoreSnapshot(
            periodDays = listOf(PeriodDayEntity(id(), day, PeriodDayOrigin.LOCAL), PeriodDayEntity(id(), day.plusDays(1))),
            schedules = listOf(
                ScheduleItemEntity(id(), "여행", date = now, endDate = day.plusDays(2).atStartOfDay(zone).toInstant(), isAllDay = true),
                ScheduleItemEntity(id(), "저녁약속", date = now.plusSeconds(19 * 3600), isAllDay = false, reminderMinutes = 30),
            ),
            inputs = listOf(
                InputItemEntity(inputId, "아침 루틴", scheduleJson = InputItemEntity.encodeSchedule(InputSchedule.Daily),
                    progressKindRaw = OutputProgressKind.SUBTASKS.rawValue, createdAt = now),
            ),
            inputSubtasks = listOf(InputSubtaskEntity(subtaskId, inputId, "물 한 잔", 0)),
            inputProgress = listOf(
                InputProgressEntity(id(), inputId, day, loggedSessions = 2, elapsedAccumSeconds = 60.0)
                    .withDoneSubtaskIds(setOf(subtaskId)),
                // 값이 전부 0인 레코드는 봉투에 싣지 않는다
                InputProgressEntity(id(), inputId, day.plusDays(1)),
            ),
            completions = listOf(ItemCompletionEntity(id(), inputId, day, now)),
            outputs = listOf(
                OutputItemEntity(outputId, "시험공부", scheduleJson = OutputItemEntity.encodeSchedule(OutputSchedule.Once),
                    progressKind = OutputProgressKind.SUBTASKS.rawValue, createdAt = now, targetDate = now),
            ),
            outputSubtasks = listOf(OutputSubtaskEntity(id(), outputId, "1챕터", isDone = true, order = 0)),
            checkIns = listOf(
                DailyCheckInEntity(id(), day, energy = 3, mood = 3, createdAt = now, completedAt = now, symptoms = "cold"),
                DailyCheckInEntity(id(), day.minusDays(1), note = "노트만", createdAt = now),
            ),
            selfReports = listOf(SelfReportEntity(id(), SelfReportEntity.encodeAnswers(mapOf("C1" to "within1m")), now)),
        )
    }

    private fun envelopeOf(store: StoreSnapshot, ledger: SeedLedgerDTO = SeedLedgerDTO()) =
        ExportImport.buildEnvelope(store, signals, ledger, now, zone)

    @Test fun envelopeRoundTripThroughJson() {
        val store = sample()
        val text = ExportCodec.encode(envelopeOf(store))
        val decoded = ExportCodec.decode(text)
        assertEquals(2, decoded.periodDays.size)
        assertEquals(setOf("2026-09-03", "2026-09-04"), decoded.periodDays.map { it.day }.toSet())
        // 종일 일정은 date-only 병기, 시간 지정은 instant
        val trip = decoded.scheduleItems.single { it.title == "여행" }
        assertEquals("2026-09-03", trip.date)
        assertEquals("2026-09-05", trip.endDay)
        val dinner = decoded.scheduleItems.single { it.title == "저녁약속" }
        assertTrue(dinner.date.endsWith("Z"), "시간 지정 일정은 instant로 나간다")
        assertEquals(30, dinner.reminderMinutes)
        assertNull(dinner.endDay)
        // 값이 0뿐인 진행 레코드는 빠진다
        assertEquals(1, decoded.inputProgress?.size)
        assertEquals("2026-09-03", decoded.inputProgress?.single()?.day)
        assertEquals(1, decoded.selfReports?.size)
        assertNull(decoded.rhythmSummary, "축 엔진 산출물은 P0에서 싣지 않는다")

        // 빈 스토어에 그대로 병합하면 원본과 같은 수가 들어온다
        val plan = ExportImport.plan(decoded, StoreSnapshot(), SeedLedgerDTO(), zone)
        assertEquals(2, plan.periodDays.size)
        assertEquals(2, plan.schedules.size)
        assertEquals(1, plan.inputs.size)
        assertEquals(1, plan.inputSubtasks.size)
        assertEquals(1, plan.inputProgress.size)
        assertEquals(1, plan.completions.size)
        assertEquals(1, plan.outputs.size)
        assertEquals(1, plan.outputSubtasks.size)
        assertEquals(2, plan.checkIns.size, "노트 단독 체크인도 살아남는다")
        assertEquals(1, plan.selfReports.size)
        // 2+2+1+1+1+1+2+1 = 11 — 서브태스크는 건수에 세지 않는다(부모에 딸린 값이라)
        assertEquals(11, plan.added)
    }

    @Test fun mergeIsIdempotent() {
        val store = sample()
        val envelope = envelopeOf(store)
        val plan = ExportImport.plan(envelope, store, SeedLedgerDTO(), zone)
        assertEquals(0, plan.added, "같은 파일을 다시 가져오면 새로 들어올 게 없다")
    }

    @Test fun dedupKeysMatchIOS() {
        val store = sample()
        val envelope = envelopeOf(store)
        // 생리일·체크인은 날짜 기준 — id가 달라도 같은 날이면 안 들어온다
        val sameDaysDifferentIds = StoreSnapshot(
            periodDays = store.periodDays.map { it.copy(id = id()) },
            checkIns = store.checkIns.map { it.copy(id = id()) },
        )
        val byDate = ExportImport.plan(envelope, sameDaysDifferentIds, SeedLedgerDTO(), zone)
        assertTrue(byDate.periodDays.isEmpty())
        assertTrue(byDate.checkIns.isEmpty())

        // 일정·Input·Output·완료·설문은 UUID 기준 — 같은 id면 제목이 달라도 안 들어온다
        val sameIds = StoreSnapshot(
            schedules = store.schedules.map { it.copy(title = "다른 제목") },
            inputs = store.inputs.map { it.copy(title = "다른 제목") },
            outputs = store.outputs.map { it.copy(title = "다른 제목") },
            completions = store.completions,
            selfReports = store.selfReports,
        )
        val byId = ExportImport.plan(envelope, sameIds, SeedLedgerDTO(), zone)
        assertTrue(byId.schedules.isEmpty()); assertTrue(byId.inputs.isEmpty())
        assertTrue(byId.outputs.isEmpty()); assertTrue(byId.completions.isEmpty()); assertTrue(byId.selfReports.isEmpty())

        // 진행 레코드는 아이템 × 날짜 — id가 달라도 그 조합이 있으면 건드리지 않는다(값을 더하면 안 된다)
        val sameProgressSlot = StoreSnapshot(
            inputProgress = listOf(InputProgressEntity(id(), store.inputs.single().id, day, loggedSessions = 99)),
        )
        assertTrue(ExportImport.plan(envelope, sameProgressSlot, SeedLedgerDTO(), zone).inputProgress.isEmpty())
    }

    @Test fun restoreKeepsTimerStopped() {
        val running = sample().let { s ->
            s.copy(
                outputs = s.outputs.map { it.copy(elapsedAccumSeconds = 10.0, timerStartedAt = now) },
                inputProgress = s.inputProgress.map { it.copy(timerStartedAt = now) },
            )
        }
        val envelope = envelopeOf(running)
        val plan = ExportImport.plan(envelope, StoreSnapshot(), SeedLedgerDTO(), zone)
        assertNull(plan.outputs.single().timerStartedAt, "복원은 정지 상태")
        assertTrue(plan.outputs.single().elapsedAccumSeconds >= 10.0, "경과는 접혀서 들어온다")
        // 돌아가는 타이머는 경과가 0이 아니라, 값이 0뿐이던 레코드까지 봉투에 실린다(iOS 가드와 같음)
        assertEquals(2, plan.inputProgress.size)
        assertTrue(plan.inputProgress.all { it.timerStartedAt == null })
    }

    @Test fun seedLedgerMergesAsUnion() {
        val local = SeedLedgerDTO(purchases = mapOf("standard" to 3), earnedDays = listOf("2026-09-01"))
        val remote = SeedLedgerDTO(purchases = mapOf("plain" to 5, "standard" to 1), earnedDays = listOf("2026-09-02"))
        val plan = ExportImport.plan(envelopeOf(StoreSnapshot(), remote), StoreSnapshot(), local, zone)
        val merged = plan.ledger!!
        assertEquals(setOf("standard", "plain"), merged.ownedThemes, "보유 테마는 합집합 — 백업이 오래됐어도 산 테마가 사라지지 않는다")
        assertEquals(listOf("2026-09-01", "2026-09-02"), merged.earnedDays.orEmpty())
        assertEquals(8, merged.spent, "같은 테마가 겹치면 소비는 큰 쪽(3) + 상대 고유분(5)")
    }

    @Test fun rejectsNewerSchemaAndCorruptFile() {
        // 버전은 전체 파싱 전에 본다 — 한 필드만 있어도 거절해야 한다
        assertFailsWith<ExportCodec.CodecError.NewerVersion> { ExportCodec.decode("{\"schemaVersion\": 99}") }
        val roundTrip = ExportCodec.encode(envelopeOf(sample()))
        assertEquals(1, ExportCodec.decode(roundTrip).schemaVersion)
        assertFailsWith<ExportCodec.CodecError.Corrupt> { ExportCodec.decode("{ not json") }
    }
}
