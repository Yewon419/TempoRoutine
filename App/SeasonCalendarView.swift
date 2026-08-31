// 템포루틴 — 계절 캘린더 (Phase 0 ③, MASTER §5.9-3 / §8.2.3 / §4 보강 I 책력 조판)
// 계절 = 숫자 잉크색(글리프 정식 이식은 §5.9-8 미학 패스), 오늘 = 은필 채운 원,
// 생리 = 코랄 형광펜(기록) / 회색 형광펜(예상, 미래만 — 과거 소급 투영 금지 §5.6.2).
// 생리 기록은 조회 전용(2026-07-20 사용자 결정 — 드래그·길게 누르기 편집 폐기, MASTER I-2b 개정 대기).
// 기록 편집 = 상단 "생리 기록" 버튼 → PeriodTrackerSheet(건강 앱 문법) + 하루 상세 토글(접근성 유지).
// 탭 = 하루 상세 push / 길게 누르기 = 빠른 일정 추가(2026-07-25 사용자 지시 — 일정 한정, 생리 기록과 무관).

import SwiftUI
import SwiftData
import TempoCore
import UIKit

struct SeasonCalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSize   // 아이패드 분할 뷰(2026-07-23)
    @Query(sort: \PeriodDay.day) private var periodDays: [PeriodDay]
    @Query(sort: \ScheduleItem.date) private var schedules: [ScheduleItem]
    @Query(sort: \InputItem.createdAt) private var inputs: [InputItem]
    @Query(sort: \OutputItem.createdAt) private var outputs: [OutputItem]
    @Query private var checkIns: [DailyCheckIn]   // 씨앗 스티커 근거(2026-08-09)

    @State private var monthAnchor = Calendar.current.startOfDay(for: .now)
    @State private var showLogSheet = false
    @State private var showNotices = false          // 소식란(2026-08-09)
    private let noticeFeed = NoticeFeed.shared      // @Observable — 미읽음 점 추종
    @State private var pushedDay: Date?
    @State private var selectedDay: Date?       // regular 분할 뷰의 우측 하루 상세 선택(2026-07-23)
    @State private var quickAddDay: Date?       // 길게 누른 날짜 → 빠른 일정 시트(2026-07-25)
    @State private var quickAddEnd: Date?       // 드래그 기간 선택의 끝 날짜 — nil = 하루(2026-07-27)
    @State private var dragStart: Date?         // 드래그 중 선택 앵커(누른 셀)
    @State private var dragEnd: Date?           // 드래그 중 현재 셀
    @State private var gridSize: CGSize = .zero // 드래그 좌표 → 셀 역산용
    @State private var dragX: CGFloat = 0       // 월 캐러셀 손가락 추종 오프셋(2026-07-27 사용자 지시)
    @State private var monthDragEngaged = false // 수평 의도 확정 후에만 추종
    @State private var monthAnimating = false   // 정착/스냅백 애니메이션 중(옆 달 유지용)
    // 드래그 프레임마다 body가 재평가된다 — 월 렌더 데이터(마크·띠·스타일·형광펜)는 여기 캐시로만
    // 읽는다. 드래그 시작 때 3개 달을 한 번 계산하고, 전환이 끝나면 비운다(성능 결함 수정 2026-07-27).
    @State private var renderCache: [Date: MonthRender] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme   // 상단 계절광 다크 감쇠
    @State private var pressFeedback = 0        // 길게 누르기 진입 햅틱(중간 — 탭보다 강하게)
    @State private var lightFeedback = 0        // 작은 햅틱(§4 — 월 이동·날짜 셀 탭. 셀 탭은 .selection→작은 승격, 2026-07-23 체감 피드백)
    // 체크인 완료일(2026-08-09) — 과거 완료일 숫자 흐림 표시의 근거 집합
    @State private var completedDays: Set<Date> = []
    // 활판 월 표제 감량분(pt, 2026-08-23 실기기 대조) — 격자가 최소 높이를 못 받을 때만 >0.
    // 시안 §2.3-10의 「6주 달은 112」를 기기 편차까지 확장: 빌드 462에서 8월(6주) 마지막 주가
    // 통째로 잘렸다(격자 295pt < 필요 344pt). 상한(150/112)에서 부족분만큼만 내린다.
    @State private var titleShrink: CGFloat = 0
    // 활판 양보 사다리(2026-08-25 개정 — 베타 "고전소설 문구 어디 들어간거야": 6주 달에서 인용문이
    // 통째로 숨었다): ① 표제 150/112→64 ② 셀 최소 54→48 ③ 인용문 숨김(최후). 시안 .phone(844)엔
    // 안전영역·홈 인디케이터가 없어 실기기가 항상 더 좁다(16차 전례).
    @State private var lpQuoteHidden = false
    @State private var lpCellTight = false

    // v16 확정: 개방형·풀하이트 — 그리드가 남은 세로를 균등 분할(grid-auto-rows: 1fr).
    // 고정 셀 높이 폐기, 최소 높이만 보장(일정 글줄 노출 여지 — 프로토 min-height 54px).
    private let minCellHeight: CGFloat = 54
    // 여러 날 띠 — 계절 밑줄(~29.5)과 3.5pt 간격을 두고(2026-07-28 시안 결정), 레인 간격 포함 13pt씩
    private let bandHeight: CGFloat = 11
    private let bandTop: CGFloat = 33.5
    private let bandGap: CGFloat = 3.5   // 숫자 영역(30)과 띠·박스·글줄 사이 간격
    private var bandSlot: CGFloat { bandHeight + 2 }
    /// 예측 형광펜 회색 — 다크에선 한 단계 밝게 (기준 대응 팔레트)
    private let highlightGray = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x9B / 255, green: 0xA2 / 255, blue: 0xA8 / 255, alpha: 1)
            : UIColor(red: 0x87 / 255, green: 0x8E / 255, blue: 0x94 / 255, alpha: 1)
    })

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: .now) }
    private var recordedDays: Set<Date> { Set(periodDays.map(\.day)) }
    private var starts: [Date] { PeriodMath.episodeStarts(days: periodDays.map(\.day)) }
    // CycleParams 경유(개정 M) — 직접 CyclePredictor를 부르면 prior·M 반영이 스냅샷과 갈라진다
    private var avgLength: Int { CycleParams.averageLength(starts: starts) }
    private var menstrualLength: Int { CycleParams.menstrualLength(days: periodDays.map(\.day)) }

    /// §5.6.2 투영 지평 — low=1 / medium=2 / high=3 주기까지만 예측 렌더.
    private var horizonCycles: Int {
        switch CyclePredictor.confidence(periodStarts: starts) {
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }

    // ── 월 그리드 파라미터 — 캐러셀이 이전/현재/다음 달을 함께 그려서 파라미터화(2026-07-27) ──
    private struct MonthLayout {
        let start: Date
        let daysInMonth: Int
        let leadingBlanks: Int
        let rowCount: Int
        private let calendar: Calendar

        init(anchor: Date, calendar: Calendar) {
            self.calendar = calendar
            self.start = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)) ?? anchor
            self.daysInMonth = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
            self.leadingBlanks = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
            self.rowCount = (leadingBlanks + daysInMonth + 6) / 7
        }

        func date(at index: Int) -> Date? {
            let dayNumber = index - leadingBlanks + 1
            guard dayNumber >= 1 && dayNumber <= daysInMonth else { return nil }
            return calendar.date(byAdding: .day, value: dayNumber - 1, to: start)
                .map { calendar.startOfDay(for: $0) }
        }
    }

    private func layout(offsetMonths: Int) -> MonthLayout {
        let base = cal.date(byAdding: .month, value: offsetMonths, to: monthAnchor) ?? monthAnchor
        return MonthLayout(anchor: base, calendar: cal)
    }
    private var currentLayout: MonthLayout { layout(offsetMonths: 0) }
    private var monthStart: Date { currentLayout.start }

    var body: some View {
        // 바깥 ZStack = 빠른 일정 바의 그릇. 본문에만 키보드 무시를 걸어야
        // 캘린더는 제자리에 있고 바만 키보드를 따라 올라온다 — 순서를 뒤집으면 바가 키보드에 가린다.
        ZStack(alignment: .bottom) {
            calendarBody
                .ignoresSafeArea(.keyboard, edges: .bottom)
            quickAddLayer
        }
        .animation(.easeOut(duration: 0.22), value: quickAddDay)
        .sheet(isPresented: $showLogSheet) {
            PeriodTrackerSheet().themeColorScheme()
        }
        .sheet(isPresented: $showNotices) { NoticesView().themeColorScheme() }
        .task { await noticeFeed.refresh() }   // 캘린더 진입 시 미읽음 점 갱신(1시간 캐시)
        .coachOverlay(id: .calendar, steps: CoachSteps.calendar)   // 기능 튜토리얼(2026-07-23)
        .sensoryFeedback(.impact(weight: .light), trigger: lightFeedback)
        .sensoryFeedback(.impact(weight: .medium), trigger: pressFeedback)
        .navigationDestination(isPresented: Binding(
            get: { pushedDay != nil },
            set: { if !$0 { pushedDay = nil } }
        )) {
            if let pushedDay {
                DayDetailView(day: pushedDay)
            }
        }
        // 체크인 완료일(2026-08-09) — 집합은 상태로 들고 셀은 조회만(드래그 프레임 경로 규칙).
        // ⚠ 씨앗 스티커는 같은 날 베타 피드백("스티커같지 않다")으로 폐기 — 과거 완료일 숫자
        // 흐림으로 대체. 등장 연출·하단 토글도 함께 걷음.
        .task(id: seedStamp) { completedDays = Seeds.completedDays(checkIns) }
    }

    /// 도장 유무·개수만 요약한 스탬프 — body 평가당 O(n) 1회로 재계산 트리거를 만든다
    /// (@Query 배열은 Equatable이 아니라 onChange 불가, 셀마다 파생 계산은 드래그 규칙 위반).
    private var seedStamp: Int {
        checkIns.count &* 1000 &+ checkIns.filter { $0.completedAt != nil }.count
    }

    /// 캘린더 본문 — 지면·계절광·(아이패드)분할. body에서 떼어내 타입체크 부담을 줄인다.
    private var calendarBody: some View {
        ZStack {
            // 캘린더 자체 지면(2026-07-28 시안 결정) — frost 바탕 + 계절광은 상단에만 걸리고
            // 사그라든다(그리드 영역은 깨끗하게 — 글로우 밑줄 가독 담보)
            // ⚠ 티켓만 예외: 캘린더 지면이 흰 발권물이다(frost = 블루그레이 색면이라 여기선 안 쓴다).
            // ⚠ 날씨 = 하늘 + 다크 베일 14%(시안 §5.3-1 — 낮 하늘 위 격자 흰 숫자 대비).
            if ThemeStore.chrome.skyGround {
                WeatherSky(veil: 0.14)
            } else if ThemeStore.chrome.videoGround {
                // 캘린더만 흐린 지면(2026-08-26 베타) — 격자가 영상 디테일과 안 겹치게.
                // 16 → 8 → 4(2026-08-27 "블러 0.5배" 판정)
                PlaylistVideoGround(blurRadius: 4)
            } else {
                (ThemeStore.chrome.ticketChrome ? TicketSpec.ticketPaper : Ink.frost)
                    .ignoresSafeArea()
            }
            if ThemeStore.chrome.texture == .dotGrid {
                DotGrid().ignoresSafeArea()   // 모던 전용 질감(시안 §1.3-1)
            }
            calendarTopGlow
            if hSize == .regular {
                // 아이패드: 캘린더 + 하루 상세 분할(2026-07-23). 우측 계절광은 선택일 단계를 따름.
                HStack(alignment: .top, spacing: 0) {
                    calendarColumn()
                        .frame(maxWidth: 560)
                    Divider().overlay(Ink.text.opacity(0.12))
                    DayDetailView(day: selectedDay ?? today)
                        .id(selectedDay ?? today)
                        .frame(maxWidth: .infinity)
                }
            } else {
                calendarColumn()
            }
            // 플리 = LP 상단 덮개(2026-08-25 대표님 "LP판 상단부가 안예뻐서 하얀 바로 덮어버리자").
            // 디스크는 화면 위로 넘쳐 잘리는데 그 잘린 테가 상태바와 겹쳐 지저분했다. 흰 바를
            // 맨 위에 얹으면 디스크가 **바 아래에서 솟은 것**으로 읽히고, 확인 큐의
            // 「상태바 시계가 디스크 위에서 읽히는지」도 같이 해소된다.
            // 덮는 높이 = 안전영역(상태바 밴드)까지. 더 내리려면 `playlistTopBarDrop`만 올린다.
            if ThemeStore.chrome.playlistChrome {
                VStack(spacing: 0) {
                    // 색을 `background`로 깐다 — 고정 높이 프레임에 `ignoresSafeArea`를 직접 걸면
                    // 뷰가 안 늘어나 상태바 밴드가 안 칠해진다(유연한 배경만 확장된다).
                    Color.clear
                        .frame(height: playlistTopBarDrop)
                        .background(Color.white.ignoresSafeArea(edges: .top))
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// LP 덮개가 안전영역 아래로 더 내려오는 몫(pt). 0 = 상태바 밴드까지만.
    private let playlistTopBarDrop: CGFloat = 0

    /// 빠른 일정 = 시트가 아니라 키보드 위에 붙는 바(2026-08-01 사용자 지시) — 뒤 캘린더가 그대로 보인다.
    @ViewBuilder
    private var quickAddLayer: some View {
        if quickAddDay != nil {
            // 바깥 탭 = 닫기. 옅은 dim으로 입력 중임을 알리되 뒤 화면은 계속 읽힌다.
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture { closeQuickAdd() }
                .transition(.opacity)
        }
        if let quickAddDay {
            QuickScheduleBar(day: quickAddDay, endDay: quickAddEnd, onClose: closeQuickAdd)
                .transition(.move(edge: .bottom))
        }
    }

    /// 빠른 일정 바 걷기 — 저장 후·바깥 탭 공용(2026-08-01)
    private func closeQuickAdd() {
        quickAddDay = nil
        quickAddEnd = nil
    }

    /// 실측 에피소드 길이(시작일 키) + 관측 우선 유효 M(2026-08-09 사용자 결정 —
    /// "기록된 생리일이 계절 경계를 이긴다"). CycleSnapshot.effectiveMenstrualLength와 같은 규칙 —
    /// 캘린더가 스냅샷과 다른 M을 쓰면 계절 라인과 밴드가 갈라진다.
    private var episodeLengthByStart: [Date: Int] {
        Dictionary(uniqueKeysWithValues:
            zip(starts, PeriodMath.episodeLengths(days: periodDays.map(\.day))))
    }

    private func effectiveM(on date: Date, projected: Bool) -> Int {
        guard !projected, let start = starts.last(where: { $0 <= date }) else { return menstrualLength }
        return min(10, max(menstrualLength, episodeLengthByStart[start] ?? 0))
    }

    /// 오늘의 단계 — 상단 글로우 색 결정용(seasonLine과 같은 계산 경로)
    private var todayPhase: CyclePhase? {
        guard let r = CyclePredictor.cycleDay(of: today, periodStarts: starts, averageLength: avgLength) else {
            return nil
        }
        return CyclePredictor.phaseForDay(r.day, cycleLength: avgLength,
                                          menstrualLength: effectiveM(on: today, projected: r.projected))
    }

    /// 상단 계절광(2026-07-28 시안 결정) — SeasonLight 원색 2겹을 상단 앵커로만, 다크는 감쇠.
    /// ⚠ 캘린더는 `SeasonLight` 뷰를 쓰지 않고 여기서 직접 그린다 — 게이트를 따로 걸어야 한다
    /// (2026-08-12: 기본 테마에서 캘린더 탭만 계절광이 남아 지면이 다른 탭과 달라 보였다).
    @ViewBuilder
    private var calendarTopGlow: some View {
        if ThemeStore.chrome.showsSeasonLight {
            calendarTopGlowLayers
        }
    }

    private var calendarTopGlowLayers: some View {
        // 다른 탭과 **같은 SeasonLight**(3겹 radial + 테마 질감) — 종전엔 2겹만 상단 앵커로 직접
        // 그려, 같은 원색인데도 세 번째 겹·선화 질감이 빠져 색감이 달리 읽혔다(2026-08-22 베타
        // "같은 가을인데 캘린더탭 색감만 이질적"). 그리드는 깨끗해야 하므로(2026-07-28 결정) 빛과
        // 질감이 헤더 아래로 사그라드는 마스크만 얹는다 — 구성은 오늘 탭과 동일, 범위만 상단.
        SeasonLight(phase: todayPhase)
            .mask(
                LinearGradient(stops: [.init(color: .black, location: 0.0),
                                       .init(color: .black, location: 0.22),
                                       .init(color: .clear, location: 0.40)],
                               startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            )
    }

    /// 캘린더 열 — compact에선 전체 화면, regular에선 분할 좌측(2026-07-23)
    private func calendarColumn() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if ThemeStore.chrome.ticketChrome {
                // 티켓 히어로 밴드(2026-08-31 시안 §3.4 증강) — 확성기 줄까지는 어두운 계절
                // 유화, 그 아래부터 흰 발권지(베타 "공지 버튼 바로 아래에서 흰색 부분 끊어줘.
                // 그 위는 다른 탭들처럼 어둡게"). 브랜드 표식·소식란이 이 위에 흰 잉크로 얹힌다
                // — 종전엔 `.cal-top`을 통째로 숨겨 소식란 진입점이 사라졌던 자리(2026-08-27
                // 베타 "공지가 없네")를 살린 것과 같은 문법, 배경만 바뀌었다.
                ticketHeroBand
                    .padding(.bottom, 14)   // 스캘럽과 조판 사이 여백(대표님 "여백 더 만들어")
                ticketHeaderBlock
            } else if ThemeStore.chrome.playlistChrome {
                // 플레이리스트 = 레코드판(시안 §4.4 ③, 2026-08-25 확정). 브랜드 표식·소식란은
                // 상단 행 유지 — 디스크는 헤더 background로 위로 넘쳐 상단 반노출이 된다.
                HStack {
                    BrandMark(diameter: 22, color: Ink.text.opacity(0.75))
                        .padding(.leading, 6)
                    Spacer()
                    noticeButton()
                }
                PlaylistRecordHeader(
                    year: cal.component(.year, from: monthStart),
                    month: cal.component(.month, from: monthStart),
                    phase: currentPhase,
                    date: today,
                    trackDay: playlistTrack.day,
                    trackLength: playlistTrack.length,
                    compact: currentLayout.rowCount >= 6,
                    onPrev: { lightFeedback += 1; shiftMonth(-1) },
                    onStop: { lightFeedback += 1; returnToTodayMonth() },
                    onNext: { lightFeedback += 1; shiftMonth(1) }
                )
            } else {
                // 상단 순서 = 시안 `.cal-wrap .season-row { order:-1 }` 전 테마 공통(2026-08-23 대표님
                // "프로토타입 디자인대로"): 계절 줄·생리 기록 → 브랜드 표식·소식란 → 거대 표제·월 이동.
                // 종전엔 포인트컬러 전용 분기(seasonRowFirst)였고 08-16 개편 뒤엔 전 테마가 표제 아래였다.
                seasonHeaderRow
                HStack {
                    BrandMark(diameter: 22, color: Ink.text.opacity(0.75))   // 오늘 탭과 동일 보정(2026-08-09 피드백)
                        .padding(.leading, 6)
                    Spacer()
                    noticeButton()
                }
                monthHeader
                // 활판 = 표제 아래 계절 고전 인용문(시안 §2.3-5, 2026-08-24 "인앱에도")
                if ThemeStore.chrome.latinCalendarHeader, !lpQuoteHidden {
                    letterpressQuoteBlock
                }
            }
            weekdayRow
            // 월 표면이 손가락을 따라 움직인다(2026-07-27 사용자 지시 — 인식 후 전환에서 추종으로).
            // 이전/현재/다음 달을 나란히 렌더하고 오프셋으로 민다 — 놓으면 임계 판정 후 정착.
            monthCarousel
                .coachAnchor(.calendarGrid)
            legend
            // ⚠ 뒤에 Spacer를 두지 않는다(2026-08-23) — 캐러셀(GeometryReader)과 남는 세로를
            // 반씩 나눠 격자가 21pt 손해 봤다. 시안은 격자 하단 = 범례 상단(.cal-wrap flex).
        }
        .padding(20)
        // 가로 드래그 = 월 이동(손가락 추종). 셀 기간 선택과의 분리는 종전과 동일 —
        // 롱프레스는 정지 0.4s 인식이라 먼저 움직이면 이 드래그가 이긴다. 선택 중엔 개입 안 함.
        .gesture(monthDragGesture)
    }

    // ── 티켓 전용 상단(시안 §3.4) ──
    /// 히어로 밴드 — 브랜드 표식·소식란(흰 잉크, 정상 위치) + 유화 배경(세이프에어리어까지 번짐).
    /// 배경만 번지는 패턴은 종전 사진 지면 상단바(TodayView.compactBar)와 같은 idiom —
    /// 전경은 제자리, `.background` 안에서만 `.ignoresSafeArea`를 태운다.
    private var ticketHeroBand: some View {
        HStack {
            BrandMark(diameter: 22, color: .white)
                .padding(.leading, 6)
            Spacer()
            noticeButton(tint: .white)
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(alignment: .top) {
            TicketHeroArtwork(phase: currentPhase, label: Self.ticketHeroLabel(monthStart))
                .ignoresSafeArea(edges: .top)
        }
    }

    /// 히어로 라벨 "2026 · JULY" — 활판 라틴 날짜 스탬프와 같은 규약(en_US 고정, 로컬라이제이션
    /// 대상 아님 — 시안 원본 문법이 라틴이다).
    private static let ticketHeroFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "yyyy · MMMM"
        return formatter
    }()

    private static func ticketHeroLabel(_ date: Date) -> String {
        ticketHeroFormatter.string(from: date).uppercased()
    }

    private var ticketHeaderBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            TicketMonthHeader(
                year: cal.component(.year, from: monthStart),
                month: cal.component(.month, from: monthStart),
                seasonLine: seasonLine,
                phase: currentPhase,
                onLogTap: { showLogSheet = true }
            )
            .coachAnchor(.calendarLog)
            // ⚠ 노치는 절취선과 **한 상자(ZStack)** 안에서 그린다(2026-08-17 베타 피드백 "노치 안맞고").
            // 종전엔 음수 패딩 **바깥**에 overlay를 붙였는데, 음수 패딩은 그린 영역만 넓히고
            // 보고 프레임은 그대로라 overlay가 좁은 상자 기준으로 붙었다 — 노치가 화면 끝이
            // 아니라 20pt 안쪽에, 선보다 위에 떠 있었다. ZStack 안에서는 선(중앙)과 노치(양 끝
            // 중앙)가 같은 좌표계를 쓰므로 어긋날 자리가 없다.
            ZStack {
                TicketPerforation()
                HStack {
                    ticketNotch(pointsLeft: false)
                    Spacer()
                    ticketNotch(pointsLeft: true)
                }
            }
            .frame(height: 18)
            .padding(.horizontal, -20)
            .padding(.top, 7)
        }
    }

    private func ticketNotch(pointsLeft: Bool) -> some View {
        TicketNotch(pointsLeft: pointsLeft)
            .fill(TicketSpec.notch)
            .frame(width: 10, height: 18)
    }

    /// 계절 라인 + 생리 기록 버튼 — 상단 순서 분기용 추출(2026-07-29, 내용 무변화)
    private var seasonHeaderRow: some View {
        HStack(alignment: .firstTextBaseline) {
            // 번들 서체 명시(2026-08-09 베타 피드백 "봄 10일차 저거도" — New York은 한글 글리프가
            // 없어 고딕 폴백되던 것, 08-01 계절 라벨 2건과 같은 뿌리)
            Text(seasonLine)
                .font(.almanacBody(.subheadline, size: 15))
                .foregroundStyle(Ink.text.opacity(0.65))
            Spacer()
            // 기록 편집 진입 — 캘린더 탭 자체는 조회 전용
            Button {
                showLogSheet = true
            } label: {
                HStack(spacing: 5) {
                    Circle().fill(Ink.record).frame(width: 7, height: 7)
                    Text("생리 기록")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ink.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(Capsule().stroke(Ink.text.opacity(0.3), lineWidth: 1))
            }
            .coachAnchor(.calendarLog)   // 기능 튜토리얼(2026-07-23)
        }
    }

    /// 옆 달은 드래그·전환 중에만 실렌더 — 유휴 렌더 비용을 종전(1개 달)으로 유지
    private var sidesVisible: Bool { monthDragEngaged || monthAnimating || dragX != 0 }

    private var monthCarousel: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            HStack(spacing: 0) {
                sidePanel(-1, width: w)
                monthGrid(offsetMonths: 0, width: w)
                sidePanel(1, width: w)
            }
            .offset(x: -w + dragX)
        }
        .clipped()
        // 격자 그릇 높이 = 표제 역산의 입력. 격자 자체(rows minHeight)는 그릇보다 커도 잘려서
        // 그릇을 재야 한다 — gridSize는 넘친 뒤의 값이라 부족분을 못 본다.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            if ThemeStore.chrome.latinCalendarHeader { fitLetterpressTitle(carouselHeight: height) }
        }
    }

    /// 활판 월 표제 상한 — 시안 §2.3-3·§2.3-10(5주 150 / 6주 112)
    private var letterpressTitleCap: CGFloat { currentLayout.rowCount >= 6 ? 112 : 150 }
    /// 실제 표제 크기 = 상한 − 감량분. 바닥 64 — 그 아래는 음각 선이 안 선다(§2.3-12 「크게 써야 선이 보인다」)
    private var letterpressTitleSize: CGFloat { max(64, letterpressTitleCap - titleShrink) }

    /// 표제 역산(2026-08-23). 격자 최소 = 행×54 + 행간 4. 부족하면 그만큼 표제를 줄이고 남으면
    /// 상한까지 되돌린다. 표제 라인박스가 1.02×크기(고정 프레임)라 한 걸음에 수렴 — 0.5pt 이하는 무시.
    /// 인용문 양보(2026-08-24): 표제가 바닥인데도 모자라면 인용문(≈85pt)을 내린다. 복귀는
    /// 여유가 인용문 높이보다 확실히 클 때만(-110pt) — 히스테리시스로 왕복을 막는다.
    private func fitLetterpressTitle(carouselHeight: CGFloat) {
        // 첫 레이아웃 패스의 설익은 높이(수십 pt)로 사다리가 한 번에 ③까지 내려가던 것 차단
        // (2026-08-26 베타 "여전히 안뜨고" 원인 ① — 스플래시·전환 중 과도기 값은 판정에 안 쓴다).
        guard carouselHeight > 150 else { return }
        let rows = CGFloat(currentLayout.rowCount)
        let need = rows * effMinCellHeight + (rows - 1) * 4
        let deficit = need - carouselHeight
        let ceiling = letterpressTitleCap - 64
        if titleShrink >= ceiling - 0.5, deficit > 0.5 {
            if !lpCellTight { lpCellTight = true; return }        // ② 셀 48
            if !lpQuoteHidden { lpQuoteHidden = true; return }    // ③ 인용문(최후)
        }
        // 회복은 양보의 역순 — 인용문 → 셀 → 표제. 인용문 복귀 임계 = 실제 비용 + 여유:
        // 6주 달은 압축 조판(§2.3-5)이라 ≈78pt(임계 82), 5주 달은 ≈98pt(임계 102).
        // (2026-08-26 원인 ② — 종전 임계 -95는 압축 전 비용 기준이라, 15 Pro 8월의 정착 여유
        // -90을 5pt 차이로 영영 못 넘었다. 한 번 숨으면 끝이던 뿌리.)
        let quoteCost: CGFloat = rows >= 6 ? 82 : 102
        if lpQuoteHidden, deficit < -quoteCost { lpQuoteHidden = false; return }
        if lpCellTight, !lpQuoteHidden, deficit < -50 { lpCellTight = false; return }
        let next = min(max(titleShrink + deficit / 1.02, 0), ceiling)
        // 양보가 걸린 동안 표제는 줄어들 수만 있다 — 회복이 여유를 먼저 먹으면 위 임계에 못 닿는다
        let clamped = (lpQuoteHidden || lpCellTight) ? max(next, titleShrink) : next
        if abs(clamped - titleShrink) > 0.5 { titleShrink = clamped }
    }

    /// 격자 셀 최소 높이 — 활판 양보 ②단계에서만 48로 준다(다른 테마는 항상 54)
    private var effMinCellHeight: CGFloat { lpCellTight ? 48 : minCellHeight }

    @ViewBuilder
    private func sidePanel(_ offsetMonths: Int, width: CGFloat) -> some View {
        if sidesVisible {
            monthGrid(offsetMonths: offsetMonths, width: width)
        } else {
            Color.clear.frame(width: width)
        }
    }

    private func monthGrid(offsetMonths: Int, width: CGFloat) -> some View {
        grid(layout: layout(offsetMonths: offsetMonths), interactive: offsetMonths == 0)
            .frame(width: width)
    }

    private func warmMonthCache() {
        var cache: [Date: MonthRender] = [:]
        for offset in -1...1 {
            let l = layout(offsetMonths: offset)
            cache[l.start] = computeRender(l)
        }
        renderCache = cache
    }

    private func endMonthTransition() {
        monthAnimating = false
        renderCache = [:]   // 전환 종료 — 다음 렌더는 신선 계산(데이터 변경 반영)
    }

    private var monthDragGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                guard dragStart == nil else { return }   // 기간 선택 중엔 월 이동 금지
                let t = value.translation
                if !monthDragEngaged {
                    guard abs(t.width) > abs(t.height) else { return }   // 수평 의도만 개입
                    warmMonthCache()   // 프레임마다 3개 달 재계산 방지 — 시작 때 한 번
                    monthDragEngaged = true
                }
                dragX = t.width
            }
            .onEnded { value in
                defer { monthDragEngaged = false }
                guard monthDragEngaged else { return }
                settleMonthDrag(translation: value.translation.width,
                                predicted: value.predictedEndTranslation.width)
            }
    }

    /// 놓는 순간 정착 — 플릭(예측 이동)도 인정. 폭 25% 넘으면 넘기고, 아니면 되돌린다.
    private func settleMonthDrag(translation: CGFloat, predicted: CGFloat) {
        let width = max(gridSize.width, 1)
        let effective = abs(predicted) > abs(translation) ? predicted : translation
        let delta: Int = effective < -width * 0.25 ? 1 : (effective > width * 0.25 ? -1 : 0)
        guard delta != 0, let next = cal.date(byAdding: .month, value: delta, to: monthStart) else {
            monthAnimating = true
            withAnimation(.snappy(duration: 0.25), completionCriteria: .logicallyComplete) {
                dragX = 0
            } completion: {
                endMonthTransition()
            }
            return
        }
        lightFeedback += 1
        if reduceMotion {
            monthAnchor = next
            dragX = 0
            endMonthTransition()
            return
        }
        monthAnimating = true
        withAnimation(.snappy(duration: 0.28), completionCriteria: .logicallyComplete) {
            dragX = delta > 0 ? -width : width
        } completion: {
            // 끝난 프레임에 달을 갈아끼우고 오프셋을 0으로 — 같은 그림이라 눈에는 이어진다
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                monthAnchor = next
                dragX = 0
            }
            endMonthTransition()
        }
    }

    /// 이 달의 잉크 글줄(§5.9-4: resolve가 캘린더에 뜨는지) — 일정 + cycle-anchored occurrence.
    /// 달력 반복(once·daily·weekly·monthly) Input·Output은 셀에 그리지 않음 — §8.2.3 잉크
    /// 글줄 계약이 「일정 + 주기 occurrence」만 명시(daily는 전 셀 노이즈이기도). projected는 faded.
    private func monthMarks(_ layout: MonthLayout) -> [Date: [(title: String, projected: Bool, isSchedule: Bool)]] {
        var marks: [Date: [(title: String, projected: Bool, isSchedule: Bool)]] = [:]
        let snap = CycleSnapshot(periodDays: periodDays)
        for dayNumber in 1...layout.daysInMonth {
            guard let d = cal.date(byAdding: .day, value: dayNumber - 1, to: layout.start) else { continue }
            let day = cal.startOfDay(for: d)
            for s in schedules where s.occurs(on: day) {
                if s.isMultiDay { continue }   // 여러 날 일정은 잉크 글줄 대신 띠로(§8.2.3)
                marks[day, default: []].append((s.title, false, true))   // 일정 = 박스 문법(2026-07-28)
            }
        }
        guard let monthEnd = cal.date(byAdding: .day, value: layout.daysInMonth, to: layout.start) else { return marks }
        for item in inputs {
            if case .cycleAnchored(let r) = item.schedule {
                for occ in snap.occurrences(of: r, createdAt: cal.startOfDay(for: item.createdAt))
                where occ.date >= layout.start && occ.date < monthEnd {
                    marks[cal.startOfDay(for: occ.date), default: []].append((item.title, occ.projected, false))
                }
            }
        }
        for item in outputs {
            guard case .cycleAnchored(let r) = item.schedule else { continue }   // 달력 반복 제외 — 위 주석과 동일 계약
            for occ in snap.occurrences(of: r, createdAt: cal.startOfDay(for: item.createdAt))
            where occ.date >= layout.start && occ.date < monthEnd {
                if item.isComplete && occ.projected { continue }   // §5.5.2 완료된 Output 미래 미표시
                marks[cal.startOfDay(for: occ.date), default: []].append((item.title, occ.projected, false))
            }
        }
        return marks
    }

    // ── 표제 (책력 조판: 거대 월 + 연도, 월 이동) ──
    private var monthHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // 모던 = 아웃라인 표제(시안 §1.3-2), 그 외 = 종전 솔리드(v6 확정 58px)
            if ThemeStore.chrome.latinCalendarHeader {
                // 활판(§2.3-3) — 라틴 숫자 표제 + 위에 얹는 빨강 이탤릭 월 라벨.
                // 시안은 세로 배치(라벨이 위)라 VStack으로 묶는다.
                VStack(alignment: .leading, spacing: 0) {
                    Text(Self.latinMonthLabel(monthStart))
                        .font(.system(size: 13, design: .serif).italic())
                        .foregroundStyle(Ink.autumn)   // 버밀리언
                        .padding(.top, -10)   // 표제 블록을 살짝 올린다(2026-08-26 베타 "좀만 높이 올려")
                    // §2.3-12: 월 150. 6주 달은 112(§2.3-10) — 기기가 더 좁으면 역산으로 더 내린다.
                    // 라인박스는 시안 line-height 1.02로 못 박는다: 서체 기본 리딩(≈1.3em)을 두면
                    // 112pt 표제가 146pt를 차지해 격자에서 34pt를 가져간다(빌드 462 실측).
                    // 잉크 음각(2026-08-31 대표님 "그 컬러를 캘린더탭 숫자에도") — 오늘 탭
                    // 계절 로고타입과 한 문법으로 묶인다(잉크값 = LetterpressLogotype.ink)
                    almanacDisplay(String(format: "%02d", cal.component(.month, from: monthStart)),
                                   size: letterpressTitleSize, color: Ink.text, inkDeboss: true)
                        .frame(height: letterpressTitleSize * 1.02)
                }
            } else {
                almanacDisplay(Loc.monthName(cal.component(.month, from: monthStart)), size: 58, color: Ink.text)
                Text(String(cal.component(.year, from: monthStart)))
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Ink.text.opacity(0.5))
            }
            Spacer()
            Button {
                lightFeedback += 1
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            Button {
                lightFeedback += 1
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            // 소식란은 브랜드 표식 행 우측(시안 .cal-top) — 2026-08-23 이동
        }
        .foregroundStyle(Ink.text)
    }

    /// 소식란(2026-08-09 사용자 지시 — 우상단 확성기, 미읽음 점).
    /// 표제 줄(기본)과 상단 행(플레이리스트) 두 자리에서 쓰여 추출(2026-08-19).
    /// `tint` = 지면 위 잉크색. 티켓 히어로 밴드(2026-08-31)는 유화 위라 흰색이 필요해 매개변수화.
    private func noticeButton(tint: Color = Ink.text) -> some View {
        Button {
            lightFeedback += 1
            showNotices = true
        } label: {
            Image(systemName: "megaphone")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 40, height: 44)
                .overlay(alignment: .topTrailing) {
                    if noticeFeed.hasUnread {
                        Circle().fill(Ink.holiday)
                            .frame(width: 6, height: 6)
                            .offset(x: -5, y: 12)
                    }
                }
        }
        .foregroundStyle(tint)
        .accessibilityLabel(noticeFeed.hasUnread ? Loc.str("소식, 새 글 있음") : Loc.str("소식"))
    }

    /// 현재 계절 트랙의 재생 위치(시안 §4.4 ③) — 일차/계절 길이. 콜드 = (0, 0).
    /// currentPhase와 같은 계산 경로(스냅샷 어긋남 방지 — CycleParams 경유 §5.6 규칙).
    private var playlistTrack: (day: Int, length: Int) {
        guard let r = CyclePredictor.cycleDay(of: today, periodStarts: starts, averageLength: avgLength) else {
            return (0, 0)
        }
        let m = effectiveM(on: today, projected: r.projected)
        let phase = CyclePredictor.phaseForDay(r.day, cycleLength: avgLength, menstrualLength: m)
        guard let span = CyclePredictor.phaseSpans(cycleLength: avgLength, menstrualLength: m)
            .first(where: { $0.phase == phase }) else { return (0, 0) }
        return (max(1, r.day - span.startDay + 1), span.length)
    }

    /// 정지 = 오늘 달로 되돌아오기(시안 §4.4 ③ 계약). 이미 오늘 달이면 아무 일 없음.
    private func returnToTodayMonth() {
        guard dragX == 0, !monthAnimating else { return }
        let now = cal.startOfDay(for: .now)
        guard !cal.isDate(now, equalTo: monthStart, toGranularity: .month) else { return }
        monthAnchor = now
    }

    /// 버튼도 같은 캐러셀 슬라이드(HIG Familiarity). Reduce Motion·폭 미확정이면 즉시 전환.
    private func shiftMonth(_ delta: Int) {
        guard dragX == 0, !monthAnimating else { return }   // 전환 중 중복 입력 무시
        guard let next = cal.date(byAdding: .month, value: delta, to: monthStart) else { return }
        let width = gridSize.width
        if reduceMotion || width <= 0 {
            monthAnchor = next
            return
        }
        warmMonthCache()
        monthAnimating = true
        withAnimation(.snappy(duration: 0.32), completionCriteria: .logicallyComplete) {
            dragX = delta > 0 ? -width : width
        } completion: {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                monthAnchor = next
                dragX = 0
            }
            endMonthTransition()
        }
    }

    /// 활판 월 라벨(§2.3-3) — 로케일 무관 라틴 「July 2026」. 시안 원본 문법이 영문이다.
    private static let latinMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static func latinMonthLabel(_ date: Date) -> String {
        latinMonthFormatter.string(from: date)
    }

    // ── 활판 인용문 블록(시안 §2.3-5) — 표제 아래, 계절 고전 문장 + 출처 + 룰 + 라틴 날짜 스탬프 ──
    /// 스탬프 "28 July" — 캘린더 라틴 표기와 같은 en_US 고정
    private static let latinDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "d MMMM"
        return formatter
    }()

    @ViewBuilder
    private var letterpressQuoteBlock: some View {
        // 콜드(기록 없음) = 계절이 없으니 인용문도 없다 — 블록째 생략
        if let phase = currentPhase {
            let six = currentLayout.rowCount >= 6   // §2.3-10 감량과 같은 축
            let q = LetterpressQuotes.quote(for: phase, day: cal.component(.day, from: today))
            // 6주 달 압축(2026-08-25 대표님 결정 "6주 달 인용문 압축") — 8월 실측에서 양보 사다리가
            // ①표제 −48 ②셀 48을 다 쓰고도 3pt가 모자라 인용문이 통째로 내려갔다. 인용문의 실제
            // 세로 비용은 블록 높이(≈86)가 아니라 **부모 VStack 간격 12를 더한 98**이고, 그 12가
            // 판정 경계에서 결정타였다. 6주 달에서만 본문 12·줄간격 1·여백 축소 + 앞뒤 간격 6으로
            // 약 24pt를 돌려준다(5주 달은 시안 값 그대로).
            let noteFont: Font = AlmanacFont.available
                ? .custom("GowunBatang-Regular", size: six ? 12 : 15)
                : .system(size: six ? 12 : 15, design: .serif)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(q.line1)\n\(q.line2)")
                    .font(noteFont)
                    .lineSpacing(six ? 1 : 5)                       // 시안 line-height 1.5/1.65 근사(6주는 압축)
                    .foregroundStyle(Ink.holiday)                   // 버밀리언(시안 --holiday)
                Text(q.source)
                    .font(AlmanacFont.available ? .custom("GowunBatang-Regular", size: 10.5)
                                                : .system(size: 10.5, design: .serif))
                    .foregroundStyle(Ink.text.opacity(0.55))
                    .padding(.top, six ? 4 : 7)
                Rectangle().fill(Ink.holiday)
                    .frame(width: 22, height: 1)
                    .padding(.vertical, six ? 4 : 9)
                Text(Self.latinDayFormatter.string(from: today))    // 이탤릭은 시스템 세리프(라틴 라벨 전례)
                    .font(.system(size: 11.5, design: .serif).italic())
                    .kerning(0.35)
                    .foregroundStyle(Ink.holiday.opacity(0.85))
            }
            // 표제와 인용문은 한 덩어리다 — 6주 달에선 열 간격 12를 6으로 당긴다(위아래 각 6pt).
            .padding(.vertical, six ? -6 : 0)
        }
    }

    private var weekdaySymbols: [String] {
        // 활판(§2.3-4) — 소문자 라틴(원본 문법). 색은 요일 행 렌더에서 전행 빨강.
        if ThemeStore.chrome.latinCalendarHeader {
            let latin = ["s", "m", "t", "w", "t", "f", "s"]
            let shift = cal.firstWeekday - 1
            return Array(latin[shift...] + latin[..<shift])
        }
        let symbols = Loc.veryShortWeekdaySymbols(cal)   // 앱 언어(기기 언어 아님, 2026-08-22)
        let shift = cal.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// 숫자 잉크색(2026-07-28 2차 개정) — 계절은 글씨에서 배경 글로우로 이동. 숫자는 먹색,
    /// 주말·공휴일만 관례색(일·공휴일=빨강, 토=파랑) 유지.
    private func numberColor(date: Date, seasonColor: Color, render: MonthRender, isToday: Bool) -> Color {
        if isToday { return Ink.paper }
        if render.holidays[date]?.isPublic == true { return Ink.holiday }
        switch cal.component(.weekday, from: date) {
        case 1: return Ink.holiday
        case 7: return Ink.saturday
        default: return Ink.text
        }
    }

    /// 계절 = 날짜 뒤 이어지는 빛 띠(2026-07-28 2차 — 같은 계절 연속 구간 연결, 사용자 지시).
    /// 형광펜 밴드와 같은 문법: 구간 양 끝만 둥글게, 행 경계는 각지게. 세로는 위아래로 사그라드는
    /// 그래디언트(빛의 질감). 예상 구간은 절반 감쇠. 색은 glow 팔레트(채도·명도 상향판).
    private func seasonBand(date: Date, index: Int, meta: SeasonMeta, projected: Bool,
                            render: MonthRender) -> some View {
        let name = meta.name
        let prev = cal.date(byAdding: .day, value: -1, to: date)
            .map { render.style[$0]?.meta?.name == name } ?? false
        let next = cal.date(byAdding: .day, value: 1, to: date)
            .map { render.style[$0]?.meta?.name == name } ?? false
        let col = index % 7
        let roundLeft = !prev || col == 0
        let roundRight = !next || col == 6
        // 밑줄형 — 직각 사각(2026-07-28 5차: 라운드 제거, 사용자 지시). 숫자 영역(상단 3+27pt)
        // 바로 밑 y 25.5~29.5. 일정 띠·박스는 3.5pt 간격을 두고 33.5부터(시안 결정).
        // 활판 = 헤어라인 1.5pt + 불투명 .9/.35(§2.3-8 — 얇아진 만큼 진하게 눌러야 띠로 읽힌다)
        let hairline = ThemeStore.chrome.hairlineSeasonBand
        return Rectangle()
            .fill(meta.glow.opacity(hairline ? (projected ? 0.35 : 0.9) : (projected ? 0.25 : 0.5)))
            .frame(height: hairline ? 1.5 : 4)
            .padding(.leading, roundLeft ? 3 : 0)
            .padding(.trailing, roundRight ? 3 : 0)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 25.5)
            .allowsHitTesting(false)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, s in
                let weekday = (cal.firstWeekday - 1 + index) % 7 + 1
                Text(s)
                    .font(ThemeStore.chrome.latinCalendarHeader
                          ? .system(size: 11, design: .serif) : .system(size: 11))
                    // 활판(§2.3-4) = 전행 빨강 세리프(원본 문법 — 날짜 숫자는 토=파랑 유지)
                    .foregroundStyle(ThemeStore.chrome.latinCalendarHeader ? Ink.autumn
                                     : weekday == 1 ? Ink.holiday
                                     : weekday == 7 ? Ink.saturday : Ink.accent)   // 구조색(기본=winter 동값)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 4)
        .almanacRule(opacity: 0.28)   // 은필 괘선
    }

    // ── 월 렌더 데이터 — 셀이 프레임마다 재계산하던 것 전부(스타일·형광펜·마크·띠) ──
    private struct MonthRender {
        let marks: [Date: [(title: String, projected: Bool, isSchedule: Bool)]]
        let bands: BandLayout
        let style: [Date: (color: Color, meta: SeasonMeta?, projected: Bool)]
        let recorded: Set<Date>
        let predicted: Set<Date>   // a11y용(시각 표시는 겨울 글로우가 대체 — 2026-07-28 사용자 결정)
        let periodShown: Set<Date> // 코랄 형광펜 표시일 = 기록 && 겨울 띠와 안 겹침(±1일 여유 포함)
        let holidays: [Date: KoreanHoliday]   // 셀 표기용 대표 1건(공휴일 우선, 2026-07-28)
    }

    private func computeRender(_ layout: MonthLayout) -> MonthRender {
        let recordedAll = recordedDays
        var recorded = Set<Date>()
        var predicted = Set<Date>()
        var periodShown = Set<Date>()
        var style: [Date: (color: Color, meta: SeasonMeta?, projected: Bool)] = [:]
        var holidays: [Date: KoreanHoliday] = [:]
        // 소스 우선순위(2026-07-28 사용자 지시): 애플 기본 캘린더의 공휴일 구독 캘린더(연동 시)
        // → 내장 테이블 폴백(미연동·구독 꺼짐). 임시공휴일 등은 애플 캘린더만 안다.
        let ekHolidays: [Date: [String]]?
        if let monthEnd = cal.date(byAdding: .day, value: layout.daysInMonth, to: layout.start) {
            ekHolidays = EventOverlay.shared.holidayNames(from: layout.start, to: monthEnd)
        } else {
            ekHolidays = nil
        }
        for offset in -1...layout.daysInMonth {
            guard let d = cal.date(byAdding: .day, value: offset, to: layout.start) else { continue }
            let day = cal.startOfDay(for: d)
            if recordedAll.contains(day) {
                recorded.insert(day)
                // 겨울 글로우와 겹치는 기록은 표시 생략(중복 — 2026-07-28 사용자 결정).
                // 모델과 어긋난 기록(월경기 밖·S0)만 코랄로 남아 "실측이 다르다"는 신호가 된다.
                // ⚠ 이름이 아니라 단계로 비교한다 — 표시명은 번역되므로 키로 쓰면
                // 다른 언어에서 이 억제가 통째로 풀린다(2026-08-21 발견)
                if cellStyle(for: day).meta?.phase != .menstrual {
                    periodShown.insert(day)
                }
            } else if isPredictedPeriod(day) {
                predicted.insert(day)
            }
            if offset >= 0 && offset < layout.daysInMonth {
                style[day] = cellStyle(for: day)
                if let ekHolidays {
                    if let name = ekHolidays[day]?.first {
                        holidays[day] = KoreanHoliday(name: name,
                                                      isPublic: !KoreanHolidays.isCommemorationName(name))
                    }
                } else if EventOverlay.usesBuiltInKoreanHolidays {
                    // 내장 표는 한국 지역 폴백 전용(2026-08-21)
                    holidays[day] = KoreanHolidays.holidays(on: day, calendar: cal).first
                }
            }
        }
        return MonthRender(marks: monthMarks(layout), bands: bandLayout(layout),
                           style: style, recorded: recorded, predicted: predicted,
                           periodShown: periodShown, holidays: holidays)
    }

    // ── 그리드 (캐러셀 한 패널 — interactive = 중앙 달만 제스처·접근성) ──
    private func grid(layout: MonthLayout, interactive: Bool) -> some View {
        let render = renderCache[layout.start] ?? computeRender(layout)
        return VStack(spacing: 4) {
            ForEach(0..<layout.rowCount, id: \.self) { row in
                // ⚠ .top 정렬(2026-08-25 베타 "일정이 많아지면 계절 줄이 어긋나") — 기본 .center는
                // 마크 수가 달라 키가 다른 셀을 세로 중앙에 놓아 숫자·계절 줄이 행마다 밀렸다.
                HStack(alignment: .top, spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        cell(layout: layout, index: row * 7 + col, render: render,
                             interactive: interactive)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(minHeight: effMinCellHeight, maxHeight: .infinity)   // 풀하이트 균등 분할(활판 양보 ② 반영)
                .overlay(alignment: .topLeading) { bandRow(row: row, bars: render.bands.bars) }
            }
        }
        .frame(maxHeight: .infinity)
        .coordinateSpace(name: interactive ? "calGrid" : "calGridSide")   // 기간 선택 좌표계(중앙만)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            if interactive { gridSize = size }
        }
        .accessibilityHidden(!interactive)   // VoiceOver가 양옆 달을 순회하지 않게
    }

    // ── 길게 누른 채 드래그 = 기간 선택 (2026-07-27 사용자 지시) ──
    private var selectionRange: ClosedRange<Date>? {
        guard let s = dragStart, let e = dragEnd else { return nil }
        return min(s, e)...max(s, e)
    }

    private func isSelected(_ date: Date) -> Bool {
        selectionRange?.contains(date) ?? false
    }

    /// 그리드 좌표 → 날짜. 행 스트라이드 = (높이+간격)/행수 — H = n·h + (n-1)·4에서 유도.
    /// 달 밖 빈 칸이면 nil(선택은 마지막 유효 셀에 머문다).
    private func dayAt(_ location: CGPoint) -> Date? {
        let layout = currentLayout
        guard gridSize.width > 0, gridSize.height > 0, layout.rowCount > 0 else { return nil }
        let col = min(6, max(0, Int(location.x / (gridSize.width / 7))))
        let rowStride = (gridSize.height + 4) / CGFloat(layout.rowCount)
        let row = min(layout.rowCount - 1, max(0, Int(location.y / rowStride)))
        return layout.date(at: row * 7 + col)
    }

    /// 길게 누르기(0.4s) → 그대로 끌면 기간 확장 → 놓으면 빠른 일정(하루=단일, 구간=여러 날).
    /// 셀→셀 이동마다 작은 햅틱(§4). 시퀀스라 0.4s 전에 떼면 탭(하루 상세)과 충돌하지 않는다.
    private func pressDrag(from date: Date) -> some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("calGrid")))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if dragStart == nil {
                    pressFeedback += 1
                    dragStart = date
                    dragEnd = date
                }
                if let drag, let hovered = dayAt(drag.location), hovered != dragEnd {
                    lightFeedback += 1
                    dragEnd = hovered
                }
            }
            .onEnded { value in
                defer {
                    dragStart = nil
                    dragEnd = nil
                }
                guard case .second(true, _) = value, let s = dragStart, let e = dragEnd else { return }
                guard s != e else {
                    // 제자리에서 떼면: compact = 하루 상세 push(2026-08-01 반전) /
                    // regular = 빠른 일정(2026-08-10 베타 피드백 — 탭이 날짜 이동을 가져가서 맞교환)
                    if hSize == .regular {
                        quickAddDay = s
                        quickAddEnd = nil
                    } else {
                        pushedDay = s
                    }
                    return
                }
                // 끌었으면 기간 빠른 일정 — 기간 선택의 진입점은 여전히 길게 누르기다
                quickAddDay = min(s, e)
                quickAddEnd = max(s, e)
            }
    }

    // ── 여러 날 일정 = 이어지는 띠 (2026-07-25 사용자 지시 — 하루짜리는 잉크 글줄 그대로) ──
    // 생리 형광펜은 숫자 뒤를 지나는 별도 레이어라 겹치지 않는다. 레인은 2개까지(셀 2줄 예산).
    private struct BandBar: Identifiable {
        let id: String
        let title: String
        let segment: BandSegment
        let lane: Int
    }

    private struct BandLayout {
        let bars: [BandBar]
        /// 셀별로 예약할 슬롯 수 = 그 셀을 지나는 띠의 최대 lane+1 — 지나는 "개수"로 예약하면
        /// lane 1 단독 셀(레인 0이 다른 주에서만 점유)에서 띠가 잉크 글줄을 덮는다(2026-07-27 리뷰)
        let countByIndex: [Int: Int]
    }

    private func bandLayout(_ layout: MonthLayout) -> BandLayout {
        let cellCount = layout.rowCount * 7
        let items = schedules.filter(\.isMultiDay).sorted { ($0.date, $0.title) < ($1.date, $1.title) }
        var bars: [BandBar] = []
        var laneCells: [Set<Int>] = [[], []]
        var countByIndex: [Int: Int] = [:]

        for item in items {
            var cells = [Bool](repeating: false, count: cellCount)
            var occupied: Set<Int> = []
            for i in 0..<cellCount {
                guard let d = layout.date(at: i), item.occurs(on: d) else { continue }
                cells[i] = true
                occupied.insert(i)
            }
            guard !occupied.isEmpty,
                  let lane = laneCells.indices.first(where: { laneCells[$0].isDisjoint(with: occupied) })
            else { continue }
            laneCells[lane].formUnion(occupied)
            for i in occupied { countByIndex[i] = max(countByIndex[i] ?? 0, lane + 1) }

            for (n, segment) in ScheduleSpan.bandSegments(cells: cells).enumerated() {
                let adjusted = clampToMonth(segment, item: item, layout: layout)
                bars.append(BandBar(id: "\(item.id)-\(n)", title: item.title, segment: adjusted,
                                    lane: lane))
            }
        }
        return BandLayout(bars: bars, countByIndex: countByIndex)
    }

    /// 달 밖에서 이어지는 쪽은 둥글게 닫지 않는다 — 다음 달로 넘어가는 게 보이도록
    private func clampToMonth(_ segment: BandSegment, item: ScheduleItem, layout: MonthLayout) -> BandSegment {
        let firstIndex = segment.row * 7 + segment.column
        let lastIndex = firstIndex + segment.length - 1
        var isStart = segment.isStart
        var isEnd = segment.isEnd
        if isStart, firstIndex == layout.leadingBlanks,
           let before = cal.date(byAdding: .day, value: -1, to: layout.start), item.occurs(on: before) {
            isStart = false
        }
        if isEnd, lastIndex == layout.leadingBlanks + layout.daysInMonth - 1,
           let after = cal.date(byAdding: .day, value: layout.daysInMonth, to: layout.start), item.occurs(on: after) {
            isEnd = false
        }
        return BandSegment(row: segment.row, column: segment.column, length: segment.length,
                           isStart: isStart, isEnd: isEnd)
    }

    private func bandRow(row: Int, bars: [BandBar]) -> some View {
        GeometryReader { proxy in
            let unit: CGFloat = proxy.size.width / 7
            ForEach(bars.filter { $0.segment.row == row }) { bar in
                bandView(bar: bar, unit: unit)
            }
        }
        .allowsHitTesting(false)   // 탭·길게 누르기는 셀이 받는다
    }

    // 타입 체커 과부하를 피해 조각냄(2026-07-25 CI 실측: 한 식에 몰면 unable to type-check)
    private func bandView(bar: BandBar, unit: CGFloat) -> some View {
        // 2026-08-12 베타 피드백("일정 색깔 기준이 뭔지 모르겠어 — 여행과 동일한 색으로 통일"):
        // 지난 일정만 산화 갈색이던 규칙을 걷는다. 모던 팔레트가 먼저 간 방향(oxide 갈색 은퇴)을
        // 은필도 따른다 — 셀 안에서 색이 뜻하는 건 계절 하나로 족하다.
        let ink: Color = Ink.text
        let radius: CGFloat = 2   // 직각화(2026-07-28 시안 결정 — 계절 밑줄과 같은 결)
        let fill: Color = Self.scheduleBandFill
        let width: CGFloat = max(0, unit * CGFloat(bar.segment.length) - 2)
        let x: CGFloat = unit * CGFloat(bar.segment.column) + 1
        let y: CGFloat = bandTop + CGFloat(bar.lane) * bandSlot
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: bar.segment.isStart ? radius : 0,
            bottomLeadingRadius: bar.segment.isStart ? radius : 0,
            bottomTrailingRadius: bar.segment.isEnd ? radius : 0,
            topTrailingRadius: bar.segment.isEnd ? radius : 0
        )
        return shape
            .fill(fill)
            .frame(width: width, height: bandHeight)
            .overlay(alignment: .leading) { bandTitle(bar: bar, ink: ink) }
            .offset(x: x, y: y)
    }

    /// 일정 띠·박스 지면 — 날씨만 다크 글래스 톤(2026-08-20 베타 피드백 "일정 회색을 더 진하게" —
    /// 잉크가 흰색이라 흰 13% 지면 위에서 흰 제목이 안 읽힌다). 다른 테마는 종전 잉크 13%.
    private static var scheduleBandFill: Color {
        ThemeStore.chrome.skyGround
            ? Color.flatRGB(0x0E, 0x1A, 0x28).opacity(0.45)   // surface(다크 글래스)와 같은 계열
            : Ink.text.opacity(0.13)
    }

    /// 제목은 시작 조각에만 — 잘린 조각은 띠만 이어진다
    @ViewBuilder
    private func bandTitle(bar: BandBar, ink: Color) -> some View {
        if bar.segment.isStart {
            Text(bar.title)
                .font(.system(size: 8.5, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(ink.opacity(0.85))
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private func cell(layout: MonthLayout, index: Int, render: MonthRender,
                      interactive: Bool) -> some View {
        if let date = layout.date(at: index) {
            if interactive {
                cellBody(date: date, index: index, render: render)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        lightFeedback += 1
                        if hSize == .regular {
                            // 아이패드 분할(2026-08-10 베타 피드백): 탭 = 우측 상세 날짜 이동 —
                            // 상세가 항상 떠 있는 화면에선 날짜 이동이 가장 잦은 동작이다
                            selectedDay = date
                        } else {
                            // 2026-08-01 베타 피드백으로 반전: 탭 = 빠른 일정(가장 잦은 동작을 가장 싼 제스처에)
                            quickAddDay = date
                            quickAddEnd = nil
                        }
                    }
                    .gesture(pressDrag(from: date))   // 길게 = 하루 상세, 끌면 기간 빠른 일정(2026-08-01)
                    .overlay {
                        // 드래그 기간 선택 명암 — 어디까지 잡혔는지(2026-07-27 사용자 지시)
                        if isSelected(date) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Ink.text.opacity(0.10))
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel(accessibilityText(for: date,
                                                          style: render.style[date] ?? (Ink.text, nil, false),
                                                          recorded: render.recorded.contains(date),
                                                          predicted: render.predicted.contains(date)))
                    .accessibilityAddTraits(.isButton)
                    // 길게 누르기 대체 액션 — 각 폼팩터에서 탭이 안 가져간 쪽을 연다
                    // (compact: 탭=빠른 일정 → 대체=하루 상세 / regular: 탭=날짜 이동 → 대체=빠른 일정, 2026-08-10)
                    .accessibilityAction(named: hSize == .regular ? Loc.str("빠른 일정 추가") : Loc.str("하루 상세 보기")) {
                        if hSize == .regular {
                            quickAddDay = date
                            quickAddEnd = nil
                        } else {
                            pushedDay = date
                        }
                    }
            } else {
                cellBody(date: date, index: index, render: render)
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func cellBody(date: Date, index: Int, render: MonthRender) -> some View {
        let style = render.style[date] ?? (Ink.text, nil, false)
            let recorded = render.recorded.contains(date)
            let predicted = render.predicted.contains(date)
            let isToday = date == today
            let bandCount = render.bands.countByIndex[index] ?? 0
            let holiday = render.holidays[date]
            let markBudget = max(0, 2 - bandCount - (holiday == nil ? 0 : 1))
            let cellMarks = render.marks[date] ?? []
            VStack(spacing: 0) {
                Text("\(cal.component(.day, from: date))")
                    .font(numberFont(isToday: isToday))
                    .monospacedDigit()
                    .foregroundStyle(numberColor(date: date, seasonColor: style.color,
                                                 render: render, isToday: isToday))
                    .skyInkShadow()   // 날씨 = 비·구름 위 숫자 가독(2026-08-22 베타)
                    // 과거 완료일 흐림 폐기(2026-08-16 베타 피드백 "체크인 완료일 회색글씨 빼고
                    // 일괄로 검정") — 2026-08-09에 씨앗 스티커 대체로 넣었던 0.38 감쇠를 걷는다.
                    // 숫자는 날짜를 읽는 것이고, 체크인 여부는 다른 표면이 말한다.
                    .frame(width: 27, height: 27)
                    .background {
                        // 오늘 = accent 채운 원(기본=은필 흑청 동값 / 모던=흰색, §8.1·시안 §1.2).
                        // 모던 기록일 = 형광펜 대신 회색 원(시안 §1.3-4). 원에는 지면색 링(3pt)
                        // — 계절 밑줄이 원을 파고들어 보이는 겹침 해소.
                        ZStack {
                            if ThemeStore.chrome.circlesRecordedDays && (isToday || render.periodShown.contains(date)) {
                                Circle().fill(Ink.frost).frame(width: 33, height: 33)
                            }
                            if isToday {
                                // 기본 = 표제와 같은 먹색(2026-08-09 베타 피드백 "8월 글씨색이랑 같게"
                                // — §8.1 은필 확정을 뒤집는 사용자 결정) / 모던 = accent(흰) 시안 유지
                                Circle().fill(ThemeStore.chrome.todayCircleUsesAccent ? Ink.accent : Ink.text)
                            } else if ThemeStore.chrome.circlesRecordedDays && render.periodShown.contains(date) {
                                Circle().fill(Ink.record.opacity(0.3))
                            }
                        }
                    }
                Color.clear.frame(height: bandGap)   // 계절 밑줄과 간격(2026-07-28 시안 결정)
                if bandCount > 0 {
                    Color.clear.frame(height: CGFloat(bandCount) * bandSlot)   // 여러 날 띠 자리
                }
                // 공휴일·기념일 = 첫 글줄(빨간날 관례, 2026-07-28) — 일정 글줄과 같은 조판
                if let holiday {
                    Text(Loc.holidayName(holiday.name))
                        .font(.system(size: 8.5, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(holiday.isPublic ? Ink.holiday : Ink.text.opacity(0.5))
                }
                // 일정 = 기간 띠와 같은 박스 문법(2026-07-28 시안 결정 — 통일성) /
                // occurrence = 잉크 글줄(먹색 78% / 예상 옅게, 프로토 v15·16)
                // 2026-08-12: 과거 산화색 75% 분기 폐기 — 띠·박스와 같은 이유로 지난 것도 먹색이다
                // 한 칸의 줄 예산은 2 — 띠·공휴일이 차지한 만큼 줄인다
                ForEach(Array(cellMarks.prefix(markBudget).enumerated()), id: \.offset) { _, mark in
                    if mark.isSchedule {
                        scheduleBox(title: mark.title)
                    } else {
                        Text(mark.title)
                            .font(.system(size: 8.5, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(mark.projected ? Ink.text.opacity(0.45)
                                             : Ink.text.opacity(0.78))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 3)
            .padding(.horizontal, 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    // 계절 빛 띠(맨 아래 — 오늘 셀도 이어진다, 은필 원이 위에 얹힘)
                    if let meta = style.meta {
                        seasonBand(date: date, index: index, meta: meta,
                                   projected: style.projected, render: render)
                    }
                    // 기본 테마 기록 회색 형광펜 = 폐기(2026-08-09 사용자 결정 — "회색 형광펜이
                    // 뭔지 모르겠어". 관측 우선으로 기록일이 전부 겨울 밴드에 들어가 존재 이유 소멸).
                    // 모던의 기록 회색 원(시안 §1.3-4)은 별개 문법이라 유지.
                }
            }
            .overlay {
                // regular 분할 뷰의 선택일 표시(색만 X — 테두리)
                if hSize == .regular && (selectedDay ?? today) == date {
                    RoundedRectangle(cornerRadius: 10).stroke(Ink.text.opacity(0.28), lineWidth: 1)
                }
            }
    }

    /// 과거 완료일 숫자 흐림(2026-08-09 베타 피드백 — 씨앗 스티커 대체).
    /// 오늘은 제외(은필 원이 담당), 미래는 완료가 성립하지 않는다.
    private func isCompletedPast(_ date: Date) -> Bool {
        date < today && completedDays.contains(date)
    }

    /// 캘린더 숫자 서체 — 모던 = Pretendard 500(오늘 600, 시안 §1.3-3),
    /// 기본 = 표제와 같은 번들 서체(2026-08-09 베타 피드백 "8월 폰트랑 같게" — 시스템 산세리프 폐기)
    private func numberFont(isToday: Bool) -> Font {
        switch ThemeStore.chrome.typeFace {
        case .notoSerif:
            // 은필 = Gowun 숫자 유지(2026-08-30 대표님 "은필 숫자는 롤백" — .notoSerif 전환의
            // 동반 변화만 되돌린다. Bodoni는 활판의 라틴 숫자 문법)
            if ThemeStore.current == .standard {
                guard AlmanacFont.available else {
                    return .system(size: 14, weight: isToday ? .bold : .semibold, design: .serif)
                }
                return .custom(isToday ? "GowunBatang-Bold" : "GowunBatang-Regular", size: 14)
            }
            // 플리 = Geist(2026-08-30 대표님 "플리 영어폰트 다 geist로")
            if ThemeStore.chrome.playlistChrome {
                return .geist(size: 14, weight: isToday ? .medium : .regular)
            }
            // 활판 소형 숫자(§2.3-11) = Bodoni Moda 400, 오늘만 500. named instance 실패 시 세리프 폴백
            guard LetterpressFont.available else {
                return .system(size: 14, weight: isToday ? .medium : .regular, design: .serif)
            }
            return .custom(isToday ? "BodoniModa-Medium" : "BodoniModa-Regular", size: 14)
        case .pretendard:
            guard ThemeFont.available else {
                return .system(size: 14, weight: isToday ? .semibold : .medium)
            }
            return .custom(isToday ? "Pretendard-SemiBold" : "Pretendard-Medium", size: 14)
        case .gowun:
            guard AlmanacFont.available else {
                return .system(size: 14, weight: isToday ? .bold : .semibold, design: .serif)
            }
            return .custom(isToday ? "GowunBatang-Bold" : "GowunBatang-Regular", size: 14)
        case .playlistSans:
            // 플리 숫자 = Geist 유지(2026-08-30 "플리 영어폰트 다 geist로" — 본문 서체 전환과 무관)
            return .geist(size: 14, weight: isToday ? .medium : .regular)
        case .dodum:
            // 티켓 숫자 = 고운돋움(단일 웨이트 — 오늘 강조는 원 채움이 담당)
            guard DodumFont.available else { return .system(size: 14, weight: isToday ? .bold : .semibold) }
            return .custom("GowunDodum-Regular", size: 14)
        case .system:
            return .system(size: 14, weight: isToday ? .bold : .semibold)
        }
    }

    /// 하루짜리 일정 = 기간 띠와 같은 박스 문법(2026-07-28 시안 결정 — 통일성). 높이·R2·서체 = 띠 동일
    private func scheduleBox(title: String) -> some View {
        let ink: Color = Ink.text   // 지난 일정 갈색 분기 폐기(2026-08-12 — bandView 주석 참조)
        return RoundedRectangle(cornerRadius: 2)
            .fill(Self.scheduleBandFill)
            .frame(height: bandHeight)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                Text(title)
                    .font(.system(size: 8.5, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(ink.opacity(0.85))
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 1)
            .padding(.bottom, 1)
    }

    /// 형광펜 밴드 — 연속 구간은 이어지고 양 끝만 둥글게 (행 경계 포함).
    private func highlightBand(for date: Date, index: Int, recorded: Bool, render: MonthRender) -> some View {
        let prev = cal.date(byAdding: .day, value: -1, to: date)
            .map { sameKind($0, recorded: recorded, render: render) } ?? false
        let next = cal.date(byAdding: .day, value: 1, to: date)
            .map { sameKind($0, recorded: recorded, render: render) } ?? false
        let col = index % 7
        let roundLeft = !prev || col == 0
        let roundRight = !next || col == 6
        return UnevenRoundedRectangle(
            topLeadingRadius: roundLeft ? 9 : 0,
            bottomLeadingRadius: roundLeft ? 9 : 0,
            bottomTrailingRadius: roundRight ? 9 : 0,
            topTrailingRadius: roundRight ? 9 : 0
        )
        .fill(Ink.record.opacity(ThemeStore.chrome.hidesRecordDot ? 0 : 0.22))   // 활판 = 숨김(§2.3-9), 그 외 진한 회색
        .frame(height: 20)
        .padding(.leading, roundLeft ? 4 : 0)
        .padding(.trailing, roundRight ? 4 : 0)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 6)   // 숫자(상단 27pt 원역) 뒤를 지나는 마커 — 프로토 z-계층과 동일
    }

    private func sameKind(_ date: Date, recorded: Bool, render: MonthRender) -> Bool {
        // 표시되는 형광펜 기준 — 숨겨진 기록일(겨울 겹침)과는 이어 그리지 않는다
        render.periodShown.contains(date)
    }

    // ── 단계 → 렌더 규칙 ──
    private func cellStyle(for date: Date) -> (color: Color, meta: SeasonMeta?, projected: Bool) {
        guard let last = starts.max() else { return (Ink.text, nil, false) }   // S0 = 전부 먹색
        // 투영 지평 밖 미래 = 먹색 (예측 렌더 중단 — h번째 예상 월경 구간 끝까지, off-by-one 정정 2026-07-28)
        if let horizon = CyclePredictor.projectionHorizon(lastStart: last, averageLength: avgLength,
                                                          horizonCycles: horizonCycles,
                                                          menstrualLength: menstrualLength, calendar: cal),
           date > horizon {
            return (Ink.text, nil, false)
        }
        guard let r = CyclePredictor.cycleDay(of: date, periodStarts: starts, averageLength: avgLength) else {
            return (Ink.text, nil, false)
        }
        // 관측 우선 유효 M(2026-08-09) — 기록된 생리일은 전부 겨울 밴드 안에 들어간다
        let meta = seasonMeta(for: CyclePredictor.phaseForDay(r.day, cycleLength: avgLength,
                                                              menstrualLength: effectiveM(on: date, projected: r.projected)))
        return (meta.color.opacity(r.projected ? 0.55 : 1.0), meta, r.projected)   // 미래/역투영 = faded
    }

    /// 회색 형광펜 = 예상 생리일 (I-2b). 미래·투영 구간의 월경기만, 오늘 이전 소급 금지.
    private func isPredictedPeriod(_ date: Date) -> Bool {
        guard date >= today, let last = starts.max() else { return false }
        if let horizon = CyclePredictor.projectionHorizon(lastStart: last, averageLength: avgLength,
                                                          horizonCycles: horizonCycles,
                                                          menstrualLength: menstrualLength, calendar: cal),
           date > horizon {
            return false
        }
        guard let r = CyclePredictor.cycleDay(of: date, periodStarts: starts, averageLength: avgLength),
              r.projected else { return false }
        return CyclePredictor.phaseForDay(r.day, cycleLength: avgLength,
                                          menstrualLength: menstrualLength) == .menstrual
    }

    /// 티켓 도판 교체용 현재 계절 — `seasonLine`과 같은 계산이되 문자열이 아니라 단계만 꺼낸다.
    /// 기록이 없으면 nil(콜드) → 겨울 그림으로 떨어진다(`TicketSpec.plateAsset`).
    private var currentPhase: CyclePhase? {
        guard let r = CyclePredictor.cycleDay(of: today, periodStarts: starts, averageLength: avgLength) else {
            return nil
        }
        let m = effectiveM(on: today, projected: r.projected)
        return CyclePredictor.phaseForDay(r.day, cycleLength: avgLength, menstrualLength: m)
    }

    // ── 계절 라인 (S0/S1/S2/S4 — §5.6.2) ──
    private var seasonLine: String {
        guard let last = starts.max() else { return Loc.str("첫 생리일을 기록하면 계절이 채워지기 시작할거예요") }
        let diff = cal.dateComponents([.day], from: last, to: today).day ?? 0
        if diff >= avgLength + TodayView.overdueGraceDays {
            return Loc.fmt("겨울 예상 · 예정일 %1$@일 지남", "\(diff - avgLength)")
        }
        guard let r = CyclePredictor.cycleDay(of: today, periodStarts: starts, averageLength: avgLength) else {
            return Loc.str("첫 생리일을 기록하면 계절이 채워지기 시작할거예요")
        }
        // 관측 우선 유효 M + 일차 = 계절 내 일차(2026-08-09 — "봄 10일차" 주기 일차 오독 해소)
        let m = effectiveM(on: today, projected: r.projected)
        let phase = CyclePredictor.phaseForDay(r.day, cycleLength: avgLength, menstrualLength: m)
        let meta = seasonMeta(for: phase)
        let spanStart = CyclePredictor.phaseSpans(cycleLength: avgLength, menstrualLength: m)
            .first { $0.phase == phase }?.startDay ?? 1
        let projected = r.projected ? Loc.str(" · 예상") : ""
        return Loc.fmt("%1$@ %2$@일차%3$@", "\(meta.name)", "\(max(1, r.day - spanStart + 1))", "\(projected)")
    }

    // ── 범례 (색맹 담보: 글리프+계절명 병행 — §8.1 SeasonGlyph) ──
    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(CyclePhase.displayOrder, id: \.self) { legendItem($0) }   // 봄→여름→가을→겨울(2026-07-29 피드백)
            Spacer()
            // 「기록」 스와치 폐기(2026-08-01 베타 피드백) — 상단 「생리 기록」 버튼과 중복 안내였다
            if ThemeStore.chrome.playlistChrome {
                // 플리 = 생리 기록이 범례 줄 우측(시안 §4.4 ③ .pl-log — 헤더에서 하단으로)
                Button {
                    showLogSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(Ink.record).frame(width: 7, height: 7)
                        Text("생리 기록")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay(Capsule().stroke(Ink.text.opacity(0.3), lineWidth: 1))
                }
                .coachAnchor(.calendarLog)
            }
        }
        // 티켓 = 달 이동 화살표가 같은 줄 양 끝에 얹힌다 — 항목이 화살표 자리까지 흐르면
        // 「봄」이 ‹ 뒤에 가려진다(2026-08-17 베타 피드백). 좌우를 화살표 폭만큼 비운다.
        .padding(.horizontal, ThemeStore.chrome.ticketChrome ? 34 : 0)
        .padding(.top, ThemeStore.chrome.ticketChrome ? 15 : 6)
        // 티켓 = 격자 마감 점선 + 그 위 양 끝에 달 이동(시안 §3.4). 위쪽 절취선과 짝을 이룬다.
        .overlay(alignment: .top) {
            if ThemeStore.chrome.ticketChrome { ticketLegendRule }
        }
    }

    private var ticketLegendRule: some View {
        // 마감 점선 제거(2026-08-18 베타 피드백 "하단 점선좀 없애주고") — 범례를 관통해 읽혔다.
        // 달 이동 화살표는 유지.
        ZStack {
            TicketMonthNav(
                onPrev: { lightFeedback += 1; shiftMonth(-1) },
                onNext: { lightFeedback += 1; shiftMonth(1) }
            )
            .padding(.horizontal, -6)
        }
    }

    private func legendItem(_ phase: CyclePhase) -> some View {
        let meta = seasonMeta(for: phase)
        return HStack(spacing: 4) {
            SeasonGlyph(phase: phase, size: 12)
            Text(meta.name)
                .font(.system(size: 12, weight: .semibold, design: .serif))
                .foregroundStyle(meta.color)
                .skyInkShadow()
        }
    }

    private func accessibilityText(for date: Date, style: (color: Color, meta: SeasonMeta?, projected: Bool),
                                   recorded: Bool, predicted: Bool) -> String {
        var parts = [date.formatted(Loc.dateTime.month().day())]
        if let meta = style.meta {
            // 개정 M-1c: 단계명 제거 — VoiceOver는 소리로 읽혀 프라이버시 표면이기도 하다.
            // "예상"은 유지: faded 시각 hedge가 전달되지 않는 채널이라 텍스트가 유일한 hedge(§5.6.2).
            parts.append(style.projected ? Loc.fmt("%1$@ 예상", "\(meta.name)") : meta.name)
        }
        if recorded { parts.append(Loc.str("생리 기록")) }
        if predicted { parts.append(Loc.str("생리 예상")) }
        return parts.joined(separator: ", ")
    }

}
