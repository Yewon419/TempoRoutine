// 템포루틴 — 씨앗 (테마 재화, 2026-08-09 사용자 결정)
// 하루 체크인을 다 적으면(오늘 한 줄 제외) 씨앗 1개. 당일 작성이 원칙, 다음날 작성까지 인정.
// **획득 원장(2026-08-20 개정)**: 지급된 날은 원장(SeedLedgerDTO.earnedDays)에도 적는다 —
// 종전 「행 존재에서 파생」만으로는 기록 정리(행 삭제)·전체 삭제가 재화 회수가 됐다(철회
// 비대칭·잔액 고착). 잔액 근거 = 원장 ∪ 파생(구 사용자 호환 — 시작 시 1회 백필).
// 재화는 기록이 아니다: 전체 삭제도 원장(획득·소비·보유)은 건드리지 않는다.
// 스트릭·연속 표시 금지(§3.4)는 그대로다 — 씨앗은 개수만 말하고 연속을 말하지 않는다.

import SwiftUI
import TempoCore

enum Seeds {
    /// 완료 판정 — 필수 2신호 + 켜져 있는 추적 신호 전부. 오늘 한 줄은 제외(사용자 규칙).
    /// 판정은 저장 순간의 추적 설정 기준 — 나중에 항목을 켜고 꺼도 이미 찍힌 도장은 불변.
    static func isComplete(energy: Int, mood: Int, sleep: Int?, appetite: Int?,
                           signals: TrackedSignals) -> Bool {
        guard energy > 0, mood > 0 else { return false }
        if signals.sleep && (sleep ?? 0) == 0 { return false }
        if signals.appetite && (appetite ?? 0) == 0 { return false }
        return true
    }

    /// 완료 도장 — 처음 완성된 순간에만 찍는다(이후 수정해도 최초 시각 유지 = 중복 지급 없음).
    /// 반환 = 이번 호출로 도장이 새로 찍혔고 지급 대상인지 — 획득 연출 트리거(2026-08-09).
    @discardableResult
    static func stampCompletion(_ record: DailyCheckIn, signals: TrackedSignals) -> Bool {
        guard record.completedAt == nil,
              isComplete(energy: record.energy, mood: record.mood,
                         sleep: record.sleep, appetite: record.appetite, signals: signals)
        else { return false }
        record.completedAt = .now
        let awarded = isAwarded(record)
        if awarded { recordEarned(day: record.day) }   // 획득 원장(2026-08-20) — 행이 지워져도 남는다
        return awarded
    }

    /// 획득 원장 기입 — 같은 날은 한 번(집합). 원장은 동기화·백업이 실어 나른다.
    private static func recordEarned(day: Date) {
        var next = ledger
        var days = Set(next.earnedDays ?? [])
        let key = ExportCodec.dayString(day)
        guard !days.contains(key) else { return }
        days.insert(key)
        next.earnedDays = days.sorted()
        write(next)
    }

    /// 구 사용자 백필(앱 시작 1회 호출) — 원장 도입 전 획득(행 파생)을 원장에 옮겨 적는다.
    /// 멱등: 이미 다 적혀 있으면 쓰기 없음.
    static func backfillEarnedLedger(_ checkIns: [DailyCheckIn]) {
        let derived = Set(checkIns.filter { isAwarded($0) }.map { ExportCodec.dayString($0.day) })
        guard !derived.isEmpty else { return }
        var next = ledger
        let existing = Set(next.earnedDays ?? [])
        let union = existing.union(derived)
        guard union != existing else { return }
        next.earnedDays = union.sorted()
        write(next)
    }

    /// 지급 판정 — 그날 또는 다음날 안에 완성된 기록만(마감 = day+2일 0시).
    static func isAwarded(_ record: DailyCheckIn) -> Bool {
        guard let stamped = record.completedAt else { return false }
        guard let deadline = Calendar.current.date(byAdding: .day, value: 2, to: record.day) else {
            return false
        }
        return stamped < deadline
    }

    /// 획득 = 원장 ∪ 파생(같은 날은 한 번). 원장 도입(2026-08-20) 전 기록·백필 전 상태를
    /// 위해 파생과의 합집합을 유지한다 — 행이 있으면 원장에 없어도 센다.
    static func balance(_ checkIns: [DailyCheckIn]) -> Int {
        earnedDayKeys(checkIns).count
    }

