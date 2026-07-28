// 시그니처 사운드 재생 — 온보딩 스플래시 1회.
//
// MASTER §4 사운드 원칙은 「옵트인 + 무음모드 존중」이다. 온보딩 스플래시는 설정 화면보다
// 먼저 뜨므로 사전 옵트인을 받을 수단이 없다. 대신 다음을 지킨다(2026-07-28 사용자 승인):
//   - AVAudioSession .ambient  → 벨소리 스위치가 꺼져 있으면 소리가 나지 않고,
//                                음악을 듣는 중이어도 그 재생을 끊지 않는다(ambient의 기본 동작)
//   - 온보딩 1회뿐, 스플래시는 탭으로 즉시 건너뛴다
//
// ⚠ `.mixWithOthers` 옵션을 .ambient에 붙이지 말 것 — playback/playAndRecord/multiRoute
//   전용이라 setCategory가 던지고, 아래 catch에 먹혀 소리가 통째로 안 난다. ambient는
//   옵션 없이도 이미 믹스된다.
// 실패는 조용히 넘긴다. 소리는 부가 요소이고 온보딩 진행을 막아서는 안 된다.

import AVFoundation
import Foundation

@MainActor
final class SignatureSound {
    static let shared = SignatureSound()

    private var player: AVAudioPlayer?

    private init() {}

    func play() {
        guard let url = Bundle.main.url(forResource: "signature", withExtension: "mp3") else {
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true, options: [])
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            player = nil
        }
    }

    /// 건너뛰기용. 뚝 끊으면 파형이 잘리며 딱 소리가 나므로 짧게 줄이고 끈다.
    /// 끝까지 재생되는 경우엔 호출하지 않는다 — 꼬리를 자를 이유가 없다.
    func fadeOut(duration: TimeInterval = 0.3) {
        guard let p = player else { return }
        p.setVolume(0, fadeDuration: duration)
        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            self.player?.stop()
            self.player = nil
        }
    }
}
