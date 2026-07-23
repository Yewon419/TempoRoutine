// 템포루틴 — HealthKit read-write 양방향 미러 (Phase 0 ⑦, MASTER §5.7 / §5.5.4 LOCKED)
// 로컬 PeriodDay가 단일 출처 — Health는 미러. 예측 입력·알고리즘은 불변.
// 상수는 Apple 레퍼런스 검증(2026-07-20): menstrualFlow + HKMetadataKeyMenstrualCycleStart(필수,
// 에피소드 첫날만 true) + 값은 iOS 18+ HKCategoryValueVaginalBleeding(.unspecified).
// 삭제 전파는 HKAnchoredObjectQuery deletedObjects만 인정 — 빈 read는 절대 삭제 아님.
// read 거부는 판별 불가(write 상태만 보임) → 빈 read를 로컬 출처가 흡수.

import Foundation
import HealthKit
import SwiftData
import TempoCore

@MainActor
@Observable
final class HealthMirror {
    static let shared = HealthMirror()

    private let store = HKHealthStore()
    private let flowType = HKCategoryType(.menstrualFlow)

    private static let linkedKey = "healthKitLinked"
    private static let anchorKey = "healthKitAnchor"
    private static let tombstonesKey = "healthKitImportTombstones"   // 로컬서 지운 imported day 재부활 방지

    /// 유저가 연동을 켰는가(앱 레벨 스위치 — read 권한 상태는 알 수 없으므로 이 플래그가 미러 동작 기준)
    var linked: Bool {
        didSet { UserDefaults.standard.set(linked, forKey: Self.linkedKey) }
    }

    private init() {
        linked = UserDefaults.standard.bool(forKey: Self.linkedKey)
    }

    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    /// write 권한만 조회 가능(§5.7) — read 거부는 Apple이 숨김
    var writeAuthorized: Bool {
        store.authorizationStatus(for: flowType) == .sharingAuthorized
    }

    func requestAccess() async -> Bool {
        guard available else { return false }
        do {
            try await store.requestAuthorization(toShare: [flowType], read: [flowType])
            // 재연동 = 처음부터 다시 비춘다(2026-07-23 실기기 결함 — 앵커가 남아 있으면 기존
            // Health 데이터가 "앵커 이후 없음"으로 떨어져 불러올 게 없다고 나온다. dedup=day·UUID라 안전)
            UserDefaults.standard.removeObject(forKey: Self.anchorKey)
            linked = true
            return true
        } catch {
            return false
        }
    }

    /// 전체 삭제(§8.2.6 wipeAll) 동반 리셋 — 다음 연동이 깨끗한 초기 가져오기가 되도록
    /// 앵커와 툼스톤을 지운다(툼스톤은 삭제된 로컬 기록에 대한 것이라 기록이 사라지면 의미도 소멸).
    static func resetImportState() {
        UserDefaults.standard.removeObject(forKey: anchorKey)
        UserDefaults.standard.removeObject(forKey: tombstonesKey)
    }

    // ── write: PeriodDay 1개 = menstrualFlow 샘플 1개 (§5.5.4) ──
    func writeSample(day: Date, isCycleStart: Bool) async -> UUID? {
        guard linked, available, writeAuthorized else { return nil }
        let sample = HKCategorySample(
            type: flowType,
            value: HKCategoryValueVaginalBleeding.unspecified.rawValue,
            start: day, end: day,
            metadata: [HKMetadataKeyMenstrualCycleStart: isCycleStart]   // menstrualFlow 필수 메타키
        )
        do {
            try await store.save(sample)
            return sample.uuid
        } catch {
            return nil
        }
    }

    func deleteSamples(uuids: [UUID]) async {
        guard linked, available, writeAuthorized, !uuids.isEmpty else { return }
        let predicate = HKQuery.predicateForObjects(with: Set(uuids))
        let samples: [HKSample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: flowType, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
        guard !samples.isEmpty else { return }
        try? await store.delete(samples)   // .appAuthored만 우리가 지울 수 있음(HK가 강제)
    }

    // ── read 병합 + 삭제 전파 ── 반환값 = 새로 가져온 건수(진단·사용자 피드백용, 2026-07-22)
    @discardableResult
    func sync(context: ModelContext, periodDays: [PeriodDay]) async -> Int {
        guard linked else { return 0 }
        guard available else { return 0 }
        let anchor = loadAnchor()
        let result: (samples: [HKSample], deleted: [HKDeletedObject], anchor: HKQueryAnchor?) =
            await withCheckedContinuation { continuation in
                let query = HKAnchoredObjectQuery(type: flowType, predicate: nil, anchor: anchor,
                                                  limit: HKObjectQueryNoLimit) { _, samples, deleted, newAnchor, _ in
                    continuation.resume(returning: (samples ?? [], deleted ?? [], newAnchor))
                }
                store.execute(query)
            }

        // 삭제 전파: deletedObjects만 인정. UUID 매칭 로그는 로컬도 삭제 —
        // .appAuthored = 유저가 Health에서 명시 삭제(재write 금지 = 레코드 소멸로 자동 충족) / .imported = 원 출처 소멸
        let deletedUUIDs = Set(result.deleted.map(\.uuid))
        var remaining: [PeriodDay] = []
        for record in periodDays {
            if let uuid = record.healthKitUUID, deletedUUIDs.contains(uuid) {
                context.delete(record)
            } else {
                remaining.append(record)
            }
        }

        // read 병합: dedup = day. 우리가 쓴 샘플의 재유입은 UUID로 스킵.
        let cal = Calendar.current
        var existingDays = Set(remaining.map(\.day))
        let knownUUIDs = Set(remaining.compactMap(\.healthKitUUID))
        let tombstones = Set(UserDefaults.standard.stringArray(forKey: Self.tombstonesKey) ?? [])
        var imported = 0
        for sample in result.samples {
            guard let category = sample as? HKCategorySample else { continue }
            let day = cal.startOfDay(for: category.startDate)
            if knownUUIDs.contains(category.uuid) { continue }
            if deletedUUIDs.contains(category.uuid) { continue }
            if existingDays.contains(day) { continue }
            if tombstones.contains(ExportCodec.dayString(day)) { continue }
            let ours = category.sourceRevision.source == HKSource.default()   // 재설치 잔재 등
            context.insert(PeriodDay(day: day, origin: ours ? .appAuthored : .healthKitImported,
                                     healthKitUUID: category.uuid))
            existingDays.insert(day)
            imported += 1
        }
        saveAnchor(result.anchor)
        return imported
    }

    // ── imported 로컬 삭제 재부활 방지 (§5.7 "로컬 편집만" 선택지의 귀결) ──
    static func addTombstone(day: Date) {
        var list = UserDefaults.standard.stringArray(forKey: tombstonesKey) ?? []
        let key = ExportCodec.dayString(day)
        if !list.contains(key) {
            list.append(key)
            UserDefaults.standard.set(list, forKey: tombstonesKey)
        }
    }

    static func clearTombstones(days: [Date]) {
        var list = UserDefaults.standard.stringArray(forKey: tombstonesKey) ?? []
        let keys = Set(days.map { ExportCodec.dayString($0) })
        list.removeAll { keys.contains($0) }
        UserDefaults.standard.set(list, forKey: tombstonesKey)
    }

    // ── anchor 영속화 ──
    private func loadAnchor() -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: Self.anchorKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor?) {
        guard let anchor,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.anchorKey)
    }
}
