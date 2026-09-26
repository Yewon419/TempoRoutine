// 템포루틴 — 씨앗 쿠폰 (2026-09-26 대표님 지시 "피드백 창에서 특정 코드 입력하면 씨앗 제공 메세지,
// 받기 누르면 씨앗 받아지는 모션과 함께 씨앗 추가")
//
// 목록 = notices/notices.json의 `coupons`(소식과 같은 GET 한 번, 배포 불필요).
// 리포가 public이라 코드 원문은 싣지 않는다: 피드백 입력칸과 같은 정규화(소문자·공백 제거)를
// 거친 코드의 SHA-256 hex만 싣고, 앱이 입력을 해시해 대조한다. 등록 = tools/make_coupon.py.
// 수령은 공지 씨앗과 같은 원장 창구(Seeds.claim — id별 1회, 동기화·백업 동승).
// 원장 키 "coupon:<id>"로 공지 id와 이름공간을 가른다.

import CryptoKit
import SwiftUI

struct Coupon: Codable, Equatable {
    let id: String
    let hash: String
    let seeds: Int

    var ledgerID: String { "coupon:\(id)" }

    var claimed: Bool { Seeds.claimedNotices.contains(ledgerID) }

    static func digest(_ normalized: String) -> String {
        SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// 쿠폰 메시지 — 소식 화면 위로 뜨는 카드. 「받기」 = 원장 기입 + 씨앗이 버튼에서 부채꼴로
/// 피어올라 흩어지고 머리 글리프가 한 번 튄다(성공 햅틱), 잠시 뒤 스스로 닫힌다.
/// 이미 받은 쿠폰은 안내만.
struct CouponMessage: View {
    let coupon: Coupon
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var alreadyClaimed: Bool
    @State private var received = false
    @State private var flying = false
    @State private var rising = false
    @State private var pulse = false
    @State private var shown = false

    init(coupon: Coupon, onClose: @escaping () -> Void) {
        self.coupon = coupon
        self.onClose = onClose
        _alreadyClaimed = State(initialValue: coupon.claimed)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { if !received { onClose() } }
            card
                .scaleEffect(shown || reduceMotion ? 1 : 0.9)
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.72)) { shown = true }
        }
        .sensoryFeedback(.success, trigger: received)
    }

    private var card: some View {
        VStack(spacing: 14) {
            headGlyph
            Text(alreadyClaimed ? Loc.str("이미 받은 쿠폰이에요") : Loc.str("씨앗이 도착했어요"))
                .font(.almanac(size: 20, weight: .bold))
                .foregroundStyle(Ink.text)
                .multilineTextAlignment(.center)
            Text(alreadyClaimed
                 ? Loc.str("쿠폰 하나당 한 번만 받을 수 있어요.")
                 : Loc.fmt("씨앗 %lld개를 보내 드려요. 아래 버튼을 눌러 받아 가세요.", coupon.seeds))
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.8))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            action
                .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
        .padding(.bottom, 22)
        .frame(maxWidth: 320)
        .background(Ink.paper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(Ink.text.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .padding(.horizontal, 28)
    }

    private var headGlyph: some View {
        let scale: CGFloat = pulse ? 1.25 : 1
        return SeedGlyph()
            .fill(Ink.text.opacity(0.85))
            .frame(width: 24, height: 32)
            .rotationEffect(.degrees(16))
            .scaleEffect(scale)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var action: some View {
        if alreadyClaimed {
            Button(Loc.str("확인")) { onClose() }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Ink.text)
                .padding(.horizontal, 22)
                .padding(.vertical, 9)
                .overlay(Capsule().stroke(Ink.text.opacity(0.25), lineWidth: 1))
        } else if received {
            Label(Loc.fmt("씨앗 %lld개를 받았어요", coupon.seeds), systemImage: "checkmark.seal")
                .font(.footnote)
                .foregroundStyle(Ink.text.opacity(0.6))
                .padding(.vertical, 9)
                .overlay { burst }
        } else {
            Button(action: receive) {
                HStack(spacing: 6) {
                    SeedGlyph()
                        .fill(Ink.paper)
                        .frame(width: 8, height: 11)
                        .rotationEffect(.degrees(16))
                    Text(Loc.fmt("씨앗 %lld개 받기", coupon.seeds))
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(Ink.paper)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Ink.text, in: Capsule())
            }
        }
    }

    private var burst: some View {
        ZStack {
            ForEach(0..<CouponMessage.burstCount, id: \.self) { index in
                burstSeed(index)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static let burstCount = 7

    private func burstSeed(_ index: Int) -> some View {
        let spread: CGFloat = CGFloat(index - CouponMessage.burstCount / 2)
        let fanX: CGFloat = spread * 26
        let fanY: CGFloat = -46 + abs(spread) * 6
        let drift: CGFloat = rising ? -44 : 0
        let offset: CGSize = flying ? CGSize(width: fanX, height: fanY + drift) : .zero
        let opacity: Double = rising ? 0 : (flying ? 1 : 0)
        return SeedGlyph()
            .fill(Ink.text.opacity(0.8))
            .frame(width: 10, height: 13)
            .rotationEffect(.degrees(flying ? Double(spread) * 18 + 16 : 16))
            .scaleEffect(flying ? 1 : 0.2)
            .offset(offset)
            .opacity(opacity)
    }

    private func receive() {
        guard Seeds.claim(noticeID: coupon.ledgerID, seeds: coupon.seeds) else {
            alreadyClaimed = true
            return
        }
        received = true
        if reduceMotion {
            closeSoon(after: 1.2)
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000)
            withAnimation(.spring(response: 0.42, dampingFraction: 0.6)) { flying = true }
            try? await Task.sleep(nanoseconds: 480_000_000)
            withAnimation(.easeIn(duration: 0.45)) { rising = true }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.45)) { pulse = true }
            try? await Task.sleep(nanoseconds: 260_000_000)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { pulse = false }
            closeSoon(after: 1.0)
        }
    }

    private func closeSoon(after seconds: Double) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            withAnimation(.easeOut(duration: 0.2)) { shown = false }
            try? await Task.sleep(nanoseconds: 200_000_000)
            onClose()
        }
    }
}
