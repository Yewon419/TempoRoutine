// 템포루틴 Android — 엔티티 ↔ DTO 변환·병합 (iOS ExportImport.swift 이식, MASTER §5.5.1)
// 재임포트 dedup: PeriodDay=day / DailyCheckIn=day / InputProgress=아이템×날짜 / 나머지=UUID.
// 씨앗 원장만 합집합 병합(덮어쓰기 아님) — 백업이 오래됐어도 그 사이 산 테마를 되돌리지 않는다.
// 실행 중 타이머는 싣지 않는다(스냅샷은 접힌 경과, 복원은 멈춘 상태).
// ⚠ rhythmSummary는 내보내지 않는다(null) — 축 엔진은 「나의 템포」 화면과 함께 P1. 재임포트는 원래 이 필드를 읽지 않는다.

package app.temporoutine.android.data

import app.temporoutine.core.DailyCheckInDTO
import app.temporoutine.core.ExportCodec
import app.temporoutine.core.ExportEnvelopeV1
import app.temporoutine.core.InputCategory
import app.temporoutine.core.InputItemDTO
import app.temporoutine.core.InputProgressDTO
import app.temporoutine.core.InputSubtaskDTO
import app.temporoutine.core.ItemCompletionDTO
import app.temporoutine.core.OutputItemDTO
import app.temporoutine.core.OutputProgressKind
import app.temporoutine.core.OutputSubtaskDTO
import app.temporoutine.core.PeriodDayDTO
import app.temporoutine.core.ScheduleItemDTO
import app.temporoutine.core.ScheduleRepeat
import app.temporoutine.core.SeedLedgerDTO
import app.temporoutine.core.SelfReportDTO
import app.temporoutine.core.TrackedSignals
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

/** 봉투 한 번에 필요한 전량. DAO 왕복을 한 곳에 모은다(iOS StoreArrays). */
data class StoreSnapshot(
    val periodDays: List<PeriodDayEntity> = emptyList(),
    val schedules: List<ScheduleItemEntity> = emptyList(),
    val inputs: List<InputItemEntity> = emptyList(),
    val inputSubtasks: List<InputSubtaskEntity> = emptyList(),
    val inputProgress: List<InputProgressEntity> = emptyList(),
    val completions: List<ItemCompletionEntity> = emptyList(),
    val outputs: List<OutputItemEntity> = emptyList(),
    val outputSubtasks: List<OutputSubtaskEntity> = emptyList(),
    val checkIns: List<DailyCheckInEntity> = emptyList(),
    val selfReports: List<SelfReportEntity> = emptyList(),
)

object ExportImport {

    // ── 내보내기: 엔티티 → 봉투 ──

