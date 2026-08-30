// 템포루틴 — 오늘 탭 (MASTER §8.2.2, 프로토 v29~v77 확정 문법)
// 위→아래: 컬랩싱 계절 헤더(2-layer crossfade — font-size 보간 금지, DESIGN v44) → 무드라인(플레인 조판)
// → S0/S4 상태 → 일정·Input·Output 3구획 직접 노출(하루 상세와 동일 데이터 — 뷰별 로컬 상태 금지)
// → 데일리 체크인 인라인 카드(§3.4). 문장형 제안 한 줄은 계절별 카피 미확정 — PENDING.

import SwiftUI
import SwiftData
import TempoCore
import UIKit

// ── 디자인 토큰 — 테마 팔레트 위임(2026-07-29 테마 시스템, Theme.swift) ──
// 값 정의는 ThemePalette.standard(종전 리터럴 동값)·.modern — 여기는 정적 API만 유지.
// 콜사이트 무수정 원칙: Ink.x 문법 그대로, 백킹만 ThemeStore.palette로.
enum Ink {
    static var winter: Color { ThemeStore.palette.winter }
    static var spring: Color { ThemeStore.palette.spring }
    static var summer: Color { ThemeStore.palette.summer }
    static var autumn: Color { ThemeStore.palette.autumn }
    static var text: Color { ThemeStore.palette.text }       // 잉크
    static var paper: Color { ThemeStore.palette.paper }     // 지면
    static var coral: Color { ThemeStore.palette.coral }     // ⚠ 은퇴(2026-07-28) — 사용처 0
    /// 생리 기록 표기(2026-07-28 — 진한 회색)
    static var record: Color { ThemeStore.palette.record }
    /// 파괴적 액션 전용
    static var danger: Color { ThemeStore.palette.danger }
    /// 완료 상태 = 짙은 회색(--ink-dim)
    static var dim: Color { ThemeStore.palette.dim }
    /// 산화 은필 — 캘린더 과거 일정 전용(모던에선 회색 재해석)
    static var oxide: Color { ThemeStore.palette.oxide }
    /// 공휴일 빨간날(모던에선 로즈 — 다홍 = 생리 전용)
    static var holiday: Color { ThemeStore.palette.holiday }
    /// 토요일 파랑(달력 관례)
    static var saturday: Color { ThemeStore.palette.saturday }
    /// 캘린더 지면
    static var frost: Color { ThemeStore.palette.frost }
    // 계절 글로우 팔레트
    static var glowWinter: Color { ThemeStore.palette.glowWinter }
    static var glowSpring: Color { ThemeStore.palette.glowSpring }
    static var glowSummer: Color { ThemeStore.palette.glowSummer }
    static var glowAutumn: Color { ThemeStore.palette.glowAutumn }
    /// 카드 표면
    static var surface: Color { ThemeStore.palette.surface }
    /// 구조 악센트(오늘 원·괘선·요일·테두리) — 기본 = winter 동값, 모던 = 흰색
    static var accent: Color { ThemeStore.palette.accent }
    /// **지면 위** 보조 활자색(시안 §3.3-⑥, 2026-08-17 배선). 사진·색면 지면(티켓)에서는
    /// `text` 저불투명 혼합이 묻혀 안 읽힌다 — 흰 계열로 올린다. 카드 **안** 활자는 해당 없음
    /// (카드는 흰 지면이라 종전 규칙이 맞다).
    /// 2026-08-18 2차: 설정은 티켓에서도 흰 지면이라 원복 — 소비처가 설정 헤더·풋터뿐이다.
    static var groundSub: Color { text.opacity(0.55) }
    /// 지면 위 활자 일반형(시안 티켓 흰 덮기 목록 2026-08-15 — 표제·일차·무드라인·날짜 도장 등).
    /// base = 다른 테마의 원래 색 / white = 사진 지면에서의 흰 불투명도(시안 color-mix 비율).
    static func onGround(_ base: Color, white: Double) -> Color {
        ThemeStore.chrome.photographicGround ? Color.white.opacity(white) : base
    }
}

struct SeasonMeta {
    /// 이 계절의 단계 — **조회·비교는 이 값으로 한다.** 표시명(`name`)은 번역되므로 키로 쓰면
    /// 다른 언어에서 조용히 어긋난다(2026-08-20 로컬라이제이션에서 실제로 드러난 결함).
    let phase: CyclePhase
    let name: String
    let color: Color
    let glow: Color        // 캘린더 지면 빛 전용(채도·명도 상향판, 2026-07-28)
    let moodline: String
    let lever: String      // Output 계절 레버 카피 (§3.6 — 허락 톤, 프로토 v70 확정)
}

/// 플리 = 계절명 영어 고정(2026-08-30 대표님 지시 — 트랙명 문법. ja·zh에도 영어,
/// 활판 라틴 스탬프 전례). 다른 테마는 종전 번역 그대로.
private func seasonName(_ localized: String, en english: String) -> String {
    ThemeStore.chrome.playlistChrome ? english : localized
}

