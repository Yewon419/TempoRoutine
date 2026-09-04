// Room 계측 테스트 — 쓰기 경로 계약(dedup·미래 금지·체크인 upsert/삭제·도장 1회·원장 기록)을 실제 DB에서 확인.
// 실행: 에뮬레이터 켠 뒤 `gradlew :app:connectedDebugAndroidTest`

package app.temporoutine.android.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.time.LocalDate

@RunWith(AndroidJUnit4::class)
class StoreTests {

    private lateinit var db: AppDatabase
    private lateinit var settings: Settings
    private lateinit var periodStore: PeriodStore
    private lateinit var checkInStore: CheckInStore
    private val today = LocalDate.of(2026, 9, 4)

    @Before fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java).build()
        settings = Settings(context)
        periodStore = PeriodStore(db.periodDays())
        checkInStore = CheckInStore(db.checkIns(), settings)
        runBlocking {
            settings.setSeedLedger(app.temporoutine.core.SeedLedgerDTO())
            settings.setTrackedSignals(app.temporoutine.core.TrackedSignals(false, false, false, false))
        }
    }

    @After fun tearDown() { db.close() }

    @Test fun periodStoreDedupsAndRefusesFuture() = runBlocking {
        periodStore.add(listOf(today, today.minusDays(1), today.plusDays(1)), emptyList(), today)
        var all = db.periodDays().all()
        assertEquals(listOf(today.minusDays(1), today), all.map { it.day })

        periodStore.add(listOf(today, today.minusDays(2)), all, today)
        all = db.periodDays().all()
        assertEquals(3, all.size)
        assertEquals(1, all.count { it.day == today })

        periodStore.toggle(today, all, today)
        all = db.periodDays().all()
        assertFalse(all.any { it.day == today })
        periodStore.toggle(today, all, today)
        assertTrue(db.periodDays().all().any { it.day == today })
    }

    @Test fun checkInUpsertDeleteAndStamp() = runBlocking {
        val r1 = checkInStore.persist(today, CheckInDraft(energy = 3, mood = 3), today)
        assertNotNull(r1.record)
        assertTrue("완성 즉시 지급", r1.awarded)
        assertNotNull(db.checkIns().forDay(today)!!.completedAt)
        assertEquals(listOf("2026-09-04"), settings.current().seedLedger.earnedDays)

        val r2 = checkInStore.persist(today, CheckInDraft(energy = 5, mood = 3, note = "짧게"), today)
        assertFalse("도장은 한 번", r2.awarded)
        val row = db.checkIns().forDay(today)!!
        assertEquals(5, row.energy)
        assertEquals("짧게", row.note)
        assertEquals(1, db.checkIns().all().size)

        // 시트 편집기(symptoms=null)는 증상을 보존한다
        db.checkIns().update(row.copy(symptoms = "cold"))
        checkInStore.persist(today, CheckInDraft(energy = 2, mood = 2), today)
        assertEquals("cold", db.checkIns().forDay(today)!!.symptoms)

        checkInStore.persist(today, CheckInDraft(), today)
        assertNull("전부 비면 삭제", db.checkIns().forDay(today))

        val future = checkInStore.persist(today.plusDays(1), CheckInDraft(energy = 3, mood = 3), today)
        assertNull(future.record)
        assertTrue(db.checkIns().all().isEmpty())
    }

    @Test fun backfilledFlag() = runBlocking {
        checkInStore.persist(today.minusDays(3), CheckInDraft(energy = 3, mood = 3), today)
        assertTrue(db.checkIns().forDay(today.minusDays(3))!!.isBackfilled)
        assertFalse("사흘 뒤 완성은 미지급", settings.current().seedLedger.earnedDays.orEmpty().contains("2026-09-01"))
    }
}
