// 템포루틴 — 2층 스토어 부트스트랩 (§5.2 CloudKit 2층 동기화 실장, 2026-07-23)
// 민감층(PeriodDay) = 로컬 전용(CloudKit 금지 — 기기 간 경로는 Apple Health E2E, §5.7)
// 플래너층(ScheduleItem·InputItem·OutputItem·OutputSubtask·ItemCompletion) + DailyCheckIn = CloudKit private DB.
// 무계정 유지: Apple ID 기반, iCloud 불가 시 로컬 전용 폴백(같은 스토어 이름 → 복구 시 재부착).
// 구 단일 스토어(default.store) → 2층 분리는 1회성 마이그레이션 — §5.5.1 백업 봉투 경로 재사용(검증된 dedup 승계).

import Foundation
import SwiftData

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
        let sensitive = ModelConfiguration("tempo-sensitive", schema: Schema(sensitiveModels),
                                           cloudKitDatabase: .none)
        do {
            let planner = ModelConfiguration("tempo-planner", schema: Schema(plannerModels),
                                             cloudKitDatabase: .private(cloudContainerID))
            let container = try ModelContainer(for: fullSchema, configurations: [sensitive, planner])
            cloudEnabled = true
            return container
        } catch {
            // iCloud 미로그인·컨테이너 불가 등 — 로컬 전용 폴백. 스토어 이름이 같아 복구 시 그대로 이어짐.
            let planner = ModelConfiguration("tempo-planner", schema: Schema(plannerModels),
                                             cloudKitDatabase: .none)
            if let local = try? ModelContainer(for: fullSchema, configurations: [sensitive, planner]) {
                return local
            }
            // 최후 폴백 — 단일 기본 스토어(여기 도달하면 스토어 계층 자체가 손상된 상황)
            return try! ModelContainer(for: fullSchema)
        }
    }

    /// 구 단일 스토어 → 2층 스토어 1회성 이관. 봉투(§5.5.1) 경유라 dedup·UUID 보존·알림 재스케줄 승계.
    /// 실패 시 플래그를 남기지 않아 다음 실행에 재시도. 구 파일은 지우지 않는다(안전망 — 수동 정리).
    @MainActor
    static func migrateLegacyStoreIfNeeded(into container: ModelContainer) {
        let flagKey = "storeSplitMigrated.v1"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: flagKey) else { return }

        let legacyURL = URL.applicationSupportDirectory.appending(path: "default.store")
        guard FileManager.default.fileExists(atPath: legacyURL.path) else {
            defaults.set(true, forKey: flagKey)   // 신규 설치 — 이관할 것 없음
            return
        }

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
            ExportImport.merge(envelope, into: dst, existing: dstArrays)
            try dst.save()
            defaults.set(true, forKey: flagKey)
        } catch {
            // 이관 실패 — 플래그 미설정으로 다음 실행 재시도. 새 스토어는 비어 있어도 동작엔 지장 없음.
        }
    }
}
