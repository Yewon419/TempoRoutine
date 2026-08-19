// 템포루틴 — 테마 탭 (2026-08-09 사용자 지시, §8.2.6·§3.8.1)
// 진입 = 설정 「테마」 행 + 오늘 탭 씨앗 배지 탭. UI 언어 = 평문 「구매」·「적용」(2026-08-09
// 2차 번복 — 「심기」는 "너무 추상적". 코드 식별자 plant/planted는 유지, 사용자 표면만 평문).
// 가격: 모던 = 씨앗 7개(2026-08-09 사용자 확정 — §3.8.1 미결 ① 해소).
// 미리보기·엠블럼은 활성 테마와 무관하게 각 테마의 팔레트 리터럴로 그린다(Ink 미사용) —
// 지금 무슨 테마를 쓰든 다른 테마의 얼굴이 제 색으로 보여야 미리보기다.

import SwiftUI
import SwiftData

extension AppTheme {
    /// 씨앗 가격 — nil = 기본(무료 상시 보유). §3.8.1 미결 ① 확정값.
    /// ⚠ 은필은 2026-08-12부터 씨앗 테마다(트랙 분리). 종전 설치는 앱 시작 시 승계된다.
    var seedPrice: Int? {
        switch self {
        case .plain: nil
        case .standard: 7
        case .modern: 7
        // 티켓 = 무료(2026-08-14 사용자 확정). 새 문법이라 문턱 없이 써보게 둔다.
        case .ticket: nil
        // 활판 = 무료(2026-08-18 이식 — 티켓과 같은 근거. 트랙 배치는 §3.8.1 미결로 유지)
        case .letterpress: nil
        // 플레이리스트 = 무료(2026-08-19 사용자 확정 — 티켓·활판과 같은 근거)
        case .playlist: nil
        // 날씨 = 무료(2026-08-18 사용자 확정)
        case .weather: nil
        }
    }

