package app.temporoutine.android

import android.app.Application
import app.temporoutine.android.data.AppDatabase
import app.temporoutine.android.data.CheckInStore
import app.temporoutine.android.data.PeriodStore
import app.temporoutine.android.data.Settings

// DI 프레임워크 없이 Application 싱글턴(Phase 1 계획 가정 9).
class TempoApp : Application() {
    val db: AppDatabase by lazy { AppDatabase.build(this) }
    val settings: Settings by lazy { Settings(this) }
    val periodStore: PeriodStore by lazy { PeriodStore(db.periodDays()) }
    val checkInStore: CheckInStore by lazy { CheckInStore(db.checkIns(), settings) }
}
