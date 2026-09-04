// 템포루틴 Android — Room DAO. 화면은 Flow로 관찰, 쓰기는 suspend.

package app.temporoutine.android.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow
import java.time.LocalDate

@Dao
interface PeriodDayDao {
    @Query("SELECT * FROM period_days ORDER BY day") fun observeAll(): Flow<List<PeriodDayEntity>>
    @Query("SELECT * FROM period_days ORDER BY day") suspend fun all(): List<PeriodDayEntity>
    @Insert(onConflict = OnConflictStrategy.ABORT) suspend fun insert(items: List<PeriodDayEntity>)
    @Delete suspend fun delete(items: List<PeriodDayEntity>)
    @Query("DELETE FROM period_days") suspend fun deleteAll()
}

@Dao
interface DailyCheckInDao {
    @Query("SELECT * FROM daily_check_ins ORDER BY day") fun observeAll(): Flow<List<DailyCheckInEntity>>
    @Query("SELECT * FROM daily_check_ins ORDER BY day") suspend fun all(): List<DailyCheckInEntity>
    @Query("SELECT * FROM daily_check_ins WHERE day = :day LIMIT 1") suspend fun forDay(day: LocalDate): DailyCheckInEntity?
    @Query("SELECT * FROM daily_check_ins WHERE day = :day LIMIT 1") fun observeDay(day: LocalDate): Flow<DailyCheckInEntity?>
    @Insert(onConflict = OnConflictStrategy.ABORT) suspend fun insert(item: DailyCheckInEntity)
    @Update suspend fun update(item: DailyCheckInEntity)
    @Delete suspend fun delete(item: DailyCheckInEntity)
    @Query("DELETE FROM daily_check_ins") suspend fun deleteAll()
}

@Dao
interface ScheduleItemDao {
    @Query("SELECT * FROM schedule_items ORDER BY date") fun observeAll(): Flow<List<ScheduleItemEntity>>
    @Query("SELECT * FROM schedule_items ORDER BY date") suspend fun all(): List<ScheduleItemEntity>
    @Insert(onConflict = OnConflictStrategy.ABORT) suspend fun insert(item: ScheduleItemEntity)
    @Update suspend fun update(item: ScheduleItemEntity)
    @Delete suspend fun delete(item: ScheduleItemEntity)
    @Query("DELETE FROM schedule_items") suspend fun deleteAll()
}

@Dao
interface InputItemDao {
    @Query("SELECT * FROM input_items ORDER BY createdAt") fun observeAll(): Flow<List<InputItemEntity>>
    @Query("SELECT * FROM input_items ORDER BY createdAt") suspend fun all(): List<InputItemEntity>
    @Insert(onConflict = OnConflictStrategy.ABORT) suspend fun insert(item: InputItemEntity)
    @Update suspend fun update(item: InputItemEntity)
    @Delete suspend fun delete(item: InputItemEntity)
    @Query("DELETE FROM input_items") suspend fun deleteAll()

    @Query("SELECT * FROM input_subtasks ORDER BY sort_order") fun observeSubtasks(): Flow<List<InputSubtaskEntity>>
    @Query("SELECT * FROM input_subtasks ORDER BY sort_order") suspend fun allSubtasks(): List<InputSubtaskEntity>
    @Insert(onConflict = OnConflictStrategy.ABORT) suspend fun insertSubtasks(items: List<InputSubtaskEntity>)
    @Query("DELETE FROM input_subtasks WHERE ownerId = :ownerId") suspend fun deleteSubtasks(ownerId: String)
    @Query("DELETE FROM input_subtasks") suspend fun deleteAllSubtasks()

    @Query("SELECT * FROM input_progress") fun observeProgress(): Flow<List<InputProgressEntity>>
    @Query("SELECT * FROM input_progress") suspend fun allProgress(): List<InputProgressEntity>
    @Query("SELECT * FROM input_progress WHERE itemId = :itemId AND occurredOn = :day LIMIT 1")
    suspend fun progress(itemId: String, day: LocalDate): InputProgressEntity?
    @Insert(onConflict = OnConflictStrategy.ABORT) suspend fun insertProgress(item: InputProgressEntity)
    @Update suspend fun updateProgress(item: InputProgressEntity)
    @Query("DELETE FROM input_progress WHERE itemId = :itemId") suspend fun deleteProgress(itemId: String)
    @Query("DELETE FROM input_progress") suspend fun deleteAllProgress()

    @Query("SELECT * FROM item_completions") fun observeCompletions(): Flow<List<ItemCompletionEntity>>
    @Query("SELECT * FROM item_completions") suspend fun allCompletions(): List<ItemCompletionEntity>
    @Query("SELECT * FROM item_completions WHERE itemId = :itemId AND occurredOn = :day")
    suspend fun completions(itemId: String, day: LocalDate): List<ItemCompletionEntity>
    @Insert(onConflict = OnConflictStrategy.ABORT) suspend fun insertCompletion(item: ItemCompletionEntity)
    @Delete suspend fun deleteCompletions(items: List<ItemCompletionEntity>)
    @Query("DELETE FROM item_completions WHERE itemId = :itemId") suspend fun deleteCompletions(itemId: String)
    @Query("DELETE FROM item_completions") suspend fun deleteAllCompletions()
}

@Dao
interface OutputItemDao {
    @Query("SELECT * FROM output_items ORDER BY createdAt") fun observeAll(): Flow<List<OutputItemEntity>>
    @Query("SELECT * FROM output_items ORDER BY createdAt") suspend fun all(): List<OutputItemEntity>
    @Insert(onConflict = OnConflictStrategy.ABORT) suspend fun insert(item: OutputItemEntity)
    @Update suspend fun update(item: OutputItemEntity)
    @Delete suspend fun delete(item: OutputItemEntity)
    @Query("DELETE FROM output_items") suspend fun deleteAll()

    @Query("SELECT * FROM output_subtasks ORDER BY sort_order") fun observeSubtasks(): Flow<List<OutputSubtaskEntity>>
    @Query("SELECT * FROM output_subtasks ORDER BY sort_order") suspend fun allSubtasks(): List<OutputSubtaskEntity>
    @Insert(onConflict = OnConflictStrategy.ABORT) suspend fun insertSubtasks(items: List<OutputSubtaskEntity>)
    @Update suspend fun updateSubtask(item: OutputSubtaskEntity)
    @Query("DELETE FROM output_subtasks WHERE ownerId = :ownerId") suspend fun deleteSubtasks(ownerId: String)
    @Query("DELETE FROM output_subtasks") suspend fun deleteAllSubtasks()
}

@Dao
interface SelfReportDao {
    @Query("SELECT * FROM self_reports ORDER BY completedAt") fun observeAll(): Flow<List<SelfReportEntity>>
    @Query("SELECT * FROM self_reports ORDER BY completedAt") suspend fun all(): List<SelfReportEntity>
    @Insert(onConflict = OnConflictStrategy.ABORT) suspend fun insert(item: SelfReportEntity)
    @Query("DELETE FROM self_reports") suspend fun deleteAll()
}