func seasonMeta(for phase: CyclePhase) -> SeasonMeta {
    switch phase {
    // 로컬라이제이션(2026-08-20): 이 값들은 String으로 흘러 Text(변수)에 닿는다 —
    // 만드는 자리에서 Loc.str로 뽑아야 번역이 붙는다(선택 언어까지 탄다).
    // ⚠ **의학 단계명(월경기·난포기…) 필드는 두지 않는다**(2026-08-21 삭제). 개정 M-1c가
    // 사용자 표면 금지인데 필드가 있으니 플레이리스트 이식이 부제에 갖다 썼다 —
    // 없으면 같은 사고가 구조적으로 불가능하다. 단계가 필요하면 `phase`(CyclePhase)를 쓸 것.
    case .menstrual:
        SeasonMeta(phase: .menstrual, name: seasonName(Loc.str("겨울"), en: "Winter"),
                   color: Ink.winter, glow: Ink.glowWinter,
                   moodline: Loc.str("이번 주는 겨울이에요. 조금은 쉬어가도 괜찮아요."),
                   lever: Loc.str("오늘은 천천히 이어가볼까요?"))
    case .follicular:
        SeasonMeta(phase: .follicular, name: seasonName(Loc.str("봄"), en: "Spring"),
                   color: Ink.spring, glow: Ink.glowSpring,
                   moodline: Loc.str("봄이에요. 가볍게 시작해보기 좋은 때예요."),
                   lever: Loc.str("시동 거는 주기예요. 가볍게 시작해도 좋아요."))
    case .ovulation:
        SeasonMeta(phase: .ovulation, name: seasonName(Loc.str("여름"), en: "Summer"),
                   color: Ink.summer, glow: Ink.glowSummer,
                   moodline: Loc.str("여름이에요. 하고 싶은 만큼 빛나도 좋아요."),
                   lever: Loc.str("마음껏 몰입해도 좋아요."))
    case .luteal:
        SeasonMeta(phase: .luteal, name: seasonName(Loc.str("가을"), en: "Autumn"),
                   color: Ink.autumn, glow: Ink.glowAutumn,
                   moodline: Loc.str("가을이에요. 스스로를 돌아보는 시간을 가져봐요."),
                   lever: Loc.str("조금 더 해볼 수 있나요? 무리하지는 말아요."))
    }
}

struct TodayView: View {
    /// §5.6.2 S4 배너 유예 — 예측일 경과 즉시가 아니라 +2일부터.
    static let overdueGraceDays = 2

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSize   // 아이패드 2열(2026-07-23)
    @Query(sort: \PeriodDay.day) private var periodDays: [PeriodDay]
    @Query(sort: \ScheduleItem.date) private var schedules: [ScheduleItem]
    @Query(sort: \InputItem.createdAt) private var inputs: [InputItem]
    @Query private var inputProgresses: [InputProgress]   // Input 진행 방식(2026-08-12)
    @Query(sort: \OutputItem.createdAt) private var outputs: [OutputItem]
    @Query private var completions: [ItemCompletion]
    @Query private var checkIns: [DailyCheckIn]