    private static func earnedDayKeys(_ checkIns: [DailyCheckIn]) -> Set<String> {
        Set(checkIns.filter { isAwarded($0) }.map { ExportCodec.dayString($0.day) })
            .union(ledger.earnedDays ?? [])
    }

    // ── 소비 원장 (2026-08-09 테마 탭 / 2026-08-11 맵 원장으로 개정) ──
    // 종전엔 plantedThemes·seedsSpent·seedsBonus·claimedNotices 네 키로 흩어져 있었고 전부
    // 이 기기 UserDefaults였다 — 폰에서 산 테마가 패드에선 잠기고 잔액은 더 많아 보였다(P-6).
    // 지금은 `SeedLedgerDTO` 한 덩어리 = 동기화(PlannerSync)·백업(내보내기 봉투)이 실어 나른다.
    private static let ledgerKey = "seedLedger"
    private static let migratedKey = "seedLedgerMigrated"
    /// 원장 변경 방송용 카운터. SwiftUI는 생 UserDefaults 읽기를 무효화하지 못해서, 소식란에서
    /// 씨앗을 받아도 오늘 탭 배지가 옛 숫자에 남아 있었다 — 표면은 이 키를 @AppStorage로 지켜본다.
    static let revisionKey = "seedLedgerRevision"

    static var ledger: SeedLedgerDTO {
        migrateIfNeeded()
        guard let data = UserDefaults.standard.data(forKey: ledgerKey),
              let decoded = try? JSONDecoder().decode(SeedLedgerDTO.self, from: data)
        else { return SeedLedgerDTO() }
        return decoded
    }

    /// 쓰기는 전부 이 창구로 — 읽고·고치고·쓰는 순서라 마이그레이션이 새 값을 덮을 일이 없다.
    private static func write(_ ledger: SeedLedgerDTO) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: ledgerKey)
        defaults.set(defaults.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }

    /// 산개 원장(v1) → 맵 원장. 1회. 테마별로 얼마를 냈는지는 남아 있지 않아 총 소비를 가격대로
    /// 배분하고, 배분이 끝난 뒤 남은 테마는 승계분(0)으로 본다 — 승계 기기의 무료 보유가 유료로
    /// 둔갑하지 않는다. 공지별 수령액도 남아 있지 않아 총액은 legacyBonus로 옮긴다.
    private static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)
        var ledger = SeedLedgerDTO()
        var remaining = defaults.integer(forKey: "seedsSpent")
        for raw in (defaults.stringArray(forKey: "plantedThemes") ?? []).sorted() {
            let paid = min(remaining, AppTheme(rawValue: raw)?.seedPrice ?? 0)
            remaining -= paid
            ledger.purchases[raw] = paid
        }
        for id in defaults.stringArray(forKey: "claimedNotices") ?? [] {
            ledger.claims[id] = 0
        }
        ledger.legacyBonus = defaults.integer(forKey: "seedsBonus")
        write(ledger)
    }

    /// 보유 테마(rawValue 집합). 보유 테마는 기록 철회로 획득이 줄어도 유지된다 — 재화 신뢰.
    static var owned: Set<String> { ledger.ownedThemes }

    static var claimedNotices: Set<String> { Set(ledger.claims.keys) }

    /// 공지 씨앗 수령 — 공지 id별 1회. 받은 액수를 공지 id에 붙여 적는다(합산 카운터 아님 —
    /// 두 기기에서 같은 공지를 받아도 병합하면 한 번으로 접힌다).
    static func claim(noticeID: String, seeds: Int) -> Bool {
        guard seeds > 0 else { return false }
        var next = ledger
        guard next.claims[noticeID] == nil else { return false }
        next.claims[noticeID] = seeds
        write(next)
        return true
    }

    /// 쓸 수 있는 씨앗 = 획득 + 보너스 − 소비. 기록 철회로 획득이 줄면 음수가 될 수 있어
    /// 표시·판정 하한 0(§3.8.1 하한 처리 — 이미 산 테마는 회수하지 않는다).
    static func available(_ checkIns: [DailyCheckIn]) -> Int {
        available(checkIns, ledger: ledger)
    }

    private static func available(_ checkIns: [DailyCheckIn], ledger: SeedLedgerDTO) -> Int {
        max(0, balance(checkIns) + ledger.bonus - ledger.spent)
    }

    /// 구매 — 이미 보유했으면 참(멱등), 잔액 부족이면 거짓. 성공 시 낸 값을 테마에 붙여 적는다.
    static func plant(_ theme: AppTheme, price: Int, checkIns: [DailyCheckIn]) -> Bool {
        var next = ledger
        guard next.purchases[theme.rawValue] == nil else { return true }
        guard available(checkIns, ledger: next) >= price else { return false }
        next.purchases[theme.rawValue] = price
        write(next)
        return true
    }

    /// 승계 — 씨앗 도입 전부터 쓰던 테마를 잠그지 않는다(§3.8.1). 낸 값 0으로 적어 구매분과 구분한다.
    static func grandfather(_ theme: AppTheme) {
        var next = ledger
        guard next.purchases[theme.rawValue] == nil else { return }
        next.purchases[theme.rawValue] = 0
        write(next)
    }

    /// 다른 기기·백업본 원장 병합(합집합). 바뀐 게 있으면 참 — 부른 쪽이 되올릴지 판단한다.
    @discardableResult
    static func merge(_ remote: SeedLedgerDTO) -> Bool {
        let current = ledger
        let merged = current.merged(with: remote)
        guard merged != current else { return false }
        write(merged)
        return true
    }

    static func awardedDays(_ checkIns: [DailyCheckIn]) -> Set<Date> {
        Set(checkIns.filter { isAwarded($0) }.map(\.day))
    }

    /// 완료 도장이 찍힌 날 전부(지급 기한 무관) — 캘린더 완료 표시용(2026-08-09 베타 피드백
    /// "숫자 흐리게로 대체"). 씨앗 지급 여부와 분리: 이 표시는 재화가 아니라 완료 사실을 말한다.
    static func completedDays(_ checkIns: [DailyCheckIn]) -> Set<Date> {
        Set(checkIns.filter { $0.completedAt != nil }.map(\.day))
    }
}

