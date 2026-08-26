// 템포루틴 — 소식란 (2026-08-09 사용자 지시)
// 개발자가 repo의 notices/notices.json에 글을 쓰고 push하면 앱이 읽어온다(SNS 형식 피드).
// 무서버 계약(§5.2) 유지: 수신 전용 GET뿐, 기기에서 나가는 데이터·식별자 0 — 신뢰 카피
// ("아무와도 공유하지 않아요")와 비충돌. 씨앗 뿌리기 = 공지에 seeds 필드, 공지 id별 1회 수령(§3.8.1).
// 진입 = 캘린더 탭 우상단 확성기 아이콘(미읽음 점 표시).

import MessageUI
import SwiftUI
import SwiftData

struct Notice: Codable, Identifiable, Equatable {
    let id: String
    let date: String        // "yyyy-MM-dd" 표기용 — 파싱하지 않고 그대로 보여준다
    let title: String
    let body: String
    let seeds: Int?
}

private struct NoticeEnvelope: Codable {
    let notices: [Notice]
}

@MainActor
@Observable
final class NoticeFeed {
    static let shared = NoticeFeed()

    /// 소식의 SSOT = repo `notices/notices.json`. 글 올리기 = 파일 편집 후 커밋·push(배포 불필요).
    private static let url = URL(string:
        "https://raw.githubusercontent.com/Yewon419/TempoRoutine/main/notices/notices.json")!

    private static let cacheKey = "noticesCache"
    private static let seenKey = "noticesSeen"
    private static let fetchedAtKey = "noticesFetchedAt"

    private(set) var notices: [Notice] = []
    /// 캐시도 없이 fetch까지 실패한 상태에서만 빈 화면 안내를 바꾼다
    private(set) var loadFailed = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode([Notice].self, from: data) {
            notices = cached
        }
    }

    var seenIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: Self.seenKey) }
    }

    var hasUnread: Bool {
        let seen = seenIDs
        return notices.contains { !seen.contains($0.id) }
    }

    func markAllSeen() {
        seenIDs = seenIDs.union(notices.map(\.id))
    }

    /// 새로고침 — force가 아니면 1시간에 한 번만(캘린더 진입마다 네트워크를 태우지 않는다).
    /// 실패는 조용히 캐시 유지 — 소식란이 앱 사용을 막아선 안 된다.
    func refresh(force: Bool = false) async {
        let last = UserDefaults.standard.double(forKey: Self.fetchedAtKey)
        if !force, last > 0, Date.now.timeIntervalSince1970 - last < 3600 { return }
        do {
            var request = URLRequest(url: Self.url)
            request.cachePolicy = .reloadIgnoringLocalCacheData   // raw CDN 캐시만 신뢰
            let (data, _) = try await URLSession.shared.data(for: request)
            let envelope = try JSONDecoder().decode(NoticeEnvelope.self, from: data)
            notices = envelope.notices.sorted { $0.date > $1.date }
            loadFailed = false
            if let encoded = try? JSONEncoder().encode(notices) {
                UserDefaults.standard.set(encoded, forKey: Self.cacheKey)
            }
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Self.fetchedAtKey)
        } catch {
            loadFailed = notices.isEmpty
        }
    }
}

