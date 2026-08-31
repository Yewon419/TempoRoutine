// 템포루틴 — 업적(기념 티켓) 표면 (2026-08-31, Achievements.swift 참조)
// 발권 배너(달성 순간) + 보관함(나의 템포 탭 진입 → 시트). 티켓은 **인쇄물** — 테마를 타지
// 않는 고정 흰 발권지 + 딥네이비 잉크(티켓 테마 상수 차용, 발권물은 지면이 뒤집히지 않는다).

import SwiftUI

// ── 티켓 잉크(테마 무관 고정) ──
private enum TicketInk {
    static let paper = TicketSpec.ticketPaper
    static let text = Color.flatRGB(0x22, 0x38, 0x4F)
    static let label = TicketSpec.label
    static let stamp = Color.flatRGB(0xA9, 0x32, 0x26)   // 검표 스탬프 레드
}

// ── 발권 배너 — 달성 순간 상단에서 내려오는 티켓 ──
struct AchievementBannerHost: View {
    // ⚠ @State 초기화로 shared를 잡으면 View init(비격리)에서 MainActor 접근이라 Swift 6가
    // 막는다 — body(MainActor)에서 computed로 읽는다. @Observable 추적은 body 읽기로 걸린다.
    private var store: Achievements { .shared }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            if let id = store.pendingBanner {
                banner(id)
                    .transition(reduceMotion ? .opacity
                                : .move(edge: .top).combined(with: .opacity))
                    .task(id: id) {
                        try? await Task.sleep(nanoseconds: 3_200_000_000)
                        dismiss()
                    }
                    .onTapGesture { dismiss() }
            }
            Spacer()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.pendingBanner)
        .allowsHitTesting(store.pendingBanner != nil)
    }

    private func dismiss() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
            store.advanceBanner()
        }
    }

    private func banner(_ id: AchievementID) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "ticket")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(TicketInk.stamp)
            VStack(alignment: .leading, spacing: 2) {
                Text("기념 티켓이 발권됐어요")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .kerning(1.4)
                    .foregroundStyle(TicketInk.label)
                Text(id.title)
                    .font(.almanacBody(.subheadline, size: 15, weight: .bold))
                    .foregroundStyle(TicketInk.text)
            }
            Spacer(minLength: 0)
            if let serial = Achievements.shared.serial(id) {
                Text(String(format: "NO. %03d", serial))
                    .font(.system(size: 9, design: .monospaced))
                    .kerning(1.2)
                    .foregroundStyle(TicketInk.label)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(TicketInk.paper)
                .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Loc.fmt("기념 티켓 발권: %1$@", id.title))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Loc.str("탭하면 닫습니다"))
    }
}

// ── 보관함 — 발권된 티켓과 남은 자리 전부 ──
struct AchievementShelfView: View {
    @Environment(\.dismiss) private var dismiss
    /// 원장 방송 — 시트가 열린 채 달성돼도 갱신되게(씨앗 revisionKey 전례)
    @AppStorage(Achievements.revisionKey) private var revision = 0

    private var store: Achievements { Achievements.shared }

    /// 정렬 — 달성(최신 먼저) → 미달성(정의 순) → 히든 미달성(맨 뒤)
    private var ordered: [AchievementID] {
        let unlocked = AchievementID.allCases
            .filter { store.isUnlocked($0) }
            .sorted { (store.unlockedDate($0) ?? .distantPast) > (store.unlockedDate($1) ?? .distantPast) }
        let locked = AchievementID.allCases.filter { !store.isUnlocked($0) && !$0.hidden }
        let hidden = AchievementID.allCases.filter { !store.isUnlocked($0) && $0.hidden }
        return unlocked + locked + hidden
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(Loc.fmt("모은 티켓 %1$@ / %2$@", "\(store.unlockedCount)", "\(store.totalCount)"))
                            .font(.almanacBody(.footnote, size: 13))
                            .foregroundStyle(Ink.text.opacity(0.6))
                        ForEach(ordered, id: \.self) { id in
                            AchievementTicket(id: id,
                                              unlockedAt: store.unlockedDate(id),
                                              serial: store.serial(id))
                        }
                    }
                    .padding(20)
                    .centeredColumn(640)
                }
            }
            .navigationTitle("기념 티켓")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }.foregroundStyle(Ink.text)
                }
            }
        }
        .themeColorScheme()
        // 방송 카운터 참조 — 없으면 컴파일러가 미사용으로 접고 갱신도 안 온다
        .id(revision)
    }
}

// ── 티켓 한 장 — 달성 = 발권물 / 미달성 = 빈 자리 점선 / 히든 미달성 = ??? ──
struct AchievementTicket: View {
    let id: AchievementID
    let unlockedAt: Date?
    let serial: Int?

    private var unlocked: Bool { unlockedAt != nil }

    var body: some View {
        if unlocked {
            issued
        } else {
            placeholder
        }
    }

    /// 발권된 티켓 — 흰 발권지 + 좌측 스탬프 + 우측 일련·세로 절취선
    private var issued: some View {
        HStack(spacing: 12) {
            Image(systemName: "ticket")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(TicketInk.stamp)
            VStack(alignment: .leading, spacing: 3) {
                Text(id.title)
                    .font(.almanacBody(.subheadline, size: 15, weight: .bold))
                    .foregroundStyle(TicketInk.text)
                Text(id.caption)
                    .font(.almanacBody(.caption, size: 12))
                    .foregroundStyle(TicketInk.text.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if let serial {
                    Text(String(format: "NO. %03d", serial))
                        .font(.system(size: 9, design: .monospaced))
                        .kerning(1.2)
                }
                if let unlockedAt {
                    Text(unlockedAt.formatted(Loc.dateTime.year().month().day()))
                        .font(.system(size: 9, design: .monospaced))
                }
            }
            .foregroundStyle(TicketInk.label)
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                // 세로 절취선(티켓 스텁 문법)
                Rectangle()
                    .fill(TicketInk.text.opacity(0.28))
                    .frame(width: 1)
                    .mask(VStack(spacing: 3) {
                        ForEach(0..<8, id: \.self) { _ in Rectangle().frame(height: 3) }
                    })
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(TicketInk.paper)
                .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// 미발권 자리 — 히든은 정체를 감춘다("???")
    private var placeholder: some View {
        HStack(spacing: 12) {
            Image(systemName: id.hidden ? "questionmark" : "ticket")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Ink.text.opacity(0.3))
            VStack(alignment: .leading, spacing: 3) {
                Text(id.hidden ? "???" : id.title)
                    .font(.almanacBody(.subheadline, size: 15, weight: .bold))
                    .foregroundStyle(Ink.text.opacity(0.45))
                Text(id.hidden ? Loc.str("발견하면 알게 돼요") : id.caption)
                    .font(.almanacBody(.caption, size: 12))
                    .foregroundStyle(Ink.text.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Ink.text.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .accessibilityElement(children: .combine)
    }
}
