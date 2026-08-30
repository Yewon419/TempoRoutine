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
                    // 지면 흐리기(캘린더 전용) — ⚠ SwiftUI `.blur`는 AVPlayerLayer(영상)에
                    // 안 먹는다(2026-08-30 뿌리 확인 — 겨울 정지 이미지만 흐려지고 영상 계절은
                    // 그대로라 "블러 조정 안됐는데?"가 반복됐다). UIVisualEffectView 실블러로 교체.
                    if blurRadius > 0 {
                        LiveBlur(radius: blurRadius)
                    }
                    // 가독 베일(2026-08-25 베타 "가독성 개선 모색") — 영상 노이즈 위 잉크 활자 가독.
                    // 흰 베일이라 탁함(어두운 스크림) 계열과 다르다. 시안 검토엔 없던 실기기 보정.
                    Color.white.opacity(0.22)
                }
            }
            .clipped()
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            // 온디맨드 다운로드 완료 시 재생성 — AVPlayer는 만들 때의 URL에 묶인다(ThemeMedia 계약)
            .id(ThemeMedia.shared.revision)
    }
}

/// 영상 위 실블러(2026-08-30) — UIBlurEffect를 UIViewPropertyAnimator에 걸고 진행률로
/// 세기를 잡는 표준 기법. radius/30 근사(light 스타일 최대 반경 ~30pt). 애니메이터는
/// coordinator가 쥔다 — 놓으면 효과가 풀리고, dismantle에서 stop 안 하면 누수 경고가 뜬다.
private struct LiveBlur: UIViewRepresentable {
    let radius: CGFloat

    final class Coordinator {
        var animator: UIViewPropertyAnimator?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: nil)
        view.isUserInteractionEnabled = false
        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear)
        animator.addAnimations { view.effect = UIBlurEffect(style: .light) }
        animator.pausesOnCompletion = true
        animator.fractionComplete = min(max(radius / 30, 0), 1)
        context.coordinator.animator = animator
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        context.coordinator.animator?.fractionComplete = min(max(radius / 30, 0), 1)
    }

    static func dismantleUIView(_ view: UIVisualEffectView, coordinator: Coordinator) {
        coordinator.animator?.stopAnimation(true)
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

    /// 참조 증가 없이 현재 플레이어만 조회 — 레이어 소유권 회복용(아래 계약 참조).
    func player(named name: String) -> AVQueuePlayer? {
        guard let entry = entries[name], entry.revision == ThemeMedia.shared.revision else { return nil }
        return entry.player
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
        // ⚠ **AVPlayer는 레이어 하나에만 그려진다**(2026-08-27 베타 — 빌드 509 이후 플리 지면이
        // 통째로 빈 지면색이던 뿌리). 오늘·캘린더 두 화면이 같은 공유 플레이어를 쓰는데, 나중에
        // 만들어진 레이어가 소유권을 가져가면 먼저 있던 레이어는 빈 채로 남는다. 종전 구현은
        // `view.playerLayer.player`가 nil이면 즉시 return이라 한 번 뺏긴 화면이 영영 안 돌아왔다.
        // 보이는 뷰가 갱신마다 소유권을 되찾는다 — 안 보이는 쪽은 어차피 화면 밖이다.
        guard let player = PlaylistPlayerPool.shared.player(named: name) else { return }
        if view.playerLayer.player !== player { view.playerLayer.player = player }
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
