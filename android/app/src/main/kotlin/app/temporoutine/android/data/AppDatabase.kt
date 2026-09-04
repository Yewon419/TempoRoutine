// 템포루틴 Android — Room 데이터베이스. 스키마 v1 = 엔티티 10종 한 번에 확정(Phase 1 계획 가정 7).
// ⚠ 새 엔티티는 여기 entities 배열에 등록 — iOS `.modelContainer(for:)` 규칙과 같은 함정(빠지면 런타임에서만 드러난다).

package app.temporoutine.android.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters

@Database(
    entities = [
        PeriodDayEntity::class,
        DailyCheckInEntity::class,
        ScheduleItemEntity::class,
        InputItemEntity::class,
        InputSubtaskEntity::class,
        InputProgressEntity::class,
        ItemCompletionEntity::class,
        OutputItemEntity::class,
        OutputSubtaskEntity::class,
        SelfReportEntity::class,
    ],
    version = 1,
    exportSchema = true,
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun periodDays(): PeriodDayDao
    abstract fun checkIns(): DailyCheckInDao
    abstract fun schedules(): ScheduleItemDao
    abstract fun inputs(): InputItemDao
    abstract fun outputs(): OutputItemDao
    abstract fun selfReports(): SelfReportDao

    companion object {
        const val NAME = "temporoutine.db"

        fun build(context: Context): AppDatabase =
            Room.databaseBuilder(context.applicationContext, AppDatabase::class.java, NAME).build()
    }
}
