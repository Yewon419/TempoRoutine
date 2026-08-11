// 템포루틴 — 커피 한 잔 (2026-08-11 사용자 지시, §3.8 단건 IAP의 첫 실물)
//
// 테마 탭 우상단에 브랜드 표식이 눈을 뜬 작은 캐릭터가 서서 가끔 고개를 젓는다. 누르면
// 말풍선이 열리고 「커피 한 잔」 소모품 IAP로 만드는 사람에게 팁을 줄 수 있다.
//
// 계약:
// - **주는 대가는 시각적 감사뿐**(2026-08-11 사용자 결정). 씨앗·테마 같은 실이익은 붙이지
//   않는다 — 붙이는 순간 §3.8.1 "씨앗은 기록으로 모인다"가 깨지고 미결 ②(IAP 테마 관계)를
//   지금 확정해야 한다. 팁은 재화 트랙 밖에 둔다.
// - **결제는 StoreKit 2 온디바이스 검증뿐**(§5.2 무서버 유지 — 영수증 서버 없음). 외부 결제
//   경로를 섞으면 3.1.1 리젝이라 IAP 외 길은 두지 않는다.
// - **문구는 「커피」계열, 「기부」금지**(2026-08-11). 자선 기부를 IAP로 받는 경로는 등록
//   비영리로 제한돼 있어, 개발자 팁을 「기부」로 쓰면 심사가 그 규정으로 읽을 여지가 있다.
// - §7 재촉 금지: 사실만 말하고 조른다는 인상을 주지 않는다. **커피를 받은 뒤엔 흔들림을
//   멈춘다** — 이미 준 사람에게 계속 손짓하는 건 실례다.

import StoreKit
import SwiftUI

// ── 원장 — 받은 커피 잔 수 ──
// 소모품이라 애플이 보유 상태를 들고 있지 않다(복원 대상 아님). 감사 표시용 로컬 카운터이며
// 잔 수가 기능을 열지 않으므로 기기 간 동기화·백업 대상도 아니다(잃어도 손해가 없다).
@MainActor
@Observable
final class TipStore {
    static let shared = TipStore()

    /// ASC 상품 ID — 콘솔에 이 값 그대로 소모품으로 등록해야 상품이 잡힌다.
    static let productID = "app.temporoutine.TempoRoutine.coffee"

    private static let cupsKey = "tipCups"
    private static let countedKey = "tipCountedTransactions"

    /// TestFlight·샌드박스 빌드에서만 참(영수증 파일명이 sandboxReceipt). App Store 배포본은
    /// receipt라 항상 거짓이다 — 아래 무료 지급 경로가 프로덕션으로 새어나갈 수 없다.
    /// 상품 등록 전에 구매 후 화면(감사 문구·잔 수·흔들림 정지)을 확인하려고 둔 시험 경로다
    /// (2026-08-11 사용자 지시). 상품이 실제로 등록되면 product가 잡혀 이 경로는 안 탄다.
    static let isSandbox: Bool = {
        guard let url = Bundle.main.appStoreReceiptURL else { return false }
        return url.lastPathComponent == "sandboxReceipt"
    }()

    /// 상품이 없는데 시험 빌드다 = 무료 지급 버튼을 띄운다
    var isFreeTrial: Bool { product == nil && Self.isSandbox }

    enum Status: Equatable {
        case loading
        case unavailable            // 상품 미등록·네트워크 실패 — 버튼을 비활성으로 두고 사실만 적는다
        case ready
        case purchasing
        case pending                // 가족 공유 승인 대기(Ask to Buy)
        case thanks
        case failed(String)
    }

    private(set) var product: Product?
    private(set) var status: Status = .loading
    private(set) var cups: Int
    /// 이미 세어 넣은 트랜잭션 — 구매 경로와 Transaction.updates 리스너가 같은 건을 두 번
    /// 세지 않게 하는 유일한 방어선(소모품은 매번 새 id라 id 집합으로만 구분된다).
    /// 문자열로 담는다 — plist 정수는 부호 있는 64비트라 UInt64를 그대로 넣지 않는다.
    private var counted: Set<String>
    private var updatesTask: Task<Void, Never>?

    private init() {
        let defaults = UserDefaults.standard
        cups = defaults.integer(forKey: Self.cupsKey)
        counted = Set(defaults.stringArray(forKey: Self.countedKey) ?? [])
    }

    /// 앱 실행 시 1회 — 앱 밖에서 완료된 거래(승인 대기 통과·다른 기기)를 받아 finish 한다.
    /// 안 걸어두면 그 거래가 큐에 남아 실행마다 다시 전달된다.
    func startListening() {
        guard updatesTask == nil else { return }
        updatesTask = Task {
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()
                record(transaction.id)
            }
        }
    }

    func load() async {
        if product != nil { return }
        status = .loading
        do {
            let items = try await Product.products(for: [Self.productID])
            if let first = items.first {
                product = first
                status = .ready
            } else {
                // 콘솔 미등록·심사 미승인 — 코드 문제가 아니다. 시험 빌드면 무료 지급으로 연다
                status = Self.isSandbox ? .ready : .unavailable
            }
        } catch {
            status = Self.isSandbox ? .ready : .unavailable
        }
    }

    func buy() async {
        guard status != .purchasing else { return }
        guard let product else {
            if Self.isSandbox { grantFree() }
            return
        }
        status = .purchasing
        do {
            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    record(transaction.id)
                    status = .thanks
                case .unverified(let transaction, _):
                    // 서명이 안 맞는 거래 — 잔은 세지 않되 큐에는 남기지 않는다
                    await transaction.finish()
                    status = .failed("영수증을 확인하지 못했어요")
                }
            case .userCancelled:
                status = .ready
            case .pending:
                status = .pending
            @unknown default:
                status = .ready
            }
        } catch {
            status = .failed("결제를 끝내지 못했어요")
        }
    }

    /// 말풍선을 닫았다 열 때 감사·실패 문구가 남아 있지 않게
    func rest() {
        switch status {
        case .thanks, .failed, .pending: status = product == nil ? .unavailable : .ready
        default: break
        }
    }

    /// 시험 지급 — 결제 없이 잔만 올린다. 트랜잭션이 없으므로 중복 방지 키도 없다.
    private func grantFree() {
        cups += 1
        UserDefaults.standard.set(cups, forKey: Self.cupsKey)
        status = .thanks
    }

    private func record(_ id: UInt64) {
        let key = String(id)
        guard !counted.contains(key) else { return }
        counted.insert(key)
        cups += 1
        let defaults = UserDefaults.standard
        defaults.set(cups, forKey: Self.cupsKey)
        defaults.set(counted.sorted(), forKey: Self.countedKey)
    }
}