// ── 소식 화면 — SNS 형식 카드 피드 ──
struct NoticesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    private var feed = NoticeFeed.shared
    /// 수령 상태는 씨앗 원장 — 생 UserDefaults 읽기는 무효화가 안 걸려서 방송 카운터를 지켜본다
    @AppStorage(Seeds.revisionKey) private var seedRevision = 0
    // 개발자에게 피드백 보내기(2026-08-26 베타 "탭 하단부에 메세지 보내는 칸 같은거")
    @State private var feedbackText = ""
    @State private var showMailComposer = false
    @State private var showMailFallback = false
    @FocusState private var feedbackFocused: Bool

    private var trimmedFeedback: String {
        feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if feed.notices.isEmpty {
                            Text(feed.loadFailed
                                 ? Loc.str("소식을 불러오지 못했어요. 잠시 뒤에 다시 열어주세요.")
                                 : Loc.str("아직 소식이 없어요."))
                                .font(.subheadline)
                                .foregroundStyle(Ink.text.opacity(0.55))
                                .padding(.top, 24)
                        }
                        ForEach(feed.notices) { notice in
                            noticeCard(notice)
                        }
                    }
                    .padding(20)
                    .centeredColumn(640)
                }
                .refreshable { await feed.refresh(force: true) }
            }
            .safeAreaInset(edge: .bottom) { feedbackBar }
            .navigationTitle("소식")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }.foregroundStyle(Ink.text)
                }
            }
        }
        .sheet(isPresented: $showMailComposer) {
            FeedbackMailComposer(text: trimmedFeedback) { sent in
                showMailComposer = false
                if sent { feedbackText = "" }   // 보냈으면 비운다 — 취소했으면 쓰던 글을 남긴다
            }
            .ignoresSafeArea()
        }
        .alert("메일 앱을 열 수 없어요", isPresented: $showMailFallback) {
            Button("확인") {}
        } message: {
            Text(Loc.fmt("%1$@ 으로 보내주세요.", FeedbackMail.address))
        }
        .task {
            await feed.refresh(force: true)
            feed.markAllSeen()
        }
    }

    /// 소식 하단 입력 바 — 메시지 앱 문법(대표님 레퍼런스). 우리 서버로 보내는 게 아니라
    /// 메일 앱을 열어 사용자가 직접 보낸다(§5.2 무서버 경계 유지).
    private var feedbackBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("개발자에게 피드백 보내기", text: $feedbackText, axis: .vertical)
                .lineLimit(1...4)
                .font(.subheadline)
                .foregroundStyle(Ink.text)
                .focused($feedbackFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Ink.paper, in: Capsule())
                .overlay(Capsule().stroke(Ink.text.opacity(0.15), lineWidth: 1))
            Button {
                sendFeedback()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Ink.paper)
                    .frame(width: 34, height: 34)
                    .background(Ink.text, in: Circle())
            }
            .disabled(trimmedFeedback.isEmpty)
            .opacity(trimmedFeedback.isEmpty ? 0.35 : 1)
            .accessibilityLabel(Loc.str("보내기"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Ink.frost.ignoresSafeArea()
                .overlay(alignment: .top) { Rectangle().fill(Ink.text.opacity(0.10)).frame(height: 1) }
        }
    }

    private func sendFeedback() {
        guard !trimmedFeedback.isEmpty else { return }
        feedbackFocused = false
        if MFMailComposeViewController.canSendMail() {
            showMailComposer = true
        } else if let url = FeedbackMail.mailtoURL(trimmedFeedback) {
            // 메일 앱이 없어도 다른 메일 클라이언트가 mailto를 물 수 있다
            openURL(url) { opened in if !opened { showMailFallback = true } }
        } else {
            showMailFallback = true
        }
    }

    private func noticeCard(_ notice: Notice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // SNS 문법의 머리줄 — 쓴 사람 + 날짜
            HStack(spacing: 8) {
                ZStack {
                    Circle().stroke(Ink.accent, lineWidth: 1.4).frame(width: 22, height: 22)
                    Circle().fill(Ink.winter).frame(width: 4, height: 4).offset(y: -11)
                }
                Text("개발자")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Ink.text)
                Spacer(minLength: 0)
                Text(notice.date)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Ink.text.opacity(0.45))
            }
            Text(notice.title)
                .font(.almanac(size: 18, weight: .bold))
                .foregroundStyle(Ink.text)
            Text(notice.body)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.85))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if let seeds = notice.seeds, seeds > 0 {
                seedRow(notice: notice, seeds: seeds)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .milkGlass()
    }

    @ViewBuilder
    private func seedRow(notice: Notice, seeds: Int) -> some View {
        if Seeds.claimedNotices.contains(notice.id) {
            Label(Loc.fmt("씨앗 %lld개를 받았어요", seeds), systemImage: "checkmark.seal")
                .font(.footnote)
                .foregroundStyle(Ink.text.opacity(0.55))
        } else {
            Button {
                guard Seeds.claim(noticeID: notice.id, seeds: seeds) else { return }
                confirmHaptic()
            } label: {
                HStack(spacing: 6) {
                    SeedGlyph()
                        .fill(Ink.paper)
                        .frame(width: 8, height: 11)
                        .rotationEffect(.degrees(16))
                    Text(Loc.fmt("씨앗 %lld개 받기", seeds))
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(Ink.paper)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Ink.text, in: Capsule())
            }
        }
    }
}
