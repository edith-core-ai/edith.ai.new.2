package com.example.edith_app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.audiofx.AcousticEchoCanceler
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * Raw audio for the live voice call.
 *
 *  - Microphone: 16 kHz, 16-bit, mono PCM, sent to Dart in 40 ms pieces
 *    through the EventChannel (this class is its stream handler).
 *    The VOICE_COMMUNICATION source plus the phone's echo canceller and
 *    noise suppressor stop her hearing her own voice on the speaker.
 *  - Speaker: 24 kHz, 16-bit, mono PCM from Gemini, played as it arrives.
 *    [flush] cuts her off at once when Hilal interrupts.
 *
 * Every call is wrapped so a phone-specific audio problem comes back to
 * Dart as an error message instead of crashing the app.
 */
@Suppress("DEPRECATION")
class EdithLiveAudio(private val context: Context) : EventChannel.StreamHandler {

    companion object {
        private const val IN_RATE = 16000
        private const val OUT_RATE = 24000
        private const val FRAME_BYTES = 1280 // 40 ms of 16 kHz mono 16-bit
        private const val SLICE_BYTES = 2400 // 50 ms of 24 kHz mono 16-bit
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    @Volatile private var sink: EventChannel.EventSink? = null
    @Volatile private var running = false
    @Volatile private var generation = 0

    private var record: AudioRecord? = null
    private var track: AudioTrack? = null
    private var echo: AcousticEchoCanceler? = null
    private var noise: NoiseSuppressor? = null
    private var micThread: Thread? = null
    private var playThread: Thread? = null
    private val queue = LinkedBlockingQueue<ByteArray>()

    private var audioChanged = false
    private var savedMode = AudioManager.MODE_NORMAL
    private var savedSpeaker = false

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    /** Returns null when the call audio is running, or a reason it is not. */
    @Synchronized
    fun start(): String? {
        if (running) return null
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            return "Microphone permission is off."
        }
        try {
            savedMode = audioManager.mode
            savedSpeaker = audioManager.isSpeakerphoneOn
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            audioChanged = true
            if (!headsetConnected()) {
                audioManager.isSpeakerphoneOn = true
            }

            val minIn = AudioRecord.getMinBufferSize(
                IN_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
            )
            if (minIn <= 0) {
                stop()
                return "This phone cannot record voice at 16 kHz."
            }
            val rec = AudioRecord(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                IN_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                maxOf(minIn, FRAME_BYTES * 4)
            )
            if (rec.state != AudioRecord.STATE_INITIALIZED) {
                rec.release()
                stop()
                return "The microphone could not start. Another app may be using it."
            }
            record = rec
            attachEffects(rec.audioSessionId)

            val minOut = AudioTrack.getMinBufferSize(
                OUT_RATE, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT
            )
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            val format = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(OUT_RATE)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build()
            val trk = AudioTrack(
                attrs,
                format,
                maxOf(minOut, OUT_RATE),
                AudioTrack.MODE_STREAM,
                AudioManager.AUDIO_SESSION_ID_GENERATE
            )
            if (trk.state != AudioTrack.STATE_INITIALIZED) {
                trk.release()
                stop()
                return "The speaker could not start."
            }
            track = trk

            queue.clear()
            running = true
            trk.play()
            rec.startRecording()
            micThread = Thread({ micLoop(rec) }, "edith-mic").also { it.start() }
            playThread = Thread({ playLoop(trk) }, "edith-play").also { it.start() }
            return null
        } catch (e: Exception) {
            stop()
            return "Audio could not start: ${e.message}"
        }
    }

    private fun micLoop(rec: AudioRecord) {
        val buf = ByteArray(FRAME_BYTES)
        while (running) {
            val n = try {
                rec.read(buf, 0, buf.size)
            } catch (e: Exception) {
                -1
            }
            if (n <= 0) {
                if (!running) break
                try {
                    Thread.sleep(10)
                } catch (e: InterruptedException) {
                    break
                }
                continue
            }
            val chunk = buf.copyOf(n)
            mainHandler.post { sink?.success(chunk) }
        }
    }

    private fun playLoop(trk: AudioTrack) {
        while (running) {
            val chunk = try {
                queue.poll(100, TimeUnit.MILLISECONDS)
            } catch (e: InterruptedException) {
                null
            }
            if (chunk == null) continue
            val gen = generation
            var off = 0
            // Written in small slices so flush() can cut her off quickly.
            while (off < chunk.size && running && gen == generation) {
                val len = minOf(SLICE_BYTES, chunk.size - off)
                val w = try {
                    trk.write(chunk, off, len)
                } catch (e: Exception) {
                    -1
                }
                if (w <= 0) break
                off += w
            }
        }
    }

    /** Queues a piece of her voice (24 kHz 16-bit mono PCM). */
    fun play(pcm: ByteArray) {
        if (running) queue.offer(pcm)
    }

    /** Throws away everything she has not said yet (Hilal interrupted). */
    fun flush() {
        generation++
        queue.clear()
        val trk = track ?: return
        try {
            trk.pause()
            trk.flush()
            trk.play()
        } catch (e: Exception) {
            // The track is being released: nothing to flush.
        }
    }

    @Synchronized
    fun stop() {
        running = false
        generation++
        queue.clear()
        try {
            micThread?.join(400)
        } catch (e: Exception) {
        }
        try {
            playThread?.join(400)
        } catch (e: Exception) {
        }
        micThread = null
        playThread = null
        try {
            record?.stop()
        } catch (e: Exception) {
        }
        try {
            record?.release()
        } catch (e: Exception) {
        }
        try {
            track?.stop()
        } catch (e: Exception) {
        }
        try {
            track?.release()
        } catch (e: Exception) {
        }
        record = null
        track = null
        try {
            echo?.release()
        } catch (e: Exception) {
        }
        try {
            noise?.release()
        } catch (e: Exception) {
        }
        echo = null
        noise = null
        if (audioChanged) restoreAudio()
    }

    private fun attachEffects(session: Int) {
        try {
            if (AcousticEchoCanceler.isAvailable()) {
                echo = AcousticEchoCanceler.create(session)
                echo?.setEnabled(true)
            }
        } catch (e: Exception) {
        }
        try {
            if (NoiseSuppressor.isAvailable()) {
                noise = NoiseSuppressor.create(session)
                noise?.setEnabled(true)
            }
        } catch (e: Exception) {
        }
    }

    private fun headsetConnected(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return try {
            audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any {
                it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                    it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun restoreAudio() {
        try {
            audioManager.isSpeakerphoneOn = savedSpeaker
        } catch (e: Exception) {
        }
        try {
            audioManager.mode = savedMode
        } catch (e: Exception) {
        }
        audioChanged = false
    }
}