// ── 캐릭터 — 브랜드 표식이 눈을 떴다 ──
/// `BrandMark`(12시가 끊긴 링 + 링 위 점) 위에 눈만 얹는다 — 링 위의 점이 머리 표식으로 남아
/// 로고를 해치지 않고 캐릭터가 된다. 흔들림은 관심을 끄는 손짓이라 §4 "상태 전환은 즉시"와
/// 별개 층(씨앗 획득 연출과 같은 놀이 언어).
struct TipMascot: View {
    var diameter: CGFloat = 26
    var color: Color = Ink.text
    /// 이미 커피를 받았으면 흔들지 않는다
    var resting: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt: Double = 0

    var body: some View {
        ZStack {
            BrandMark(diameter: diameter, color: color)
            eyes
        }
        .rotationEffect(.degrees(tilt), anchor: .bottom)
        // 화면에 뜨고 한 박자 뒤 첫 인사, 이후 6초마다 짧게. 계속 흔들면 배경 소음이 된다.
        // 루프를 통째로 이 클로저 안에 둔다 — 뷰 메서드로 쪼개면 Swift 6에서 격리가 갈린다.
        .task(id: resting) {
            guard !reduceMotion, !resting else {
                // 커피를 받는 순간 흔들다 멈추면 기울어진 채로 굳는다 — 바로 세운다
                withAnimation(.easeOut(duration: 0.2)) { tilt = 0 }
                return
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            while !Task.isCancelled {
                for angle in [-11.0, 9.0, -6.0, 3.0, 0.0] {
                    withAnimation(.spring(response: 0.17, dampingFraction: 0.45)) { tilt = angle }
                    try? await Task.sleep(nanoseconds: 105_000_000)
                }
                try? await Task.sleep(nanoseconds: 6_000_000_000)
            }
        }
    }

    private var eyes: some View {
        let size: CGFloat = diameter * 0.115
        let gap: CGFloat = diameter * 0.20
        return HStack(spacing: gap) {
            eye(size)
            eye(size)
        }
        .offset(y: diameter * 0.03)
    }

    private func eye(_ size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

// ── 말풍선 ──
/// 툴바 아이템에 붙이면 내비게이션 바 밖으로 잘려서, 화면 ZStack 위에 얹고 우상단 아래로
/// 정렬한다(꼬리가 캐릭터를 가리킨다). 바깥을 누르면 닫힌다.
struct TipBubble: View {
    let store: TipStore

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            BubbleTail()
                .fill(Ink.surface)
                .frame(width: 18, height: 9)
                .padding(.trailing, 14)
            card
        }
        .frame(maxWidth: 300, alignment: .trailing)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("혼자 만들고 있어요")
                .font(.almanac(size: 17, weight: .bold))
                .foregroundStyle(Ink.text)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Ink.text.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            actionRow
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .milkGlass()
    }

    private var message: String {
        if store.cups > 0 {
            return "커피 \(store.cups)잔을 받았어요. 당신의 친절 덕에 며칠 더 즐겁게 개발하게 됐어요!"
        }
        return "광고도 구독도 없이 만들고 있어요."
    }

    @ViewBuilder
    private var actionRow: some View {
        switch store.status {
        case .loading:
            note("잠시만요")
        case .unavailable:
            note("지금은 준비 중이에요")
        case .purchasing:
            note("결제 창을 여는 중이에요")
        case .pending:
            note("승인을 기다리는 중이에요")
        case .thanks:
            Label("잘 마실게요", systemImage: "checkmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Ink.text.opacity(0.6))
        case .failed(let reason):
            VStack(alignment: .leading, spacing: 8) {
                note(reason)
                buyButton
            }
        case .ready:
            buyButton
        }
    }

    @ViewBuilder
    private var buyButton: some View {
        if let label = buyLabel {
            Button {
                confirmHaptic()
                Task { await store.buy() }
            } label: {
                Text(label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Ink.paper)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Ink.text, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    /// 상품이 잡히면 실제 가격, 시험 빌드면 값 없이 「시험용」 표기(진짜 결제로 오인하지 않게)
    private var buyLabel: String? {
        if let product = store.product {
            return "커피 한 잔 · \(product.displayPrice)"
        }
        return store.isFreeTrial ? "커피 한 잔 (시험용)" : nil
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Ink.text.opacity(0.5))
    }
}

/// 위를 가리키는 꼬리 — 말풍선이 우상단 캐릭터에서 나온 것처럼
private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
