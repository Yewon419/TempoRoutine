// 플리 지면 = 계절 배경 영상 (시안 §4.4 ⑪, 2026-08-25)
// 봄·여름·가을 = 루프 영상(별도 세션 제작: Kling 3.0 + 0.5배속·가로 팬·크로스페이드 루프,
// 무음 1080×1920 ~10.5s), **겨울 = 정지 이미지**(색 빠진 계절 — 정적이 은유에 맞다, 대표님 결정).
// 계절광·틴트 없음 — 계절별 영상이 색을 스스로 담당한다. 콜드 = 겨울(티켓 전례).
// reduce motion = 일시정지(첫 프레임 유지). 무음 + .ambient 세션 — 사용자의 음악 재생을 끊지 않는다
// (음악 은유 테마가 진짜 음악을 끊으면 안 된다).

import AVFoundation
import SwiftData
import SwiftUI
import TempoCore

struct PlaylistVideoGround: View {
    /// 지면 흐리기(2026-08-26 베타 "캘린더 탭만 배경 블러처리") — 캘린더만 >0.
    /// 격자는 숫자·밑줄·띠가 촘촘해서 영상 디테일(벚꽃·물결)이 그대로 비치면 서로 먹는다.
    /// 오늘 탭은 카드가 면을 이미 덮어 흐리기가 필요 없다 — 0으로 둔다.
    var blurRadius: CGFloat = 0

    @Query(sort: \PeriodDay.day) private var periodDays: [PeriodDay]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var phase: CyclePhase {
        CycleSnapshot(periodDays: periodDays)
            .phase(on: Calendar.current.startOfDay(for: .now)) ?? .menstrual
    }

    var body: some View {
        // ⚠ scaledToFill을 ZStack에 직접 두면 레이아웃 프레임까지 커진다(TicketGround 전례 —
        // 2026-08-25 베타 "캘린더 확대 버그"의 뿌리: 겨울 정지 이미지가 화면 폭을 밀어냈다).
        // Color.clear가 제안 크기를 정확히 차지하고 콘텐츠는 overlay로만(레이아웃 무영향).
        Color.clear
            .overlay {
                ZStack {
                    Ink.paper   // 로드 전·에셋 결손 폴백 = 지면색
                    switch phase {
                    case .menstrual:
                        if let url = ThemeMedia.shared.localURL(named: "playlist-winter-bg.png"),
                           let image = UIImage(contentsOfFile: url.path) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        }
                    case .follicular:
                        PlaylistLoopVideo(name: "playlist-spring-bg-v2", paused: reduceMotion)
                    case .ovulation:
                        PlaylistLoopVideo(name: "playlist-summer-bg-v2", paused: reduceMotion)
                    case .luteal:
                        PlaylistLoopVideo(name: "playlist-autumn-bg-v2", paused: reduceMotion)
                    }
                    // 가독 베일(2026-08-25 베타 "가독성 개선 모색") — 영상 노이즈 위 잉크 활자 가독.
                    // 흰 베일이라 탁함(어두운 스크림) 계열과 다르다. 시안 검토엔 없던 실기기 보정.
                    Color.white.opacity(0.22)
                }
                // opaque: true — 기본 블러는 가장자리를 투명으로 물려 테두리가 비친다
                .blur(radius: blurRadius, opaque: true)
            }
            .clipped()
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            // 온디맨드 다운로드 완료 시 재생성 — AVPlayer는 만들 때의 URL에 묶인다(ThemeMedia 계약)
            .id(ThemeMedia.shared.revision)
    }
}

/// 계절 영상 공유 플레이어 풀(2026-08-26 대표님 "탭 옮길 때마다 영상 초기화되는거 수정") —
/// 탭을 옮기면 TabView가 지면 뷰를 파괴·재생성하고, 플레이어가 뷰 소유라 매번 0초부터 다시
/// 시작했다. 플레이어를 뷰 밖 풀에 두고 뷰는 붙였다 뗄 뿐 — 재생 위치가 탭·화면을 건너 이어진다.
@MainActor
final class PlaylistPlayerPool {
    static let shared = PlaylistPlayerPool()

    private struct Entry {
        let player: AVQueuePlayer
        let looper: AVPlayerLooper   // 참조 유지용 — 놓으면 루프가 끊긴다
        let revision: Int
        var attached: Int
    }
    private var entries: [String: Entry] = [:]

    /// 이름의 공유 플레이어를 얻고 참조를 센다. 파일 미수신 = nil(지면색 폴백 계약 유지).
    /// ThemeMedia.revision이 갈리면(온디맨드 갱신·캐시 비우기) 낡은 파일에 묶인 플레이어를
    /// 버리고 새로 만든다 — 이름이 같아도 내용물이 다를 수 있는 유일한 경로가 revision이다.
    func acquire(_ name: String) -> AVQueuePlayer? {
        let revision = ThemeMedia.shared.revision
        if var entry = entries[name], entry.revision == revision {
            entry.attached += 1
            entries[name] = entry
            return entry.player
        }
        guard let url = ThemeMedia.shared.localURL(named: name + ".mp4") else { return nil }
        // 무음 재생이 사용자의 음악을 끊지 않게 — ambient + mixWithOthers
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        entries[name] = Entry(player: player, looper: looper, revision: revision, attached: 1)
        return player
    }

    /// 참조 반납 — 붙은 뷰가 0이면 멈춘다(테마 이탈 뒤 안 보이는 재생이 배터리를 먹지 않게).
    /// 위치는 플레이어에 남아 다음 acquire가 이어 튼다.
    func release(_ name: String) {
        guard var entry = entries[name] else { return }
        entry.attached = max(0, entry.attached - 1)
        entries[name] = entry
        if entry.attached == 0 { entry.player.pause() }
    }
}

/// mp4 무한 루프 지면 — 플레이어는 풀 소유, 뷰는 AVPlayerLayer로 붙기만 한다(cover 크롭)
private struct PlaylistLoopVideo: UIViewRepresentable {
    let name: String
    let paused: Bool

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer {
            // layerClass 재정의라 다운캐스트가 항상 성립한다
            layer as? AVPlayerLayer ?? AVPlayerLayer()
        }
        var attachedName: String?
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        if let player = PlaylistPlayerPool.shared.acquire(name) {
            view.playerLayer.player = player
            view.attachedName = name
            // 재생 배속 0.5(2026-08-25 베타 "좀 더 천천히") — 재인코딩 불요
            if !paused, player.rate == 0 { player.rate = 0.5 }
        }
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        guard let player = view.playerLayer.player else { return }
        if paused {
            player.pause()
        } else if player.rate == 0 {
            player.rate = 0.5
        }
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        if let name = view.attachedName {
            PlaylistPlayerPool.shared.release(name)
        }
    }
}
