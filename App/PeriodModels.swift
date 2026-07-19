// 템포루틴 — PeriodDay 일별 기록 모델 (MASTER §5.5.4 LOCKED)
// §5.5 CloudKit 호환 P0 빌드 규칙: 프로퍼티 전부 기본값, unique 제약 금지, 관계는 사용 시 optional.
// dedup(하루 1개)은 스키마 제약이 아니라 쓰기 경로에서 보장한다.

import Foundation
import SwiftData

enum PeriodDayOrigin: String, Codable {
    case local              // 이 앱에서 직접 기록
    case appAuthored        // 이 앱이 HealthKit에 쓴 것
    case healthKitImported  // 타 앱/기기에서 HealthKit으로 들어온 것
}

@Model
final class PeriodDay {
    var id: UUID = UUID()
    var day: Date = Date()              // start-of-day 정규화, 하루 1개 (dedup 키 — 일 단위)
    var origin: PeriodDayOrigin = PeriodDayOrigin.local
    var healthKitUUID: UUID?            // 해당 일의 HKSample UUID (1:1)

    init(day: Date, origin: PeriodDayOrigin = .local, healthKitUUID: UUID? = nil) {
        self.id = UUID()
        self.day = Calendar.current.startOfDay(for: day)
        self.origin = origin
        self.healthKitUUID = healthKitUUID
    }
}
