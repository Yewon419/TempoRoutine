// 템포루틴 — 2층 스토어 부트스트랩 (§5.2 CloudKit 2층 동기화 실장, 2026-07-23)
// 민감층(PeriodDay) = 로컬 전용(CloudKit 금지 — 기기 간 경로는 Apple Health E2E, §5.7)
// 플래너층(ScheduleItem·InputItem·OutputItem·OutputSubtask·ItemCompletion) + DailyCheckIn = CloudKit private DB.
// 무계정 유지: Apple ID 기반, iCloud 불가 시 로컬 전용 폴백(같은 스토어 이름 → 복구 시 재부착).
// 구 단일 스토어(default.store) → 2층 분리는 1회성 마이그레이션 — §5.5.1 백업 봉투 경로 재사용(검증된 dedup 승계).

import Foundation
import SwiftData

@MainActor
enum AppStores {
    static let cloudContainerID = "iCloud.app.temporoutine.TempoRoutine"

    /// 이번 실행에서 플래너층 CloudKit이 실제로 켜졌는가 — 온보딩 저장 위치 카피가 참조(§3.10 정확성)
    private(set) static var cloudEnabled = false

    private static let sensitiveModels: [any PersistentModel.Type] = [PeriodDay.self]
    private static let plannerModels: [any PersistentModel.Type] =
        [ScheduleItem.self, InputItem.self, OutputItem.self, OutputSubtask.self,
         ItemCompletion.self, DailyCheckIn.self]

    static func makeContainer() -> ModelContainer {
        let fullSchema = Schema(sensitiveModels + plannerModels)
        // 민감층 config는 클라우드/로컬 폴백에서 동일 — PeriodDay 저장 위치가 실행마다 안 바뀐다.
        let sensitive = ModelConfiguration("tempo-sensitive", schema: Schema(sensitiveModels),
                                           cloudKitDatabase: .none)
        do {
            let planner = ModelConfiguration("tempo-planner", schema: Schema(plannerModels),
                                             cloudKitDatabase: .private(cloudContainerID))
            let container = try ModelContainer(for: fullSchema, configurations: [sensitive, planner])
            container.mainContext.autosaveEnabled = true   // 수동 생성 컨테이너 — 암묵 기본값에 걸지 않는다(2026-07-23)
            cloudEnabled = true
            return container
        } catch {
            // iCloud 미로그인·컨테이너 불가 등 — 로컬 전용 폴백. **반드시 같은 named 스토어**를 쓴다.
            // ⚠ default.store로 갈라지면 실행마다 스토어가 바뀌어 "저장됐는데 재시작하면 0"이 된다
            //   (2026-07-24 split-brain 결함 수정 — 옛 `try! ModelContainer(for: fullSchema)` 제거).
            let planner = ModelConfiguration("tempo-planner", schema: Schema(plannerModels),
                                             cloudKitDatabase: .none)
            let container = try! ModelContainer(for: fullSchema, configurations: [sensitive, planner])
            container.mainContext.autosaveEnabled = true
            cloudEnabled = false
            return container
        }
    }

    /// default.store에 남은 데이터를 named 2층 스토어로 회수. **매 실행 재실행 가능**(dedup=day·UUID라
    /// 멱등 — 다 옮겨지면 added=0 no-op). 이전 split-brain 실행이 default.store에 남긴 기록(예: HealthKit
    /// 가져오기 93건)까지 회수한다(2026-07-24). 플래그 제거 — 한 번 놓치면 영영 갇히던 문제 해소.
    @discardableResult
    static func migrateLegacyStoreIfNeeded(into container: ModelContainer) -> Int {
        let legacyURL = URL.applicationSupportDirectory.appending(path: "default.store")
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return 0 }
        do {
            let fullSchema = Schema(sensitiveModels + plannerModels)
            let legacyConfig = ModelConfiguration(schema: fullSchema, url: legacyURL,
                                                  cloudKitDatabase: .none)
            let legacy = try ModelContainer(for: fullSchema, configurations: [legacyConfig])
            let src = ModelContext(legacy)
            let legacyArrays = StoreArrays(
                periodDays: try src.fetch(FetchDescriptor<PeriodDay>()),
                schedules: try src.fetch(FetchDescriptor<ScheduleItem>()),
                inputs: try src.fetch(FetchDescriptor<InputItem>()),
                outputs: try src.fetch(FetchDescriptor<OutputItem>()),
                completions: try src.fetch(FetchDescriptor<ItemCompletion>()),
                checkIns: try src.fetch(FetchDescriptor<DailyCheckIn>()))
            let envelope = ExportImport.buildEnvelope(from: legacyArrays)

            let dst = container.mainContext
            let dstArrays = StoreArrays(
                periodDays: try dst.fetch(FetchDescriptor<PeriodDay>()),
                schedules: try dst.fetch(FetchDescriptor<ScheduleItem>()),
                inputs: try dst.fetch(FetchDescriptor<InputItem>()),
                outputs: try dst.fetch(FetchDescriptor<OutputItem>()),
                completions: try dst.fetch(FetchDescriptor<ItemCompletion>()),
                checkIns: try dst.fetch(FetchDescriptor<DailyCheckIn>()))
            let added = ExportImport.merge(envelope, into: dst, existing: dstArrays)
            if added > 0 { try dst.save() }
            return added
        } catch {
            return 0   // 이관 실패 — 다음 실행 재시도. 새 스토어는 비어 있어도 동작엔 지장 없음.
        }
    }
}
