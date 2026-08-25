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
                        PlaylistLoopVideo(name: "playlist-spring-bg", paused: reduceMotion)
                    case .ovulation:
                        PlaylistLoopVideo(name: "playlist-summer-bg", paused: reduceMotion)
                    case .luteal:
                        PlaylistLoopVideo(name: "playlist-autumn-bg", paused: reduceMotion)
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
        guard let url = ThemeMedia.shared.localURL(named: name + ".mp4") else {
            return view   // 미수신·결손 = 지면색 폴백(§4.5 계약 — 다운로드 완료 시 .id(revision)가 재생성)
        }
        // 무음 재생이 사용자의 음악을 끊지 않게 — ambient + mixWithOthers
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        view.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        view.playerLayer.player = player
        view.player = player
        if !paused { player.rate = 0.5 }   // 재생 배속 0.5(2026-08-25 베타 "좀 더 천천히") — 재인코딩 불요
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        if paused {
            view.player?.pause()
        } else if view.player?.rate == 0 {
            view.player?.rate = 0.5
        }
    }
}
