// 템포루틴 — 설정 탭 (MASTER §8.2.6)
// 섹션 순서(2026-08-12 정보 구조 재편): 테마 → 알림 → 건강 앱 → 기기 간 동기화 →
// 다시 보기 → 리듬 설문 → 데이터 → 모든 기록 삭제. 자주 만지는 것이 위, 파괴적인 것이 맨 아래.
// 헤더 규칙 = 여러 행을 묶는 이름일 때만 둔다. 단일 행 섹션(테마·동기화·설문·삭제)은
// 행 라벨이 곧 이름이라 헤더가 중복이 된다.
// 내보내기 = 평문 JSON + 공유 시트(유저가 저장 위치 결정) + 민감 경고 / 가져오기 = merge·dedup(§5.5.1)
// 전체 삭제 = 분리 배치·확인 다이얼로그·undo 토스트(destructive-nav-separation).

import SwiftUI
import SwiftData
import TempoCore
import UIKit
import UniformTypeIdentifiers
import UserNotifications   // 임시 테스트 알림(2026-08-08) — 기능 제거 시 함께 걷을 것

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var periodDays: [PeriodDay]
    @Query private var schedules: [ScheduleItem]
    @Query private var inputs: [InputItem]
    @Query private var outputs: [OutputItem]
    @Query private var completions: [ItemCompletion]
    @Query private var checkIns: [DailyCheckIn]
    @Query private var inputProgresses: [InputProgress]   // 내보내기·삭제 동반 처리(2026-08-12)

    @State private var shareURL: URL?
    @State private var showImporter = false
    @State private var showWipeConfirm = false
    @State private var showResetConfirm = false
    @State private var showResetFinalConfirm = false
    /// 언어 변경 대기값(2026-08-22 대표님 "언어 바꾸면 앱 재시작") — 피커는 이 값에 묶고, 확인을
    /// 눌러야 저장·종료한다. @AppStorage에 직접 묶으면 종료 전에 루트 리빌드가 먼저 돌아 옛 언어
    /// 조각이 스치고 무거운 재구성이 헛돈다.
    @State private var pendingLanguage: String?
    @State private var message: String?
    @State private var messageOffersPermission = false   // 건강 읽기 권한 안내 알럿에만 설정 버튼(2026-08-01)
    @AppStorage("onboardingDone") private var onboardingDone = false   // 온보딩 다시 보기(2026-08-01)
    @Query private var selfReports: [SelfReportRecord]
    @State private var showSelfReport = false
    @State private var undoSnapshot: ExportEnvelopeV1?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var lightFeedback = 0   // 작은 햅틱(§4 — 연동 토글, 확정 아님)
    @AppStorage(ThemeStore.storageKey) private var appTheme = AppTheme.plain.rawValue
    /// 사분면 커버 리마인더(§5.12 ⑤) — 기본 꺼짐. 켜는 순간에만 시스템 권한을 묻는다.
    @AppStorage(CoverageReminder.storageKey) private var coverageReminderOn = false
    @State private var notificationDenied = false
    /// 아침 일정 브리핑·생리 예측 알림(2026-08-05 사용자 결정) — 기본 켬.
    @AppStorage(DailyNotices.briefingKey) private var morningBriefingOn = true
    @AppStorage(DailyNotices.periodKey) private var periodForecastOn = true
    /// 임시 테스트 알림 안내 문구(2026-08-08 — 기능 제거 시 함께 걷을 것)
    @State private var testNoticeHint: String?

    /// 테마 진입 = 테마 탭 시트(2026-08-09 — 구 인라인 Picker 폐기, 심기·적용은 ThemeShopView 담당).
    /// 오늘 탭 진입과 같은 키를 공유한다 — 테마 리빌드에서 살아남아야 해서 뷰 밖에 둔다(RootTab 주석).
    @AppStorage(RootTab.themeShopKey) private var showThemeShop = false
    // 하늘 상태 스위처(날씨 테마 확인용, 2026-08-19 — Phase ②에서 WeatherKit로 대체)
    /// 앱 언어(2026-08-22 베타 "설정에도 언어선택") — 온보딩 첫 단계와 같은 저장 키
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue
    @AppStorage(WxState.conditionKey) private var wxCondition = WxCondition.clear.rawValue
    @AppStorage(WxState.daypartKey) private var wxDaypart = ""

    private func applyWxState() {
        WxState.apply(conditionRaw: wxCondition, daypartRaw: wxDaypart.isEmpty ? nil : wxDaypart)
    }
    /// 기기 간 동기화 토글 상태(2026-08-10) — 원장은 PlannerSync, 여기는 렌더 트리거용 미러
    @State private var syncOn = PlannerSync.isEnabled

    /// 개인정보 처리방침(2026-08-12) — ASC 메타데이터에 등록한 것과 같은 주소여야 한다.
    /// 커스텀 도메인을 붙이면 여기와 ASC를 함께 고칠 것.
    static let privacyPolicyURL = URL(string: "https://yewon419.github.io/temporoutine-site/privacy.html")!

    /// 브리핑·예측 토글 — 켜는 순간 권한 확인(미결정이면 시트), 거부면 되돌린다.
    /// 재스케줄은 DailyNotices가 앱 활성·백그라운드마다 돌아 토글 반영이 늦지 않지만,
    /// 켠 직후 바로 반영되도록 여기서도 한 번 건다.
    private func noticeBinding(_ storage: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { storage.wrappedValue },
            set: { on in
                lightFeedback += 1
                guard on else {
                    storage.wrappedValue = false
                    DailyNotices.reschedule(periodDays: periodDays, schedules: schedules)
                    return
                }
                let currentPeriods = periodDays
                let currentSchedules = schedules
                Task {
                    let granted = await CoverageReminder.requestPermission()
                    storage.wrappedValue = granted
                    notificationDenied = !granted
                    if granted {
                        DailyNotices.reschedule(periodDays: currentPeriods, schedules: currentSchedules)
                    }
                }
            }
        )
    }

    /// 켜는 순간 = 시스템 권한 시트(§3.6.1 더블 컨센트). 거부되면 토글을 되돌리고
    /// 설정 이동 버튼만 붙인다 — 켜진 척하는 스위치가 제일 나쁘다.
    private var coverageBinding: Binding<Bool> {
        Binding(
            get: { coverageReminderOn },
            set: { on in
                lightFeedback += 1
                guard on else {
                    coverageReminderOn = false
                    notificationDenied = false
                    CoverageReminder.cancelAll()
                    return
                }
                let current = periodDays   // @Query 배열은 Task 밖에서 잡는다(healthBinding과 같은 이유)
                Task {
                    let granted = await CoverageReminder.requestPermission()
                    coverageReminderOn = granted
                    notificationDenied = !granted
                    if granted {
                        CoverageReminder.reschedule(periodDays: current, context: modelContext)
                    }
                }
            }
        )
    }

    private var store: StoreArrays {
        StoreArrays(periodDays: periodDays, schedules: schedules, inputs: inputs,
                    outputs: outputs, completions: completions, checkIns: checkIns,
                    inputProgresses: inputProgresses, selfReports: selfReports)
    }

    /// 설정 행 재질(2026-08-20 베타 피드백 "설정탭만 이질적" — 시안 `.list-group`은 그 테마의
    /// 카드 재질과 동일하다). nil = 시스템 insetGrouped 그대로(기본·포인트컬러·티켓).
    /// 활판은 채움 없음(§2.6 — 눌린 것은 면이 아니라 선), 행 구분은 세퍼레이터가 담당.
    private static var themedRowGround: AnyView? {
        switch ThemeStore.chrome.settingsList {
        case .system: nil
        case .glass: AnyView(Rectangle().fill(.ultraThinMaterial).overlay { Ink.surface })
        case .bare: AnyView(Color.clear)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            List {
                // 행 재질 트레이트는 Group에 걸어 안의 전 행에 전파한다(개별 Section 무수정)
                Group {
                // 테마(2026-08-09 — 테마 탭 진입 행. 심기·적용·미리보기는 ThemeShopView, §3.8.1)
                Section {
                    Button {
                        lightFeedback += 1
                        showThemeShop = true
                    } label: {
                        HStack {
                            Text("테마").foregroundStyle(Ink.text)
                            Spacer()
                            Text((AppTheme(rawValue: appTheme) ?? .plain).displayName)
                                .foregroundStyle(Ink.text.opacity(0.5))
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Ink.text.opacity(0.35))
                        }
                    }
                } footer: {
                    // 서체 고지(Pretendard 라이선스 권장 표기 — 시안 §1.6)
                    Text("매일매일 체크인하면 씨앗을 모을 수 있고, 씨앗으로 새 테마를 구매할 수 있어요!")
                        .foregroundStyle(Ink.groundSub)
                }
                // 언어(2026-08-22 베타 피드백) — 확인하면 **그 자리에서 바뀐다**(번들 덮어쓰기 +
                // RootTabView `.id(…appLanguage)` 리빌드). 종전엔 `exit(0)`으로 앱을 닫았는데,
                // 버튼으로 앱을 종료시키는 패턴은 심사 리젝 전례가 있어 1.0 제출 전 걷어냈다
                // (2026-08-23). 설정 앱의 앱별 언어로 보내는 대안은 안 된다 — 시스템은 AppleLanguages만
                // 건드리고 우리 `appLanguage` 키는 그대로라 앱이 계속 옛 언어를 본다.
                // 온보딩 0단계도 같은 즉시 전환이다.
                // 이름은 각자의 언어로(endonym) — 지금 화면이 무슨 언어든 자기 언어를 찾을 수 있게.
                Section {
                    Picker(selection: Binding(
                        get: { pendingLanguage ?? appLanguage },
                        set: { pendingLanguage = $0 == appLanguage ? nil : $0 }
                    )) {
                        ForEach(AppLanguage.allCases) { lang in
                            if lang == .system {
                                Text("기기 설정 따름").tag(lang.rawValue)
                            } else {
                                Text(verbatim: lang.nativeName).tag(lang.rawValue)
                            }
                        }
                    } label: {
                        Text("언어").foregroundStyle(Ink.text)
                    }
                    .alert("언어를 바꿀까요?",
                           isPresented: Binding(get: { pendingLanguage != nil },
                                                set: { if !$0 { pendingLanguage = nil } })) {
                        Button("바꾸기") {
                            guard let raw = pendingLanguage, let lang = AppLanguage(rawValue: raw) else { return }
                            Loc.apply(lang)   // appLanguage + AppleLanguages + App Group 저장
                        }
                        Button("취소", role: .cancel) { pendingLanguage = nil }
                    } message: {
                        Text("고른 언어로 바로 바뀌어요. 혹시 옛 언어가 남아 있으면 앱을 완전히 닫았다 열어 주세요.")
                    }
                }

                // 알림(§5.11 계열) — 브리핑·예측 = 기본 켬(2026-08-05 사용자 결정),
                // 커버 리마인더 = 기본 꺼짐(§5.12 ⑤). 켜는 순간에만 시스템 권한을 묻는다.
                Section {
                    Toggle("아침 일정 브리핑", isOn: noticeBinding($morningBriefingOn))
                        .tint(Ink.text)
                    Toggle("생리 예측 알림", isOn: noticeBinding($periodForecastOn))
                        .tint(Ink.text)
                    Toggle("기록이 부족한 시기 알려주기", isOn: coverageBinding)
                        .tint(Ink.text)
                    // ⚠ 임시 테스트 기능(2026-08-08 사용자 지시 — 검증 끝나면 이 버튼·상태·import 제거)
                    Button("테스트 알림 보내기") {
                        lightFeedback += 1
                        Task {
                            let granted = await CoverageReminder.requestPermission()
                            notificationDenied = !granted
                            guard granted else { testNoticeHint = nil; return }
                            let content = UNMutableNotificationContent()
                            content.title = Loc.str("테스트 알림이에요")
                            content.body = Loc.str("이 문구가 보이면 알림이 정상 동작하는 거예요.")
                            content.sound = .signature   // 시그니처 칼림바(2026-08-09)
                            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                            try? await UNUserNotificationCenter.current().add(
                                UNNotificationRequest(identifier: "test-notice",
                                                      content: content, trigger: trigger))
                            testNoticeHint = Loc.str("5초 뒤에 와요. 앱을 홈으로 내려두세요 — 앱이 떠 있으면 배너가 안 보여요.")
                        }
                    }
                    .foregroundStyle(Ink.text)
                    if let hint = testNoticeHint {
                        Text(hint)
                            .font(.footnote)
                            .foregroundStyle(Ink.text.opacity(0.55))
                    }
                    if notificationDenied {
                        Button("알림 설정 열기") { openAppSettings() }
                            .foregroundStyle(Ink.text)
                    }
                } header: {
                    Text("알림")
                        .foregroundStyle(Ink.groundSub)
                } footer: {
                    Text(notificationDenied
                         ? Loc.str("알림이 꺼져 있어요. 설정에서 알림을 켜면 다시 고를 수 있어요.")
                         : Loc.str("브리핑은 일정 당일 아침 8시에, 생리 예측 알림은 예상일 전날과 당일에 한 번씩 알림이 가요."))
                        .foregroundStyle(Ink.groundSub)
                }

                // HealthKit read-write 미러 (§5.7·§8.2.6 — 조건부 카피)
                Section {
                    Toggle("건강 앱과 연동", isOn: healthBinding)
                        .tint(Ink.text)
                        .disabled(!mirror.available)
                        .onChange(of: mirror.linked) { _, _ in lightFeedback += 1 }
                    if mirror.available {
                        // 읽기 권한 재요청은 애플이 막음(§5.7) — 설정 앱 원탭 이동이 최선(2026-07-24)
                        Button("건강 권한 설정 열기") { openAppSettings() }
                            .foregroundStyle(Ink.text)
                    }
                } header: {
                    Text("건강 앱")
                        .foregroundStyle(Ink.groundSub)
                } footer: {
                    // 진단 내역은 알럿에서 내려 여기로(2026-08-01) — 0건의 "왜"는 남기되 안내 문구는 깨끗하게
                    VStack(alignment: .leading, spacing: 4) {
                        Text(healthCaption)
                        if mirror.linked && !mirror.lastSyncReport.isEmpty {
                            Text(Loc.fmt("마지막 동기화 · %1$@", "\(mirror.lastSyncReport)"))
                        }
                    }
                    .foregroundStyle(Ink.groundSub)
                }

                // 기기 간 동기화(2026-08-10 재구현 — PlannerSync/CKSyncEngine, §5.2)
                // 토글 라벨이 곧 섹션 이름이라 헤더를 두지 않는다(2026-08-12 정보 구조 재편).
                Section {
                    Toggle("기기 간 동기화", isOn: Binding(
                        get: { syncOn },
                        set: { on in
                            lightFeedback += 1
                            syncOn = on
                            PlannerSync.shared.setEnabled(on)
                        }
                    ))
                    .tint(Ink.text)
                    if syncOn {
                        Button("지금 동기화") {
                            lightFeedback += 1
                            Task { await PlannerSync.shared.syncNow() }
                        }
                        .foregroundStyle(Ink.text)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("일정·Input·Output·체크인이 같은 Apple 계정의 기기끼리 당신의 iCloud로 연동됩니다. 생리 기록은 iCloud로 보내지 않습니다.")
                        if !PlannerSync.shared.lastReport.isEmpty {
                            Text(Loc.fmt("마지막 동기화 · %1$@", "\(PlannerSync.shared.lastReport)"))
                        }
                        // 연결 상태 진단(2026-08-11) — 엔진이 안 떠 있으면 기기 iCloud 설정 안내
                        if syncOn && !PlannerSync.shared.running {
                            Text("iCloud 연결 안 됨 — 기기 설정 > Apple 계정 > iCloud에서 템포루틴이 켜져 있는지, 폰과 같은 계정인지 확인해 주세요.")
                        }
                    }
                    .foregroundStyle(Ink.groundSub)
                }

                // 기능 튜토리얼 리셋(2026-07-23 — JejuNow 「사용법 다시 보기」 동형)
                // 두 행을 묶는 이름이 없어 헤더를 붙였다(2026-08-12 정보 구조 재편).
                Section {
                    Button("사용법 다시 보기") {
                        lightFeedback += 1
                        CoachStore.resetAll()
                    }
                    .foregroundStyle(Ink.text)
                    // 온보딩 다시 보기(2026-08-01 베타 피드백) — 앱 삭제·재설치 없이 첫 안내를 다시 본다.
                    // 기록은 건드리지 않는다(플래그만 내림) — 온보딩에서 기준일을 다시 적으면 그때 반영.
                    Button("온보딩 다시 보기") {
                        lightFeedback += 1
                        // 재진입 표식(2026-08-09 베타 피드백) — 온보딩 좌상단 X(즉시 나가기) 노출 조건.
                        // 첫 실행 온보딩엔 X가 없어야 한다(건너뛸 수 없는 최초 설정).
                        UserDefaults.standard.set(true, forKey: "onboardingRevisit")
                        onboardingDone = false
                    }
                    .foregroundStyle(Ink.text)
                } header: {
                    Text("다시 보기")
                        .foregroundStyle(Ink.groundSub)
                }

                // 앱 내 자기보고 설문(v1.6 §4) — 언제든 재진입. 웹 응답과 연결하지 않는다.
                // (사전 설문 코드 섹션은 2026-08-09 사용자 결정으로 폐기 — 사전 설문 자체를 접음)
                Section {
                    Button(selfReports.isEmpty ? Loc.str("리듬 설문 하기") : Loc.str("리듬 설문 다시 하기")) {
                        lightFeedback += 1
                        showSelfReport = true
                    }
                    .foregroundStyle(Ink.text)
                } footer: {
                    // 「이전 설문 확인」은 별도 화면 없이 다시 하기에 합쳐졌다(2026-08-24 대표님
                    // 지시) — 다시 하기를 누르면 이전 응답이 채워진 채 열린다.
                    Text(selfReports.isEmpty
                         ? Loc.str("응답은 이 기기에만 저장돼요.")
                         : Loc.str("다시 하기를 누르면 이전 응답이 채워진 채 열려요. 확인만 하고 닫아도 돼요."))
                        .foregroundStyle(Ink.groundSub)
                }

                // 데이터 — 내보내기·가져오기·처리방침. 저빈도 액션이라 삭제 바로 위로 내렸다
                // (2026-08-12 정보 구조 재편 — 「내 기록이 어디 있나」 맥락끼리 인접).
                Section {
                    Button("JSON으로 내보내기") { exportData() }
                        .foregroundStyle(Ink.text)
                    Button("백업 가져오기") { showImporter = true }
                        .foregroundStyle(Ink.text)
                    // 심사 지침 5.1.1(i)은 ASC 메타데이터뿐 아니라 **앱 안에서도** 처리방침에
                    // 닿을 수 있기를 요구한다(2026-08-12). 데이터 섹션에 두는 이유 = 내보내기·
                    // 삭제와 같은 "내 기록이 어디 있나" 맥락.
                    Link("개인정보 처리방침", destination: Self.privacyPolicyURL)
                        .foregroundStyle(Ink.text)
                } header: {
                    Text("데이터")
                        .foregroundStyle(Ink.groundSub)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        // 저장 실측 표시(2026-07-23 진단 겸 정보) — 스토어에 실제로 있는 개수
                        Text(Loc.fmt("이 파일엔 생리·컨디션 기록이 들어있어요. 지금 저장된 기록: 생리 %1$@일 · 체크인 %2$@건", "\(periodDays.count)", "\(checkIns.count)"))
                        // 기기 이전 경로 노출(2026-08-19, 개정 P 후속) — 경로는 종전부터 동작, 카피만 신설
                        Text("기기를 바꾸시나요? 내보내기 파일을 새 기기로 보내고 「백업 가져오기」로 열면 기록이 이어져요.")
                    }
                    .foregroundStyle(Ink.groundSub)
                }

                // 파괴적 액션 — 분리 배치(§8.2.6)
                Section {
                    Button("모든 기록 삭제", role: .destructive) { showWipeConfirm = true }
                        .foregroundStyle(Ink.danger)
                }

                // 앱 초기화(2026-08-25 대표님 지시 "모든 기록 삭제가 앱 초기화가 아니네") —
                // 기록 삭제와 분리해 둔다: 기록만 지우는 경로(undo 있음)는 살리고, 이건
                // 새 설치와 동일한 리셋(undo 없음·확인 2단)이다.
                Section {
                    Button("앱 초기화", role: .destructive) { showResetConfirm = true }
                        .foregroundStyle(Ink.danger)
                } footer: {
                    Text("기록, 씨앗과 구매한 테마, 설정, iCloud 동기화 기록까지 전부 지우고 처음부터 시작해요.")
                        .foregroundStyle(Ink.groundSub)
                }

                // ── 하늘 상태 스위처(날씨 테마 전용, 2026-08-19) — WeatherKit 연결(Phase ②)
                // 전까지의 확인용. 시간대 고정까지 합쳐 12상태를 시각과 무관하게 확인한다.
                if ThemeStore.chrome.skyGround {
                    Section {
                        Picker("하늘", selection: $wxCondition) {
                            ForEach(WxCondition.allCases) { c in
                                Text(c.displayName).tag(c.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        Picker("시간대", selection: $wxDaypart) {
                            Text("시계 따름").tag("")
                            Text("낮").tag(Daypart.day.rawValue)
                            Text("노을").tag(Daypart.dusk.rawValue)
                            Text("밤").tag(Daypart.night.rawValue)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("하늘 (확인용)")
                            .foregroundStyle(Ink.groundSub)
                    } footer: {
                        Text("날씨 연동 전 임시 스위치예요. 「시계 따름」이면 시간대가 기기 시계를 따라요.")
                            .foregroundStyle(Ink.groundSub)
                    }
                    .onChange(of: wxCondition) { _, _ in applyWxState() }
                    .onChange(of: wxDaypart) { _, _ in applyWxState() }
                }
                }   // Group — 행 재질 전파 끝
                .listRowBackground(Self.themedRowGround)
            }
            .scrollContentBackground(.hidden)
            .centeredColumn(680)   // 아이패드 중앙 조판(2026-07-23) — 배경은 루트로 이동

            if undoSnapshot != nil {
                undoToast
            }
        }
        .background {
            // 티켓 = 흰 지면(2026-08-18 2차 — 유화는 오늘·나의 템포만)
            ZStack {
                if ThemeStore.chrome.skyGround {
                    WeatherSky()   // 날씨 = 오늘의 하늘(시안 §5.3-1)
                } else if ThemeStore.chrome.videoGround {
                    PlaylistVideoGround()   // 플리 = 계절 배경 영상(§4.4 ⑪)
                } else {
                    Ink.paper
                    SeasonLight(phase: CycleSnapshot(periodDays: periodDays).phase(on: Calendar.current.startOfDay(for: .now)), motif: .open)
                }
            }
            .ignoresSafeArea()
        }
        .navigationTitle("설정")
        .sheet(item: Binding(
            get: { shareURL.map(ShareFile.init) },
            set: { if $0 == nil { shareURL = nil } }
        )) { file in
            ActivityShareSheet(url: file.url)
        }
        .sheet(isPresented: $showSelfReport) {
            // 다시 하기 = 마지막 응답을 채워서 연다(동기화로 내려온 응답 포함 — completedAt 최신)
            SelfReportFlow(previousAnswers: selfReports.max(by: { $0.completedAt < $1.completedAt })?
                .answers ?? [:])
                .themeColorScheme()
        }
        // 테마 탭 시트 표시는 RootTabView 한 곳(2026-08-11) — 여기선 플래그만 세운다
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            importData(result)
        }
        .confirmationDialog("모든 기록을 삭제할까요?", isPresented: $showWipeConfirm, titleVisibility: .visible) {
            Button("기록만 삭제", role: .destructive) { wipeAll(includeHealth: false) }
            if periodDays.contains(where: { $0.origin == .appAuthored }) {
                Button("건강 앱에 쓴 기록도 삭제", role: .destructive) { wipeAll(includeHealth: true) }
            }
            Button("취소", role: .cancel) {}
        } message: {
            // §5.7: 이 앱이 쓴 것만 지움 — 타 앱·건강앱 원본은 건강 앱에서
            Text("이 기기의 생리·컨디션·계획 기록이 모두 지워져요. 건강 앱 옵션은 이 앱이 건강 앱에 쓴 기록만 지우고, 다른 앱이나 건강 앱의 원본은 건강 앱에서 지울 수 있어요.")
        }
        // 초기화 확인 2단(undo가 없어서) — 1단 = 지워지는 것 명시, 2단 = 최종 확인
        .confirmationDialog("앱을 초기화할까요?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("초기화", role: .destructive) { showResetFinalConfirm = true }
            Button("취소", role: .cancel) {}
        } message: {
            Text("모든 기록과 함께 씨앗, 구매한 테마, 설정, iCloud 동기화 기록이 지워지고 온보딩부터 다시 시작해요. 건강 앱에 쓴 기록은 지우지 않아요.")
        }
        .alert("정말 초기화할까요?", isPresented: $showResetFinalConfirm) {
            Button("전부 지우고 처음부터", role: .destructive) { Task { await resetApp() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("되돌릴 수 없어요.")
        }
        .alert("데이터", isPresented: Binding(get: { message != nil },
                                          set: { if !$0 { message = nil; messageOffersPermission = false } })) {
            if messageOffersPermission {
                Button("권한 설정 열기") { message = nil; messageOffersPermission = false; openAppSettings() }
            }
            Button("확인") { message = nil; messageOffersPermission = false }
        } message: {
            Text(message ?? "")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: lightFeedback)
    }

    // ── undo 토스트 ──
    private var undoToast: some View {
        HStack(spacing: 12) {
            Text("모든 기록을 삭제했어요.")
                .font(.footnote)
                .foregroundStyle(Ink.paper)
            Button("되돌리기") { undoWipe() }
                .font(.footnote.weight(.bold))
                .foregroundStyle(Ink.paper)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Ink.text, in: Capsule())
        .padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // ── 동작 ──
    private func exportData() {
        do {
            let data = try ExportCodec.encode(ExportImport.buildEnvelope(from: store))
            let name = Loc.fmt("TempoRoutine-백업-%1$@.json", "\(ExportCodec.dayString(.now))")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            shareURL = url
        } catch {
            message = Loc.str("내보내기에 실패했어요. 다시 시도해 주세요.")
        }
    }

    private func importData(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        do {
            let envelope = try ExportCodec.decode(try Data(contentsOf: url))
            let added = ExportImport.merge(envelope, into: modelContext, existing: store)
            if added > 0 { refreshDerivedSurfaces() }
            message = added > 0 ? Loc.fmt("%lld건을 가져왔어요.", added) : Loc.str("새로 가져올 기록이 없어요.")
        } catch ExportCodec.CodecError.newerVersion {
            message = Loc.str("이 백업은 지금 앱보다 새로운 버전이에요. 앱을 업데이트한 뒤 가져와 주세요.")
        } catch {
            message = Loc.str("가져올 수 없는 파일이에요.")
        }
    }

    private let mirror = HealthMirror.shared

    private func openAppSettings() {
        lightFeedback += 1
        HealthMirror.openAppSettings()
    }

    private var healthBinding: Binding<Bool> {
        Binding(
            get: { mirror.linked },
            set: { on in
                if on {
                    let current = store
                    Task {
                        guard await mirror.requestAccess() else {
                            message = Loc.str("건강 앱 권한을 허용하지 않으면 연동할 수 없어요.")
                            return
                        }
                        await mirror.sync(context: modelContext, periodDays: current.periodDays)
                        let outcome = mirror.lastOutcome
                        messageOffersPermission = outcome.suggestsPermissionCheck
                        message = outcome.message
                    }
                } else {
                    mirror.linked = false   // 미러 중지 — 기존 기록은 양쪽 다 유지
                }
            }
        )
    }

    private var healthCaption: String {
        if !mirror.available { return Loc.str("이 기기에선 건강 앱을 사용할 수 없습니다.") }
        if mirror.linked && mirror.writeAuthorized {
            return Loc.str("생리 기록이 건강 앱에도 저장돼요. 이 앱이 쓴 기록만 건강 앱에서 고칠 수 있어요.")
        }
        if mirror.linked {
            return Loc.str("가져올 기록이 없다면 읽기 권한이 꺼진 경우가 많아요. 아래 ‘건강 권한 설정 열기’를 눌러 템포루틴의 ‘생리’ 읽기를 켜주세요.")
        }
        return Loc.str("기록은 이 기기에만 저장됩니다.")   // 아이패드 지원 정합(2026-07-23, §3.10 개정과 동일 원칙)
    }

    /// 삭제·복원·가져오기 직후 파생 표면 재정렬(2026-08-20 감사) — 위젯 스냅샷·브리핑·예측·
    /// 커버 알림이 이 세 경로에서 갱신되지 않아, 전체 삭제 후에도 위젯이 옛 목록을 보여주고
    /// 다음 날 아침 브리핑이 지운 일정 제목을 읽었다. @Query 배열은 트랜잭션 직후 stale일 수
    /// 있어 컨텍스트에서 직접 읽는다.
    private func refreshDerivedSurfaces() {
        let periods = (try? modelContext.fetch(FetchDescriptor<PeriodDay>())) ?? []
        let scheds = (try? modelContext.fetch(
            FetchDescriptor<ScheduleItem>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let ins = (try? modelContext.fetch(
            FetchDescriptor<InputItem>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let outs = (try? modelContext.fetch(
            FetchDescriptor<OutputItem>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let comps = (try? modelContext.fetch(FetchDescriptor<ItemCompletion>())) ?? []
        let progresses = (try? modelContext.fetch(FetchDescriptor<InputProgress>())) ?? []
        WidgetBridge.publish(periodDays: periods, schedules: scheds, inputs: ins,
                             outputs: outs, completions: comps, inputProgresses: progresses)
        DailyNotices.reschedule(periodDays: periods, schedules: scheds)
        CoverageReminder.reschedule(periodDays: periods, context: modelContext)
    }

    private func wipeAll(includeHealth: Bool) {
        undoDismissTask?.cancel()
        let snapshot = ExportImport.buildEnvelope(from: store)
        if includeHealth {
            let uuids = periodDays.filter { $0.origin == .appAuthored }.compactMap(\.healthKitUUID)
            Task { await mirror.deleteSamples(uuids: uuids) }
        }
        HealthMirror.resetImportState()   // 앵커·툼스톤 리셋 — 재연동이 초기 가져오기가 되도록(2026-07-23)
        ExportImport.wipeAll(store, context: modelContext)
        refreshDerivedSurfaces()
        withAnimation { undoSnapshot = snapshot }
        undoDismissTask = Task {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled {
                withAnimation { undoSnapshot = nil }
            }
        }
    }

    /// 앱 초기화(2026-08-25) — 새 설치와 동일한 상태로. 순서가 계약이다:
    /// ① 알림 전부 취소 ② CloudKit 존 삭제(실패해도 진행 — 아래 ⑤에서 플래그로 이월)
    /// ③ 로컬 스토어 전량 삭제 ④ UserDefaults(표준+App Group) 전량 삭제 ⑤ 존 삭제 실패 시
    /// purgePending 재기록(④가 지웠으므로 ④ 뒤여야 한다) ⑥ 파생 표면 리셋.
    /// 건강 앱 기록은 안 지운다 — 앱을 삭제해도 건강 앱 데이터는 남는 것과 같은 경계.
    /// undo 없음(확인 2단이 그 자리를 대신한다). exit(0) 재시작도 안 쓴다(심사 리스크로 제거
    /// 이력) — onboardingDone 제거가 루트 fullScreenCover를 즉시 되살린다.
    private func resetApp() async {
        undoDismissTask?.cancel()
        undoSnapshot = nil

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let zonePurged = await PlannerSync.shared.purgeForReset()

        HealthMirror.resetImportState()
        ExportImport.wipeAll(store, context: modelContext)
        try? modelContext.save()

        // UserDefaults — 앱이 쓴 도메인만 지운다. removePersistentDomain은 @AppStorage에
        // 키별 변경 통지가 안 가는 수가 있어 키 단위로 지운다(onboardingDone 제거 →
        // 루트 fullScreenCover가 이 통지로 온보딩을 되살린다).
        let standard = UserDefaults.standard
        if let bundleID = Bundle.main.bundleIdentifier,
           let domain = standard.persistentDomain(forName: bundleID) {
            for key in domain.keys { standard.removeObject(forKey: key) }
        }
        if let group = UserDefaults(suiteName: WidgetShared.appGroupID),
           let domain = group.persistentDomain(forName: WidgetShared.appGroupID) {
            for key in domain.keys { group.removeObject(forKey: key) }
        }
        if !zonePurged {
            standard.set(true, forKey: PlannerSync.purgePendingKey)
        }

        // 인메모리 캐시 — UserDefaults만 비우면 남는 것들
        ThemeStore.apply(nil)          // 정적 팔레트 → 기본 테마
        TipStore.shared.resetForAppReset()

        // 위젯 — 빈 스냅샷 발행(홈 화면 위젯이 옛 데이터를 계속 그리지 않게)
        WidgetBridge.publish(periodDays: [])
    }

    private func undoWipe() {
        guard let snapshot = undoSnapshot else { return }
        undoDismissTask?.cancel()
        // 전량 삭제 직후라 기존 셋이 비어 있어 스냅샷 전체가 재삽입된다(UUID 보존)
        ExportImport.merge(snapshot, into: modelContext, existing: store)
        refreshDerivedSurfaces()
        withAnimation { undoSnapshot = nil }
    }
}

private struct ShareFile: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
