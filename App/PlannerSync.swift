// 템포루틴 — 기기 간 동기화 v2 (2026-08-10 사용자 결정, MASTER §5.2)
//
// 설계 원칙 (7/24 롤백 사고의 교훈):
// - **스토어는 건드리지 않는다.** 단일 default.store 그대로 — SwiftData 멀티컨피그(2층 스토어)는
//   실기기 영속화 결함으로 롤백됐고 그 방식은 재도전 금지(repo CLAUDE.md). 여기는 스토어 밖에서
//   CKSyncEngine이 레코드만 미러하는 별도 층이다. 동기화가 죽어도 로컬 데이터는 무사하다.
// - **동기 범위 = 일정·Input·Output(서브태스크 포함)·완료 기록·체크인.** 생리 기록(PeriodDay)은
//   절대 미동기(§5.2 — 우리 컨테이너에 건강 데이터 저장 금지, 기기 간 경로는 Apple 건강 앱 E2E).
// - **페이로드 = 내보내기 DTO JSON 재사용**(§5.5.1 직렬화 검증본). 레코드 1개 = 아이템 1개,
//   충돌 = last-writer-wins(서버 레코드 위에 최신 로컬 페이로드 재저장).
// - **변경 감지 = 스냅샷 diff.** 쓰기 경로 수십 곳에 훅을 심는 대신, 동기화 시점에 전 아이템을
//   DTO로 인코딩(sortedKeys — 결정론 바이트)해 마지막 동기 상태와 비교한다. 수백 건 수준이라 싸다.
// - 진단 표면 필수(설정 동기화 섹션) — Windows 개발이라 로그·리포트가 유일한 눈이다.

import CloudKit
import Foundation
import SwiftData
import TempoCore

@MainActor
final class PlannerSync: NSObject {
    static let shared = PlannerSync()

    static let enabledKey = "plannerSyncOn"
    private static let containerID = "iCloud.app.temporoutine.TempoRoutine"
    private static let zoneName = "TempoSync"
    private static let recordType = "TRItem"
    private static let lastReportKey = "plannerSyncLastReport"
    /// 씨앗 소비 원장(2026-08-11, §3.8.1) — 아이템이 아니라 단일 원장이라 고정 이름 1건.
    /// **기존 TRItem 타입을 그대로 쓴다** — 새 레코드 타입은 CloudKit 콘솔 프로덕션 스키마 배포가
    /// 선행 조건이라(08-11 "오류 12" 실측) 코드만으로 못 켠다.
    private static let ledgerRecordName = "seedledger"