/// 씨앗 글리프 — 위가 살짝 뾰족한 물방울꼴. 은필 선화 모티프와 같은 단색 계열(§4).
struct SeedGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.5, y: 0))
        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h),
                       control: CGPoint(x: w * 1.12, y: h * 0.68))
        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: 0),
                       control: CGPoint(x: -w * 0.12, y: h * 0.68))
        return p
    }
}

/// 오늘 탭 우상단 잔액 배지. 돈 문법(코인·금액) 금지 — 씨앗 글리프 + 개수만.
/// 개수 변화 = 숫자 롤링 + 스프링(2026-08-09 획득 연출 — 스티커와 같은 놀이 언어).
struct SeedBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            SeedGlyph()
                .fill(Ink.onGround(Ink.text.opacity(0.75), white: 0.9))   // 지면 위 배지(시안 흰 덮기)
                .frame(width: 9, height: 12)
                .rotationEffect(.degrees(16))
            Text("\(count)")
                .font(.almanacBody(.footnote, size: 13))
                .monospacedDigit()
                .foregroundStyle(Ink.onGround(Ink.text.opacity(0.8), white: 0.9))
                .contentTransition(.numericText(value: Double(count)))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Ink.surface, in: Capsule())
        .overlay(Capsule().stroke(Ink.text.opacity(0.15), lineWidth: 1))
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Loc.fmt("씨앗 %lld개", count))
    }
}

// ── 획득 연출 (2026-08-09 사용자 지시) ──
// 도장이 찍히는 순간, 편집기 위로 씨앗이 스프링으로 피어올랐다가 잦아든다(스티커 등장과
// 같은 놀이 언어 — 데이터 상태 표시가 아니라서 §4 "상태 전환은 즉시" 원칙과 별개 층).
// trigger 증가 = 1회 재생. 성공 햅틱 동반.
struct SeedBurst: ViewModifier {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if shown {
                    SeedGlyph()
                        .fill(Ink.text.opacity(0.85))
                        .frame(width: 15, height: 20)
                        .rotationEffect(.degrees(16))
                        .offset(y: -26)
                        .transition(reduceMotion ? .opacity
                                    : .scale(scale: 0.1).combined(with: .offset(y: 18)))
                        .accessibilityHidden(true)
                }
            }
            .sensoryFeedback(.success, trigger: trigger)
            .onChange(of: trigger) { _, _ in
                withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.55)) {
                    shown = true
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
                        shown = false
                    }
                }
            }
    }
}

extension View {
    /// 씨앗 획득 연출 — 체크인 편집기(오늘 탭·하루 상세·트래커)에 붙인다.
    func seedBurst(trigger: Int) -> some View {
        modifier(SeedBurst(trigger: trigger))
    }
}