    var shopCaption: String {
        switch self {
        case .plain: "기본 테마."
        case .standard: "은필과 종이. 계절이 빛으로 스며드는 지면이에요."
        case .modern: "기본 지면에 다홍 한 점. 계절은 밝기로 갈려요."
        case .ticket: "색면 위에 놓인 한 장의 티켓. 일상을 여행처럼."
        case .letterpress: "종이에 눌러 새긴 하루. 잉크 없는 음각의 물성."
        case .playlist: "지금 재생 중인 계절. 하루가 트랙처럼 흘러요."
        case .weather: "지면이 곧 오늘의 하늘. 시간과 날씨가 화면을 물들여요."
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
    @State private var celebrateTick = 0           // 성공 햅틱
    // 커피 한 잔(2026-08-11) — 우상단 캐릭터 + 말풍선. 씨앗 트랙 밖의 팁이다(§3.8).
    private var tips = TipStore.shared
    @State private var showTip = false
    /// 미리보기 시트(2026-08-18 사용자 지시) — 하드코딩 목업 화면
    @State private var previewing: AppTheme?

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
                            Text("지금은 무료 체험 기간이에요. \(ThemeTrial.daysLeft)일 동안 모든 테마를 자유롭게 바꿔볼 수 있어요.")
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
        .task { await tips.load() }
        .sensoryFeedback(.impact(weight: .light), trigger: lightFeedback)
        .sensoryFeedback(.success, trigger: celebrateTick)
        // 구매 확인(2026-08-09) — 씨앗을 쓰는 확정 액션이라 한 번 묻는다(§8.2.6 확인 문법)
        .confirmationDialog(
            plantCandidate.map { "「\($0.displayName)」 구매" } ?? "",
            isPresented: Binding(get: { plantCandidate != nil },
                                 set: { if !$0 { plantCandidate = nil } }),
            titleVisibility: .visible
        ) {
            if let price = plantCandidate?.seedPrice {
                Button("씨앗 \(price)개로 구매") {
                    if let theme = plantCandidate { plant(theme) }
                    plantCandidate = nil
                }
            }
            Button("취소", role: .cancel) { plantCandidate = nil }
        }
        // 성공 메시지(연출 한 박자 뒤) — 구매와 적용이 분리라 여기서 적용을 권한다
        .alert(plantedAlert.map { "「\($0.displayName)」을 구매했어요" } ?? "",
               isPresented: Binding(get: { plantedAlert != nil },
                                    set: { if !$0 { plantedAlert = nil } }),
               presenting: plantedAlert) { theme in
            Button("지금 적용하기") { apply(theme) }
            Button("나중에") { plantedAlert = nil }
        } message: { theme in
            Text("씨앗 \(theme.seedPrice ?? 0)개를 썼어요.")
        }
        .sheet(item: $previewing) { theme in
            ThemePreviewScreen(theme: theme)
        }
        .onAppear {
            // 쓰고 있는 테마가 유료면 보유로 승계 — 쓰던 테마를 잠그지 않는다(신뢰).
            // 낸 값 0으로 적힌다(Seeds.grandfather) — 구매분과 섞이면 병합 때 유료로 오인된다.
            // 앱 시작 시에도 같은 승계가 돈다(TempoRoutineApp) — 여기는 보완 벨트.
            if current.seedPrice != nil { Seeds.grandfather(current) }
        }
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
        .accessibilityLabel("만드는 사람에게 커피 한 잔")
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
        theme.seedPrice == nil || Seeds.owned.contains(theme.rawValue)
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
                    Button("씨앗 \(price)개로 소장") {
                        lightFeedback += 1
                        plantCandidate = theme
                    }
                    .font(.footnote)
                    .foregroundStyle(Ink.text.opacity(0.55))
                }
            }
        } else if let price = theme.seedPrice {
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
                        Text("씨앗 \(price)개로 구매")
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
                    Text("씨앗 \(price)개로 구매할 수 있어요 · 지금 \(available)개")
                        .font(.footnote)
                        .foregroundStyle(Ink.text.opacity(0.55))
                }
            }
        }
    }

    /// 선 apply → AppStorage 갱신(설정과 같은 경로 — 루트 `.id` 리빌드가 전 화면을 갈아입힌다).
    /// ~~리빌드로 이 시트도 함께 닫힌다~~ **폐기(2026-08-11 사용자: "계속 테마 탭에 머물게")** —
    /// 탭·시트 플래그를 뷰 밖에 둬서 리빌드를 건너 살아남는다. 갈아입은 뒤에도 이 화면에 머문다.
    private func apply(_ theme: AppTheme) {
        confirmHaptic()
        ThemeStore.apply(theme.rawValue)
        appTheme = theme.rawValue
    }

    /// 심기 = 구매만(2026-08-09 사용자 지시 — 적용과 분리). 성공 = 새싹 연출 + 성공 햅틱 +
    /// 한 박자 뒤 성공 알럿(알럿이 연출을 바로 덮지 않게). 적용은 카드의 「적용하기」 또는 알럿 버튼.
    private func plant(_ theme: AppTheme) {
        guard let price = theme.seedPrice,
              Seeds.plant(theme, price: price, checkIns: checkIns) else { return }
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
            VStack(alignment: .leading, spacing: 16) {
                header
                sampleCard(title: "일정", rows: [("저녁 산책", "19:00")])
                sampleCard(title: "Input", rows: [("아침명상 5분", "체크"), ("물 자주 마시기", "체크")])
                sampleCard(title: "Output", rows: [("자격증 공부", "30:00 타이머")])
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                headline
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("18")
                        .font(displayFont(size: 34))
                        .foregroundStyle(groundInk.opacity(0.85))
                    Text("Aug Tue")
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
    private func sampleCard(title: String, rows: [(String, String)]) -> some View {
        let card = VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(displayFont(size: 15))
                .foregroundStyle(p.text)
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
            card.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
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
            ForEach(["오늘", "캘린더", "나의 템포", "설정"], id: \.self) { name in
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(p.text.opacity(name == "오늘" ? 1 : 0.45))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .background((chrome.ticketChrome ? TicketSpec.ticketPaper : p.surface),
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

    var body: some View {
        let p = theme.palette(point: PointColor(rawValue: pointColor) ?? .vermilion)
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
