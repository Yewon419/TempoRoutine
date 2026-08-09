// 템포루틴 — 테마 탭 (2026-08-09 사용자 지시, §8.2.6·§3.8.1)
// 진입 = 설정 「테마」 행 + 오늘 탭 씨앗 배지 탭. 구매 언어 = 「심기」(상거래 밖 — §3.8.1,
// 돈 문법 금지). 가격: 모던 = 씨앗 7개(2026-08-09 사용자 확정 — §3.8.1 미결 ① 해소).
// 미리보기·엠블럼은 활성 테마와 무관하게 각 테마의 팔레트 리터럴로 그린다(Ink 미사용) —
// 지금 무슨 테마를 쓰든 다른 테마의 얼굴이 제 색으로 보여야 미리보기다.

import SwiftUI
import SwiftData

extension AppTheme {
    /// 씨앗 가격 — nil = 기본(무료 상시 보유). §3.8.1 미결 ① 확정값.
    var seedPrice: Int? {
        switch self {
        case .standard: nil
        case .modern: 7
        }
    }

    var palette: ThemePalette {
        self == .modern ? .modern : .standard
    }

    var shopCaption: String {
        switch self {
        case .standard: "은필과 종이. 템포루틴의 기본 지면이에요."
        case .modern: "니어블랙 지면에 다홍 한 점. 밤의 얼굴이에요."
        }
    }
}

struct ThemeShopView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var checkIns: [DailyCheckIn]
    @AppStorage(ThemeStore.storageKey) private var appTheme = AppTheme.standard.rawValue
    /// planted는 UserDefaults라 뷰 갱신이 안 걸린다 — 화면 수명 동안의 사본으로 렌더한다.
    @State private var plantedSet: Set<String> = []
    @State private var lightFeedback = 0

    private var current: AppTheme { AppTheme(rawValue: appTheme) ?? .standard }
    private var available: Int { Seeds.available(checkIns) }

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        ForEach(AppTheme.allCases) { theme in
                            themeCard(theme)
                        }
                        Text("씨앗은 하루 체크인을 완성하면 하나씩 모여요.")
                            .font(.caption)
                            .foregroundStyle(Ink.text.opacity(0.45))
                    }
                    .padding(20)
                    .centeredColumn(640)
                }
            }
            .navigationTitle("테마")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }.foregroundStyle(Ink.text)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: lightFeedback)
        .onAppear {
            // 이미 모던을 쓰던 베타 기기 = 심긴 것으로 승계 — 쓰던 테마를 잠그지 않는다(신뢰)
            if current == .modern {
                var planted = Seeds.planted
                planted.insert(AppTheme.modern.rawValue)
                Seeds.planted = planted
            }
            plantedSet = Seeds.planted
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("모은 씨앗으로\n새 지면을 심을 수 있어요.")
                .font(.almanacBody(.subheadline, size: 16, weight: .bold))
                .foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            SeedBadge(count: available)
        }
    }

    private func isPlanted(_ theme: AppTheme) -> Bool {
        theme.seedPrice == nil || plantedSet.contains(theme.rawValue)
    }

    private func themeCard(_ theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ThemeEmblem(palette: theme.palette)
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.displayName)
                        .font(.almanac(size: 20, weight: .bold))
                        .foregroundStyle(Ink.text)
                    Text(theme.shopCaption)
                        .font(.footnote)
                        .foregroundStyle(Ink.text.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            ThemePreview(theme: theme)
            actionRow(theme)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .milkGlass()
    }

    @ViewBuilder
    private func actionRow(_ theme: AppTheme) -> some View {
        if current == theme {
            Label("적용 중", systemImage: "checkmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Ink.text.opacity(0.55))
        } else if isPlanted(theme) {
            Button {
                apply(theme)
            } label: {
                Text("적용하기")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Ink.paper)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Ink.text, in: Capsule())
            }
        } else if let price = theme.seedPrice {
            if available >= price {
                Button {
                    plant(theme, price: price)
                } label: {
                    HStack(spacing: 6) {
                        SeedGlyph()
                            .fill(Ink.paper)
                            .frame(width: 8, height: 11)
                            .rotationEffect(.degrees(16))
                        Text("씨앗 \(price)개 심기")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(Ink.paper)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Ink.text, in: Capsule())
                }
            } else {
                // 재촉 금지(§7) — 사실만: 몇 개가 더 필요한지
                HStack(spacing: 6) {
                    SeedGlyph()
                        .fill(Ink.text.opacity(0.4))
                        .frame(width: 8, height: 11)
                        .rotationEffect(.degrees(16))
                    Text("씨앗 \(price)개로 심을 수 있어요 · 지금 \(available)개")
                        .font(.footnote)
                        .foregroundStyle(Ink.text.opacity(0.55))
                }
            }
        }
    }

    /// 선 apply → AppStorage 갱신(설정과 같은 경로 — 루트 `.id` 리빌드가 전 화면을 갈아입힌다).
    /// 리빌드로 이 시트도 함께 닫힌다 — 새 지면이 곧바로 보이는 게 자연스러운 마무리.
    private func apply(_ theme: AppTheme) {
        confirmHaptic()
        ThemeStore.apply(theme.rawValue)
        appTheme = theme.rawValue
    }

    private func plant(_ theme: AppTheme, price: Int) {
        guard Seeds.plant(theme, price: price, checkIns: checkIns) else { return }
        plantedSet = Seeds.planted
        apply(theme)   // 심으면 바로 그 지면으로 — 확정 햅틱은 apply가 담당
    }
}

