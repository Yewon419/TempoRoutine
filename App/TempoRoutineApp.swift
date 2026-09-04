// 템포루틴 — 앱 엔트리
// 저장 = 단일 SwiftData 스토어(default.store). 2층 CloudKit 스토어 분리는 2026-07-24 롤백
// (실기기 영속화 결함 — Windows/CI-only라 멀티컨피그 디버그 불가) — 그 방식은 재도전 금지.
// 기기 간 동기화는 2026-08-10 재구현: 스토어는 그대로 두고 CKSyncEngine이 플래너·체크인
// 레코드만 미러한다(PlannerSync — §5.2 계약, 생리 기록은 절대 미동기).
// 새 @Model 추가 시 아래 Schema 배열에 반드시 등록(repo CLAUDE.md).

import SwiftUI
import SwiftData

@main
struct TempoRoutineApp: App {
    /// 스위처 가림은 씬 단계에서 몬다(§5.7) — 루트 뷰의 scenePhase는 `.id(appTheme)` 리빌드에
    /// 얽혀 있고, 표지는 테마와 무관하게 항상 떠야 한다.
    @Environment(\.scenePhase) private var scenePhase

    /// 단일 스토어 컨테이너 — 종전 .modelContainer(for:)와 같은 스키마·같은 기본 위치(default.store).
    /// 명시 생성으로 바꾼 이유 = PlannerSync(CKSyncEngine)가 뷰 밖에서 같은 스토어를 써야 해서.
    /// ⚠ 폴백 분기 금지(repo CLAUDE.md split-brain 규칙) — 실패는 조용한 갈라짐보다 크래시가 낫다.
    static let container: ModelContainer = {
        // ⚠ 새 @Model은 여기 등록이 필수 — 빠지면 컴파일은 되고 실기기에서 조용히 실패한다
        // (repo CLAUDE.md 1번 함정). InputSubtask·InputProgress = Input 진행 방식(2026-08-12).
        let schema = Schema([PeriodDay.self, ScheduleItem.self, InputItem.self,
                             InputSubtask.self, InputProgress.self,
                             OutputItem.self, OutputSubtask.self, ItemCompletion.self,
                             DailyCheckIn.self, SelfReportRecord.self])
        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("스토어 열기 실패: \(error)")   // 크래시 로그 — 사용자 표면 아님(번역 제외)
        }
    }()

    /// 개발자 모드 스토어(2026-08-27, DevMode.swift 머리말) — 같은 스키마, 다른 파일.
    /// static let이라 dev 모드를 켜기 전엔 만들어지지 않는다. 동기화(PlannerSync)는 실컨테이너에만
    /// 붙어 있어 이 스토어의 데이터는 어디로도 안 나간다.
    static let devContainer: ModelContainer = {
        let schema = Schema([PeriodDay.self, ScheduleItem.self, InputItem.self,
                             InputSubtask.self, InputProgress.self,
                             OutputItem.self, OutputSubtask.self, ItemCompletion.self,
                             DailyCheckIn.self, SelfReportRecord.self])
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let config = ModelConfiguration(url: base.appendingPathComponent("dev-store.sqlite"))
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("개발자 스토어 열기 실패: \(error)")
        }
    }()

    init() {
        // 팔레트 캐시는 첫 렌더 전에 확정돼야 한다(Ink가 정적 캐시를 읽는다 — Theme.swift)
        // 앱 언어 선택 복원(2026-08-21) — 팔레트와 같은 이유로 첫 렌더 전에 확정한다
        Loc.restore()
        let savedTheme = UserDefaults.standard.string(forKey: ThemeStore.storageKey)
        // 온보딩 전(신규 설치·앱 초기화 직후)은 은필 고정(2026-09-04 베타 "은필라이트로 고정").
        // 저장은 하지 않는다 — 실제 선택·저장은 온보딩 테마 단계가 맡는다.
        // 튜토리얼 라이트 잠금은 실행을 넘기지 않는다(중간에 그만둔 사람 구제) — Coach.swift
        TutorialGate.releaseStaleLock()
        let onboardingDone = UserDefaults.standard.bool(forKey: "onboardingDone")
        ThemeStore.apply(onboardingDone ? savedTheme : (savedTheme ?? AppTheme.standard.rawValue),
                         pointRawValue: UserDefaults.standard.string(forKey: PointColor.storageKey))
        // 하늘 상태 복원(날씨 테마, 2026-08-19) — 설정 스위처가 저장한 확인용 값.
        // Phase ②에서 WeatherKit이 이 자리를 대체한다.
        WxState.apply(conditionRaw: UserDefaults.standard.string(forKey: WxState.conditionKey),
                      daypartRaw: UserDefaults.standard.string(forKey: WxState.daypartKey))
        WxState.loadReadout()   // 기온·강수 마지막 값(2026-08-20) — 3시간 넘으면 읽는 쪽이 감춘다
        // 가격 개편 승계(2026-08-27, 대표님 결정 "적용 중인 테마만 승계") — 전 테마 유료화로
        // 기존 설치의 지면이 잠기지 않게, 업데이트 후 **첫 실행 1회만** 적용 중 테마를 0원
        // 보유 처리한다. ⚠ 종전(2026-08-12 은필 전례)엔 매 실행 돌았는데, 전 테마 유료화
        // 뒤엔 그게 「체험 중 적용 → 재실행 = 공짜 소유」 구멍이 된다 — 1회성 플래그로 봉인.
        // 새 설치는 첫 실행에 저장값이 없어(온보딩 전) 아무것도 승계되지 않고 플래그만 선다.
        let pricingMigratedKey = "themePricingV2Migrated"
        if !UserDefaults.standard.bool(forKey: pricingMigratedKey) {
            UserDefaults.standard.set(true, forKey: pricingMigratedKey)
            if let saved = savedTheme.flatMap(AppTheme.init(rawValue:)), saved.seedPrice != nil {
                Seeds.grandfather(saved)
            }
        }
        // 수동 생성 컨테이너는 autosave 명시(repo CLAUDE.md 2026-07-23 실측)
        Self.container.mainContext.autosaveEnabled = true
        if DevMode.active { Self.devContainer.mainContext.autosaveEnabled = true }
        PlannerSync.shared.configure(container: Self.container)
        // 잠금화면 타이머 버튼의 실행부 등록(2026-08-14). 인텐트는 앱 프로세스에서 도는데,
        // 앱이 꺼져 있었다면 이 init과 perform()의 순서가 보장되지 않는다 — 먼저 도착한
        // 명령은 브리지가 보류하고 있다가 등록 직후 흘려보낸다(Shared/TimerIntents).
        TimerIntentBridge.register(TimerIntentHandler.shared)
        // 앱 밖에서 끝난 결제(승인 대기 통과·다른 기기)를 받아 finish 한다 — 안 걸어두면
        // 그 거래가 큐에 남아 실행마다 다시 전달된다(StoreKit 2 계약).
        TipStore.shared.startListening()
        ThemePassStore.shared.start()   // 테마 패스 entitlement 재검사 + 거래 수신(2026-08-27)
        // 탭·시트 상태는 테마 리빌드에서 살아남으려고 UserDefaults에 두지만 실행 간에는
        // 이월하지 않는다(2026-08-11) — 앱을 다시 열면 「오늘」에서, 시트는 닫힌 채로 시작한다.
        UserDefaults.standard.set(RootTab.today.rawValue, forKey: RootTab.storageKey)
        UserDefaults.standard.set(false, forKey: RootTab.themeShopKey)
    }

    /// 개발자 모드 관찰 — 소식란 커맨드(//dev)가 이 키를 토글하면 씬이 재평가돼 컨테이너가
    /// 갈아끼워진다. `.id`가 루트를 통째로 다시 세운다(테마·언어 리빌드와 같은 문법).
    @AppStorage(DevMode.key) private var devModeActive = false

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .id(devModeActive)
            // 다크 = 적응형 토큰으로 대응(Ink — 2026-07-20 사용자 결정). 정식 다크 테마는 미학 패스.
        }
        .modelContainer(devModeActive ? Self.devContainer : Self.container)
        // 앱 스위처 가림(§5.7 P0). **`.inactive`부터 덮는다** — 스냅샷은 백그라운드 진입 시점에
        // 찍히지만, 스위처를 띄우는 동안(비활성) 카드에 실제 화면이 그대로 보인다. 그 사이 기기를
        // 건네주면 가린 의미가 없다. 대가로 시스템 권한 시트가 뜰 때도 잠깐 표지가 스친다 —
        // 거슬리면 `.background`만 덮는 쪽으로 완화할 수 있다(가림 범위는 그만큼 줄어든다).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { PrivacyShield.uncover() } else { PrivacyShield.cover() }
        }
    }
}
