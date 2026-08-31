// 템포루틴 — 업적(기념 티켓) 시스템 (2026-08-31 대표님 승인 C2 확장안)
// 마일스톤을 「기념 티켓」으로 발권하고, 달성 뒤에도 보관함(나의 템포 탭)에서 다시 꺼내 본다.
// 달성 힘든 업적 + 히든 업적(달성 전 = "???") 포함.
//
// 원칙:
// - **연속(스트릭) 기반 업적 금지** — §3.4 "연속 표시 금지"는 재화(씨앗)와 동일하게 적용.
//   전부 누적·이벤트 기반이다.
// - **업적은 기록이 아니다**(씨앗 원장 철학) — 기록 삭제·전체 삭제가 업적 회수가 되면 안 된다.
//   판정 카운터를 원장에 누적하고, 행 파생으로 다시 세지 않는다.
// - 개발자 모드 중엔 원장 기입 금지(씨앗 stampCompletion 전례 — dev 기록이 실업적을 벌면 안 된다).
// - 저장 = UserDefaults JSON 원장 + 방송 카운터(Seeds.revisionKey 전례). 동기화(PlannerSync)
//   탑승은 후속 — 1차는 이 기기 로컬.

import SwiftUI

// ── 업적 정의 ──
enum AchievementID: String, CaseIterable, Codable {
    // 보이는 업적 — 누적 마일스톤
    case firstCheckIn      // 첫 체크인 완성
    case checkIns10
    case checkIns50
    case checkIns100
    case checkIns365       // 달성 힘듦
    case firstTheme        // 유료 테마 첫 구매(0원 승계 제외)
    case allThemes         // 전 유료 테마 보유(달성 힘듦)
    case firstCycle        // 첫 주기 완주(리캡 첫 발행과 연동)
    case fourSeasons       // 나의 템포 4계절 패턴 완성
    case anniversary       // 함께한 지 1년
    case seeds100          // 누적 획득 씨앗 100(달성 힘듦)
    // 히든 — 달성 전엔 "???"
    case nightOwl          // 새벽(0~4시) 체크인 완성
    case newYear           // 1월 1일 체크인
    case coffeeFriend      // 커피 5잔
    case mascotNap         // 커피 캐릭터 재우기(B2 연동)
    case seasonTap         // 계절 표제의 숨은 반응 발견(B1 연동)

    var hidden: Bool {
        switch self {
        case .nightOwl, .newYear, .coffeeFriend, .mascotNap, .seasonTap: true
        default: false
        }
    }

    var title: String {
        switch self {
        case .firstCheckIn: Loc.str("첫 걸음")
        case .checkIns10:   Loc.str("열 밤의 기록")
        case .checkIns50:   Loc.str("쉰 밤의 기록")
        case .checkIns100:  Loc.str("백 밤의 기록")
        case .checkIns365:  Loc.str("일 년치 밤들")
        case .firstTheme:   Loc.str("새 옷")
        case .allThemes:    Loc.str("옷장 완성")
        case .firstCycle:   Loc.str("한 바퀴")
        case .fourSeasons:  Loc.str("사계 수집가")
        case .anniversary:  Loc.str("일 주년")
        case .seeds100:     Loc.str("씨앗 부자")
        case .nightOwl:     Loc.str("올빼미")
        case .newYear:      Loc.str("새해 첫 기록")
        case .coffeeFriend: Loc.str("단골손님")
        case .mascotNap:    Loc.str("쉿, 자는 중")
        case .seasonTap:    Loc.str("계절을 만진 손")
        }
    }

    /// 달성 조건 문구 — 미달성 카드에 그대로 노출(히든은 노출 안 함)
    var caption: String {
        switch self {
        case .firstCheckIn: Loc.str("첫 체크인을 완성해요")
        case .checkIns10:   Loc.str("체크인 10일을 완성해요")
        case .checkIns50:   Loc.str("체크인 50일을 완성해요")
        case .checkIns100:  Loc.str("체크인 100일을 완성해요")
        case .checkIns365:  Loc.str("체크인 365일을 완성해요")
        case .firstTheme:   Loc.str("첫 테마를 구매해요")
        case .allThemes:    Loc.str("모든 테마를 모아요")
        case .firstCycle:   Loc.str("한 주기를 처음부터 끝까지 함께해요")
        case .fourSeasons:  Loc.str("나의 템포에서 네 계절 패턴을 완성해요")
        case .anniversary:  Loc.str("템포루틴과 1년을 함께해요")
        case .seeds100:     Loc.str("씨앗을 누적 100개 모아요")
        case .nightOwl:     Loc.str("깊은 새벽에 체크인을 완성했어요")
        case .newYear:      Loc.str("1월 1일에 기록을 남겼어요")
        case .coffeeFriend: Loc.str("개발자에게 커피를 다섯 잔 사줬어요")
        case .mascotNap:    Loc.str("우상단 친구를 꾹 눌러 재웠어요")
        case .seasonTap:    Loc.str("계절 이름의 숨은 반응을 찾았어요")
        }
    }
}

// ── 원장 + 판정 ──
@MainActor
@Observable
final class Achievements {
    static let shared = Achievements()