    @State private var showLogSheet = false
    @State private var addSheet: CardKind?
    @State private var editingSchedule: ScheduleItem?   // 일정 행 탭 = 수정 시트(2026-07-23)
    @State private var pendingDelete: QuickDeleteTarget?   // 행 길게 누르기 = 빠른 삭제(2026-07-27)
    @State private var isCollapsed = false
    @State private var confirmFeedback = 0   // 확정 순간 햅틱(§4 — 아이템 완료)
    @State private var lightFeedback = 0     // 작은 햅틱(§4 — 진행도 조정 등, 확정 아님)
    // 알림 권한 안내 카드(2026-08-08) — 기본 켬 알림의 능동 권한 획득 경로, 1회
    @State private var showNoticeCard = false
    // 씨앗 배지 탭 = 테마 탭(2026-08-09). 플래그를 뷰 밖에 두는 이유는 RootTab 주석 참조 —
    // 테마를 갈아입으면 루트가 리빌드돼 @State였던 이 값이 날아가고 시트가 닫혔다(2026-08-11).
    @AppStorage(RootTab.themeShopKey) private var showThemeShop = false
    /// 씨앗 원장 방송 카운터 — 소비·수령은 생 UserDefaults라 이 키를 지켜봐야 배지가 따라온다
    /// (2026-08-11: 소식란에서 씨앗을 받아도 배지가 옛 숫자로 남아 있던 결함)
    @AppStorage(Seeds.revisionKey) private var seedRevision = 0
    /// 날씨 수치 갱신 도장(2026-08-20) — 씨앗 카운터와 같은 이유. WeatherKit 응답이
    /// 정적 캐시(WxState)에만 들어가면 이 화면이 다시 그려질 이유가 없어 줄이 안 뜬다.
    @AppStorage(WxState.readoutStampKey) private var wxStamp = 0.0


    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: .now) }
    private var snapshot: CycleSnapshot { CycleSnapshot(periodDays: periodDays) }
    private var todayInfo: (meta: SeasonMeta, dayInCycle: Int, dayInPhase: Int, projected: Bool)? { snapshot.phaseInfo(on: today) }

    // 단계별 에너지 프로필(2026-07-23) — 표본 3개+면 무드라인·Input 예시 개인화, 미달이면 기본 유지
    private var energyProfile: EnergyProfile { EnergyProfile(checkIns: checkIns, snapshot: snapshot) }
    private var todayEnergyLevel: EnergyLevel? {
        snapshot.phase(on: today).flatMap { energyProfile.level(for: $0) }
    }
    private var moodlineText: String? {
        guard let info = todayInfo else { return nil }
        if let phase = snapshot.phase(on: today), let level = todayEnergyLevel {
            return EnergyProfile.moodline(for: phase, level: level)
        }
        return info.meta.moodline
    }

    var body: some View {
        ZStack(alignment: .top) {
            if ThemeStore.chrome.photographicGround {
                TicketGround(phase: snapshot.phase(on: today))   // 계절 유화 + 스크림(시안 §3)
            } else if ThemeStore.chrome.skyGround {
                WeatherSky()   // 날씨 = 오늘의 하늘(시안 §5.3-1)
            } else if ThemeStore.chrome.videoGround {
                PlaylistVideoGround()   // 플리 = 계절 배경 영상(시안 §4.4 ⑪, 2026-08-25)
            } else {
                Ink.paper.ignoresSafeArea()
                SeasonLight(phase: snapshot.phase(on: today))   // 계절광(§4) — 지면 위 고정 빛
            }
            // 플리 오늘 탭 2단계(시안 §4.4 ⑫, 폰 전용 — 2026-08-26 s2 폐기): s0 = 플레이어 단독
            // 센터, 탭/스와이프 → s1 = 전체(체크인 포함). 되감기 = 맨 위에서 당김.
            if ThemeStore.chrome.playlistChrome, hSize != .regular, plStage == 0,
               !snapshot.isColdStart, todayInfo != nil {
                playlistStageZero
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    largeHeader
                    stateSurfaces
                    if showNoticeCard { noticePermissionCard }
                    if hSize == .regular {
                        // 아이패드: 3구획 좌열 + 체크인 우측 레일(2026-07-23).
                        // 콜드에도 연다(2026-08-25 베타 "계절 기록 전에도 일정·인풋·아웃풋 열어둬")
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 16) {
                                section(kind: .schedule) { scheduleSection }
                                section(kind: .input) { inputSection }
                                section(kind: .output) { outputSection }
                            }
                            .frame(maxWidth: .infinity)
                            CheckInCard(day: today).ticketCardGap().frame(width: 360)
                        }
                    } else {
                        // 콜드에도 연다(2026-08-25 베타) — 콜드 안내(stateSurfaces)와 공존
                        section(kind: .schedule) { scheduleSection }
                        section(kind: .input) { inputSection }
                        section(kind: .output) { outputSection }
                        // 체크인 = 항상 Output 아래(2026-08-26 대표님 "슬라이드 없이 아웃풋 아래
                        // 바로 달아줘" — 플리 s2 단계 폐기. "한 다섯번 스크롤해야" 열리던 전환 자체가
                        // 은유보다 비쌌다). 플리는 s0(플레이어 단독)→s1(전체)만 남는다.
                        CheckInCard(day: today).ticketCardGap()
                    }
                }
                .padding(20)   // 상단 추가 여백 없음 — 캘린더 탭과 로고 높이 통일(2026-08-18 베타 피드백)
                .centeredColumn(1000)
                .background {
                    GeometryReader { geo in
                        Color.clear.onGeometryChange(for: CGFloat.self) {
                            $0.frame(in: .named("todayScroll")).minY
                        } action: { offset in
                            // 성능: 프레임마다 상태 갱신 금지 — 임계 통과 순간에만 flip
                            // (연속 crossfade가 매 프레임 전체 재계산을 유발해 스크롤 버벅임)
                            let shouldCollapse = offset < -56
                            let shouldExpand = offset > -40
                            if shouldCollapse && !isCollapsed {
                                isCollapsed = true
                            } else if shouldExpand && isCollapsed {
                                isCollapsed = false
                            }
                        }
                        .frame(width: geo.size.width, height: 1)
                    }
                }
            }
            .coordinateSpace(name: "todayScroll")
            .scrollDismissesKeyboard(.interactively)   // 스크롤로도 키보드 닫힘
            // 플리 s1 → s0 되감기 = 맨 위 당김(−64). s2는 폐기(2026-08-26) — 체크인은 상시.
            .onScrollGeometryChange(for: Double.self) { g in
                g.contentOffset.y + g.contentInsets.top
            } action: { _, top in
                guard ThemeStore.chrome.playlistChrome, hSize != .regular else { return }
                if plStage == 1, top < -64 { plAdvance(0) }
            }
            compactBar
            }
        }
        .sheet(isPresented: $showLogSheet) { PeriodTrackerSheet().themeColorScheme() }
        // 테마 탭 시트 표시는 RootTabView 한 곳 — 진입점이 둘(여기·설정)이라 각자 띄우면
        // 같은 플래그를 보는 시트가 두 개가 된다(2026-08-11). 여기선 플래그만 세운다.
        .sheet(item: $addSheet) { kind in
            Group {
                switch kind {
                case .schedule: ScheduleAddSheet(defaultDate: today)
                case .input:    InputAddSheet(currentSeason: todayInfo?.meta, energyLevel: todayEnergyLevel)
                case .output:   OutputAddSheet(energyLevel: todayEnergyLevel)
                }
            }
            .themeColorScheme()
        }
        .sheet(item: $editingSchedule) { item in
            ScheduleAddSheet(defaultDate: today, editing: item).themeColorScheme()
        }
        .quickDeleteDialog($pendingDelete, completions: completions, context: modelContext)
        .sensoryFeedback(.impact(weight: .medium), trigger: confirmFeedback)
        .sensoryFeedback(.impact(weight: .light), trigger: lightFeedback)
        .coachOverlay(id: .today, steps: CoachSteps.today)   // 기능 튜토리얼(2026-07-23)
        // 씨앗 최초 획득 안내(2026-08-12) — 체크인을 완성해 씨앗이 처음 생기는 순간 발동한다.
        // 오늘 코치를 끝낸 뒤로 미루는 이유: 둘이 겹치면 어둠이 두 겹으로 깔린다.
        // 판정은 잔액(available)이 아니라 총 획득(balance) — 다 써서 0이 돼도 이미 겪은 일이다.
        .coachOverlay(id: .seed, steps: CoachSteps.seed,
                      enabled: Seeds.balance(checkIns) > 0 && CoachStore.isDone(.today))
        .task(id: schedules.count + periodDays.count) {
            // 예약할 내용이 처음 생기는 시점을 잡는다 — 일정·생리 기록이 바뀔 때마다 재판정
            showNoticeCard = await DailyNotices.shouldOfferPermission(periodDays: periodDays,
                                                                      schedules: schedules)
        }
    }

    // ── 알림 권한 안내 카드 (2026-08-08 — DailyNotices 헤더 주석의 "영원히 침묵" 결함 해소) ──
    // 카드 탭이 §5.11의 "사용자 행동 순간". 어느 쪽을 골라도 다시 묻지 않는다(재촉 금지 §7).
    private var noticePermissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("일정 있는 날 아침 브리핑과\n생리 예정일을 알림으로 챙겨드릴 수 있어요.")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Ink.text)
            HStack(spacing: 10) {
                Button("알림 받기") {
                    lightFeedback += 1
                    let currentPeriods = periodDays
                    let currentSchedules = schedules
                    Task {
                        _ = await DailyNotices.requestPermission(periodDays: currentPeriods,
                                                                 schedules: currentSchedules)
                        showNoticeCard = false
                    }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Ink.paper)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Ink.text, in: Capsule())
                Button("괜찮아요") {
                    lightFeedback += 1
                    DailyNotices.hasPromptedPermission = true
                    showNoticeCard = false
                }
                .font(.footnote)
                .foregroundStyle(Ink.text.opacity(0.55))
            }
            Text("설정의 알림에서 언제든 바꿀 수 있습니다.")
                .font(.caption)
                .foregroundStyle(Ink.text.opacity(0.45))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .milkGlass()
    }

    // ── 컬랩싱 헤더: 큰 층 ──
    private var largeHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 좌상단 브랜드 표식(2026-08-09 사용자 지시) + 우상단 씨앗 잔액.
            // 씨앗 탭 = 테마 탭 진입 / 표시값 = 소비 차감 후 available(심기 도입).
            HStack {
                // 22pt + leading 6(2026-08-09 베타 피드백 "살짝 오른쪽으로 그리고 좀 더 크게")
                BrandMark(diameter: 22, color: Ink.onGround(Ink.text.opacity(0.75), white: 0.8))
                    .padding(.leading, 6)
                Spacer()
                Button {
                    lightFeedback += 1
                    showThemeShop = true
                } label: {
                    SeedBadge(count: Seeds.available(checkIns))
                }
                .buttonStyle(.plain)
                .accessibilityHint("테마 화면을 엽니다")
                .coachAnchor(.todaySeed)   // 최초 획득 안내 대상(2026-08-12)
            }
            if let info = todayInfo {
                if ThemeStore.chrome.playlistChrome {
                    // 플레이리스트(시안 §4.4 ②) — 계절명·날짜·일차가 플레이어 카드에 이미 있어
                    // 기본 헤더 조판은 통째로 중복이다. 무드라인·생리 토글은 아래 그대로 흐른다.
                    PlaylistPlayerCard(meta: info.meta, dayInCycle: info.dayInCycle,
                                       cycleLength: snapshot.averageLength,
                                       phase: snapshot.phase(on: today), date: today)
                } else {
                    // 계절명(주인공) + 오늘 날짜(부인공) — 날짜 크게 표시 요청(2026-08-01 베타 피드백).
                    // 하루 상세와 같은 조판 언어: 큰 숫자 + 월·요일 작게. 아래 줄의 날짜 표기는 중복이라 걷음.
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        // 모던 = 아웃라인 표제(시안 §1.3-2), 그 외 = 종전 솔리드(v39~41 확정: 58px)
                        almanacDisplay(info.meta.name,
                                       size: ThemeStore.chrome.debossDisplay ? 84 : 58,
                                       color: Ink.onGround(info.meta.color.opacity(snapshot.isSingleRecord ? 0.6 : 1.0),
                                                           white: snapshot.isSingleRecord ? 0.6 : 1.0))
                            // 영어 계절명("Autumn")이 날짜 도장과 한 줄에 못 들어가 「Autum / n」으로
                            // 꺾였다(2026-08-22 베타). 한 줄 고정 + 축소 허용 — 한국어 2자는 무영향.
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                        todayDateStamp
                    }
                    HStack(spacing: 6) {
                        // 모던 = 니어블랙 가독 보정(시안 §1.3-7): 단계 100%·날짜 68%
                        // 개정 M-1c: 의학 단계명 제거 — 계절명은 위 대형 표기가 이미 담당, 일차만 남긴다.
                        // 일차 = 계절 내 일차(2026-08-09 — "봄 10일차" 주기 일차 오독 해소, 전 표면 통일)
                        Text(Loc.fmt("%lld일차", info.dayInPhase))
                            .foregroundStyle(Ink.onGround(info.meta.color.opacity(ThemeStore.chrome.boostsContrast ? 1.0 : 0.85), white: 0.9))
                        if snapshot.isSingleRecord { Text("예측 기반").foregroundStyle(Ink.onGround(Ink.text.opacity(0.45), white: 0.62)) }
                        else if info.projected { Text("예상").foregroundStyle(Ink.onGround(Ink.text.opacity(0.45), white: 0.62)) }
                    }
                    .font(.almanacBody(.footnote, size: 13))
                    .skyInkShadow()   // 날씨 = 흰 구름 위 가독(2026-08-20)
                    .groundHaze()     // 은필·기본 = 선화 위 안개(2026-08-22)
                    skyReadout        // 날씨 테마 전용 수치 줄(2026-08-20 사용자 요청)
                }
                Text(moodlineText ?? info.meta.moodline)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Ink.onGround(Ink.text.opacity(0.85), white: 0.88))
                    .padding(.top, 2)
                    .skyInkShadow()
                    .groundHaze()   // 베타 "가을이에요 문구 뒤에도 뿌옇게"(2026-08-22)
                // 기록 진입을 오늘 탭에도(2026-08-01 베타 피드백). 2026-08-02 교정: 캡슐 버튼+시트가
                // 아니라 하루 상세와 같은 인라인 토글이다("이 스위치야") — 그 자리에서 켜고 끈다.
                periodToggle
                    .padding(.top, 8)
                TicketSerial(date: today)   // 발권 번호(시안 §3.3-⑤, 티켓만)
            } else {
                Text("계절 기록 전")
                    .font(.almanac(size: 44, weight: .bold))
                    .foregroundStyle(Ink.text)
                skyReadout   // 기록 전에도 하늘은 뜬다 — 수치도 같이(2026-08-20)
            }
        }
        // 상단 24pt 제거(2026-08-18 베타 피드백 "로고 위치 캘린더 탭과 같은 위치로") —
        // 캘린더는 20pt(컨테이너)뿐인데 여기만 24pt를 더 얹어 로고가 한 층 낮게 앉았다
    }

    /// 오늘 날짜 도장 — 하루 상세(§8.2.3)와 같은 문법, 계절명에 눌리지 않게 44px
    private var todayDateStamp: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(Calendar.current.component(.day, from: today))")
                .font(.almanac(size: 44, weight: .bold))
                .foregroundStyle(Ink.onGround(Ink.text.opacity(0.85), white: 0.92))
            Text(today.formatted(Loc.dateTime.month().weekday(.abbreviated)))
                .font(.almanacBody(.caption, size: 12))
                .foregroundStyle(Ink.onGround(Ink.text.opacity(0.55), white: 0.62))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(today.formatted(Loc.dateTime.month().day().weekday(.wide)))
        .skyInkShadow()   // 날씨 = 흰 구름 위 날짜 가독(2026-08-20 베타 피드백)
    }

    /// 날씨 수치 한 줄(2026-08-20 사용자 요청) — **날씨 테마 전용**. 지금 기온이 주인공,
    /// 최고·최저·강수 확률은 보조. 값이 없거나(권한·네트워크 실패) 3시간 넘게 낡았으면
    /// 줄 자체가 사라진다 — 빈 자리를 남기거나 옛 기온을 내걸지 않는다.
    /// 좁은 폭에서 두 줄로 접히도록 HStack이 아니라 이어붙인 Text 하나로 둔다.
    @ViewBuilder
    private var skyReadout: some View {
        // wxStamp는 값이 아니라 「갱신 신호」다 — 물고 있어야 실측이 들어온 순간 이 줄이 뜬다
        if ThemeStore.chrome.skyGround, wxStamp > 0, let wx = WxState.readout {
            let now: Int = Int(wx.currentC.rounded())
            let high: Int = Int(wx.highC.rounded())
            let low: Int = Int(wx.lowC.rounded())
            let chance: Int = Int((wx.precipitationChance * 100).rounded())
            let precip: String = Loc.str(wx.precipitationIsSnow ? Loc.str("눈") : Loc.str("비"))
            let lead: Text = Text(Loc.fmt("지금 %lld°", now)).foregroundStyle(Ink.text.opacity(0.95))
            let tail: String = Loc.fmt("최고 %1$lld° 최저 %2$lld°", high, low)
                + " · " + Loc.fmt("%1$@ %2$lld%%", precip, chance)
            let rest: Text = Text(verbatim: " · " + tail).foregroundStyle(Ink.text.opacity(0.7))
            (lead + rest)
                .font(.almanacBody(.footnote, size: 13))
                .skyInkShadow()
                // 접근성 라벨은 String을 받는 오버로드라 로컬라이즈 경로가 아니다 — Text로 넘긴다
                .accessibilityLabel(Text(verbatim: Loc.fmt(
                    Loc.str("지금 %1$lld도, 최고 %2$lld도, 최저 %3$lld도, %4$@ 올 확률 %5$lld퍼센트"),
                    now, high, low, precip, chance)))
        }
    }

    // ── 컬랩싱 헤더: 컴팩트 바 층 ──
    // ── 플리 오늘 탭 3단계(시안 §4.4 ⑫) — 진입·테마 전환마다 s0으로 복귀(루트 .id 리빌드) ──
    @State private var plStage = 0
    @State private var plStageAt = Date.distantPast
    /// s0 스와이프 추종분(2026-08-26 베타 "여기 스와이프 부드럽게 처리") — 종전엔 손을 뗄 때
    /// 단계가 툭 바뀌기만 해서 화면이 손가락을 안 따라왔다. 손을 떼면 @GestureState가 스스로
    /// 0으로 돌아가며 제자리 스프링백이 된다(임계 미달 시).
    @GestureState private var plDragY: CGFloat = 0

    private func plAdvance(_ to: Int) {
        guard Date.now.timeIntervalSince(plStageAt) > 0.5 else { return }   // 관성 두 단계 건너뜀 방지
        plStageAt = .now
        withAnimation(.easeOut(duration: 0.3)) { plStage = min(1, max(0, to)) }   // s2 폐기(2026-08-26)
    }

    /// s0 — 플레이어 단독 센터 + 힌트 셰브런. 탭 또는 세로 스와이프로 s1.
    private var playlistStageZero: some View {
        VStack(spacing: 0) {
            HStack {
                // 지면 보정·진입점을 일반 오늘 탭과 동형으로(2026-08-28 전체 점검) — s0는 별도
                // 뷰 트리라 배지가 **탭 안 되는 표시**로만 있었다. 다른 화면에선 테마 탭 진입점이다.
                BrandMark(diameter: 22, color: Ink.onGround(Ink.text.opacity(0.75), white: 0.8))
                    .padding(.leading, 6)
                Spacer()
                Button {
                    lightFeedback += 1
                    showThemeShop = true
                } label: {
                    SeedBadge(count: Seeds.available(checkIns))
                }
                .buttonStyle(.plain)
                .accessibilityHint("테마 화면을 엽니다")
            }
            Spacer()
            if let info = todayInfo {
                PlaylistPlayerCard(meta: info.meta, dayInCycle: info.dayInCycle,
                                   cycleLength: snapshot.averageLength,
                                   phase: snapshot.phase(on: today), date: today)
                    .onTapGesture { plAdvance(1) }
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Ink.text.opacity(0.45))
                .padding(.top, 18)
            Spacer()
        }
        .padding(20)
        .contentShape(Rectangle())
        // 추종 = 이동 절반만 따라간다(고무줄). 임계를 넘기면 손을 뗄 때 s1로.
        .offset(y: plDragY * 0.5)
        .opacity(1 - min(0.3, abs(plDragY) / 300))
        .gesture(
            DragGesture(minimumDistance: 8)
                .updating($plDragY) { value, state, transaction in
                    state = value.translation.height
                    transaction.animation = nil   // 추종 구간은 애니메이션 없이 즉시
                }
                .onEnded { v in
                    // 던지듯 짧게 넘겨도 열리게 예측 이동량을 함께 본다
                    if abs(v.translation.height) > 30 || abs(v.predictedEndTranslation.height) > 90 {
                        plAdvance(1)
                    }
                }
        )
        .accessibilityAction(named: Loc.str("전체 보기")) { plAdvance(1) }
    }

    private var compactBar: some View {
        HStack {
            Spacer()
            Text(todayInfo?.meta.name ?? Loc.str("템포루틴"))
                .font(.almanac(size: 28, weight: .bold))   // v39~41: 58 → 28px 컴팩트 바
                .foregroundStyle(todayInfo?.meta.color ?? Ink.text)
            Spacer()
        }
        .padding(.vertical, 10)
        // 사진 지면(티켓) = 발권지 불투명 바(2026-08-25 베타 "상단 가을 바가 너무 어둡다" —
        // ultraThin이 어두운 유화를 그대로 비쳤다). 그 외 테마는 종전 재질.
        .background {
            if ThemeStore.chrome.photographicGround {
                TicketSpec.ticketPaper.ignoresSafeArea(edges: .top)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Ink.text.opacity(0.12)).frame(height: 1)   // 경계 극세 괘선(§3.3-⑦ 동조)
                    }
            } else {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea(edges: .top)
            }
        }
        .opacity(isCollapsed ? 1 : 0)
        .allowsHitTesting(false)
    }

    // ── 생리 기록 토글 (DayDetailView.periodToggle과 동형 — 2026-08-02 베타 피드백 교정) ──
    // 오늘 탭은 기준일이 항상 오늘이라 하루 상세의 미래 금지 가드(§5.5.4)는 걸 필요가 없다.
    private var periodToggle: some View {
        Toggle(isOn: Binding(
            get: { periodDays.contains { $0.day == today } },
            set: { on in
                confirmFeedback += 1
                let all = periodDays
                if on {
                    Task { await PeriodStore.add(days: [today], context: modelContext, existing: all) }
                } else {
                    let records = all.filter { $0.day == today }
                    Task { await PeriodStore.remove(records: records, context: modelContext, all: all) }
                }
            }
        )) {
            Text("생리 기록")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Ink.onGround(Ink.text, white: 0.88))
        }
        .tint(Ink.text)
        // 라벨을 스위치 바로 앞에(2026-08-23 대표님 "오른쪽 버튼 앞에 바짝") — 전폭 Toggle은 라벨을
        // 왼쪽 끝에 두고 사이를 비운다. fixedSize로 내용만큼 줄여 오른쪽으로 몬다.
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // ── S0 / S4 상태 표면 ──
    @ViewBuilder
    private var stateSurfaces: some View {
        if snapshot.isColdStart {
            VStack(alignment: .leading, spacing: 14) {
                Text("첫 생리 시작일을 기록하면, 당신의 계절이 시작돼요.")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Ink.text.opacity(0.8))
                Button {
                    showLogSheet = true
                } label: {
                    Text("첫 생리일 기록")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Ink.paper)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Ink.text, in: Capsule())
                }
            }
            .padding(.vertical, 12)
        } else if overdueDiff >= avgLength + Self.overdueGraceDays {
            Text(Loc.fmt("예정일에서 %lld일이 지났어요. 리듬은 늘 조금씩 다르니, 생리가 시작되면 캘린더에서 기록해 주세요.",
                         overdueDiff - avgLength))
                .font(.footnote)
                .foregroundStyle(Ink.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Ink.record.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var avgLength: Int { snapshot.averageLength }
    private var overdueDiff: Int {
        guard let last = snapshot.starts.max() else { return 0 }
        return cal.dateComponents([.day], from: last, to: today).day ?? 0
    }

    // ── 3구획 공통 셸 ──
    private func section(kind: CardKind, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TicketFieldLabel(text: ticketFieldName(kind))   // 발권 필드명(시안 §3.3-④, 티켓만)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.almanac(size: 17, weight: .bold))
                        .foregroundStyle(Ink.text)
                    // 플레이리스트 = 곡수 메타(시안 §4.4 ⑦ — 유형 라벨은 제목과 중복이라 기각)
                    if let meta = playlistTrackMeta(kind) {
                        Text(meta)
                            .font(.system(size: 10, weight: .medium))
                            .kerning(1.8)
                            .foregroundStyle(Ink.dim)
                    }
                }
                InfoBadge(title: kind.title, message: kind.info)   // 제목 뒤 ⓘ(2026-08-06 베타 피드백)
                Spacer()
                Button {
                    lightFeedback += 1
                    addSheet = kind
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Ink.text.opacity(0.6))
                        .frame(width: 32, height: 32)
                }
            }
            rows()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .milkGlass(stub: ticketStub(for: kind))
        .ticketCardGap()   // 티켓 간격 34 균일화(2026-08-25 베타)
        .coachAnchor(kind == .schedule ? .todaySchedule : kind == .input ? .todayInput : .todayOutput)
    }

    /// 플레이리스트 곡수 메타(시안 §4.4 ⑦) — 트랙 리스트의 `N tracks`. 체크인 카드는 트랙이
    /// 아니라 이 셸(section)을 안 쓰므로 자연히 제외된다. 다른 테마에서는 nil.
    private func playlistTrackMeta(_ kind: CardKind) -> String? {
        guard ThemeStore.chrome.playlistChrome else { return nil }
        let count = switch kind {
        case .schedule: todaySchedules.count + EventOverlay.shared.events(on: today).count
        case .input: todayInputs.count
        case .output: todayOutputs.count
        }
        return "\(count) \(count == 1 ? "TRACK" : "TRACKS")"
    }

    /// 티켓 스텁에 세울 «핵심 값 하나»(시안 §3.3-③). 티켓 테마가 아니면 쓰이지 않는다.
    /// 비어 있는 구획은 nil — 세울 값이 없는 스텁은 빈 칸으로 남아 발권물처럼 안 읽힌다.
    private func ticketStub(for kind: CardKind) -> String? {
        switch kind {
        case .schedule:
            // 시각 있는 첫 일정. 종일뿐이면 세울 값이 없다(발권물의 시각 칸에 「종일」은 어색하다)
            guard let first = todaySchedules.first(where: { !$0.isAllDay }) else { return nil }
            return first.date.formatted(Loc.shortTime)
        case .input:
            let items = todayInputs
            guard !items.isEmpty else { return nil }
            return "\(items.filter { isChecked($0.id) }.count) / \(items.count)"
        case .output:
            let items = todayOutputs
            guard !items.isEmpty else { return nil }
            let mean = items.map(\.percent).reduce(0, +) / Double(items.count)
            return "\(Int((mean * 100).rounded()))%"
        }
    }

    // ① 일정 (오늘) — 시각 있는 것 시간순, 종일(무시각)은 맨 뒤(2026-08-09 사용자 결정)
    private var todaySchedules: [ScheduleItem] {
        sortedByTimeOfDay(schedules.filter { $0.occurs(on: today) }) { item in
            item.isAllDay ? nil : cal.component(.hour, from: item.date) * 60
                + cal.component(.minute, from: item.date)
        }
    }

    @ViewBuilder
    private var scheduleSection: some View {
        if todaySchedules.isEmpty && EventOverlay.shared.events(on: today).isEmpty {
            Text("아직 없어요").font(.footnote).foregroundStyle(Ink.text.opacity(0.45))
        }
        ForEach(todaySchedules) { item in
            Button {
                lightFeedback += 1
                editingSchedule = item
            } label: {
                // 제목 먼저·시각 trailing(2026-08-09 베타 피드백 "일정명과 종일 위치 바꿔" —
                // 하루 상세 행과 같은 문법으로 통일)
                HStack(spacing: 10) {
                    Text(item.title).font(.subheadline).foregroundStyle(Ink.text)
                    // 여러 날 일정 — 오늘이 몇 일차인지(§8.2.3)
                    if let index = item.dayIndex(on: today) {
                        Text(Loc.fmt("%1$lld/%2$lld일차", index, item.spanDays))
                            .font(.caption2)
                            .foregroundStyle(Ink.text.opacity(0.5))
                    }
                    Spacer()
                    Text(item.isAllDay ? Loc.str("종일")
                         : item.date.formatted(Loc.shortTime))
                        .font(.caption)
                        .foregroundStyle(Ink.text.opacity(0.5))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(quickDeleteGesture(.schedule(item), into: $pendingDelete,
                                                    feedback: $confirmFeedback))
            .accessibilityHint("탭하면 수정, 길게 누르면 삭제할 수 있어요")
            .accessibilityAction(named: Loc.str("삭제")) { pendingDelete = .schedule(item) }
        }
        OverlayEventRows(day: today)      // EventKit read-only 오버레이(§3.6.1 — 미저장)
        CalendarConnectRow()
    }

    // ② Input (오늘) — 하루 상세와 동일 데이터(ItemCompletion) 양방향 동기화.
    // 시각 있는 것 시간순·없으면 맨 뒤(2026-08-09)
    private var todayInputs: [InputItem] {
        sortedByTimeOfDay(todayInputsUnsorted) { $0.timeMinutes }
    }

    private var todayInputsUnsorted: [InputItem] {
        inputs.filter { item in
            switch item.schedule {
            case .once:
                // 적어 넣은 그날에만(2026-08-20 개정 — Output과 통일). 과거에 다른 날
                // 완료한 이력이 있으면 그 완료일에는 기록으로 남는다(isChecked = 오늘 완료)
                item.onceShows(on: today) || isChecked(item.id)
            case .daily, .weekly, .monthly:
                item.occursByCalendar(on: today)
            case .cycleAnchored(let r):
                snapshot.occurrence(of: r, createdAt: cal.startOfDay(for: item.createdAt), on: today) != nil
                    || isChecked(item.id)
            }
        }
    }

    private func isChecked(_ itemID: UUID) -> Bool {
        completions.contains { $0.itemID == itemID && cal.isDate($0.occurredOn, inSameDayAs: today) }
    }

    private func toggleCheck(_ itemID: UUID) {
        if let existing = completions.first(where: { $0.itemID == itemID && cal.isDate($0.occurredOn, inSameDayAs: today) }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(ItemCompletion(itemID: itemID, occurredOn: today))
        }
    }

    /// 그날의 진행 레코드 — 없으면 nil(안 만진 날은 레코드도 안 생긴다)
    private func progressRecord(_ itemID: UUID) -> InputProgress? {
        inputProgresses.first { $0.itemID == itemID && cal.isDate($0.occurredOn, inSameDayAs: today) }
    }

    private func ensureProgress(_ itemID: UUID) -> InputProgress {
        if let existing = progressRecord(itemID) { return existing }
        let created = InputProgress(itemID: itemID, occurredOn: today)
        modelContext.insert(created)
        return created
    }

    /// 목표 도달 = 그날 체크(2026-08-12). 하루 상세와 같은 규칙 — 되돌리면 체크도 풀리고,
    /// 스톱워치는 판정이 항상 false라 손 체크를 지우지 않도록 걸러낸다.
    private func syncAutoCompletion(_ item: InputItem, fulfilled: Bool) {
        guard item.progressKind != .stopwatch else { return }
        let checked = isChecked(item.id)
        guard fulfilled != checked else { return }
        confirmFeedback += 1
        toggleCheck(item.id)
    }

    private func inputCheckRow(_ item: InputItem) -> some View {
        let checked = isChecked(item.id)
        return Button {
            confirmFeedback += 1
            toggleCheck(item.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(checked ? Ink.text : Ink.text.opacity(0.35))
                Text(item.title)
                    .font(.subheadline)
                    .foregroundStyle(Ink.text)
                    .strikethrough(checked, color: Ink.dim)
                Spacer()
                // 파서가 읽은 시각 — 일정 행과 같은 trailing 문법(2026-08-09)
                if let t = item.timeMinutes {
                    Text(timeOfDayLabel(t))
                        .font(.caption)
                        .foregroundStyle(Ink.text.opacity(0.5))
                }
            }
        }
        .simultaneousGesture(quickDeleteGesture(.input(item), into: $pendingDelete,
                                                feedback: $confirmFeedback))
        .accessibilityValue(checked ? Loc.str("완료") : Loc.str("미완료"))
        .accessibilityAction(named: Loc.str("삭제")) { pendingDelete = .input(item) }
    }

    @ViewBuilder
    private var inputSection: some View {
        if todayInputs.isEmpty {
            Text("아직 없어요").font(.footnote).foregroundStyle(Ink.text.opacity(0.45))
        } else {
            ForEach(todayInputs) { item in
                VStack(alignment: .leading, spacing: 4) {
                    inputCheckRow(item)
                    // 진행 방식이 붙은 Input만(2026-08-12) — 하루 상세와 같은 데이터·같은 컨트롤
                    if let goal = item.progressGoal {
                        InputProgressControl(
                            goal: goal,
                            itemID: item.id,
                            itemTitle: item.title,
                            subtasks: item.subtasks ?? [],
                            progress: progressRecord(item.id),
                            ensureProgress: { ensureProgress(item.id) },
                            onChange: { fulfilled in syncAutoCompletion(item, fulfilled: fulfilled) }
                        )
                        .padding(.leading, 26)   // 체크 아이콘 폭만큼 들여쓰기
                    }
                }
            }
        }
    }

    // ③ Output (오늘 occurrence) + 계절 레버 카피 — 시각 정렬은 Input과 동일(2026-08-09)
    private var todayOutputs: [OutputItem] {
        sortedByTimeOfDay(todayOutputsUnsorted) { $0.timeMinutes }
    }

    private var todayOutputsUnsorted: [OutputItem] {
        outputs.filter { item in
            switch item.schedule {
            case .once, .daily, .weekly, .monthly:
                return item.occursByCalendar(on: today)
            case .cycleAnchored(let r):
                guard let occ = snapshot.occurrence(of: r, createdAt: cal.startOfDay(for: item.createdAt), on: today) else {
                    return false
                }
                return !(item.isComplete && occ.projected)
            }
        }
    }

    /// 콜드스타트(생리 미기록)에서는 Output이 있어도 주기 앵커를 못 풀어 전부 안 보임 — 이유를 밝힌다.
    private var outputEmptyMessage: String {
        let hasColdBlocked = snapshot.isColdStart && outputs.contains {
            if case .cycleAnchored = $0.schedule { return true }
            return false
        }
        return hasColdBlocked ? Loc.str("생리를 기록하면 계획이 보이기 시작해요.")
                              : Loc.str("아직 없어요")
    }

    @ViewBuilder
    private var outputSection: some View {
        if todayOutputs.isEmpty {
            Text(outputEmptyMessage).font(.footnote).foregroundStyle(Ink.text.opacity(0.45))
        } else {
            ForEach(todayOutputs) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                        if let target = item.targetDate {
                            DDayBadge(target: target, from: today)
                        }
                        if item.isComplete {
                            Text("완료").font(.caption2.weight(.semibold)).foregroundStyle(Ink.text.opacity(0.6))
                        }
                        Spacer()
                        if let t = item.timeMinutes {   // 파서 시각 — trailing 문법(2026-08-09)
                            Text(timeOfDayLabel(t))
                                .font(.caption)
                                .foregroundStyle(Ink.text.opacity(0.5))
                        }
                    }
                    outputProgress(item)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .simultaneousGesture(quickDeleteGesture(.output(item), into: $pendingDelete,
                                                        feedback: $confirmFeedback))
                .accessibilityAction(named: Loc.str("삭제")) { pendingDelete = .output(item) }
            }
        }
        if let meta = todayInfo?.meta, !todayOutputs.isEmpty {
            Text(meta.lever)
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.55))
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func outputProgress(_ item: OutputItem) -> some View {
        switch item.progressKind {
        case .checkOnly:
            // 체크만(2026-08-18) — 저장은 percent 0↔1. 완료는 종전대로 파생(isComplete).
            Button {
                item.percent = item.percent >= 1 ? 0 : 1
                if item.percent >= 1 { confirmFeedback += 1 } else { lightFeedback += 1 }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: item.percent >= 1 ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.percent >= 1 ? Ink.text : Ink.text.opacity(0.35))
                    Text(item.percent >= 1 ? Loc.str("완료") : Loc.str("체크"))
                        .font(.footnote)
                        .foregroundStyle(Ink.text.opacity(item.percent >= 1 ? 1 : 0.6))
                    Spacer()
                }
            }
            .accessibilityValue(item.percent >= 1 ? Loc.str("완료") : Loc.str("미완료"))
        case .subtasks:
            let list = (item.subtasks ?? []).sorted { $0.order < $1.order }
            ForEach(list) { sub in
                Button {
                    confirmFeedback += 1
                    sub.isDone.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: sub.isDone ? "checkmark.square.fill" : "square")
                            .foregroundStyle(sub.isDone ? Ink.text : Ink.text.opacity(0.35))
                        Text(sub.title).font(.footnote).foregroundStyle(Ink.text)
                            .strikethrough(sub.isDone, color: Ink.dim)
                        Spacer()
                    }
                }
                .accessibilityValue(sub.isDone ? Loc.str("완료") : Loc.str("미완료"))
            }
        case .sessions:
            SessionProgressControl(logged: item.loggedSessions,
                                   target: item.targetSessions) { next, completed in
                item.loggedSessions = next
                if completed { confirmFeedback += 1 } else { lightFeedback += 1 }
            }
        case .percent:
            HStack(spacing: 10) {
                Slider(value: Binding(get: { item.percent }, set: { item.percent = $0 }), in: 0...1)
                    .tint(Ink.text)
                Text(item.percent.formatted(.percent.precision(.fractionLength(0))))
                    .font(.footnote).monospacedDigit()
                    .foregroundStyle(Ink.text.opacity(0.7))
                    .frame(width: 44, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(item.percent.formatted(.percent.precision(.fractionLength(0))))
        case .timer, .stopwatch:
            TimerProgressControl(backing: item, activityID: item.id, activityTitle: item.title,
                                 isTimer: item.progressKind == .timer,
                                 targetSeconds: item.targetSeconds ?? 0,
                                 isInput: false) { completed in
                if completed { confirmFeedback += 1 } else { lightFeedback += 1 }
            }
        }
    }

}

// ── Output 목표일 배지(2026-08-01 베타 피드백) — 오늘 탭·하루 상세 공용 ──
// 기준일은 그 화면이 보고 있는 날짜다(하루 상세에서 과거를 보면 그날 기준 D-N).
struct DDayBadge: View {
    let target: Date
    var from: Date = .now

    private var remaining: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: from),
                                  to: cal.startOfDay(for: target)).day ?? 0
    }

    private var label: String {
        if remaining == 0 { return "D-DAY" }
        return remaining > 0 ? "D-\(remaining)" : "D+\(-remaining)"
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            // 지난 목표일은 벌점이 아니라 사실 표기 — 경고색을 쓰지 않는다(§7 가드레일 톤)
            .foregroundStyle(Ink.text.opacity(remaining < 0 ? 0.45 : 0.7))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Ink.text.opacity(0.08), in: Capsule())
            .accessibilityLabel(Text(verbatim: remaining >= 0
                                     ? Loc.fmt("목표일까지 %lld일", remaining)
                                     : Loc.fmt("목표일에서 %lld일 지남", -remaining)))
    }
}
