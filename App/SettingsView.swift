// 템포루틴 — 설정 탭 (Phase 0 ⑤: 데이터 섹션만 — MASTER §8.2.6)
// 내보내기 = 평문 JSON + 공유 시트(유저가 저장 위치 결정) + 민감 경고 / 가져오기 = merge·dedup(§5.5.1)
// 전체 삭제 = 분리 배치·확인 다이얼로그·undo 토스트(destructive-nav-separation).
// HealthKit·추적 항목·사운드·테마 섹션은 해당 빌드 단계에서.

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

    @State private var shareURL: URL?
    @State private var showImporter = false
    @State private var showWipeConfirm = false
    @State private var message: String?
    @State private var messageOffersPermission = false   // 건강 읽기 권한 안내 알럿에만 설정 버튼(2026-08-01)
    @AppStorage("onboardingDone") private var onboardingDone = false   // 온보딩 다시 보기(2026-08-01)
    @Query private var selfReports: [SelfReportRecord]
    @State private var showSelfReport = false
    @State private var undoSnapshot: ExportEnvelopeV1?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var lightFeedback = 0   // 작은 햅틱(§4 — 연동 토글, 확정 아님)
    @AppStorage(ThemeStore.storageKey) private var appTheme = AppTheme.standard.rawValue
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
    /// 기기 간 동기화 토글 상태(2026-08-10) — 원장은 PlannerSync, 여기는 렌더 트리거용 미러
    @State private var syncOn = PlannerSync.isEnabled

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
                    outputs: outputs, completions: completions, checkIns: checkIns)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            List {
                Section {
                    Button("JSON으로 내보내기") { exportData() }
                        .foregroundStyle(Ink.text)
                    Button("백업 가져오기") { showImporter = true }
                        .foregroundStyle(Ink.text)
                } header: {
                    Text("데이터")
                } footer: {
                    // 저장 실측 표시(2026-07-23 진단 겸 정보) — 스토어에 실제로 있는 개수
                    Text("이 파일엔 생리·컨디션 기록이 들어있어요. 지금 저장된 기록: 생리 \(periodDays.count)일 · 체크인 \(checkIns.count)건")
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
                } footer: {
                    // 진단 내역은 알럿에서 내려 여기로(2026-08-01) — 0건의 "왜"는 남기되 안내 문구는 깨끗하게
                    VStack(alignment: .leading, spacing: 4) {
                        Text(healthCaption)
                        if mirror.linked && !mirror.lastSyncReport.isEmpty {
                            Text("마지막 동기화 · \(mirror.lastSyncReport)")
                        }
                    }
                }

                // 기기 간 동기화(2026-08-10 재구현 — PlannerSync/CKSyncEngine, §5.2)
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
                } header: {
                    Text("기기 간 동기화")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("일정·Input·Output·체크인이 같은 Apple 계정의 기기끼리 당신의 iCloud로 이어져요. 생리 기록은 iCloud로 보내지 않아요 — 기기 간 전달은 건강 앱 연동이 맡아요.")
                        if !PlannerSync.shared.lastReport.isEmpty {
                            Text("마지막 동기화 · \(PlannerSync.shared.lastReport)")
                        }
                        // 연결 상태 진단(2026-08-11) — 엔진이 안 떠 있으면 기기 iCloud 설정 안내
                        if syncOn && !PlannerSync.shared.running {
                            Text("iCloud 연결 안 됨 — 기기 설정 > Apple 계정 > iCloud에서 템포루틴이 켜져 있는지, 폰과 같은 계정인지 확인해 주세요.")
                        }
                    }
                }

                // 알림(§5.11 계열) — 브리핑·예측 = 기본 켬(2026-08-05 사용자 결정),
                // 커버 리마인더 = 기본 꺼짐(§5.12 ⑤). 켜는 순간에만 시스템 권한을 묻는다.
                Section {
                    Toggle("아침 일정 브리핑", isOn: noticeBinding($morningBriefingOn))
                        .tint(Ink.text)
                    Toggle("생리 예측 알림", isOn: noticeBinding($periodForecastOn))
                        .tint(Ink.text)
                    Toggle("기록이 빈 시기 알려주기", isOn: coverageBinding)
                        .tint(Ink.text)
                    // ⚠ 임시 테스트 기능(2026-08-08 사용자 지시 — 검증 끝나면 이 버튼·상태·import 제거)
                    Button("테스트 알림 보내기") {
                        lightFeedback += 1
                        Task {
                            let granted = await CoverageReminder.requestPermission()
                            notificationDenied = !granted
                            guard granted else { testNoticeHint = nil; return }
                            let content = UNMutableNotificationContent()
                            content.title = "테스트 알림이에요"
                            content.body = "이 문구가 보이면 알림이 정상 동작하는 거예요."
                            content.sound = .signature   // 시그니처 칼림바(2026-08-09)
                            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                            try? await UNUserNotificationCenter.current().add(
                                UNNotificationRequest(identifier: "test-notice",
                                                      content: content, trigger: trigger))
                            testNoticeHint = "5초 뒤에 와요. 앱을 홈으로 내려두세요 — 앱이 떠 있으면 배너가 안 보여요."
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
                } footer: {
                    Text(notificationDenied
                         ? "알림이 꺼져 있어요. 설정에서 알림을 켜면 다시 고를 수 있어요."
                         : "브리핑은 일정이 있는 날 아침 8시에 한 번, 예측 알림은 예상 시작 전날과 당일에 한 번씩 와요. 빈 시기 알림은 한 주기를 네 구간으로 나눠 기록이 하나도 없는 구간에만 저녁에 한 번 알려요.")
                }

                // 기능 튜토리얼 리셋(2026-07-23 — JejuNow 「사용법 다시 보기」 동형)
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
                } footer: {
                    Text("사용법은 각 화면을 열 때 처음 안내가 다시 나와요. 온보딩은 첫 실행 화면을 처음부터 다시 봐요 — 기록은 지워지지 않아요.")
                }

                // 앱 내 자기보고 설문(v1.6 §4) — 언제든 재진입. 웹 응답과 연결하지 않는다.
                // (사전 설문 코드 섹션은 2026-08-09 사용자 결정으로 폐기 — 사전 설문 자체를 접음)
                Section {
                    Button(selfReports.isEmpty ? "리듬 설문 하기" : "리듬 설문 다시 하기") {
                        lightFeedback += 1
                        showSelfReport = true
                    }
                    .foregroundStyle(Ink.text)
                } footer: {
                    Text(selfReports.isEmpty
                         ? "17개 문항, 2분쯤 걸려요. 답은 이 기기에만 저장돼요."
                         : "마지막 응답 \(selfReports.count)건이 이 기기에 저장돼 있어요. 다시 답하면 새 응답으로 쌓여요.")
                }

                // 테마(2026-08-09 — 테마 탭 진입 행. 심기·적용·미리보기는 ThemeShopView, §3.8.1)
                Section {
                    Button {
                        lightFeedback += 1
                        showThemeShop = true
                    } label: {
                        HStack {
                            Text("테마").foregroundStyle(Ink.text)
                            Spacer()
                            Text((AppTheme(rawValue: appTheme) ?? .standard).displayName)
                                .foregroundStyle(Ink.text.opacity(0.5))
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Ink.text.opacity(0.35))
                        }
                    }
                } header: {
                    Text("테마")
                } footer: {
                    // 서체 고지(Pretendard 라이선스 권장 표기 — 시안 §1.6)
                    Text("체크인으로 모은 씨앗으로 새 테마를 구매할 수 있어요. 모던에는 Pretendard 서체(SIL 오픈 폰트 라이선스)가 쓰여요.")
                }

                // 파괴적 액션 — 분리 배치(§8.2.6)
                Section {
                    Button("모든 기록 삭제", role: .destructive) { showWipeConfirm = true }
                        .foregroundStyle(Ink.danger)
                }
            }
            .scrollContentBackground(.hidden)
            .centeredColumn(680)   // 아이패드 중앙 조판(2026-07-23) — 배경은 루트로 이동

            if undoSnapshot != nil {
                undoToast
            }
        }
        .background {
            ZStack {
                Ink.paper
                SeasonLight(phase: CycleSnapshot(periodDays: periodDays).phase(on: Calendar.current.startOfDay(for: .now)), motif: .open)
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
        .sheet(isPresented: $showSelfReport) { SelfReportFlow() }
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
            let name = "TempoRoutine-백업-\(ExportCodec.dayString(.now)).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            shareURL = url
        } catch {
            message = "내보내기에 실패했어요. 다시 시도해 주세요."
        }
    }

    private func importData(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        do {
            let envelope = try ExportCodec.decode(try Data(contentsOf: url))
            let added = ExportImport.merge(envelope, into: modelContext, existing: store)
            message = added > 0 ? "\(added)건을 가져왔어요." : "새로 가져올 기록이 없어요."
        } catch ExportCodec.CodecError.newerVersion {
            message = "이 백업은 지금 앱보다 새로운 버전이에요. 앱을 업데이트한 뒤 가져와 주세요."
        } catch {
            message = "가져올 수 없는 파일이에요."
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
                            message = "건강 앱 권한을 허용하지 않으면 연동할 수 없어요."
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
        if !mirror.available { return "이 기기에선 건강 앱을 사용할 수 없어요." }
        if mirror.linked && mirror.writeAuthorized {
            return "생리 기록이 건강 앱에도 저장돼요. 이 앱이 쓴 기록만 건강 앱에서 고칠 수 있어요."
        }
        if mirror.linked {
            return "가져올 기록이 없다면 읽기 권한이 꺼진 경우가 많아요. 아래 ‘건강 권한 설정 열기’를 눌러 템포루틴의 ‘생리’ 읽기를 켜주세요. (애플 정책상 앱이 이 권한 창을 다시 띄울 수 없어 설정에서만 켤 수 있어요.)"
        }
        return "기록은 이 기기에만 저장돼요."   // 아이패드 지원 정합(2026-07-23, §3.10 개정과 동일 원칙)
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
        withAnimation { undoSnapshot = snapshot }
        undoDismissTask = Task {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled {
                withAnimation { undoSnapshot = nil }
            }
        }
    }

    private func undoWipe() {
        guard let snapshot = undoSnapshot else { return }
        undoDismissTask?.cancel()
        // 전량 삭제 직후라 기존 셋이 비어 있어 스냅샷 전체가 재삽입된다(UUID 보존)
        ExportImport.merge(snapshot, into: modelContext, existing: store)
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
