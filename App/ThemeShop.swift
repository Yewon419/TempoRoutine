// 템포루틴 — 테마 탭 (2026-08-09 사용자 지시, §8.2.6·§3.8.1)
// 진입 = 설정 「테마」 행 + 오늘 탭 씨앗 배지 탭. UI 언어 = 평문 「구매」·「적용」(2026-08-09
// 2차 번복 — 「심기」는 "너무 추상적". 코드 식별자 plant/planted는 유지, 사용자 표면만 평문).
// 가격(2026-08-27 대표님 확정): 기본·은필 20 / 포인트컬러·날씨 50 / 활판·티켓·플리 100(₩5,000
// IAP 병행은 Phase 2). 구 가격표(모던 7 등)는 원장 호환으로만 남는다.
// 미리보기·엠블럼은 활성 테마와 무관하게 각 테마의 팔레트 리터럴로 그린다(Ink 미사용) —
// 지금 무슨 테마를 쓰든 다른 테마의 얼굴이 제 색으로 보여야 미리보기다.

import SwiftUI
import SwiftData
import UIKit   // openSettingsURLString(날씨 위치 게이트)

extension AppTheme {
    /// 씨앗 가격 — 3단 가격표(2026-08-27 대표님 확정): 기본·은필 20 / 포인트컬러·날씨 50 /
    /// 활판·티켓·플리 100(또는 ₩5,000 IAP — Phase 2). **무료 테마는 더 없다** — 소유의 뿌리는
    /// 체험 종료 시트의 기본/은필 택1(0원 승계)이다. 구 가격(은필·모던 7, 나머지 무료)으로 산
    /// 사람은 원장이 그대로 소유를 말한다(재과금 없음).
    /// ⚠ nil 반환이 사라졌지만 시그니처는 유지한다 — `seedPrice == nil` 분기(무료 판정)들이
    /// 자연히 "해당 없음"이 되는 쪽이 안전하다.
    var seedPrice: Int? {
        switch self {
        case .plain: 20
        case .standard: 20
        case .modern: 50
        case .weather: 50
        case .letterpress: 100
        case .ticket: 100
        case .playlist: 100
        }
    }

    var shopCaption: String {
        switch self {
        case .plain: Loc.str("심플 테마.")
        case .standard: Loc.str("은필과 종이. 계절이 빛으로 스며드는 지면이에요.")
        case .modern: Loc.str("기본 지면에 단색 한 점. 계절은 밝기로 갈려요.")
        case .ticket: Loc.str("색면 위에 놓인 한 장의 티켓. 일상을 여행처럼.")
        case .letterpress: Loc.str("종이에 눌러 새긴 하루. 잉크 없는 음각의 물성.")
        case .playlist: Loc.str("지금 재생 중인 계절. 하루가 트랙처럼 흘러요.")
        case .weather: Loc.str("지면이 곧 오늘의 하늘. 시간과 날씨가 화면을 물들여요.")
        }
    }
}

