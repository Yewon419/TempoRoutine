// 템포루틴 Android — 시그니처 사운드 (iOS SignatureSound.swift 이식). 온보딩 스플래시에서 1회.
// 건너뛰기용 fadeOut: 뚝 끊으면 파형이 잘리며 딱 소리가 나므로 짧게 줄이고 끈다. 끝까지 재생되면 부르지 않는다.

package app.temporoutine.android.onboarding

import android.content.Context
import android.media.MediaPlayer
import app.temporoutine.android.R
import kotlinx.coroutines.delay

class SignatureSound(private val context: Context) {
    private var player: MediaPlayer? = null

    fun play() {
        release()
        val p = MediaPlayer.create(context, R.raw.signature) ?: return   // 리소스 문제면 조용히 무음
        p.setOnCompletionListener { release() }
        player = p
        p.start()
    }

    suspend fun fadeOut(durationMs: Long = 300) {
        val p = player ?: return
        val steps = 6
        for (i in 1..steps) {
            val v = 1f - i.toFloat() / steps
            runCatching { p.setVolume(v, v) }
            delay(durationMs / steps)
        }
        release()
    }

    fun release() {
        player?.let { runCatching { if (it.isPlaying) it.stop() }; it.release() }
        player = null
    }
}
