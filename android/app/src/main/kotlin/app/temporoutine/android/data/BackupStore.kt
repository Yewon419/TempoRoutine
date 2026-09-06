// 템포루틴 Android — 백업 쓰기 단일 창구 (iOS SettingsView.exportData/importData + ExportImport.wipeAll 이식)
// 읽기(스냅샷)·병합 적용·전체 삭제를 여기 모은다. 순수 규칙은 ExportImport, DB 왕복은 이 클래스.
// 되돌리기: 삭제 직전 봉투를 그대로 다시 병합한다(§8.2.6) — 재화(씨앗 원장)는 애초에 안 지우므로 복원 대상이 아니다.

package app.temporoutine.android.data

import app.temporoutine.core.ExportCodec
import app.temporoutine.core.ExportEnvelopeV1
import java.time.Instant

class BackupStore(private val db: AppDatabase, private val settings: Settings) {

    suspend fun snapshot(): StoreSnapshot = StoreSnapshot(
        periodDays = db.periodDays().all(),
        schedules = db.schedules().all(),
        inputs = db.inputs().all(),
        inputSubtasks = db.inputs().allSubtasks(),
        inputProgress = db.inputs().allProgress(),
        completions = db.inputs().allCompletions(),
        outputs = db.outputs().all(),
        outputSubtasks = db.outputs().allSubtasks(),
        checkIns = db.checkIns().all(),
        selfReports = db.selfReports().all(),
    )

    /** 내보내기 — 봉투 JSON 문자열. 파일 쓰기는 호출측(SAF). */
    suspend fun exportJson(exportedAt: Instant = Instant.now()): String {
        val current = settings.current()
        return ExportCodec.encode(ExportImport.buildEnvelope(snapshot(), current.trackedSignals, current.seedLedger, exportedAt))
    }

    /** 가져오기 — 병합 후 추가 건수. 봉투 파싱 실패는 호출측이 CodecError로 받는다. */
    suspend fun importEnvelope(envelope: ExportEnvelopeV1): Int {
        val plan = ExportImport.plan(envelope, snapshot(), settings.current().seedLedger)
        apply(plan)
        return plan.added
    }

    private suspend fun apply(plan: ExportImport.MergePlan) {
        if (plan.periodDays.isNotEmpty()) db.periodDays().insert(plan.periodDays)
        plan.schedules.forEach { db.schedules().insert(it) }
        plan.inputs.forEach { db.inputs().insert(it) }
        if (plan.inputSubtasks.isNotEmpty()) db.inputs().insertSubtasks(plan.inputSubtasks)
        plan.inputProgress.forEach { db.inputs().insertProgress(it) }
        plan.completions.forEach { db.inputs().insertCompletion(it) }
        plan.outputs.forEach { db.outputs().insert(it) }
        if (plan.outputSubtasks.isNotEmpty()) db.outputs().insertSubtasks(plan.outputSubtasks)
        plan.checkIns.forEach { db.checkIns().insert(it) }
        plan.selfReports.forEach { db.selfReports().insert(it) }
        // 씨앗 원장은 합집합 병합 — 아이템이 아니라 재화라 added에 세지 않는다
        plan.ledger?.let { settings.setSeedLedger(it) }
    }

    /**
     * 모든 기록 삭제 — 되돌리기용으로 삭제 직전 봉투를 돌려준다.
     * 씨앗 원장(설정)은 지우지 않는다: 재화는 기록이 아니다(iOS와 같은 경계).
     */
    suspend fun wipeAll(): ExportEnvelopeV1 {
        val current = settings.current()
        val snapshot = ExportImport.buildEnvelope(snapshot(), current.trackedSignals, current.seedLedger)
        db.periodDays().deleteAll()
        db.schedules().deleteAll()
        db.inputs().deleteAllSubtasks()
        db.inputs().deleteAllProgress()
        db.inputs().deleteAllCompletions()
        db.inputs().deleteAll()
        db.outputs().deleteAllSubtasks()
        db.outputs().deleteAll()
        db.checkIns().deleteAll()
        db.selfReports().deleteAll()
        return snapshot
    }
}