struct ThemeShopView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var checkIns: [DailyCheckIn]
    @AppStorage(ThemeStore.storageKey) private var appTheme = AppTheme.plain.rawValue
    /// 포인트컬러의 선택 색(2026-08-17) — 테마와 별개 키라 테마를 오갔다 돌아와도 남는다
    @AppStorage(PointColor.storageKey) private var pointColor = PointColor.vermilion.rawValue
    /// 원장 방송 카운터 — 생 UserDefaults 읽기는 무효화가 안 걸려서, 이 키를 지켜봐야 구매 직후와
    /// 동기화로 내려온 다른 기기의 구매가 화면에 반영된다(2026-08-11).
    @AppStorage(Seeds.revisionKey) private var seedRevision = 0
    @State private var lightFeedback = 0
    // 심기 플로우(2026-08-09 사용자 지시 — 확인 → 축하 연출 → 성공 메시지. 심기와 적용은 분리)
    @State private var plantCandidate: AppTheme?   // 확인 다이얼로그 대상
    @State private var sprout: AppTheme?           // 새싹 축하 연출 중인 카드
    @State private var plantedAlert: AppTheme?     // 성공 알럿(연출 뒤 한 박자 늦게)
    // 테마 패스(₩5,000 IAP, 2026-08-27 Phase 2)
    @State private var passStore = ThemePassStore.shared
    @State private var purchasedByPass = false     // 성공 알럿 문구 분기(씨앗 vs 결제)
    @State private var passFailedAlert = false
    @State private var restoreResult: Int?         // 복원 결과 알럿(nil = 닫힘)
    @State private var restoring = false           // 복원 대기(AppStore.sync는 수 초 걸린다)
    @State private var celebrateTick = 0           // 성공 햅틱
    // 커피 한 잔(2026-08-11) — 우상단 캐릭터 + 말풍선. 씨앗 트랙 밖의 팁이다(§3.8).
    private var tips = TipStore.shared
    @State private var showTip = false
    /// 미리보기 시트(2026-08-18 사용자 지시) — 하드코딩 목업 화면
    @State private var previewing: AppTheme?
    /// 날씨 위치 게이트(2026-08-19) — 거부 시 적용 차단 + 설정 안내
    @State private var showWeatherLocationAlert = false
    @Environment(\.openURL) private var openURL

    private var current: AppTheme { AppTheme(rawValue: appTheme) ?? .plain }
    private var available: Int { Seeds.available(checkIns) }

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        // 7일 무료 체험 안내(2026-08-19) — 기간은 사실만, 재촉 문구 금지(§7)
                        if ThemeTrial.isActive {
                            Text(Loc.fmt("지금은 무료 체험 기간이에요. %1$@일 동안 모든 테마를 자유롭게 바꿔볼 수 있어요.", "\(ThemeTrial.daysLeft)"))
                                .font(.footnote)
                                .foregroundStyle(Ink.text.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(AppTheme.allCases) { theme in
                            themeCard(theme)
                        }
                        Text("씨앗은 하루 체크인을 완성하면 하나씩 모여요.")
                            .font(.caption)
                            .foregroundStyle(Ink.text.opacity(0.45))
                        // 구매 복원(2026-08-27) — 비소모품(₩5,000 패스)의 심사 요구 버튼.
                        // 기기 교체·재설치 후 애플 결제 소유를 원장에 되새긴다.
                        // AppStore.sync()는 계정 확인 때문에 수 초 걸린다 — 누른 뒤 아무 반응이
                        // 없으면 씹힌 걸로 읽힌다(2026-08-27 결제 대기 피드백과 같은 뿌리).
                        if restoring {
                            HStack(spacing: 7) {
                                ProgressView().controlSize(.small).tint(Ink.text.opacity(0.45))
                                Text(Loc.str("구매를 확인하는 중이에요"))
                                    .font(.caption)
                                    .foregroundStyle(Ink.text.opacity(0.45))
                            }
                        } else {
                            Button(Loc.str("구매 복원")) {
                                lightFeedback += 1
                                restoring = true
                                Task { @MainActor in
                                    restoreResult = await ThemePassStore.shared.restore()
                                    restoring = false
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(Ink.text.opacity(0.45))
                            .underline()
                        }
                    }
                    .padding(20)
                    .centeredColumn(640)
                }
                tipLayer
            }
            .navigationTitle("테마")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }.foregroundStyle(Ink.text)
                }
                ToolbarItem(placement: .confirmationAction) { mascotButton }
            }
        }
        // 첫 진입 안내(2026-08-12 사용자 지시) — 잔액이 무엇인지, 구매와 적용이 왜 따로인지.
        // NavigationStack 바깥에 붙여 시트 전체(툴바 포함)를 덮는다.
        .coachOverlay(id: .themeShop, steps: CoachSteps.themeShop)
        .task { await tips.load(); await passStore.load() }
        .sensoryFeedback(.impact(weight: .light), trigger: lightFeedback)
        .sensoryFeedback(.success, trigger: celebrateTick)
        // 구매 확인(2026-08-09) — 씨앗을 쓰는 확정 액션이라 한 번 묻는다(§8.2.6 확인 문법)
        .confirmationDialog(
            plantCandidate.map { Loc.fmt("「%1$@」 구매", "\($0.displayName)") } ?? "",
            isPresented: Binding(get: { plantCandidate != nil },
                                 set: { if !$0 { plantCandidate = nil } }),
            titleVisibility: .visible
        ) {
            if let price = plantCandidate?.seedPrice {
                Button(Loc.fmt("씨앗 %lld개로 구매", price)) {
                    if let theme = plantCandidate { plant(theme) }
                    plantCandidate = nil
                }
            }
            Button("취소", role: .cancel) { plantCandidate = nil }
        }
        // 성공 메시지(연출 한 박자 뒤) — 구매와 적용이 분리라 여기서 적용을 권한다
        .alert(plantedAlert.map { Loc.fmt("「%1$@」을 구매했어요", "\($0.displayName)") } ?? "",
               isPresented: Binding(get: { plantedAlert != nil },
                                    set: { if !$0 { plantedAlert = nil } }),
               presenting: plantedAlert) { theme in
            Button("지금 적용하기") { apply(theme) }
            Button("나중에") { plantedAlert = nil }
        } message: { theme in
            Text(purchasedByPass ? Loc.str("결제가 완료됐어요.")
                                 : Loc.fmt("씨앗 %lld개를 썼어요.", theme.seedPrice ?? 0))
        }
        .sheet(item: $previewing) { theme in
            ThemePreviewScreen(theme: theme)
        }
        .alert("결제를 끝내지 못했어요", isPresented: $passFailedAlert) {
            Button("확인") {}
        } message: {
            Text("결제가 이루어지지 않았어요. 잠시 뒤에 다시 시도해 주세요.")
        }
        .alert(restoreResult.map { $0 > 0 ? Loc.str("구매를 복원했어요.") : Loc.str("복원할 구매가 없어요.") } ?? "",
               isPresented: Binding(get: { restoreResult != nil },
                                    set: { if !$0 { restoreResult = nil } })) {
            Button("확인") { restoreResult = nil }
        }
        // 날씨 위치 게이트(2026-08-19) — 시스템 설정의 위치 허가로 보낸다
        .alert("위치 허가가 필요해요", isPresented: $showWeatherLocationAlert) {
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("날씨 테마는 지금 계신 곳의 하늘을 그려요. 설정 > 위치에서 접근을 허용하면 쓸 수 있어요.")
        }
        // (2026-08-27) 종전의 onAppear 승계 벨트("쓰는 유료 테마 = 0원 보유")는 제거 —
        // 전 테마 유료화 뒤엔 「체험 중 아무 테마나 적용 → 탭 열면 공짜 소유」 구멍이 된다.
        // 기존 설치 승계는 앱 시작의 1회성 마이그레이션(TempoRoutineApp)이 담당한다.
    }

    // ── 커피 한 잔 (2026-08-11) ──
    /// 말풍선은 툴바 아이템에 붙이면 내비게이션 바 밖으로 잘린다 — 화면 ZStack 위에 얹고
    /// 우상단 아래로 정렬해 꼬리가 캐릭터를 가리키게 한다. 바깥을 누르면 닫힌다.
    @ViewBuilder
    private var tipLayer: some View {
        if showTip {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { closeTip() }
            TipBubble(store: tips)
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .transition(reduceMotion ? .opacity
                            : .scale(scale: 0.85, anchor: .topTrailing).combined(with: .opacity))
        }
    }

    private var mascotButton: some View {
        Button {
            lightFeedback += 1
            if showTip {
                closeTip()
            } else {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.78)) {
                    showTip = true
                }
            }
        } label: {
            TipMascot(diameter: 26, color: Ink.text, resting: tips.cups > 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("개발자에게 커피 사주기")
    }

    private func closeTip() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.85)) {
            showTip = false
        }
        tips.rest()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("모은 씨앗으로\n새 테마를 구매할 수 있어요.")
                .font(.almanacBody(.subheadline, size: 16, weight: .bold))
                .foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            SeedBadge(count: available)
                .coachAnchor(.themeSeedBalance)   // 첫 진입 안내 1단계(2026-08-12)
        }
    }

    /// 첫 진입 안내 2단계가 가리킬 카드 — 값을 치르는 첫 테마 하나만 잡는다.
    /// 여러 카드에 같은 앵커를 붙이면 마지막 하나만 남아 엉뚱한 카드를 가리킨다(PreferenceKey reduce).
    private var coachTargetTheme: AppTheme? {
        AppTheme.allCases.first { $0.seedPrice != nil }
    }

    private func isPlanted(_ theme: AppTheme) -> Bool {
        // 개발자 모드 = 전 테마 개방(2026-08-27) — 스크린샷·시연용. 원장은 안 건드린다.
        DevMode.active || theme.seedPrice == nil || Seeds.owned.contains(theme.rawValue)
    }

    private func themeCard(_ theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // 엠블럼·미리보기는 지금 고른 포인트색으로 그린다 — 카드가 실제 얼굴을 보여야 한다
                ThemeEmblem(palette: theme.palette(point: PointColor(rawValue: pointColor) ?? .vermilion))
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
            Button {
                lightFeedback += 1
                previewing = theme
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "eye")
                        .font(.caption2)
                    Text("미리보기")
                        .font(.footnote)
                }
                .foregroundStyle(Ink.text.opacity(0.65))
            }
            .buttonStyle(.plain)
            // 포인트컬러만 색 선택 행을 단다(2026-08-17) — 테마를 색마다 쪼개는 대신
            // 테마 안의 선택지로 뒀다. 적용 중일 때만 노출한다: 안 쓰는 테마의 색을
            // 미리 고르게 하면 「지금 무슨 색인지」가 화면에서 사라진다.
            if theme == .modern && current == .modern {
                pointColorRow
            }
            if theme == coachTargetTheme {
                actionRow(theme).coachAnchor(.themeCardAction)
            } else {
                actionRow(theme)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .milkGlass()
        // 축하 연출(2026-08-09) — 심는 순간 카드 위로 봄 새싹이 피어오른다(§3.8.1 「피우기」 언어)
        .overlay(alignment: .top) {
            if sprout == theme {
                SeasonGlyph(phase: .follicular, size: 26)
                    .offset(y: -30)
                    .transition(reduceMotion ? .opacity
                                : .scale(scale: 0.1).combined(with: .offset(y: 22)))
                    .accessibilityHidden(true)
            }
        }
    }

    /// 포인트색 선택 — 색 원 7개. 라벨을 붙이면 줄이 길어져 스와치만 두고 이름은 접근성으로 넘긴다.
    private var pointColorRow: some View {
        HStack(spacing: 10) {
            ForEach(PointColor.allCases) { color in
                Button {
                    lightFeedback += 1
                    ThemeStore.apply(appTheme, pointRawValue: color.rawValue)   // 선 apply(테마 적용과 같은 경로)
                    pointColor = color.rawValue
                } label: {
                    Circle()
                        .fill(swatch(color))
                        .frame(width: 22, height: 22)
                        .overlay {
                            // 선택 표시 = 지면색 링 + 바깥 테두리(체크 아이콘은 22pt에서 뭉갠다)
                            if pointColor == color.rawValue {
                                Circle().stroke(Ink.paper, lineWidth: 2)
                                    .padding(2)
                                Circle().stroke(Ink.text.opacity(0.55), lineWidth: 1.5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.displayName)
                .accessibilityAddTraits(pointColor == color.rawValue ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("포인트색 선택")
    }

    /// 스와치는 활성 테마와 무관하게 각 색의 리터럴로 그린다(미리보기 원칙 — 파일 머리말)
    private func swatch(_ color: PointColor) -> Color {
        let light = color.ink.light
        return Color(red: Double(light.0) / 255, green: Double(light.1) / 255, blue: Double(light.2) / 255)
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
        } else if ThemeTrial.isActive {
            // 7일 무료 체험(2026-08-19 사용자 결정) — 씨앗 테마도 적용 개방. 소장(구매)은
            // 체험 중에도 가능해야 해서(원장 로직 불변) 보조 텍스트 버튼으로 남긴다.
            HStack(spacing: 14) {
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
                if let price = theme.seedPrice, available >= price {
                    Button(Loc.fmt("씨앗 %lld개로 소장", price)) {
                        lightFeedback += 1
                        plantCandidate = theme
                    }
                    .font(.footnote)
                    .foregroundStyle(Ink.text.opacity(0.55))
                }
            }
        } else if let price = theme.seedPrice {
            VStack(alignment: .leading, spacing: 8) {
                if available >= price {
                    Button {
                        lightFeedback += 1
                        plantCandidate = theme   // 구입 확인 다이얼로그(2026-08-09)
                    } label: {
                        HStack(spacing: 6) {
                            SeedGlyph()
                                .fill(Ink.paper)
                                .frame(width: 8, height: 11)
                                .rotationEffect(.degrees(16))
                            Text(Loc.fmt("씨앗 %lld개로 구매", price))
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
                        Text(Loc.fmt("씨앗 %1$lld개로 구매할 수 있어요 · 지금 %2$lld개", price, available))
                            .font(.footnote)
                            .foregroundStyle(Ink.text.opacity(0.55))
                    }
                }
                passBuyButton(theme)
            }
        }
    }

    /// ₩5,000 테마 패스(2026-08-27 Phase 2) — 프리미엄 3종에만, 씨앗 경로와 병기.
    /// 상품이 안 잡히면(콘솔 미등록·네트워크) 씨앗 경로만 남는다 — 가짜 가격을 띄우지 않는다.
    /// 샌드박스 시험 빌드에서는 등록 전에도 무료 시험 버튼이 뜬다(커피 팁 전례).
    @ViewBuilder
    private func passBuyButton(_ theme: AppTheme) -> some View {
        if passStore.purchasing == theme {
            // 결제 시트가 뜨기까지의 공백을 비워 두지 않는다(2026-08-27 베타 — 커피와 같은 뿌리)
            HStack(spacing: 7) {
                ProgressView().controlSize(.small).tint(Ink.text.opacity(0.5))
                Text(Loc.str("결제 창을 여는 중이에요"))
                    .font(.footnote)
                    .foregroundStyle(Ink.text.opacity(0.55))
            }
        } else if let product = passStore.product(for: theme) {
            Button {
                lightFeedback += 1
                buyPass(theme)
            } label: {
                Text(Loc.fmt("%1$@으로 구매", product.displayPrice))
                    .font(.footnote)
                    .foregroundStyle(Ink.text.opacity(0.55))
                    .underline()
            }
            .disabled(passStore.purchasing != nil)
        } else if passStore.trialAvailable(for: theme) {
            Button {
                lightFeedback += 1
                buyPass(theme)
            } label: {
                Text(Loc.str("₩5,000으로 구매 (시험 · 무료)"))   // 샌드박스 전용 — 카탈로그 미수록(한국어 고정)
                    .font(.footnote)
                    .foregroundStyle(Ink.text.opacity(0.55))
                    .underline()
            }
        }
    }

    private func buyPass(_ theme: AppTheme) {
        Task { @MainActor in
            switch await ThemePassStore.shared.buy(theme) {
            case .done:
                purchasedByPass = true
                celebrate(theme)
            case .failed:
                passFailedAlert = true
            case .cancelled, .pending:
                break   // 취소는 조용히, 승인 대기는 통과 시 updates 리스너가 소유를 적는다
            }
        }
    }

    /// 선 apply → AppStorage 갱신(설정과 같은 경로 — 루트 `.id` 리빌드가 전 화면을 갈아입힌다).
    /// ~~리빌드로 이 시트도 함께 닫힌다~~ **폐기(2026-08-11 사용자: "계속 테마 탭에 머물게")** —
    /// 탭·시트 플래그를 뷰 밖에 둬서 리빌드를 건너 살아남는다. 갈아입은 뒤에도 이 화면에 머문다.
    private func apply(_ theme: AppTheme) {
        // 날씨 = 위치 게이트(2026-08-19 사용자 확정 — 체험 중에도 동일): 미결정이면 시스템
        // 시트를 기다리고, 거부면 적용을 막고 설정 안내를 띄운다. 하늘은 위치 없이 못 그린다.
        if theme == .weather {
            Task { @MainActor in
                switch await WxProvider.shared.requestAuthorization() {
                case .authorizedWhenInUse, .authorizedAlways:
                    confirmHaptic()
                    ThemeStore.apply(theme.rawValue)
                    appTheme = theme.rawValue
                default:
                    showWeatherLocationAlert = true
                }
            }
            return
        }
        confirmHaptic()
        ThemeStore.apply(theme.rawValue)
        appTheme = theme.rawValue
    }

    /// 심기 = 구매만(2026-08-09 사용자 지시 — 적용과 분리). 성공 = 새싹 연출 + 성공 햅틱 +
    /// 한 박자 뒤 성공 알럿(알럿이 연출을 바로 덮지 않게). 적용은 카드의 「적용하기」 또는 알럿 버튼.
    private func plant(_ theme: AppTheme) {
        guard let price = theme.seedPrice,
              Seeds.plant(theme, price: price, checkIns: checkIns) else { return }
        purchasedByPass = false   // 성공 알럿 문구 = 씨앗
        celebrate(theme)
    }

    /// 구매 성공 연출(새싹 + 성공 햅틱 + 한 박자 뒤 알럿) — 씨앗·₩5,000 패스 공용
    private func celebrate(_ theme: AppTheme) {
        celebrateTick += 1
        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.55)) {
            sprout = theme
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            plantedAlert = theme
            try? await Task.sleep(nanoseconds: 600_000_000)
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
                sprout = nil
            }
        }
    }
}

// ── 테마 미리보기 화면(2026-08-18 사용자 지시) — 오늘 탭을 하드코딩 표본으로 실물 재현 ──
// ⚠ 실제 뷰(TodayView)를 재사용하지 않는 이유: Ink·ThemeStore가 전역 정적이라 적용 없이는
//   다른 테마로 못 그린다. 미니어처(ThemePreview)와 같은 원칙 — 전부 팔레트 파라미터로.
struct ThemePreviewScreen: View {
    let theme: AppTheme
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PointColor.storageKey) private var pointColor = PointColor.vermilion.rawValue

    private var p: ThemePalette { theme.palette(point: PointColor(rawValue: pointColor) ?? .vermilion) }
    private var chrome: ThemeChrome { theme.chrome }

    var body: some View {
        ZStack(alignment: .top) {
            ground
            if chrome.skyGround { weatherGlow }
            VStack(alignment: .leading, spacing: 16) {
                header
                sampleCard(title: Loc.str("일정"), rows: [(Loc.str("저녁 산책"), "19:00")], trackCount: 1)
                sampleCard(title: "Input", rows: [(Loc.str("아침명상 5분"), Loc.str("체크")), (Loc.str("물 자주 마시기"), Loc.str("체크"))], trackCount: 2)
                sampleCard(title: "Output", rows: [(Loc.str("자격증 공부"), Loc.str("30:00 타이머"))], trackCount: 1)
                Spacer(minLength: 0)
                tabBarMock
            }
            .padding(20)
            // 닫기 — 목업 위 우상단(시트 기본 내림 제스처도 살아 있다)
            .overlay(alignment: .topTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(groundInk.opacity(0.5))
                }
                .padding(.top, 14)
                .padding(.trailing, 16)
                .accessibilityLabel("미리보기 닫기")
            }
        }
        .presentationDragIndicator(.visible)
        // 미리보는 테마의 colorScheme — 활성 테마(RootTabView 루트 값)가 아니라 이 시트가
        // 보여주는 테마 기준이어야 한다(2026-08-19 베타 피드백 — 시스템 다크에서 라이트
        // 고정 테마를 미리볼 때 List·glassEffect 같은 시스템 컴포넌트만 검게 떨어졌다).
        .preferredColorScheme(chrome.forcesDarkAppearance ? .dark : chrome.forcesLightAppearance ? .light : nil)
    }

    /// 지면 — 티켓은 유화+스크림(오늘 탭과 동일 문법), 그 외는 팔레트 지면색
    @ViewBuilder
    private var ground: some View {
        if chrome.photographicGround {
            Color.clear
                .overlay {
                    ZStack {
                        p.paper
                        Image(TicketSpec.plateAsset(for: .ovulation))
                            .resizable()
                            .scaledToFill()
                        LinearGradient(
                            colors: [Color(red: 74 / 255, green: 96 / 255, blue: 124 / 255).opacity(0.62),
                                     Color(red: 46 / 255, green: 64 / 255, blue: 90 / 255).opacity(0.82)],
                            startPoint: .top, endPoint: .bottom)
                    }
                }
                .clipped()
                .ignoresSafeArea()
        } else if chrome.skyGround {
            // 날씨 — 미리보기 표본은 맑음×낮 고정(시안 §5의 기본 상태)
            let s = SkySpec.stops(.clear, .day)
            LinearGradient(colors: [s.a, s.b, s.c], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        } else {
            p.paper.ignoresSafeArea()
        }
    }

    /// 지면 위 활자색 — 사진 지면(티켓)·하늘 지면(날씨)은 흰 계열
    private var groundInk: Color {
        chrome.photographicGround || chrome.skyGround ? .white : p.text
    }

    /// 날씨 정적 글로우(시안 §5.3-5 맑음×낮 동값) — 표본은 항상 이 상태라 파티클 없이
    /// 우상단 웜 글로우만으로도 진짜 날씨 지면처럼 읽힌다.
    private var weatherGlow: some View {
        Rectangle().fill(RadialGradient(
            stops: [
                .init(color: Color(red: 1, green: 246 / 255, blue: 216 / 255).opacity(0.85), location: 0),
                .init(color: Color(red: 1, green: 238 / 255, blue: 190 / 255).opacity(0.22), location: 0.42),
                .init(color: .clear, location: 0.7),
            ],
            center: UnitPoint(x: 0.82, y: 0.04), startRadius: 0, endRadius: 300))
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// 헤더 — 플레이리스트는 플레이어 카드가 헤더를 대신한다(시안 §4.4 ②, 실제 오늘 탭과 동형).
    /// 미리보기의 존재 이유가 "그 테마의 얼굴을 보여주는 것"이라 이 분기가 핵심이다.
    @ViewBuilder
    private var header: some View {
        if chrome.playlistChrome {
            playlistHeader
        } else {
            standardHeader
        }
    }

    private var playlistHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(verbatim: "NOW PLAYING")   // 디자인 요소(PlaylistChrome와 동일)
                        .font(.system(size: 9, weight: .medium))
                        .kerning(1.6)
                        .foregroundStyle(p.dim)
                    Rectangle().fill(p.text.opacity(0.22)).frame(height: 1)
                }
                Text("여름")
                    .font(displayFont(size: 28))
                    .foregroundStyle(p.text)
                    .padding(.top, 5)
                // 실제 카드와 같은 문법(날짜만) — 단계명은 §M-1c 금지, 날짜는 포매터라
                // 언어를 따라간다(종전엔 한국어 날짜가 박혀 있었다)
                Text(Date.now.formatted(Loc.dateTime.month().day().weekday(.wide)))
                    .font(.caption2)
                    .foregroundStyle(p.dim)
                    .padding(.top, 1)
                previewSeekBar(progress: 0.62)
                    .padding(.top, 10)
                HStack {
                    Text("18일차")
                    Spacer(minLength: 0)
                    Text("29일")
                }
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(p.dim)
                .padding(.top, 5)
            }
            RoundedRectangle(cornerRadius: 10)
                .fill(p.summer)
                .frame(width: 56, height: 56)
        }
        .padding(16)
        // .clear — Almanac.MilkGlass와 동일 재질(2026-08-20 "여전히 안투명" 대응)
        .playlistGlass(radius: 20)
        .padding(.top, 20)
    }

    /// 시크바 — 실제 `PlaylistSeekBar`와 같은 문법이되 전역 `Ink` 대신 팔레트 파라미터로
    /// (미리보기 전체 원칙 — 활성 테마와 무관하게 제 색으로 뜬다).
    private func previewSeekBar(progress: Double) -> some View {
        GeometryReader { geo in
            let x = geo.size.width * CGFloat(min(max(progress, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(p.text.opacity(0.22)).frame(height: 3)
                Capsule().fill(p.accent).frame(width: max(x, 3), height: 3)
                Circle().fill(p.accent).frame(width: 9, height: 9).offset(x: x - 4.5)
            }
        }
        .frame(height: 9)
    }

    private var standardHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                headline
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(verbatim: "18")   // 미리보기 목업 숫자 — 번역 대상 아님
                        .font(displayFont(size: 34))
                        .foregroundStyle(groundInk.opacity(0.85))
                    Text(verbatim: "Aug Tue")   // 티켓 미리보기 목업
                        .font(.caption2)
                        .foregroundStyle(groundInk.opacity(0.55))
                }
            }
            Text("여름이에요. 하고 싶은 만큼 빛나도 좋아요.")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(groundInk.opacity(0.85))
        }
        .padding(.top, 34)
    }

    /// 표제 「여름」 — 활판 = 음각(종이색 + 그림자 2겹), 그 외 = 계절색 솔리드(티켓 = 흰)
    @ViewBuilder
    private var headline: some View {
        if chrome.debossDisplay {
            Text("여름")
                .font(displayFont(size: 64))
                .foregroundStyle(p.paper)
                .shadow(color: Color(red: 90 / 255, green: 84 / 255, blue: 72 / 255).opacity(0.52),
                        radius: 0.7, x: -1, y: -1)
                .shadow(color: .white, radius: 0.8, x: 1, y: 1.2)
        } else {
            Text("여름")
                .font(displayFont(size: 54))
                .foregroundStyle(chrome.photographicGround ? .white : p.summer)
        }
    }

    /// 카드 — 플레이리스트 = 리퀴드 글래스 / 활판 = 음각 윤곽선 / 티켓 = 발권지 / 그 외 = 팔레트 표면
    @ViewBuilder
    private func sampleCard(title: String, rows: [(String, String)], trackCount: Int? = nil) -> some View {
        let card = VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(displayFont(size: 15))
                    .foregroundStyle(p.text)
                // 플레이리스트 = 곡수 메타(시안 §4.4 ⑦ 실제 TodayView 동형 — "N TRACKS")
                if chrome.playlistChrome, let trackCount {
                    Text("\(trackCount) \(trackCount == 1 ? "TRACK" : "TRACKS")")
                        .font(.system(size: 9, weight: .medium))
                        .kerning(1.6)
                        .foregroundStyle(p.dim)
                }
            }
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0)
                        .font(.footnote)
                        .foregroundStyle(p.text)
                    Spacer()
                    Text(row.1)
                        .font(.caption2)
                        .foregroundStyle(p.text.opacity(0.45))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        if chrome.liquidGlassCards {
            // 플레이리스트 — 시스템 리퀴드 글래스. 재질이라 활성 테마와 무관하게 제 모습으로 뜬다.
            // ⚠ `isEnabled:` 파라미터는 SDK에 없다(CI 실측 2026-08-19) — 분기로 켠다.
            // .clear — Almanac.MilkGlass와 동일 재질(2026-08-20 "여전히 안투명" 대응)
            card.playlistGlass(radius: 20)
        } else {
            card.background {
                if chrome.engravedCards {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white, lineWidth: 1)
                            .offset(x: 1, y: 1.2)
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(red: 90 / 255, green: 84 / 255, blue: 72 / 255).opacity(0.34),
                                    lineWidth: 1)
                    }
                } else if chrome.ticketChrome {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(TicketSpec.ticketPaper)
                        .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(p.surface)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(p.accent.opacity(0.18), lineWidth: 1))
                }
            }
        }
    }

    private var tabBarMock: some View {
        HStack {
            ForEach([Loc.str("오늘"), Loc.str("캘린더"), Loc.str("나의 템포"), Loc.str("설정")], id: \.self) { name in
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(p.text.opacity(name == Loc.str("오늘") ? 1 : 0.45))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        // 틴트 유리 바(2026-08-20)는 지면색으로 근사 — 목업엔 실제 블러가 없다
        .background((chrome.ticketChrome ? TicketSpec.ticketPaper
                     : chrome.tintedTabBar ? p.paper.opacity(0.75) : p.surface),
                    in: Capsule())
    }

    /// 표제 서체 — 테마 서체 분기(전역 폰트 함수는 활성 테마를 보므로 여기서 직접 고른다)
    private func displayFont(size: CGFloat) -> Font {
        switch chrome.typeFace {
        case .notoSerif:
            return LetterpressFont.available ? .custom("NotoSerifKR-Light", size: size)
                                             : .system(size: size, weight: .light, design: .serif)
        case .pretendard:
            return ThemeFont.available ? .custom("Pretendard-SemiBold", size: size)
                                       : .system(size: size, weight: .semibold)
        case .gowun:
            return AlmanacFont.available ? .custom("GowunBatang-Bold", size: size)
                                         : .system(size: size, weight: .bold, design: .serif)
        case .system:
            return .system(size: size, weight: .semibold)
        }
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
    /// 포인트컬러 미리보기는 고른 색을 따라간다(다른 테마는 무시)
    @AppStorage(PointColor.storageKey) private var pointColor = PointColor.vermilion.rawValue

    private var titleFont: Font {
        switch theme.chrome.typeFace {
        case .notoSerif:
            return LetterpressFont.available ? .custom("NotoSerifKR-Light", size: 22)
                                             : .system(size: 22, weight: .light, design: .serif)
        case .pretendard:
            return ThemeFont.available ? .custom("Pretendard-SemiBold", size: 22)
                                       : .system(size: 22, weight: .semibold)
        case .gowun:
            return AlmanacFont.available ? .custom("GowunBatang-Bold", size: 22)
                                         : .system(size: 22, weight: .bold, design: .serif)
        case .system:
            return .system(size: 22, weight: .semibold)
        }
    }

    private var chrome: ThemeChrome { theme.chrome }
    /// 지면 위 활자색 — 사진 지면(티켓)·하늘 지면(날씨)은 흰 계열(ThemePreviewScreen과 동일 규칙)
    private func groundInk(_ p: ThemePalette) -> Color {
        chrome.photographicGround || chrome.skyGround ? .white : p.text
    }

    var body: some View {
        let p = theme.palette(point: PointColor(rawValue: pointColor) ?? .vermilion)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("8월")
                    .font(titleFont)
                    .foregroundStyle(groundInk(p))
                Text(verbatim: "2026")   // 미리보기 목업 숫자
                    .font(.caption)
                    .foregroundStyle(groundInk(p).opacity(0.5))
                Spacer(minLength: 0)
                // 계절 도트 — 표시 순서(봄→여름→가을→겨울, §8.1)
                HStack(spacing: 5) {
                    Circle().fill(p.spring).frame(width: 7, height: 7)
                    Circle().fill(p.summer).frame(width: 7, height: 7)
                    Circle().fill(p.autumn).frame(width: 7, height: 7)
                    Circle().fill(p.winter).frame(width: 7, height: 7)
                }
            }
            innerCard(p)
                .frame(height: 46)
        }
        .padding(12)
        .background { ground(p) }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(groundInk(p).opacity(0.12), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // 이 미니 카드가 보여주는 테마 기준 colorScheme — ThemePreviewScreen과 같은 이유
        // (활성 테마가 다크를 안 켜는 상태에서 이 카드만 라이트 고정 테마일 수 있다).
        // ⚠ preferredColorScheme 금지(2026-08-20 결함 수정) — 그건 프리퍼런스라 카드가 아니라
        // **테마 탭 시트 전체**에 버블돼, 카드 7장이 시트 외관을 서로 뒤집었다(마지막 평가
        // 카드가 승자 — "레전드 일관성없음" 베타 피드백의 유력 뿌리). 환경값은 서브트리 한정.
        .transformEnvironment(\.colorScheme) { scheme in
            if chrome.forcesDarkAppearance { scheme = .dark }
            else if chrome.forcesLightAppearance { scheme = .light }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Loc.fmt("%1$@ 테마 미리보기", "\(theme.displayName)"))
    }

    /// 카드 지면 — 티켓은 유화, 날씨는 하늘, 그 외는 팔레트 지면색(ThemePreviewScreen과 동형,
    /// 2026-08-19 베타 피드백 대응 — 이 미니 카드가 자기 테마의 얼굴을 안 보여주고 있었다)
    @ViewBuilder
    private func ground(_ p: ThemePalette) -> some View {
        if chrome.photographicGround {
            Image(TicketSpec.plateAsset(for: .ovulation))
                .resizable()
                .scaledToFill()
                .overlay(Color.black.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if chrome.skyGround {
            let s = SkySpec.stops(.clear, .day)
            LinearGradient(colors: [s.a, s.b, s.c], startPoint: .top, endPoint: .bottom)
        } else {
            RoundedRectangle(cornerRadius: 12).fill(p.paper)
        }
    }

    /// 안쪽 표본 행 — 플레이리스트만 리퀴드 글래스, 그 외는 팔레트 표면
    @ViewBuilder
    private func innerCard(_ p: ThemePalette) -> some View {
        let row = HStack(spacing: 8) {
            Circle().fill(p.accent).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(groundInk(p).opacity(0.55)).frame(width: 64, height: 5)
                Capsule().fill(groundInk(p).opacity(0.25)).frame(width: 96, height: 5)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        if chrome.liquidGlassCards {
            row.playlistGlass(radius: 9)
        } else {
            row.background {
                RoundedRectangle(cornerRadius: 9)
                    .fill(p.surface)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(p.accent.opacity(0.18), lineWidth: 1))
            }
        }
    }
}

// ── 체험 종료 선택 시트(2026-08-19 사용자 결정) — 기본·은필 중 하나를 골라 영구 보유 ──
// 표시는 RootTabView 한 곳(2026-08-12 시트 원칙). 선택 전 닫기 불가 — 닫아버리면 미보유
// 테마가 적용된 채 남는다. 은필 선택 = grandfather(0원 원장 기재, 병합이 유료로 안 센다).
struct TrialEndSheet: View {
    @AppStorage(ThemeStore.storageKey) private var appTheme = AppTheme.plain.rawValue
    @State private var choice: AppTheme
    @State private var lightFeedback = 0
    let onResolved: () -> Void

    init(onResolved: @escaping () -> Void) {
        self.onResolved = onResolved
        // 기본 선택 = 온보딩에서 골랐던 테마("이전 거랑 연결"). 기록 없으면 은필.
        let saved = UserDefaults.standard.string(forKey: ThemeTrial.choiceKey)
        _choice = State(initialValue: saved.flatMap(AppTheme.init(rawValue:)) ?? .standard)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("무료 체험이 끝났어요")
                .font(.almanac(size: 24, weight: .bold))
                .foregroundStyle(Ink.text)
                .padding(.top, 28)
            Text("기본과 은필 중 당신의 테마를 골라 가지세요. 고른 테마는 계속 쓸 수 있어요.")
                .font(.subheadline)
                .foregroundStyle(Ink.text.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            ForEach([AppTheme.standard, AppTheme.plain]) { theme in
                choiceCard(theme)
            }
            Spacer(minLength: 0)
            Button {
                confirm()
            } label: {
                Text(Loc.fmt("「%1$@」으로 시작하기", "\(choice.displayName)"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Ink.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Ink.text, in: Capsule())
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Ink.paper.ignoresSafeArea())
        .interactiveDismissDisabled(true)
        .sensoryFeedback(.impact(weight: .light), trigger: lightFeedback)
    }

    private func choiceCard(_ theme: AppTheme) -> some View {
        let selected = choice == theme
        return Button {
            lightFeedback += 1
            choice = theme
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ThemePreview(theme: theme)
                HStack(spacing: 8) {
                    Text(theme.displayName)
                        .font(.almanac(size: 17, weight: .bold))
                        .foregroundStyle(Ink.text)
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(Ink.text.opacity(selected ? 0.9 : 0.3))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .milkGlass()
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(Ink.text.opacity(selected ? 0.8 : 0), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Loc.fmt("%1$@ 테마", "\(theme.displayName)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func confirm() {
        if choice.seedPrice != nil { Seeds.grandfather(choice) }   // 은필 = 0원 기재(멱등)
        // resolve를 appTheme 변경(= 루트 `.id` 리빌드) 앞에 — 리빌드 직후 .task 재판정이
        // 아직 미해결 상태를 보고 시트를 다시 띄우는 레이스를 막는다.
        ThemeTrial.resolve()
        ThemeStore.apply(choice.rawValue)
        appTheme = choice.rawValue
        onResolved()
    }
}