    fun buildEnvelope(
        store: StoreSnapshot, signals: TrackedSignals, ledger: SeedLedgerDTO,
        exportedAt: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault(),
    ): ExportEnvelopeV1 {
        val subtasksByInput = store.inputSubtasks.groupBy { it.ownerId }
        val subtasksByOutput = store.outputSubtasks.groupBy { it.ownerId }
        return ExportEnvelopeV1(
            exportedAt = exportedAt,
            periodDays = store.periodDays.map {
                PeriodDayDTO(ExportCodec.dayString(it.day), it.origin, it.healthKitUUID?.let(::uuidOrNull))
            },
            scheduleItems = store.schedules.map { item ->
                val day = item.date.atZone(zone).toLocalDate()
                ScheduleItemDTO(
                    id = uuid(item.id), title = item.title,
                    date = if (item.isAllDay) ExportCodec.dayString(day) else ExportCodec.instantString(item.date),
                    isAllDay = item.isAllDay,
                    repeatRule = ScheduleRepeat.fromRawValue(item.repeatRule) ?: ScheduleRepeat.NONE,
                    createdAt = item.createdAt,
                    endDate = item.endDate?.let { ExportCodec.instantString(it) },
                    reminderMinutes = item.reminderMinutes.takeIf { it >= 0 },
                    // 종일 종료는 date-only 병기 — 시차 이동 시 하루 밀림 방지(instant는 구 빌드 호환)
                    endDay = if (item.isAllDay) item.endDate?.let { ExportCodec.dayString(it.atZone(zone).toLocalDate()) } else null,
                )
            },
            inputItems = store.inputs.map { item ->
                val subs = subtasksByInput[item.id].orEmpty().sortedBy { it.order }
                InputItemDTO(
                    id = uuid(item.id), title = item.title,
                    category = InputCategory.fromRawValue(item.category) ?: InputCategory.OTHER,
                    schedule = item.schedule, createdAt = item.createdAt,
                    backfilled = item.backfilled.takeIf { it },
                    timeMinutes = item.timeMinutes,
                    progressKind = item.progressKind,
                    targetSessions = item.targetSessions.takeIf { it > 0 },
                    targetSeconds = item.targetSeconds,
                    subtasks = subs.takeIf { it.isNotEmpty() }?.map { InputSubtaskDTO(uuid(it.id), it.title, it.order) },
                )
            },
            outputItems = store.outputs.map { item ->
                OutputItemDTO(
                    id = uuid(item.id), title = item.title, schedule = item.schedule, progressKind = item.kind,
                    subtasks = subtasksByOutput[item.id].orEmpty().sortedBy { it.order }
                        .map { OutputSubtaskDTO(uuid(it.id), it.title, it.isDone, it.order) },
                    targetSessions = item.targetSessions, loggedSessions = item.loggedSessions,
                    percent = item.percent, createdAt = item.createdAt, targetDate = item.targetDate,
                    targetSeconds = item.targetSeconds,
                    // 실행 중이어도 스냅샷은 접힌 경과로(실행 상태는 봉투 밖)
                    elapsedSeconds = item.elapsedSeconds().takeIf { it > 0 },
                    timeMinutes = item.timeMinutes,
                )
            },
            completions = store.completions.map {
                ItemCompletionDTO(uuid(it.id), uuid(it.itemId), ExportCodec.dayString(it.occurredOn), it.completedAt)
            },
            checkIns = store.checkIns.map {
                DailyCheckInDTO(
                    id = uuid(it.id), day = ExportCodec.dayString(it.day), energy = it.energy, mood = it.mood,
                    sleep = it.sleep, pain = it.pain, appetite = it.appetite, note = it.note,
                    createdAt = it.createdAt, irritability = it.irritability,
                    isBackfilled = it.isBackfilled.takeIf { flag -> flag },
                    completedAt = it.completedAt,
                    symptoms = it.symptoms.takeIf { s -> s.isNotEmpty() },
                )
            },
            trackedSignals = signals,
            rhythmSummary = null,
            seedLedger = ledger,
            // 값이 0뿐인 레코드는 싣지 않는다(복원해도 아무 뜻이 없다)
            inputProgress = store.inputProgress.mapNotNull { record ->
                val elapsed = record.elapsedSeconds()
                val done = record.doneSubtaskIds.toList().sorted()
                if (record.loggedSessions == 0 && record.percent == 0.0 && elapsed == 0.0 && done.isEmpty()) return@mapNotNull null
                InputProgressDTO(
                    id = uuid(record.id), itemID = uuid(record.itemId),
                    occurredOn = record.occurredOn.atStartOfDay(zone).toInstant(),
                    loggedSessions = record.loggedSessions, percent = record.percent, elapsedSeconds = elapsed,
                    doneSubtaskIDs = done.map(::uuid),
                    day = ExportCodec.dayString(record.occurredOn),   // 날짜-키 병기 — 읽기는 이쪽 우선
                )
            }.takeIf { it.isNotEmpty() },
            selfReports = store.selfReports.takeIf { it.isNotEmpty() }?.map {
                SelfReportDTO(uuid(it.id), it.answers, it.completedAt, it.sharedToServer)
            },
        )
    }

    // ── 재임포트: merge·dedup → 추가할 행 묶음 ──

