package com.sysmentalhealth.solace_mobile

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AudioEffect
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val CONTROL_CHANNEL = "com.sysmentalhealth.solace_mobile/audio_control"
    private val STREAM_CHANNEL = "com.sysmentalhealth.solace_mobile/audio_stream"
    private val PERMISSION_REQUEST_CODE = 1002

    private companion object {
        const val TAG = "SolaceAudio"

        // 20 ms is the resolution every VAD threshold is expressed in.
        const val DEFAULT_FRAME_MS = 20
    }

    private var eventSink: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioManager by lazy {
        getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    @Volatile
    private var isRecording = false
    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null
    private var aec: AcousticEchoCanceler? = null
    private var ns: NoiseSuppressor? = null
    private var aecActive = false

    private var lastSampleRate = 16000
    private var lastFrameMs = DEFAULT_FRAME_MS
    private var resumeAfterPause = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> {
                    val granted = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                    result.success(granted)
                }
                "requestPermission" -> {
                    val granted = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                    if (granted) {
                        result.success(true)
                    } else {
                        pendingPermissionResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.RECORD_AUDIO),
                            PERMISSION_REQUEST_CODE
                        )
                    }
                }
                "startRecording" -> {
                    val sampleRate = call.argument<Int>("sampleRate") ?: 16000
                    val frameMs = call.argument<Int>("frameMs") ?: DEFAULT_FRAME_MS
                    val started = startPcmRecording(sampleRate, frameMs)
                    result.success(started)
                }
                "stopRecording" -> {
                    stopPcmRecording()
                    result.success(true)
                }
                "captureInfo" -> result.success(captureInfo())
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STREAM_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    // Keep the sink: Dart restarts capture on resume and would
                    // otherwise have to re-listen, which used to kill capture
                    // permanently (spec §3.3).
                    eventSink = null
                    stopPcmRecording()
                }
            }
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    override fun onPause() {
        super.onPause()
        resumeAfterPause = isRecording
        if (isRecording) stopPcmRecording()
    }

    override fun onResume() {
        super.onResume()
        if (resumeAfterPause) {
            resumeAfterPause = false
            startPcmRecording(lastSampleRate, lastFrameMs)
        }
    }

    private fun startPcmRecording(sampleRate: Int, frameMs: Int): Boolean {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            return false
        }
        if (isRecording) {
            stopPcmRecording()
        }
        lastSampleRate = sampleRate
        lastFrameMs = frameMs

        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        // 16-bit mono = 2 bytes per sample. 20 ms at 16 kHz = 320 samples = 640 bytes.
        val frameBytes = (sampleRate * 2 * frameMs) / 1000
        val minBufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        val bufferSize = maxOf(minBufferSize, frameBytes * 4)

        try {
            // Keep normal media audio mode so all audio playback routes to the
            // main loudspeaker with full-frequency fidelity, not through the in-call earpiece.
            audioManager.mode = AudioManager.MODE_NORMAL
            audioManager.isSpeakerphoneOn = true

            var record = try {
                AudioRecord(
                    MediaRecorder.AudioSource.VOICE_RECOGNITION,
                    sampleRate,
                    channelConfig,
                    audioFormat,
                    bufferSize
                )
            } catch (e: Exception) {
                null
            }
            if (record == null || record.state != AudioRecord.STATE_INITIALIZED) {
                record?.release()
                record = AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    sampleRate,
                    channelConfig,
                    audioFormat,
                    bufferSize
                )
            }
            audioRecord = record
            if (record == null || record.state != AudioRecord.STATE_INITIALIZED) {
                record?.release()
                audioRecord = null
                restoreAudioMode()
                return false
            }

            isRecording = true
            attachEffects(record.audioSessionId)
            logCaptureConfiguration(record)
            record.startRecording()

            recordingThread = thread(start = true, name = "PCM-AudioRecorder") {
                val readBuffer = ByteArray(frameBytes)
                val accumulator = ByteArray(frameBytes * 4)
                val samplesPerFrame = frameBytes / 2
                var filled = 0
                var seq = 0
                while (isRecording) {
                    val read = try {
                        record.read(readBuffer, 0, readBuffer.size)
                    } catch (e: IllegalStateException) {
                        Log.w(TAG, "read failed: $e")
                        -1
                    }
                    if (read < 0) break
                    if (read == 0) continue

                    // Emit only complete frames: a short frame would make every
                    // millisecond count in Dart device-dependent.
                    var consumed = 0
                    while (consumed < read) {
                        val take = minOf(frameBytes - filled, read - consumed)
                        System.arraycopy(readBuffer, consumed, accumulator, filled, take)
                        filled += take
                        consumed += take
                        if (filled == frameBytes) {
                            val chunk = accumulator.copyOf(frameBytes)
                            val frameSeq = seq
                            val sampleOffset = frameSeq * samplesPerFrame
                            mainHandler.post {
                                eventSink?.success(
                                    mapOf(
                                        "seq" to frameSeq,
                                        "samples" to sampleOffset,
                                        "pcm" to chunk
                                    )
                                )
                            }
                            seq++
                            filled = 0
                        }
                    }
                }

                try {
                    record.stop()
                } catch (_: Exception) {}
                releaseEffects()
                try {
                    record.release()
                } catch (_: Exception) {}
                audioRecord = null
                restoreAudioMode()
            }

            return true
        } catch (e: Exception) {
            Log.e(TAG, "startRecording failed", e)
            isRecording = false
            audioRecord?.release()
            audioRecord = null
            releaseEffects()
            restoreAudioMode()
            return false
        }
    }

    private fun stopPcmRecording() {
        isRecording = false
        recordingThread?.join(500)
        recordingThread = null
    }

    /**
     * Query, do not blindly enable: the platform may already have inserted an
     * AEC for VOICE_COMMUNICATION, and a second one double-processes the signal
     * (pumping, hollow near-end).
     */
    private fun attachEffects(sessionId: Int) {
        aecActive = false
        if (AcousticEchoCanceler.isAvailable()) {
            try {
                val effect = AcousticEchoCanceler.create(sessionId)
                if (effect != null) {
                    aec = effect
                    if (!effect.enabled) effect.enabled = true
                    aecActive = effect.enabled
                }
            } catch (e: Exception) {
                Log.w(TAG, "AcousticEchoCanceler unavailable: $e")
            }
        }
        if (NoiseSuppressor.isAvailable()) {
            try {
                val effect = NoiseSuppressor.create(sessionId)
                if (effect != null) {
                    ns = effect
                    if (!effect.enabled) effect.enabled = true
                }
            } catch (e: Exception) {
                Log.w(TAG, "NoiseSuppressor unavailable: $e")
            }
        }
        // ponytail: the effect handles are held until stop, not released right
        // after create(). Releasing an effect we created tears it down on most
        // devices, which silently disables the very thing we just enabled.
    }

    private fun releaseEffects() {
        try {
            aec?.release()
        } catch (_: Exception) {}
        aec = null
        try {
            ns?.release()
        } catch (_: Exception) {}
        ns = null
        aecActive = false
    }

    /**
     * Ground truth for "is AEC actually engaged on this device?". getEffects()
     * includes platform-inserted effects; getClientFormat() may differ from the
     * device format because the platform resamples. Shipped in release builds:
     * without this line nobody can tell which echo regime the app is in.
     */
    private fun logCaptureConfiguration(record: AudioRecord) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        try {
            val config = audioManager.activeRecordingConfigurations
                .firstOrNull { it.clientAudioSessionId == record.audioSessionId }
                ?: audioManager.activeRecordingConfigurations.firstOrNull()
            val hasAec = config?.effects?.any { it.type == AudioEffect.EFFECT_TYPE_AEC } ?: false
            val hasNs = config?.effects?.any { it.type == AudioEffect.EFFECT_TYPE_NS } ?: false
            Log.i(
                TAG,
                "capture session=${record.audioSessionId} aec=$aecActive effectsAec=$hasAec " +
                    "effectsNs=$hasNs clientRate=${config?.clientFormat?.sampleRate} " +
                    "deviceRate=${config?.format?.sampleRate}"
            )
        } catch (e: Exception) {
            Log.w(TAG, "capture configuration probe failed: $e")
        }
    }

    private fun captureInfo(): Map<String, Any?> = mapOf(
        "aec_active" to aecActive,
        "aec_source" to if (aecActive) "platform" else "software-fallback",
        "sample_rate" to lastSampleRate,
        "frame_ms" to lastFrameMs
    )

    private fun restoreAudioMode() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                audioManager.clearCommunicationDevice()
            }
            audioManager.isSpeakerphoneOn = false
            audioManager.mode = AudioManager.MODE_NORMAL
        } catch (e: Exception) {
            Log.w(TAG, "could not restore audio mode: $e")
        }
    }

    override fun onDestroy() {
        stopPcmRecording()
        releaseEffects()
        super.onDestroy()
    }
}