    /// 사용자 토글(기본 켬) — 끄면 엔진을 내리되 로컬 데이터·동기 상태 파일은 보존
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) == nil
            || UserDefaults.standard.bool(forKey: enabledKey)
    }

    private(set) var accountAvailable = false
    private(set) var running = false
    var lastReport: String {
        get { UserDefaults.standard.string(forKey: Self.lastReportKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastReportKey) }
    }

    private var container: ModelContainer?
    private var engine: CKSyncEngine?
    private var zone: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }
    /// 서버 레코드 캐시(systemFields) — 재실행 후엔 비어 있어도 된다(첫 저장이 serverRecordChanged로
    /// 한 번 튕긴 뒤 서버본 위에 재저장되며 자연 복구).
    private var recordCache: [CKRecord.ID: CKRecord] = [:]
    /// 마지막으로 서버와 합의된 페이로드(recordName → JSON) — diff 기준선 + 에코 방지
    private var synced: [String: Data] = [:]

    // ── 상태 파일 (Application Support/PlannerSync/) ──

    private var stateDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("PlannerSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private var engineStateURL: URL { stateDir.appendingPathComponent("engineState.json") }
    private var syncedURL: URL { stateDir.appendingPathComponent("synced.json") }

    private func loadPersisted() {
        if let data = try? Data(contentsOf: syncedURL),
           let decoded = try? JSONDecoder().decode([String: Data].self, from: data) {
            synced = decoded
        }
    }

    private func persistSynced() {
        if let data = try? JSONEncoder().encode(synced) {
            try? data.write(to: syncedURL, options: .atomic)
        }
    }

    // ── 수명 ──

    func configure(container: ModelContainer) {
        self.container = container
        loadPersisted()
        guard Self.isEnabled else { return }
        Task { await start() }
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on {
            Task { await start(); await syncNow() }
        } else {
            engine = nil
            running = false
            lastReport = "동기화 꺼짐"
        }
    }

    private func start() async {
        guard engine == nil, container != nil else { return }
        let ck = CKContainer(identifier: Self.containerID)
        let status = (try? await ck.accountStatus()) ?? .couldNotDetermine
        accountAvailable = status == .available
        guard accountAvailable else {
            lastReport = "iCloud 계정 없음 — 로그인하면 이어져요"
            return
        }
        var stateSerialization: CKSyncEngine.State.Serialization?
        if let data = try? Data(contentsOf: engineStateURL) {
            stateSerialization = try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        }
        let config = CKSyncEngine.Configuration(database: ck.privateCloudDatabase,
                                                stateSerialization: stateSerialization,
                                                delegate: self)
        let engine = CKSyncEngine(config)
        self.engine = engine
        running = true
        // 존 보장 — 최초 1회(이미 있으면 서버가 무시)
        if !UserDefaults.standard.bool(forKey: "plannerSyncZoneSaved") {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zone))])
        }
    }

    /// 앱 활성·백그라운드 진입에서 부른다 — diff 큐잉 + 즉시 왕복
    func kick() {
        guard Self.isEnabled else { return }
        Task { await syncNow() }
    }

    func syncNow() async {
        // 수동 「지금 동기화」 자가 회복(2026-08-11 실기기 — 패드가 "동기화 꺼짐" 리포트에 갇힘):
        // 토글이 꺼져 있으면 켜고 시작한다 — 버튼을 눌렀다는 것 자체가 켜겠다는 의사다.
        if !Self.isEnabled {
            UserDefaults.standard.set(true, forKey: Self.enabledKey)
        }
        if engine == nil { await start() }
        guard let engine else { return }
        queueLocalDiff()
        // 오류를 삼키지 않는다(2026-08-11 — 패드가 원인 안 보이는 채 멈춰 있던 교훈).
        // 리포트가 이 왕복에서 안 바뀌었으면 "변경 없음"이라도 찍는다 — 침묵이 제일 나쁘다.
        let before = lastReport
        do {
            try await engine.sendChanges()
        } catch {
            stampReport(suffix: "보내기 오류 — \(shortError(error))")
            return
        }
        do {
            try await engine.fetchChanges()
        } catch {
            stampReport(suffix: "가져오기 오류 — \(shortError(error))")
            return
        }
        if lastReport == before {
            stampReport(suffix: "왕복 완료 — 새 변경 없음")
        }
    }

    private func shortError(_ error: Error) -> String {
        if let ck = error as? CKError {
            return "\(ck.code.rawValue)(\(Self.codeName(ck.code)))"
        }
        return String(describing: error).prefix(60).description
    }

    // ── 스냅샷·diff ──

    /// 결정론 인코딩 — 같은 내용이면 같은 바이트(sortedKeys). diff의 성립 조건.
    private static let payloadEncoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return enc
    }()

    private func snapshot() -> [String: Data] {
        guard let context = container?.mainContext else { return [:] }
        var map: [String: Data] = [:]
        func put<T: Encodable>(_ kind: String, _ id: UUID, _ dto: T) {
            if let data = try? Self.payloadEncoder.encode(dto) {
                map["\(kind)_\(id.uuidString)"] = data
            }
        }
        let schedules = (try? context.fetch(FetchDescriptor<ScheduleItem>())) ?? []
        for item in schedules {
            put("schedule", item.id,
                ScheduleItemDTO(id: item.id, title: item.title,
                                date: item.isAllDay ? ExportCodec.dayString(item.date) : ExportCodec.instantString(item.date),
                                isAllDay: item.isAllDay, repeatRule: item.repeatRule, createdAt: item.createdAt,
                                endDate: item.endDate.map { ExportCodec.instantString($0) },
                                reminderMinutes: item.reminderMinutes >= 0 ? item.reminderMinutes : nil))
        }
        let inputs = (try? context.fetch(FetchDescriptor<InputItem>())) ?? []
        for item in inputs {
            put("input", item.id,
                InputItemDTO(id: item.id, title: item.title, category: item.category,
                             schedule: item.schedule, createdAt: item.createdAt,
                             backfilled: item.backfilled ? true : nil,
                             timeMinutes: item.timeMinutes,
                             // 진행 방식 정의(2026-08-12) — 값은 아래 inputprogress 레코드
                             progressKind: item.progressKind,
                             targetSessions: item.targetSessions > 0 ? item.targetSessions : nil,
                             targetSeconds: item.targetSeconds,
                             subtasks: (item.subtasks?.isEmpty ?? true) ? nil
                                 : item.subtasks?.sorted { $0.order < $1.order }
                                     .map { InputSubtaskDTO(id: $0.id, title: $0.title, order: $0.order) }))
        }
        // Input 그날치 진행(2026-08-12) — 레코드 1개 = 아이템 × 날짜 1개.
        // 실행 중인 타이머는 접힌 경과만 싣는다(실행 상태는 이 기기 것 — Output과 같은 계약).
        let inputProgresses = (try? context.fetch(FetchDescriptor<InputProgress>())) ?? []
        for record in inputProgresses {
            put("inputprogress", record.id,
                InputProgressDTO(id: record.id, itemID: record.itemID,
                                 occurredOn: record.occurredOn,
                                 loggedSessions: record.loggedSessions,
                                 percent: record.percent,
                                 elapsedSeconds: record.elapsedAccumSeconds,
                                 doneSubtaskIDs: record.doneSubtaskIDs.sorted { $0.uuidString < $1.uuidString }))
        }
        let outputs = (try? context.fetch(FetchDescriptor<OutputItem>())) ?? []
        for item in outputs {
            put("output", item.id,
                OutputItemDTO(id: item.id, title: item.title, schedule: item.schedule,
                              progressKind: item.progressKind,
                              subtasks: (item.subtasks ?? []).sorted { $0.order < $1.order }.map {
                                  OutputSubtaskDTO(id: $0.id, title: $0.title, isDone: $0.isDone, order: $0.order)
                              },
                              targetSessions: item.targetSessions, loggedSessions: item.loggedSessions,
                              percent: item.percent, createdAt: item.createdAt,
                              targetDate: item.targetDate,
                              targetSeconds: item.targetSeconds,
                              elapsedSeconds: item.elapsedAccumSeconds > 0 ? item.elapsedAccumSeconds : nil,
                              timeMinutes: item.timeMinutes))
        }
        let completions = (try? context.fetch(FetchDescriptor<ItemCompletion>())) ?? []
        for item in completions {
            put("completion", item.id,
                ItemCompletionDTO(id: item.id, itemID: item.itemID,
                                  occurredOn: ExportCodec.dayString(item.occurredOn),
                                  completedAt: item.completedAt))
        }
        let checkIns = (try? context.fetch(FetchDescriptor<DailyCheckIn>())) ?? []
        for item in checkIns {
            put("checkin", item.id,
                DailyCheckInDTO(id: item.id, day: ExportCodec.dayString(item.day), energy: item.energy,
                                mood: item.mood, sleep: item.sleep, pain: item.pain, appetite: item.appetite,
                                note: item.note, createdAt: item.createdAt,
                                irritability: item.irritability,
                                isBackfilled: item.isBackfilled ? true : nil,
                                completedAt: item.completedAt))
        }
        // 씨앗 소비 원장 — 획득(체크인 completedAt)만 이어지고 소비는 기기마다 따로 놀던 결함(P-6)
        if let ledger = try? Self.payloadEncoder.encode(Seeds.ledger) {
            map[Self.ledgerRecordName] = ledger
        }
        return map
    }

    private var pendingPayloads: [String: Data] = [:]

    private func queueLocalDiff() {
        guard let engine else { return }
        let current = snapshot()
        var saves: [CKSyncEngine.PendingRecordZoneChange] = []
        for (name, payload) in current where synced[name] != payload {
            pendingPayloads[name] = payload
            saves.append(.saveRecord(CKRecord.ID(recordName: name, zoneID: zone)))
        }
        for name in synced.keys where current[name] == nil {
            saves.append(.deleteRecord(CKRecord.ID(recordName: name, zoneID: zone)))
        }
        if !saves.isEmpty {
            engine.state.add(pendingRecordZoneChanges: saves)
        }
    }

    private func makeRecord(for recordID: CKRecord.ID) -> CKRecord? {
        let name = recordID.recordName
        let payload = pendingPayloads[name] ?? snapshot()[name]
        guard let payload else { return nil }   // 큐잉 후 삭제된 아이템 — 저장 건너뜀
        let record = recordCache[recordID] ?? CKRecord(recordType: Self.recordType, recordID: recordID)
        record["payload"] = payload as NSData
        return record
    }

    // ── 서버 → 로컬 적용 (upsert / 삭제) ──

    private func apply(records: [CKRecord], deletions: [CKRecord.ID]) {
        guard let context = container?.mainContext else { return }
        var pulled = 0
        var ledgerMerged = false
        for record in records {
            guard let payload = record["payload"] as? Data else { continue }
            let name = record.recordID.recordName
            recordCache[record.recordID] = record
            if synced[name] == payload { continue }   // 에코(내가 올린 것)
            // 씨앗 원장만 덮어쓰기가 아니라 병합이다 — 전체 last-writer-wins면 이쪽 구매와
            // 저쪽 공지 수령이 겹칠 때 한쪽이 통째로 날아간다(합집합이라 왕복이 수렴한다).
            if name == Self.ledgerRecordName {
                if let remote = try? JSONDecoder().decode(SeedLedgerDTO.self, from: payload),
                   Seeds.merge(remote) {
                    ledgerMerged = true
                }
                synced[name] = payload
                pulled += 1
                continue
            }
            if upsert(name: name, payload: payload, context: context) {
                pulled += 1
                synced[name] = payload
            }
        }
        // 병합 결과(원격 ≠ 로컬)를 되올린다 — 다음 왕복까지 미루면 저쪽은 계속 옛 원장을 본다
        if ledgerMerged, let engine {
            pendingPayloads[Self.ledgerRecordName] = try? Self.payloadEncoder.encode(Seeds.ledger)
            engine.state.add(pendingRecordZoneChanges: [
                .saveRecord(CKRecord.ID(recordName: Self.ledgerRecordName, zoneID: zone))
            ])
        }
        var removed = 0
        for recordID in deletions {
            let name = recordID.recordName
            recordCache[recordID] = nil
            if deleteLocal(name: name, context: context) { removed += 1 }
            synced[name] = nil
        }
        if pulled > 0 || removed > 0 {
            try? context.save()
            persistSynced()
            stampReport(suffix: "내림 \(pulled)·삭제 \(removed)")
        }
    }

    private func upsert(name: String, payload: Data, context: ModelContext) -> Bool {
        let dec = JSONDecoder()
        if name.hasPrefix("schedule_"), let dto = try? dec.decode(ScheduleItemDTO.self, from: payload) {
            let date = dto.isAllDay ? ExportCodec.day(from: dto.date) : ExportCodec.instant(from: dto.date)
            guard let date else { return false }
            let existing = fetchOne(ScheduleItem.self, id: dto.id, context: context)
            let item = existing ?? ScheduleItem(title: dto.title, date: date, isAllDay: dto.isAllDay,
                                                repeatRule: dto.repeatRule,
                                                endDate: dto.endDate.flatMap { ExportCodec.instant(from: $0) },
                                                reminderMinutes: dto.reminderMinutes ?? -1)
            item.id = dto.id
            item.title = dto.title
            item.date = date
            item.isAllDay = dto.isAllDay
            item.repeatRule = dto.repeatRule
            item.endDate = dto.endDate.flatMap { ExportCodec.instant(from: $0) }
            item.reminderMinutes = dto.reminderMinutes ?? -1
            item.createdAt = dto.createdAt
            if existing == nil { context.insert(item) }
            ScheduleReminder.schedule(id: item.id, title: item.title, date: item.date,
                                      isAllDay: item.isAllDay, repeatRule: item.repeatRule,
                                      reminderMinutes: item.reminderMinutes)
            return true
        }
        if name.hasPrefix("input_"), let dto = try? dec.decode(InputItemDTO.self, from: payload) {
            let existing = fetchOne(InputItem.self, id: dto.id, context: context)
            let item = existing ?? InputItem(title: dto.title, category: dto.category,
                                             schedule: dto.schedule, backfilled: dto.backfilled ?? false)
            item.id = dto.id
            item.title = dto.title
            item.category = dto.category
            item.schedule = dto.schedule
            item.createdAt = dto.createdAt
            item.backfilled = dto.backfilled ?? false
            item.timeMinutes = dto.timeMinutes
            // 진행 방식 정의(2026-08-12) — 구 기기가 올린 레코드는 전부 nil이라 단순 체크로 내려온다
            item.progressKind = dto.progressKind
            item.targetSessions = dto.targetSessions ?? 0
            item.targetSeconds = dto.targetSeconds
            reconcileInputSubtasks(item: item, dtos: dto.subtasks ?? [], context: context)
            if existing == nil { context.insert(item) }
            return true
        }
        // prefix가 "input_"이 아니라 "inputprogress_"라 위 분기와 겹치지 않는다
        if name.hasPrefix("inputprogress_"), let dto = try? dec.decode(InputProgressDTO.self, from: payload) {
            let existing = fetchOne(InputProgress.self, id: dto.id, context: context)
            let record = existing ?? InputProgress(itemID: dto.itemID, occurredOn: dto.occurredOn)
            record.id = dto.id
            record.itemID = dto.itemID
            record.occurredOn = Calendar.current.startOfDay(for: dto.occurredOn)
            record.loggedSessions = dto.loggedSessions
            record.percent = dto.percent
            // 실행 중(timerStartedAt)은 이 기기 상태 — 누적만 맞춘다(Output 타이머와 같은 규칙)
            if !record.isTimerRunning { record.elapsedAccumSeconds = dto.elapsedSeconds }
            record.doneSubtaskIDs = Set(dto.doneSubtaskIDs)
            if existing == nil { context.insert(record) }
            return true
        }
        if name.hasPrefix("output_"), let dto = try? dec.decode(OutputItemDTO.self, from: payload) {
            let existing = fetchOne(OutputItem.self, id: dto.id, context: context)
            let item = existing ?? OutputItem(title: dto.title, schedule: dto.schedule,
                                              progressKind: dto.progressKind)
            item.id = dto.id
            item.title = dto.title
            item.schedule = dto.schedule
            item.progressKind = dto.progressKind
            item.targetSessions = dto.targetSessions
            item.loggedSessions = dto.loggedSessions
            item.percent = dto.percent
            item.createdAt = dto.createdAt
            item.targetDate = dto.targetDate
            item.targetSeconds = dto.targetSeconds
            // 실행 중(timerStartedAt)은 이 기기 상태 — 누적만 맞춘다
            if !item.isTimerRunning { item.elapsedAccumSeconds = dto.elapsedSeconds ?? 0 }
            item.timeMinutes = dto.timeMinutes
            reconcileSubtasks(item: item, dtos: dto.subtasks, context: context)
            if existing == nil { context.insert(item) }
            return true
        }
        if name.hasPrefix("completion_"), let dto = try? dec.decode(ItemCompletionDTO.self, from: payload) {
            guard fetchOne(ItemCompletion.self, id: dto.id, context: context) == nil,
                  let day = ExportCodec.day(from: dto.occurredOn) else { return false }
            let completion = ItemCompletion(itemID: dto.itemID, occurredOn: day)
            completion.id = dto.id
            completion.completedAt = dto.completedAt
            context.insert(completion)
            return true
        }
        if name.hasPrefix("checkin_"), let dto = try? dec.decode(DailyCheckInDTO.self, from: payload) {
            guard let day = ExportCodec.day(from: dto.day) else { return false }
            // 체크인 dedup 키 = 날짜(§5.5) — 다른 기기가 같은 날 다른 UUID로 만들었을 수 있다
            let byID = fetchOne(DailyCheckIn.self, id: dto.id, context: context)
            let byDay = byID ?? fetchCheckIn(day: day, context: context)
            let item = byDay ?? DailyCheckIn(day: day, energy: dto.energy, mood: dto.mood,
                                             isBackfilled: dto.isBackfilled ?? false)
            item.id = dto.id
            item.day = day
            item.energy = dto.energy
            item.mood = dto.mood
            item.sleep = dto.sleep
            item.pain = dto.pain
            item.appetite = dto.appetite
            item.irritability = dto.irritability
            item.note = dto.note
            item.createdAt = dto.createdAt
            item.isBackfilled = dto.isBackfilled ?? false
            item.completedAt = dto.completedAt
            if byDay == nil { context.insert(item) }
            return true
        }
        return false
    }

    private func deleteLocal(name: String, context: ModelContext) -> Bool {
        guard let uuid = UUID(uuidString: String(name.drop(while: { $0 != "_" }).dropFirst())) else { return false }
        if name.hasPrefix("schedule_"), let item = fetchOne(ScheduleItem.self, id: uuid, context: context) {
            ScheduleReminder.cancel(id: item.id)
            context.delete(item)
            return true
        }
        if name.hasPrefix("input_"), let item = fetchOne(InputItem.self, id: uuid, context: context) {
            // 진행 레코드는 itemID 참조라 cascade가 닿지 않는다(2026-08-12) — 손으로 걷는다.
            // 체크리스트 항목(InputSubtask)은 관계 cascade라 아이템과 같이 지워진다.
            let progresses = (try? context.fetch(FetchDescriptor<InputProgress>())) ?? []
            for record in progresses where record.itemID == item.id { context.delete(record) }
            context.delete(item)
            return true
        }
        if name.hasPrefix("inputprogress_"), let record = fetchOne(InputProgress.self, id: uuid, context: context) {
            context.delete(record)
            return true
        }
        if name.hasPrefix("output_"), let item = fetchOne(OutputItem.self, id: uuid, context: context) {
            context.delete(item)   // 서브태스크는 cascade
            return true
        }
        if name.hasPrefix("completion_"), let item = fetchOne(ItemCompletion.self, id: uuid, context: context) {
            context.delete(item)
            return true
        }
        if name.hasPrefix("checkin_"), let item = fetchOne(DailyCheckIn.self, id: uuid, context: context) {
            context.delete(item)
            return true
        }
        return false
    }

    /// UUID로 1건 조회 — #Predicate가 제네릭 KeyPath를 못 받아 전량 fetch 후 필터.
    /// 아이템 수백 건 수준이라 수용(동기화는 프레임 경로가 아니다).
    private func fetchOne<T: PersistentModel & SyncIdentifiable>(_ type: T.Type, id: UUID,
                                                                 context: ModelContext) -> T? {
        ((try? context.fetch(FetchDescriptor<T>())) ?? []).first { $0.syncID == id }
    }

    private func fetchCheckIn(day: Date, context: ModelContext) -> DailyCheckIn? {
        let all = (try? context.fetch(FetchDescriptor<DailyCheckIn>())) ?? []
        return all.first { $0.day == day }
    }

    /// Input 체크리스트 항목 조정 — isDone이 없다는 것 말고는 Output판과 같다(2026-08-12).
    /// 완료 여부는 그날의 InputProgress가 id로 참조하므로 여기서 id를 보존해야 한다.
    private func reconcileInputSubtasks(item: InputItem, dtos: [InputSubtaskDTO], context: ModelContext) {
        var existing = Dictionary(uniqueKeysWithValues: (item.subtasks ?? []).map { ($0.id, $0) })
        var next: [InputSubtask] = []
        for dto in dtos {
            if let sub = existing.removeValue(forKey: dto.id) {
                sub.title = dto.title
                sub.order = dto.order
                next.append(sub)
            } else {
                let sub = InputSubtask(title: dto.title, order: dto.order)
                sub.id = dto.id
                next.append(sub)
            }
        }
        for (_, orphan) in existing { context.delete(orphan) }
        item.subtasks = next
    }

    private func reconcileSubtasks(item: OutputItem, dtos: [OutputSubtaskDTO], context: ModelContext) {
        var existing = Dictionary(uniqueKeysWithValues: (item.subtasks ?? []).map { ($0.id, $0) })
        var next: [OutputSubtask] = []
        for dto in dtos {
            if let sub = existing.removeValue(forKey: dto.id) {
                sub.title = dto.title
                sub.isDone = dto.isDone
                sub.order = dto.order
                next.append(sub)
            } else {
                let sub = OutputSubtask(title: dto.title, order: dto.order)
                sub.id = dto.id
                sub.isDone = dto.isDone
                next.append(sub)
            }
        }
        for (_, orphan) in existing { context.delete(orphan) }
        item.subtasks = next
    }

    private func stampReport(suffix: String) {
        let time = Date.now.formatted(date: .omitted, time: .shortened)
        lastReport = "\(time) · \(suffix)"
    }
}