    /** 병합 결과 — 쓰기는 호출측(스토어)이 한 트랜잭션으로. `added`는 아이템 건수(재화는 세지 않는다). */
    data class MergePlan(
        val periodDays: List<PeriodDayEntity> = emptyList(),
        val schedules: List<ScheduleItemEntity> = emptyList(),
        val inputs: List<InputItemEntity> = emptyList(),
        val inputSubtasks: List<InputSubtaskEntity> = emptyList(),
        val inputProgress: List<InputProgressEntity> = emptyList(),
        val completions: List<ItemCompletionEntity> = emptyList(),
        val outputs: List<OutputItemEntity> = emptyList(),
        val outputSubtasks: List<OutputSubtaskEntity> = emptyList(),
        val checkIns: List<DailyCheckInEntity> = emptyList(),
        val selfReports: List<SelfReportEntity> = emptyList(),
        val ledger: SeedLedgerDTO? = null,
    ) {
        val added: Int
            get() = periodDays.size + schedules.size + inputs.size + inputProgress.size +
                completions.size + outputs.size + checkIns.size + selfReports.size
    }

    fun plan(envelope: ExportEnvelopeV1, existing: StoreSnapshot, ledger: SeedLedgerDTO, zone: ZoneId = ZoneId.systemDefault()): MergePlan {
        val existingDays = existing.periodDays.map { it.day }.toSet()
        val periodDays = envelope.periodDays.mapNotNull { dto ->
            val day = ExportCodec.day(dto.day) ?: return@mapNotNull null
            if (day in existingDays) null
            else PeriodDayEntity(day = day, origin = dto.origin, healthKitUUID = dto.healthKitUUID?.let(::idString))
        }.distinctBy { it.day }

        val scheduleIds = existing.schedules.map { it.id }.toSet()
        val schedules = envelope.scheduleItems.mapNotNull { dto ->
            if (idString(dto.id) in scheduleIds) return@mapNotNull null
            val start = if (dto.isAllDay) ExportCodec.day(dto.date)?.atStartOfDay(zone)?.toInstant()
            else ExportCodec.instant(dto.date)
            start ?: return@mapNotNull null
            // 종일 종료는 date-only(endDay) 우선 — 구 봉투는 instant 폴백
            val end = dto.endDay?.let { ExportCodec.day(it)?.atStartOfDay(zone)?.toInstant() }
                ?: dto.endDate?.let { ExportCodec.instant(it) }
            ScheduleItemEntity(
                id = idString(dto.id), title = dto.title, date = start, endDate = end, isAllDay = dto.isAllDay,
                repeatRule = dto.repeatRule.rawValue, reminderMinutes = dto.reminderMinutes ?: -1, createdAt = dto.createdAt,
            )
        }

        val inputIds = existing.inputs.map { it.id }.toSet()
        val newInputs = envelope.inputItems.filter { idString(it.id) !in inputIds }
        val inputs = newInputs.map { dto ->
            InputItemEntity(
                id = idString(dto.id), title = dto.title, category = dto.category.rawValue,
                progressKindRaw = dto.progressKind?.rawValue ?: "",
                targetSessions = dto.targetSessions ?: 0, targetSeconds = dto.targetSeconds,
                scheduleJson = InputItemEntity.encodeSchedule(dto.schedule), createdAt = dto.createdAt,
                backfilled = dto.backfilled ?: false, timeMinutes = dto.timeMinutes,
            )
        }
        // 서브태스크 id를 보존한다 — 진행 레코드의 완료 id가 이 id를 가리킨다
        val inputSubtasks = newInputs.flatMap { dto ->
            dto.subtasks.orEmpty().map { InputSubtaskEntity(idString(it.id), idString(dto.id), it.title, it.order) }
        }

        // 진행도는 "얼마나 했나"라 두 기기 값을 더하면 안 된다 — 없을 때만 채운다(완료 기록과 같은 문법)
        val existingProgress = existing.inputProgress.map { it.itemId to it.occurredOn }.toSet()
        val inputProgress = envelope.inputProgress.orEmpty().mapNotNull { dto ->
            val day = dto.day?.let { ExportCodec.day(it) } ?: dto.occurredOn.atZone(zone).toLocalDate()
            val key = idString(dto.itemID) to day
            if (key in existingProgress) return@mapNotNull null
            InputProgressEntity(
                id = idString(dto.id), itemId = idString(dto.itemID), occurredOn = day,
                loggedSessions = dto.loggedSessions, percent = dto.percent,
                elapsedAccumSeconds = dto.elapsedSeconds,   // 실행 상태는 싣지 않는다(멈춘 채로 온다)
                timerStartedAt = null,
            ).withDoneSubtaskIds(dto.doneSubtaskIDs.map(::idString).toSet())
        }.distinctBy { it.itemId to it.occurredOn }

        val outputIds = existing.outputs.map { it.id }.toSet()
        val newOutputs = envelope.outputItems.filter { idString(it.id) !in outputIds }
        val outputs = newOutputs.map { dto ->
            OutputItemEntity(
                id = idString(dto.id), title = dto.title,
                scheduleJson = OutputItemEntity.encodeSchedule(dto.schedule), progressKind = dto.progressKind.rawValue,
                targetSessions = dto.targetSessions, loggedSessions = dto.loggedSessions, percent = dto.percent,
                createdAt = dto.createdAt, targetDate = dto.targetDate, targetSeconds = dto.targetSeconds,
                elapsedAccumSeconds = dto.elapsedSeconds ?: 0.0,   // 복원 = 정지 상태
                timerStartedAt = null, timeMinutes = dto.timeMinutes,
            )
        }
        val outputSubtasks = newOutputs.flatMap { dto ->
            dto.subtasks.map { OutputSubtaskEntity(idString(it.id), idString(dto.id), it.title, it.isDone, it.order) }
        }

        val completionIds = existing.completions.map { it.id }.toSet()
        val completions = envelope.completions.mapNotNull { dto ->
            if (idString(dto.id) in completionIds) return@mapNotNull null
            val day = ExportCodec.day(dto.occurredOn) ?: return@mapNotNull null
            ItemCompletionEntity(idString(dto.id), idString(dto.itemID), day, dto.completedAt)
        }

        val checkInDays = existing.checkIns.map { it.day }.toSet()
        val checkIns = envelope.checkIns.mapNotNull { dto ->
            val day = ExportCodec.day(dto.day) ?: return@mapNotNull null
            if (day in checkInDays) return@mapNotNull null
            // 노트·증상 단독 행도 유효(§5.5 개정) — 신호 필수 가드는 그런 체크인을 복원에서 버렸다
            val hasSignals = dto.energy >= 1 && dto.mood >= 1
            val hasNote = !dto.note.isNullOrBlank()
            val hasSymptoms = !dto.symptoms.isNullOrEmpty()
            if (!hasSignals && !hasNote && !hasSymptoms) return@mapNotNull null
            DailyCheckInEntity(
                id = idString(dto.id), day = day, energy = dto.energy, mood = dto.mood, sleep = dto.sleep,
                pain = dto.pain, appetite = dto.appetite, irritability = dto.irritability, note = dto.note,
                createdAt = dto.createdAt, isBackfilled = dto.isBackfilled ?: false,
                completedAt = dto.completedAt,   // 씨앗 근거 복원
                symptoms = dto.symptoms.orEmpty(),
            )
        }.distinctBy { it.day }

        val reportIds = existing.selfReports.map { it.id }.toSet()
        val selfReports = envelope.selfReports.orEmpty().mapNotNull { dto ->
            if (idString(dto.id) in reportIds) return@mapNotNull null
            SelfReportEntity(idString(dto.id), SelfReportEntity.encodeAnswers(dto.answers), dto.completedAt, dto.sharedToServer)
        }

        return MergePlan(
            periodDays = periodDays, schedules = schedules, inputs = inputs, inputSubtasks = inputSubtasks,
            inputProgress = inputProgress, completions = completions, outputs = outputs,
            outputSubtasks = outputSubtasks, checkIns = checkIns, selfReports = selfReports,
            ledger = envelope.seedLedger?.let { ledger.merged(it) },
        )
    }

    private fun uuid(id: String): UUID = uuidOrNull(id) ?: UUID.nameUUIDFromBytes(id.toByteArray())

    private fun uuidOrNull(id: String): UUID? = try {
        UUID.fromString(id)
    } catch (e: IllegalArgumentException) {
        null
    }

    /** 엔티티 id 표기는 대문자 문자열(iOS UUID 문자열과 같은 모양). */
    private fun idString(id: UUID): String = id.toString().uppercase()
}
