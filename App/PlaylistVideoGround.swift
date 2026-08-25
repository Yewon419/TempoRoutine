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
    @Query(sort: \PeriodDay.day) private var periodDays: [PeriodDay]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var phase: CyclePhase {
        CycleSnapshot(periodDays: periodDays)
            .phase(on: Calendar.current.startOfDay(for: .now)) ?? .menstrual
    }

    var body: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()   // 로드 전·에셋 결손 폴백 = 지면색
            switch phase {
            case .menstrual:
                if let url = Bundle.main.url(forResource: "playlist-winter-bg", withExtension: "png"),
                   let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                }
            case .follicular:
                PlaylistLoopVideo(name: "playlist-spring-bg", paused: reduceMotion)
                    .ignoresSafeArea()
            case .ovulation:
                PlaylistLoopVideo(name: "playlist-summer-bg", paused: reduceMotion)
                    .ignoresSafeArea()
            case .luteal:
                PlaylistLoopVideo(name: "playlist-autumn-bg", paused: reduceMotion)
                    .ignoresSafeArea()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 번들 mp4 무한 루프 — AVPlayerLooper + AVPlayerLayer(cover 크롭)
private struct PlaylistLoopVideo: UIViewRepresentable {
    let name: String
    let paused: Bool

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer {
            // layerClass 재정의라 다운캐스트가 항상 성립한다
            layer as? AVPlayerLayer ?? AVPlayerLayer()
        }
        var looper: AVPlayerLooper?
        var player: AVQueuePlayer?
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp4") else {
            return view   // 에셋 결손 = 지면색 폴백(§4.5 계약)
        }
        // 무음 재생이 사용자의 음악을 끊지 않게 — ambient + mixWithOthers
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        view.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        view.playerLayer.player = player
        view.player = player
        if !paused { player.play() }
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        if paused {
            view.player?.pause()
        } else if view.player?.rate == 0 {
            view.player?.play()
        }
    }
}
