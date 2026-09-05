// 템포루틴 — 업적(기념 배지) 표면 (2026-08-31 신설 → 2026-09-04 배지로 교체)
//
// 획득 배너(달성 순간, 하단 파티클 동반) + 보관함(나의 템포 탭 → 시트).
// 2026-09-04 베타 2건 반영: ① 「티켓 말고 배지로 바꾸자」 — 발권물 문법(흰 발권지·절취선·
// NO. 일련번호)을 걷고 **원형 배지**로 바꿨다. 배지는 지면 위에 놓이는 물건이라 테마 팔레트를
// 그대로 탄다(발권물만 테마 무관 흰 종이였다). ② 「달성 시 아래에서 파티클 빵 터뜨려줘」.
//
// 파티클은 화면 **아래에서 위로** 솟는다. 난수는 인덱스로 한 번만 만들어 두고(body에서 뽑으면
// 프레임마다 값이 바뀐다) reduce motion이면 아예 그리지 않는다.

import SwiftUI

// ── 배지 한 알 ──
/// 획득 = 먹색 채움 + 종이색 기호 / 미획득 = 점선 링 + 흐린 기호 / 히든 미획득 = 물음표
struct AchievementBadge: View {
    let id: AchievementID
    let unlocked: Bool
    var diameter: CGFloat = 52

    private var hiddenLocked: Bool { !unlocked && id.hidden }

    var body: some View {
        ZStack {
            if unlocked {
                Circle().fill(Ink.text)
                Circle().stroke(Ink.paper.opacity(0.35), lineWidth: 1).padding(3)
            } else {
                Circle().stroke(Ink.text.opacity(0.25),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            Image(systemName: hiddenLocked ? "questionmark" : id.symbol)
                .font(.system(size: diameter * 0.36, weight: .medium))
                .foregroundStyle(unlocked ? Ink.paper : Ink.text.opacity(0.3))
        }
        .frame(width: diameter, height: diameter)
    }
}

// ── 획득 배너 — 달성 순간 상단에서 내려오는 카드 + 하단 파티클 ──
struct AchievementBannerHost: View {
    // ⚠ @State 초기화로 shared를 잡으면 View init(비격리)에서 MainActor 접근이라 Swift 6가
    // 막는다 — body(MainActor)에서 computed로 읽는다. @Observable 추적은 body 읽기로 걸린다.
    private var store: Achievements { .shared }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if let id = store.pendingBanner {
                if !reduceMotion {
                    CelebrationBurst()
                        .id(id)   // 업적이 바뀌면 처음부터 다시 터진다
                        .allowsHitTesting(false)
                }
                banner(id)
                    .transition(reduceMotion ? .opacity
                                : .move(edge: .top).combined(with: .opacity))
                    .task(id: id) {
                        try? await Task.sleep(nanoseconds: 3_200_000_000)
                        dismiss()
                    }
                    .onTapGesture { dismiss() }
            }
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
            AchievementBadge(id: id, unlocked: true, diameter: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("기념 배지를 받았어요")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .kerning(1.4)
                    .foregroundStyle(Ink.text.opacity(0.5))
                Text(id.title)
                    .font(.almanacBody(.subheadline, size: 15, weight: .bold))
                    .foregroundStyle(Ink.text)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            // 떠 있는 것은 지면 문법을 안 쓴다(TipBubble 전례) — 불투명 지면 + 카드색
            RoundedRectangle(cornerRadius: 16)
                .fill(Ink.paper)
                .overlay { RoundedRectangle(cornerRadius: 16).fill(Ink.surface) }
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Loc.fmt("기념 배지 획득: %1$@", id.title))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Loc.str("탭하면 닫습니다"))
    }
}

// ── 파티클 — 화면 아래에서 솟아오르는 색 조각(2026-09-04 베타) ──
private struct CelebrationBurst: View {
    /// 한 조각의 궤적. 난수는 여기서 **한 번만** 뽑는다(body에서 뽑으면 프레임마다 달라진다).
    private struct Fleck: Identifiable {
        let id: Int
        let x: CGFloat          // 가로 위치 비율 0~1
        let rise: CGFloat       // 솟는 높이(pt)
        let drift: CGFloat      // 좌우 흔들림(pt)
        let size: CGFloat
        let spin: Double
        let delay: Double
        let color: Color
    }

    private let flecks: [Fleck]
    @State private var launched = false