// ── 테마 엠블럼 — 주기 원 + 겨울 점(브랜드 모티프)을 그 테마의 팔레트로 ──
struct ThemeEmblem: View {
    let palette: ThemePalette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.paper)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.text.opacity(0.15), lineWidth: 1))
            Circle()
                .stroke(palette.accent, lineWidth: 1.6)
                .frame(width: 24, height: 24)
            Circle()
                .fill(palette.winter)
                .frame(width: 5, height: 5)
                .offset(y: -12)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

// ── 테마 미리보기 — 오늘 탭 축소 흉내(표제·계절 도트·카드 표면)를 그 테마의 색으로 ──
struct ThemePreview: View {
    let theme: AppTheme

    private var titleFont: Font {
        if theme == .modern {
            return ThemeFont.available ? .custom("Pretendard-SemiBold", size: 22)
                                       : .system(size: 22, weight: .semibold)
        }
        return AlmanacFont.available ? .custom("GowunBatang-Bold", size: 22)
                                     : .system(size: 22, weight: .bold, design: .serif)
    }

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("8월")
                    .font(titleFont)
                    .foregroundStyle(p.text)
                Text("2026")
                    .font(.caption)
                    .foregroundStyle(p.text.opacity(0.5))
                Spacer(minLength: 0)
                // 계절 도트 — 표시 순서(봄→여름→가을→겨울, §8.1)
                HStack(spacing: 5) {
                    Circle().fill(p.spring).frame(width: 7, height: 7)
                    Circle().fill(p.summer).frame(width: 7, height: 7)
                    Circle().fill(p.autumn).frame(width: 7, height: 7)
                    Circle().fill(p.winter).frame(width: 7, height: 7)
                }
            }
            RoundedRectangle(cornerRadius: 9)
                .fill(p.surface)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(p.accent.opacity(0.18), lineWidth: 1))
                .overlay(alignment: .leading) {
                    HStack(spacing: 8) {
                        Circle().fill(p.accent).frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 4) {
                            Capsule().fill(p.text.opacity(0.55)).frame(width: 64, height: 5)
                            Capsule().fill(p.text.opacity(0.25)).frame(width: 96, height: 5)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(height: 46)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(p.paper))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.text.opacity(0.12), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(theme.displayName) 테마 미리보기")
    }
}
