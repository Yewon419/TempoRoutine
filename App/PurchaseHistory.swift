// 템포루틴 — 구입 내역 (2026-09-04 대표님 지시 "설정탭에 구입내역 볼수있게")
//
// 이 앱의 「구입」은 두 갈래다: **실제 결제**(테마 패스 ₩5,000 · 커피 한 잔)와 **씨앗 구매**
// (체크인으로 모은 재화). 진실을 든 곳이 각각 애플과 씨앗 원장이라 섹션을 섞지 않는다.
//
// - 결제 = StoreKit `Transaction.all`. 온디바이스 검증뿐이다(§5.2 무서버 — 영수증 서버 없음).
//   ⚠ **소모품(커피)은 finish 하면 이력에서 지워지는 게 기본값이다.** 그래서 project.yml에
//   `INFOPLIST_KEY_SKIncludeConsumableInAppPurchaseHistory: YES`(iOS 18+)를 켰다 — 이 키가
//   빠지면 커피가 한 줄도 안 뜬다. 코드가 아니라 빌드 설정을 봐야 하는 자리다.
// - 씨앗 = `Seeds.ledger.purchases`(테마 rawValue → 낸 씨앗 수). **날짜가 없다** — 원장이 낸
//   값만 적기 때문에 씨앗 섹션은 금액만 말하고 시간순으로 세우지 않는다.
// - 환불(revocationDate)된 건은 지우지 않고 「환불됨」으로 남긴다 — 내역은 내역이다.
//   보유 회수는 여전히 안 한다(§3.8.1 "이미 산 테마는 회수하지 않는다").
//
// 무료로 열린 테마(승계·샌드박스 시험 지급)는 결제도 씨앗 지출도 아니라 두 섹션 어디에도
// 안 뜬다 — 보유 목록은 테마 탭이 보여준다.

import StoreKit
import SwiftData
import SwiftUI
import TempoCore

// ── 값 타입 ──

/// 결제 한 건 — 표시에 필요한 만큼만 뽑아 둔다(뷰가 StoreKit 타입을 들고 다니지 않게).
struct PurchaseRecord: Identifiable, Sendable {
    let id: UInt64
    let title: String
    let date: Date
    /// 통화 서식까지 끝낸 금액. 애플이 금액을 안 주면 nil(표기 생략).
    let amount: String?
    let revoked: Bool
}

/// 씨앗으로 연 테마 한 건 — 날짜가 없어 결제와 같은 자료형에 담지 않는다.
struct SeedPurchaseRow: Identifiable, Sendable {
    let id: String
    let title: String
    let seeds: Int
}

@MainActor
enum PurchaseHistory {
    /// 상품 ID → 화면 이름. 콘솔 상품명을 쓰지 않는다 — 번역 카탈로그를 타야 한다.
    /// 모르는 ID(옛 상품·새 상품)는 ID를 그대로 보여준다: 내역에서 줄이 사라지는 것보다 낫다.
    static func title(for productID: String) -> String {
        if let theme = ThemePassStore.productIDs[productID] {
            return Loc.fmt("%1$@ 테마", theme.displayName)
        }
        if productID == TipStore.productID { return Loc.str("커피 한 잔") }
        return productID
    }

    static func load() async -> [PurchaseRecord] {
        var records: [PurchaseRecord] = []
        for await result in StoreKit.Transaction.all {
            // 서명이 안 맞는 거래는 내역에 적지 않는다(결제 경로와 같은 태도 — TipJar·ThemePass)
            guard case .verified(let transaction) = result else { continue }
            records.append(PurchaseRecord(id: transaction.id,
                                          title: title(for: transaction.productID),
                                          date: transaction.purchaseDate,
                                          amount: amountText(transaction),
                                          revoked: transaction.revocationDate != nil))
        }
        return records.sorted { $0.date > $1.date }
    }

    /// 소모품의 `price`는 수량이 이미 곱해진 총액이다(애플 문서) — 다시 곱하지 않는다.
    private static func amountText(_ transaction: StoreKit.Transaction) -> String? {
        guard let price = transaction.price else { return nil }
        guard let code = transaction.currency?.identifier ?? Loc.locale.currency?.identifier else {
            return nil
        }
        // 문서에 있는 이니셜라이저를 그대로 쓴다 — `.currency(code:)` 축약형은 Decimal 참조
        // 문서에 안 나와 있어 확신할 수 없다(Windows라 컴파일로 확인이 안 된다).
        return price.formatted(Decimal.FormatStyle.Currency(code: code, locale: Loc.locale))
    }

    /// 씨앗을 낸 테마만(0 = 승계·무료 지급이라 「구입」이 아니다). 날짜가 없어 이름순으로 세운다.
    static var seedPurchases: [SeedPurchaseRow] {
        Seeds.ledger.purchases
            .compactMap { raw, paid -> SeedPurchaseRow? in
                guard paid > 0, let theme = AppTheme(rawValue: raw) else { return nil }
                return SeedPurchaseRow(id: raw, title: theme.displayName, seeds: paid)
            }
            .sorted { $0.title < $1.title }
    }
}

// ── 화면 — 설정에서 push ──

struct PurchaseHistoryView: View {
    @Query private var periodDays: [PeriodDay]