    /// 방송 카운터 — 표면이 @AppStorage로 지켜본다(씨앗 revisionKey 전례)
    static let revisionKey = "achievementRevision"
    private static let ledgerKey = "achievementLedger"
    private static let firstLaunchKey = "firstLaunchDate"

    /// 달성 배너 큐 — RootTabView 오버레이가 하나씩 꺼내 발권 연출을 띄운다
    private(set) var pendingBanner: AchievementID?
    private var bannerQueue: [AchievementID] = []

    private struct Ledger: Codable {
        /// id → 달성 시각(ISO 아님 — Date 그대로, JSON 인코딩)
        var unlocked: [String: Date] = [:]
        /// 완성 체크인 누적(행 파생 아님 — 삭제 무관, 씨앗 원장 철학)
        var completedCount: Int = 0
    }

    private var ledger: Ledger {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.ledgerKey),
                  let decoded = try? JSONDecoder().decode(Ledger.self, from: data) else { return Ledger() }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: Self.ledgerKey)
            let rev = UserDefaults.standard.integer(forKey: Self.revisionKey)
            UserDefaults.standard.set(rev + 1, forKey: Self.revisionKey)
        }
    }

    // ── 조회 ──
    func unlockedDate(_ id: AchievementID) -> Date? { ledger.unlocked[id.rawValue] }
    func isUnlocked(_ id: AchievementID) -> Bool { unlockedDate(id) != nil }
    var unlockedCount: Int { ledger.unlocked.count }
    var totalCount: Int { AchievementID.allCases.count }
    /// 발권 일련번호 — 달성 순서(1부터). 티켓 조판의 NO. 자리
    func serial(_ id: AchievementID) -> Int? {
        guard let date = unlockedDate(id) else { return nil }
        return ledger.unlocked.values.sorted().firstIndex(of: date).map { $0 + 1 }
    }

    // ── 달성 ──
    /// 멱등 — 이미 달성이면 no-op. dev 모드는 기입 금지(씨앗 전례).
    func unlock(_ id: AchievementID) {
        guard !DevMode.active, !isUnlocked(id) else { return }
        var next = ledger
        next.unlocked[id.rawValue] = .now
        ledger = next
        bannerQueue.append(id)
        if pendingBanner == nil { advanceBanner() }
    }

    /// 배너 하나 닫힘 → 다음 큐. 연출 뷰가 사라질 때 부른다.
    func advanceBanner() {
        pendingBanner = bannerQueue.isEmpty ? nil : bannerQueue.removeFirst()
    }

    // ── 판정 훅 ──
    /// 체크인 완성 도장 직후(Seeds.stampCompletion 안 — 4개 호출부의 단일 깔때기).
    /// `stampedAt` = 도장 시각(새벽 판정), `day` = 기록 날짜(새해 판정).
    func checkInStamped(day: Date, stampedAt: Date) {
        guard !DevMode.active else { return }
        var next = ledger
        next.completedCount += 1
        let count = next.completedCount
        ledger = next
        unlock(.firstCheckIn)
        if count >= 10 { unlock(.checkIns10) }
        if count >= 50 { unlock(.checkIns50) }
        if count >= 100 { unlock(.checkIns100) }
        if count >= 365 { unlock(.checkIns365) }
        let hour = Calendar.current.component(.hour, from: stampedAt)
        if (0..<4).contains(hour) { unlock(.nightOwl) }
        let md = Calendar.current.dateComponents([.month, .day], from: day)
        if md.month == 1, md.day == 1 { unlock(.newYear) }
    }

    /// 유료 테마 구매 직후(씨앗 심기·₩5,000 패스 공용). 0원 승계는 부르지 않는다.
    func themePurchased() {
        unlock(.firstTheme)
        let paidThemes = AppTheme.allCases.filter { $0.seedPrice != nil }
        if paidThemes.allSatisfy({ Seeds.owned.contains($0.rawValue) }) { unlock(.allThemes) }
    }

    /// 누적 획득 씨앗 판정 — 씨앗 지급 직후 잔액이 아니라 **누적 획득**으로 센다
    func seedsEarned(total: Int) {
        if total >= 100 { unlock(.seeds100) }
    }

    /// 나의 템포 4계절 패턴 완성(RhythmView 진행 계산부)
    func seasonsUnlocked(_ count: Int) {
        if count >= 4 { unlock(.fourSeasons) }
    }

    /// 커피 팁 수령(TipStore) — 잔 수 누적 기준
    func coffeeReceived(totalCups: Int) {
        if totalCups >= 5 { unlock(.coffeeFriend) }
    }

    /// 앱 시작 1회 — 첫 실행일 기록 + 1주년 판정.
    /// 첫 실행일이 없던 구 사용자는 오늘부터 센다(설치일을 소급 추정하지 않는다 — 거짓 축하 방지).
    func appLaunched() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.firstLaunchKey) == nil {
            defaults.set(Date.now.timeIntervalSinceReferenceDate, forKey: Self.firstLaunchKey)
            return
        }
        let first = Date(timeIntervalSinceReferenceDate: defaults.double(forKey: Self.firstLaunchKey))
        if let year = Calendar.current.date(byAdding: .year, value: 1, to: first), Date.now >= year {
            unlock(.anniversary)
        }
    }
}