/// UUID 동일성 조회 공용 창구 — #Predicate가 제네릭 KeyPath를 못 받아 프로토콜로 우회
protocol SyncIdentifiable {
    var syncID: UUID { get }
}

extension ScheduleItem: SyncIdentifiable { var syncID: UUID { id } }
extension InputItem: SyncIdentifiable { var syncID: UUID { id } }
extension OutputItem: SyncIdentifiable { var syncID: UUID { id } }
extension ItemCompletion: SyncIdentifiable { var syncID: UUID { id } }
extension DailyCheckIn: SyncIdentifiable { var syncID: UUID { id } }

// ── CKSyncEngine 델리게이트 ──

extension PlannerSync: CKSyncEngineDelegate {

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            if let data = try? JSONEncoder().encode(update.stateSerialization) {
                try? data.write(to: engineStateURL, options: .atomic)
            }
        case .accountChange:
            engine = nil
            running = false
            recordCache = [:]
            lastReport = "iCloud 계정 변경 — 다음 실행에서 다시 연결해요"
        case .fetchedRecordZoneChanges(let changes):
            apply(records: changes.modifications.map(\.record),
                  deletions: changes.deletions.map(\.recordID))
        case .fetchedDatabaseChanges(let changes):
            // 사용자가 iCloud에서 존을 지웠으면 기준선을 비워 다음 diff가 전체 재업로드하게 한다
            for deletion in changes.deletions where deletion.zoneID.zoneName == Self.zoneName {
                synced = [:]
                persistSynced()
                UserDefaults.standard.set(false, forKey: "plannerSyncZoneSaved")
            }
        case .sentDatabaseChanges(let sent):
            // ⚠ 성공분이 있을 때만 플래그 — 실패까지 true로 접으면 존 저장이 영영 재시도 안 됨(08-11 정정)
            if !sent.savedZones.isEmpty {
                UserDefaults.standard.set(true, forKey: "plannerSyncZoneSaved")
            }
            for failure in sent.failedZoneSaves {
                stampReport(suffix: "존 오류 \((failure.error as? CKError)?.code.rawValue ?? -1)")
            }
        case .sentRecordZoneChanges(let sent):
            var pushed = 0
            for record in sent.savedRecords {
                let name = record.recordID.recordName
                recordCache[record.recordID] = record
                if let payload = record["payload"] as? Data { synced[name] = payload }
                pendingPayloads[name] = nil
                pushed += 1
            }
            for recordID in sent.deletedRecordIDs {
                synced[recordID.recordName] = nil
                recordCache[recordID] = nil
            }
            for failure in sent.failedRecordSaves {
                handleSaveFailure(failure, syncEngine: syncEngine)
            }
            if pushed > 0 || !sent.deletedRecordIDs.isEmpty {
                persistSynced()
                stampReport(suffix: "올림 \(pushed)")
            }
        default:
            break
        }
    }

    private func handleSaveFailure(_ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave,
                                   syncEngine: CKSyncEngine) {
        let recordID = failure.record.recordID
        guard let ckError = failure.error as? CKError else { return }
        switch ckError.code {
        case .serverRecordChanged:
            // 충돌 = last-writer-wins: 서버본 위에 최신 로컬 페이로드를 다시 얹는다
            if let server = ckError.serverRecord {
                recordCache[recordID] = server
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            }
        case .zoneNotFound:
            synced = [:]
            persistSynced()
            UserDefaults.standard.set(false, forKey: "plannerSyncZoneSaved")
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zone))])
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        case .unknownItem:
            // 서버에서 사라진 레코드 — 캐시를 비우고 새 레코드로 재생성
            recordCache[recordID] = nil
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        default:
            // 진단 상세(2026-08-11 — "오류 12"만으론 원인 특정 불가했던 교훈): 코드 이름+설명까지
            let detail = ckError.localizedDescription.prefix(80)
            stampReport(suffix: "오류 \(ckError.code.rawValue)(\(Self.codeName(ckError.code))) \(detail)")
        }
    }

    private static func codeName(_ code: CKError.Code) -> String {
        switch code {
        case .invalidArguments: "invalidArguments — 프로덕션 스키마 미배포 의심"
        case .notAuthenticated: "notAuthenticated"
        case .permissionFailure: "permissionFailure"
        case .quotaExceeded: "quotaExceeded"
        case .networkUnavailable, .networkFailure: "network"
        case .serverRejectedRequest: "serverRejected"
        default: String(describing: code)
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            await self.makeRecord(for: recordID)
        }
    }
}
