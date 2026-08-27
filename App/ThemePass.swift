// 템포루틴 — 테마 패스 (₩5,000 비소모품 IAP, 2026-08-27 대표님 가격 확정 Phase 2)
//
// 활판·티켓·플레이리스트를 씨앗 100개 **또는** 개당 ₩5,000으로 연다. 결제는 StoreKit 2
// 온디바이스 검증뿐(§5.2 무서버 — 커피 팁과 같은 계약, 영수증 서버 없음).
//
// 소유 기록 = 씨앗 원장에 0원 구매(Seeds.grandfather)로 적는다:
// - 씨앗 소비와 안 섞인다(available 불변 — 낸 씨앗이 0이니 spent가 안 움직인다).
// - 원장은 동기화(PlannerSync)·백업이 실어 나르므로 같은 iCloud의 다른 기기에도 열린다.
// - 애플 쪽 소유(비소모품 entitlement)는 **실행마다 재검사해 원장에 되새긴다** — 앱 초기화·
//   재설치로 원장이 비어도 결제 소유가 복구된다(애플 규칙: 비소모품은 언제나 복원 가능).
// 환불(revocation)은 회수하지 않는다 — §3.8.1 "이미 산 테마는 회수하지 않는다"와 같은 태도.
// 다만 entitlement 재검사·updates 리스너는 revoked 거래로는 소유를 새로 적지 않는다.

import StoreKit
import SwiftUI

@MainActor
@Observable
final class ThemePassStore {
    static let shared = ThemePassStore()

    /// ASC 상품 ID — 콘솔에 이 값 그대로 **비소모품**으로 등록해야 상품이 잡힌다(₩5,000 티어).
    static let productIDs: [String: AppTheme] = [
        "app.temporoutine.TempoRoutine.theme.letterpress": .letterpress,
        "app.temporoutine.TempoRoutine.theme.ticket": .ticket,
        "app.temporoutine.TempoRoutine.theme.playlist": .playlist,
    ]

    static func productID(for theme: AppTheme) -> String? {
        productIDs.first { $0.value == theme }?.key
    }

    private(set) var products: [String: Product] = [:]
    private(set) var purchasing: AppTheme?
    private var updatesTask: Task<Void, Never>?

    private init() {}

    /// 앱 실행 시 1회 — entitlement 재검사(재설치·초기화 복구) + 앱 밖에서 끝난 거래 수신.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task {
            await refreshEntitlements()
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update,
                      let theme = Self.productIDs[transaction.productID] else { continue }
                await transaction.finish()
                if transaction.revocationDate == nil { Seeds.grandfather(theme) }
            }
        }
    }

    func load() async {
        guard products.isEmpty else { return }
        guard let items = try? await Product.products(for: Set(Self.productIDs.keys)) else { return }
        for item in items { products[item.id] = item }
    }

    func product(for theme: AppTheme) -> Product? {
        Self.productID(for: theme).flatMap { products[$0] }
    }

    /// 콘솔 등록 전 시험 경로(커피 팁 전례) — 샌드박스 빌드에서만 무료로 연다.
    /// App Store 배포본은 sandboxReceipt가 아니라 이 경로를 절대 못 탄다.
    func trialAvailable(for theme: AppTheme) -> Bool {
        product(for: theme) == nil && TipStore.isSandbox && Self.productID(for: theme) != nil
    }

    enum BuyResult { case done, cancelled, pending, failed }

    func buy(_ theme: AppTheme) async -> BuyResult {
        guard purchasing == nil else { return .cancelled }
        guard let product = product(for: theme) else {
            // 상품 미등록 + 샌드박스 = 시험 지급(무료). 프로덕션에선 버튼 자체가 안 뜬다.
            if trialAvailable(for: theme) { Seeds.grandfather(theme); return .done }
            return .failed
        }
        purchasing = theme
        defer { purchasing = nil }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    Seeds.grandfather(theme)
                    return .done
                case .unverified(let transaction, _):
                    // 서명이 안 맞는 거래 — 소유는 안 적되 큐에는 남기지 않는다(커피 팁 전례)
                    await transaction.finish()
                    return .failed
                }
            case .userCancelled: return .cancelled
            case .pending: return .pending   // 가족 공유 승인 대기 — 통과하면 updates가 받는다
            @unknown default: return .cancelled
            }
        } catch {
            return .failed
        }
    }

    /// 구매 복원(비소모품 심사 요구) — 스토어 동기화 후 entitlement 재검사.
    /// 반환 = 이번에 새로 열린 테마 수(이미 열려 있던 것은 안 센다).
    func restore() async -> Int {
        try? await AppStore.sync()
        return await refreshEntitlements()
    }

    @discardableResult
    private func refreshEntitlements() async -> Int {
        var granted = 0
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  let theme = Self.productIDs[transaction.productID],
                  transaction.revocationDate == nil else { continue }
            if !Seeds.owned.contains(theme.rawValue) { granted += 1 }
            Seeds.grandfather(theme)
        }
        return granted
    }
}
