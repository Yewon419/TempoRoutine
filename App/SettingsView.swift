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
    @State private var undoSnapshot: ExportEnvelopeV1?
    @State private var undoDismissTask: Task<Void, Never>?

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
                    Text("이 파일엔 생리·컨디션 기록이 들어있어요.")
                }

                // HealthKit read-write 미러 (§5.7·§8.2.6 — 조건부 카피)
                Section {
                    Toggle("건강 앱과 연동", isOn: healthBinding)
                        .tint(Ink.text)
                        .disabled(!mirror.available)
                } header: {
                    Text("건강 앱")
                } footer: {
                    Text(healthCaption)
                }

                // 파괴적 액션 — 분리 배치(§8.2.6)
                Section {
                    Button("모든 기록 삭제", role: .destructive) { showWipeConfirm = true }
                        .foregroundStyle(Ink.danger)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Ink.paper.ignoresSafeArea())

            if undoSnapshot != nil {
                undoToast
            }
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
        .alert("데이터", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("확인") { message = nil }
        } message: {
            Text(message ?? "")
        }
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

    private var healthBinding: Binding<Bool> {
        Binding(
            get: { mirror.linked },
            set: { on in
                if on {
                    let current = store
                    Task {
                        if await mirror.requestAccess() {
                            await mirror.sync(context: modelContext, periodDays: current.periodDays)
                        }
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
            return "건강 앱 쓰기가 꺼져 있어요. 설정 앱의 건강 > 데이터 접근에서 허용할 수 있어요."
        }
        return "기록은 이 아이폰에만 저장돼요."
    }

    private func wipeAll(includeHealth: Bool) {
        undoDismissTask?.cancel()
        let snapshot = ExportImport.buildEnvelope(from: store)
        if includeHealth {
            let uuids = periodDays.filter { $0.origin == .appAuthored }.compactMap(\.healthKitUUID)
            Task { await mirror.deleteSamples(uuids: uuids) }
        }
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
