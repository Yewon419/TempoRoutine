// 템포루틴 — 설정 탭 (Phase 0 ⑤: 데이터 섹션만 — MASTER §8.2.6)
// 내보내기 = 평문 JSON + 공유 시트(유저가 저장 위치 결정) + 민감 경고 / 가져오기 = merge·dedup(§5.5.1)
// 전체 삭제 = 분리 배치·확인 다이얼로그·undo 토스트(destructive-nav-separation).
// HealthKit·추적 항목·사운드·테마 섹션은 해당 빌드 단계에서.

import SwiftUI
import SwiftData
import TempoCore
import UIKit
import UniformTypeIdentifiers

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
    @State private var surveyCodeInput = ""
    @State private var surveyCodeMessage: String?
    @State private var surveyCodeRedeeming = false
    @State private var undoSnapshot: ExportEnvelopeV1?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var lightFeedback = 0   // 작은 햅틱(§4 — 연동 토글, 확정 아님)
    @AppStorage(ThemeStore.storageKey) private var appTheme = AppTheme.standard.rawValue

    /// 테마 선택 — 리빌드(.id) 전에 팔레트 캐시를 먼저 확정한다(선 apply, Theme.swift 반응성 설계)
    private var themeBinding: Binding<AppTheme> {
        Binding(
            get: { AppTheme(rawValue: appTheme) ?? .standard },
            set: { theme in
                lightFeedback += 1
                ThemeStore.apply(theme.rawValue)
                appTheme = theme.rawValue
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
                        onboardingDone = false
                    }
                    .foregroundStyle(Ink.text)
                } footer: {
                    Text("사용법은 각 화면을 열 때 처음 안내가 다시 나와요. 온보딩은 첫 실행 화면을 처음부터 다시 봐요 — 기록은 지워지지 않아요.")
                }

                // 사전 설문 참여 코드(v1.6 §9 3-8) — 온보딩을 이미 지난 사용자의 재진입 경로.
                // 온보딩에만 두면 기존 설치자는 코드를 영영 못 쓴다.
                Section {
                    if SurveyCode.isPrecursorUnlocked {
                        Label("선행 테마가 열려 있어요", systemImage: "checkmark.seal")
                            .foregroundStyle(Ink.text)
                    } else {
                        HStack(spacing: 8) {
                            TextField("TEMPO-XXXXXXXX", text: $surveyCodeInput)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .font(.subheadline.monospaced())
                            Button("확인") {
                                lightFeedback += 1
                                redeemSurveyCode()
                            }
                            .foregroundStyle(Ink.text)
                            .disabled(surveyCodeRedeeming || surveyCodeInput.isEmpty)
                        }
                        if let message = surveyCodeMessage {
                            Text(message).font(.footnote).foregroundStyle(Ink.text.opacity(0.6))
                        }
                    }
                } header: {
                    Text("사전 설문 코드")
                } footer: {
                    Text("사전 설문을 하고 받은 코드를 넣으면 선행 테마가 열려요. 코드는 한 번만 쓸 수 있어요.")
                }

                // 테마(§8.2.6 — 무료 설정 스위치, 테스트 중. IAP 설계 확정 시 재검토 — 2026-07-29)
                Section {
                    Picker("테마", selection: themeBinding) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .tint(Ink.text)
                } header: {
                    Text("테마")
                } footer: {
                    // 서체 고지(Pretendard 라이선스 권장 표기 — 시안 §1.6)
                    Text("모던 테마는 실험 중이에요. 화면 전체의 색이 바뀌어요. 모던에는 Pretendard 서체(SIL 오픈 폰트 라이선스)가 쓰여요.")
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

    private func redeemSurveyCode() {
        surveyCodeRedeeming = true
        surveyCodeMessage = nil
        Task {
            let outcome = await SurveyCode.redeem(surveyCodeInput)
            surveyCodeRedeeming = false
            surveyCodeMessage = outcome.message
            if outcome == .unlocked { surveyCodeInput = "" }
        }
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