    init() {
        let palette: [Color] = [Ink.winter, Ink.spring, Ink.summer, Ink.autumn]
        var made: [Fleck] = []
        for index in 0..<22 {
            made.append(Fleck(id: index,
                              x: CGFloat.random(in: 0.08...0.92),
                              rise: CGFloat.random(in: 260...520),
                              drift: CGFloat.random(in: -70...70),
                              size: CGFloat.random(in: 5...10),
                              spin: Double.random(in: -220...220),
                              delay: Double(index) * 0.018,
                              color: palette[index % palette.count]))
        }
        flecks = made
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                ForEach(flecks) { fleck in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(fleck.color)
                        .frame(width: fleck.size, height: fleck.size * 1.6)
                        .rotationEffect(.degrees(launched ? fleck.spin : 0))
                        .opacity(launched ? 0 : 1)
                        .offset(x: geo.size.width * fleck.x + (launched ? fleck.drift : 0),
                                y: launched ? -fleck.rise : 12)
                        .animation(.easeOut(duration: 1.5).delay(fleck.delay), value: launched)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .ignoresSafeArea()
        .onAppear { launched = true }
        .accessibilityHidden(true)
    }
}

// ── 보관함 — 받은 배지와 남은 자리 전부 ──
struct AchievementShelfView: View {
    @Environment(\.dismiss) private var dismiss
    /// 원장 방송 — 시트가 열린 채 달성돼도 갱신되게(씨앗 revisionKey 전례)
    @AppStorage(Achievements.revisionKey) private var revision = 0

    private var store: Achievements { Achievements.shared }

    /// 정렬 — 획득(최신 먼저) → 미획득(정의 순) → 히든 미획득(맨 뒤)
    private var ordered: [AchievementID] {
        let unlocked = AchievementID.allCases
            .filter { store.isUnlocked($0) }
            .sorted { (store.unlockedDate($0) ?? .distantPast) > (store.unlockedDate($1) ?? .distantPast) }
        let locked = AchievementID.allCases.filter { !store.isUnlocked($0) && !$0.hidden }
        let hidden = AchievementID.allCases.filter { !store.isUnlocked($0) && $0.hidden }
        return unlocked + locked + hidden
    }

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 12)]

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(Loc.fmt("모은 배지 %1$@ / %2$@", "\(store.unlockedCount)", "\(store.totalCount)"))
                            .font(.almanacBody(.footnote, size: 13))
                            .foregroundStyle(Ink.text.opacity(0.6))
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(ordered, id: \.self) { id in
                                AchievementCell(id: id, unlockedAt: store.unlockedDate(id))
                            }
                        }
                    }
                    .padding(20)
                    .centeredColumn(640)
                }
            }
            .navigationTitle("기념 배지")
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

// ── 보관함 한 칸 ──
struct AchievementCell: View {
    let id: AchievementID
    let unlockedAt: Date?

    private var unlocked: Bool { unlockedAt != nil }
    private var hiddenLocked: Bool { !unlocked && id.hidden }

    var body: some View {
        VStack(spacing: 8) {
            AchievementBadge(id: id, unlocked: unlocked)
            Text(hiddenLocked ? "???" : id.title)
                .font(.almanacBody(.subheadline, size: 14, weight: .bold))
                .foregroundStyle(Ink.text.opacity(unlocked ? 1 : 0.45))
                .multilineTextAlignment(.center)
                .lineLimit(1)
            // 설명 줄 수가 1~2로 갈려 칸 높이가 제각각이었다(2026-09-05 베타 "칸이 제각각이야").
            // 두 줄 자리를 미리 잡아 두고, 남는 높이는 아래 maxHeight가 행에 맞춰 늘린다.
            Text(hiddenLocked ? Loc.str("발견하면 알게 돼요") : id.caption)
                .font(.almanacBody(.caption, size: 11))
                .foregroundStyle(Ink.text.opacity(unlocked ? 0.6 : 0.35))
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
            Spacer(minLength: 0)
            if let unlockedAt {
                Text(unlockedAt.formatted(Loc.dateTime.year().month().day()))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Ink.text.opacity(0.45))
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        // 행 안에서 가장 높은 칸에 맞춰 늘어난다 — 격자가 들쭉날쭉하지 않게
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .milkGlass()
        .accessibilityElement(children: .combine)
    }
}
