// 템포루틴 — 하루 기록 저장 규칙 (2026-09-16)
//
// 같은 `DailyCheckIn`을 편집기 둘이 쓴다: 오늘 탭 `CheckInCard`, 생리 기록 시트 `CheckInEditor`.
// 종전엔 저장 조건·소급 판정·사진 수명을 각자 들고 있어 개정이 한쪽만 따라왔다.
// - 2026-08-16: 식욕 배선이 시트에만 빠져 「식욕 켠 사람은 영영 씨앗을 못 받음」
// - 2026-09-16: 시트 쪽 보존 조건이 증상(09-01)·사진(09-04) 개정을 안 따라와, 칩을 해제하면
//   증상·사진이 붙은 기록이 통째로 삭제됐다.
// 규칙은 이 파일 하나뿐이다. 편집기는 **자기가 편집하지 않는 필드도 초안에 실어 그대로 돌려준다** —
// 그래야 「내용이 남았는가」 판정이 화면에 보이는 것만이 아니라 기록 전체를 본다.

import Foundation
import SwiftData
import TempoCore

/// 한 날짜의 기록 초안 — 편집기가 들고 있는 @State를 저장 직전에 한 덩어리로 모은 값.
struct CheckInDraft {
    var energy = 0
    var mood = 0
    var sleep = 0
    var appetite = 0
    var note = ""
    var symptoms: Set<CheckInSymptom> = []
    var photoName: String?

    var hasSignals: Bool { energy > 0 && mood > 0 }
    var hasNote: Bool { !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// 저장할 내용이 남았는가 — 필수 2신호(§5.5) 또는 노트 단독(2026-07-22) 또는
    /// 증상 단독(2026-09-01 — 아픈 날은 신호를 안 매길 수 있다) 또는 사진 단독(2026-09-04).
    /// 전부 비면 기록 철회(스킵 무벌점).
    var hasContent: Bool { hasSignals || hasNote || !symptoms.isEmpty || photoName != nil }
}

enum CheckInStore {

    /// 초안을 그 날 기록에 반영한다. 돌려주는 값 = 이번에 씨앗을 받았는가(획득 연출 트리거).
    /// `all` = 사진 파일 참조 수를 세기 위한 전체 기록(@Query 배열 그대로).
    @MainActor
    @discardableResult
    static func apply(_ draft: CheckInDraft, day: Date, record: DailyCheckIn?,
                      all: [DailyCheckIn], context: ModelContext,
                      signals: TrackedSignals) -> Bool {
        if let existing = record {
            guard draft.hasContent else {
                releasePhoto(existing.photoName, excluding: existing, in: all)
                context.delete(existing)   // 전부 해제 = 기록 철회
                return false
            }
            existing.energy = draft.energy
            existing.mood = draft.mood
            existing.sleep = draft.sleep > 0 ? draft.sleep : nil
            // irritability·pain은 건드리지 않는다 — 입력 행이 사라졌을 뿐(2026-08-05 병합),
            // 과거에 기록된 값을 0 초안으로 덮어쓰면 리듬 집계 표본이 파괴된다.
            existing.appetite = draft.appetite > 0 ? draft.appetite : nil
            existing.symptomSet = draft.symptoms
            existing.note = draft.hasNote ? draft.note : nil
            existing.photoName = draft.photoName
            return Seeds.stampCompletion(existing, signals: signals)
        }
        guard draft.hasContent else { return false }
        // 소급 = 카드가 보고 있는 날 ≠ **논리적 오늘**(AppDay 새벽 4시 경계). 회상 기반이라 적합
        // 가중치가 다르다(v1.5 §3-4). 종전엔 시트만 자정 기준이라 00~04시에 같은 기록이
        // 입력 경로에 따라 소급으로 갈렸고, AxisProfile이 소급 행을 버려 집계 표본이 달라졌다.
        let created = DailyCheckIn(day: day, energy: draft.energy, mood: draft.mood,
                                   isBackfilled: !AppDay.isToday(day))
        created.sleep = draft.sleep > 0 ? draft.sleep : nil
        created.appetite = draft.appetite > 0 ? draft.appetite : nil
        created.symptomSet = draft.symptoms
        created.note = draft.hasNote ? draft.note : nil
        created.photoName = draft.photoName
        let earned = Seeds.stampCompletion(created, signals: signals)
        context.insert(created)
        return earned
    }

    /// 사진 파일은 그 이름을 쓰는 기록이 더 없을 때만 지운다(2026-09-16). 날짜 넘김 버그로 어제·오늘이
    /// 같은 이름을 함께 든 기기가 이미 있다 — 그대로 지우면 남은 쪽 사진이 빈칸이 된다.
    /// `owner` = 지금 그 이름을 놓는 기록(자기 참조는 세지 않는다).
    @MainActor
    static func releasePhoto(_ name: String?, excluding owner: DailyCheckIn?, in all: [DailyCheckIn]) {
        guard let name else { return }
        let stillReferenced = all.contains { $0 !== owner && $0.photoName == name }
        if !stillReferenced { CheckInPhotoStore.delete(name) }
    }
}