    @State private var payments: [PurchaseRecord] = []
    @State private var loaded = false
    @State private var restoring = false
    @State private var restoreResult: Int?
    @State private var lightFeedback = 0

    var body: some View {
        List {
            // 행 재질은 설정과 같은 것을 쓴다(하위 화면이 부모와 다른 재질이면 이질적이다)
            Group {
                paymentSection
                seedSection
                restoreSection
            }
            .listRowBackground(SettingsView.themedRowGround)
        }
        .scrollContentBackground(.hidden)
        .centeredColumn(680)
        .background { ground }
        .navigationTitle("구입 내역")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(ThemeStore.chrome.skyGround ? .dark : nil, for: .navigationBar)
        .task { await reload() }
        .sensoryFeedback(.impact(weight: .light), trigger: lightFeedback)
        .alert(restoreResult.map { $0 > 0 ? Loc.str("구매를 복원했어요.")
                                          : Loc.str("복원할 구매가 없어요.") } ?? "",
               isPresented: Binding(get: { restoreResult != nil },
                                    set: { if !$0 { restoreResult = nil } })) {
            Button("확인") { restoreResult = nil }
        }
    }

    // ── 결제 ──
    @ViewBuilder
    private var paymentSection: some View {
        Section {
            if !loaded {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(Ink.text.opacity(0.5))
                    Text("불러오는 중이에요")
                        .foregroundStyle(Ink.onSky.opacity(0.6))
                }
            } else if payments.isEmpty {
                Text("아직 결제한 내역이 없어요.")
                    .foregroundStyle(Ink.onSky.opacity(0.6))
            } else {
                ForEach(payments) { record in
                    paymentRow(record)
                }
            }
        } header: {
            Text("결제")
                .foregroundStyle(Ink.groundSub)
        } footer: {
            Text("애플 계정에 남아 있는 결제 기록이에요. 영수증과 환불 요청은 App Store에서 할 수 있어요.")
                .foregroundStyle(Ink.groundSub)
        }
    }

    private func paymentRow(_ record: PurchaseRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .foregroundStyle(Ink.onSky)
                Text(record.date.formatted(Loc.dateTime.year().month().day()))
                    .font(.footnote)
                    .foregroundStyle(Ink.onSky.opacity(0.5))
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                if let amount = record.amount {
                    Text(verbatim: amount)
                        .foregroundStyle(Ink.onSky.opacity(0.7))
                }
                if record.revoked {
                    Text("환불됨")
                        .font(.footnote)
                        .foregroundStyle(Ink.danger)
                }
            }
        }
    }

    // ── 씨앗 ──
    private var seedRows: [SeedPurchaseRow] { PurchaseHistory.seedPurchases }

    @ViewBuilder
    private var seedSection: some View {
        if !seedRows.isEmpty {
            Section {
                ForEach(seedRows) { row in
                    HStack {
                        Text(row.title)
                            .foregroundStyle(Ink.onSky)
                        Spacer(minLength: 0)
                        Text(Loc.fmt("씨앗 %lld개", row.seeds))
                            .foregroundStyle(Ink.onSky.opacity(0.7))
                    }
                }
            } header: {
                Text("씨앗으로 연 테마")
                    .foregroundStyle(Ink.groundSub)
            } footer: {
                Text("체크인으로 모은 씨앗을 낸 테마예요. 원장에는 낸 씨앗 수만 남아서 날짜는 알 수 없어요.")
                    .foregroundStyle(Ink.groundSub)
            }
        }
    }

    // ── 복원 ──
    @ViewBuilder
    private var restoreSection: some View {
        Section {
            if restoring {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(Ink.text.opacity(0.5))
                    Text("구매를 확인하는 중이에요")
                        .foregroundStyle(Ink.onSky.opacity(0.6))
                }
            } else {
                Button("구매 복원") {
                    lightFeedback += 1
                    restoring = true
                    Task { @MainActor in
                        restoreResult = await ThemePassStore.shared.restore()
                        restoring = false
                        await reload()
                    }
                }
                .foregroundStyle(Ink.onSky)
            }
        } footer: {
            Text("기기를 바꾸거나 앱을 다시 설치했을 때 눌러 주세요. 결제한 테마가 다시 열려요.")
                .foregroundStyle(Ink.groundSub)
        }
    }

    @MainActor
    private func reload() async {
        payments = await PurchaseHistory.load()
        loaded = true
    }

    /// 지면 — 설정과 같은 문법. 단 **플리 영상 지면은 쓰지 않는다**: AVPlayer는 레이어 하나에만
    /// 그려져서(repo CLAUDE.md) 이 화면이 소유권을 가져가면 뒤에 있던 설정 지면이 빈 채로
    /// 남을 수 있다. 하위 화면 한 장을 위해 부모 화면을 걸 이유가 없다.
    private var ground: some View {
        ZStack {
            if ThemeStore.chrome.skyGround {
                WeatherSky()
            } else {
                Ink.paper
                SeasonLight(phase: CycleSnapshot(periodDays: periodDays)
                    .phase(on: Calendar.current.startOfDay(for: .now)),
                            motif: .open)
            }
        }
        .ignoresSafeArea()
    }
}
