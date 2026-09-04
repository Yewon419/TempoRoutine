// 템포루틴 — 심사용 샘플 백업 검증 (iOS ReviewSampleTests.swift 1:1 이식)
// `tools/review-sample-backup.json`은 iOS 앱이 실제로 내보낸 봉투 — Android에서도 같은 성질(화면이 채워진다)이 성립해야 한다.
// 건수는 하한만 본다.

package app.temporoutine.core

import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Test
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ReviewSampleTests {

    companion object {
        /** 리포 루트의 tools/review-sample-backup.json — Gradle 테스트 작업 디렉터리 = android/tempocore */
        val sampleFile: File = File("../../tools/review-sample-backup.json")
    }

    private fun loadSample(): ExportEnvelopeV1 {
        assumeTrue(sampleFile.exists(), "샘플 파일 없음: ${sampleFile.absolutePath}")
        return ExportCodec.decode(sampleFile.readText(Charsets.UTF_8))
    }

    @Test fun testSampleDecodes() {
        assertEquals(1, loadSample().schemaVersion)
    }

    @Test fun testSampleFillsInsightScreens() {
        val envelope = loadSample()
        assertTrue(envelope.periodDays.size >= 15, "주기가 여러 번 있어야 사계·예측이 켜진다")
        assertTrue(envelope.checkIns.size >= 60, "체크인이 얇으면 「패턴은 아직 또렷하지 않아요」로 떨어진다")
        for (day in envelope.periodDays) assertNotNull(ExportCodec.day(day.day), "생리 기록 날짜 파싱 실패: ${day.day}")
        for (checkIn in envelope.checkIns) assertNotNull(ExportCodec.day(checkIn.day), "체크인 날짜 파싱 실패: ${checkIn.day}")
    }

    @Test fun testSampleFillsPlanner() {
        val envelope = loadSample()
        assertTrue(envelope.scheduleItems.size >= 3)
        assertTrue(envelope.inputItems.size >= 3)
        assertTrue(envelope.outputItems.size >= 3)
        assertTrue(envelope.completions.size >= 20, "루틴 체크가 있어야 캘린더 완료 표시가 뜬다")

        assertTrue(envelope.scheduleItems.any { it.repeatRule != ScheduleRepeat.NONE }, "반복 일정이 없으면 심사일에 오늘 탭이 빈다")
        assertTrue(envelope.inputItems.any { it.schedule == InputSchedule.Daily }, "매일 루틴이 없으면 심사일에 오늘 탭이 빈다")
        assertTrue(envelope.outputItems.any { it.schedule == OutputSchedule.Once }, "`.once` 목표는 완료까지 계속 표시된다")

        for (item in envelope.scheduleItems) {
            if (item.isAllDay) assertNotNull(ExportCodec.day(item.date), "종일 일정 날짜 파싱 실패: ${item.date}")
            else assertNotNull(ExportCodec.instant(item.date), "일정 시각 파싱 실패: ${item.date}")
        }

        assertTrue(envelope.outputItems.any { it.percent > 0 || it.loggedSessions > 0 || it.subtasks.any { s -> s.isDone } },
            "진행 중인 목표가 하나도 없으면 전부 시작 전으로 보인다")
    }

    @Test fun testSampleLetsReviewerBuyATheme() {
        val envelope = loadSample()
        val ledger = envelope.seedLedger
        assertNotNull(ledger, "씨앗 원장이 없으면 테마 구매를 못 본다")
        assertTrue((ledger.earnedDays?.size ?: 0) >= 7, "테마 한 벌 값(씨앗 7개)보다 많아야 한다")
        assertTrue(ledger.purchases.isEmpty(), "이미 사둔 상태로 주면 구매를 눌러볼 수 없다")
    }

    @Test fun testSampleCarriesNoNotes() {
        val envelope = loadSample()
        for (checkIn in envelope.checkIns) assertNull(checkIn.note, "합성 표본에 한 줄 기록이 있으면 실제 기록이 섞인 것이다")
        assertTrue(envelope.selfReports.orEmpty().isEmpty(), "설문 응답은 합성 대상이 아니다")
    }
}
