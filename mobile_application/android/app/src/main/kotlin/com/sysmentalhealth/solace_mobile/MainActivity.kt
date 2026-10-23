package com.sysmentalhealth.solace_mobile

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AudioEffect
import android.media.audiofx.NoiseSuppressor
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
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
    private val PERMISSIONS_CHANNEL = "com.sysmentalhealth.solace_mobile/app_permissions"
    private val USAGE_CHANNEL = "com.sysmentalhealth.solace_mobile/usage_collector"
    private val CAMERA_CONTROL_CHANNEL = "com.sysmentalhealth.solace_mobile/camera_control"
    private val CAMERA_STREAM_CHANNEL = "com.sysmentalhealth.solace_mobile/camera_stream"
    private val FACE_CHANNEL = "com.sysmentalhealth.solace_mobile/face_models"
    private val NOT_IMPLEMENTED = Any()
    private val PERMISSION_REQUEST_CODE = 1002
    private val CAMERA_PERMISSION_REQUEST_CODE = 1003

    private companion object {
        const val TAG = "SolaceAudio"

        // 20 ms is the resolution every VAD threshold is expressed in.
        const val DEFAULT_FRAME_MS = 20
    }

    private var eventSink: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var cameraSink: EventChannel.EventSink? = null
    private var pendingCameraResult: MethodChannel.Result? = null
    private val camera: CameraFrameCapture by lazy {
        CameraFrameCapture(this, this, flutterEngine?.renderer) { jpeg -> mainHandler.post { cameraSink?.success(jpeg) } }
    }
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
                "outputRoute" -> result.success(outputRoute())
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

        // Optional camera frames for the emotion module. The camera opens only when Dart asks (after the person
        // turned it on), only after the CAMERA permission is granted, and closes when the app is paused.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAMERA_CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(
                    ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED,
                )
                "start" -> {
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                        camera.start { ok -> mainHandler.post { result.success(ok) } }
                    } else {
                        pendingCameraResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.CAMERA),
                            CAMERA_PERMISSION_REQUEST_CODE,
                        )
                    }
                }
                "stop" -> {
                    camera.stop()
                    result.success(true)
                }
                // Where the smooth self view is (a Flutter texture), or null when there is none.
                "previewInfo" -> result.success(camera.previewInfo())
                else -> result.notImplemented()
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CAMERA_STREAM_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    cameraSink = events
                }

                override fun onCancel(arguments: Any?) {
                    cameraSink = null
                }
            }
        )

        // Backs the permissions page. Android owns these permissions, so the app
        // can only report their real state and send the user to the system
        // screen; it cannot flip them itself.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSIONS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "microphoneGranted" -> {
                    val granted = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                    result.success(granted)
                }
                "cameraGranted" -> {
                    val granted = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.CAMERA
                    ) == PackageManager.PERMISSION_GRANTED
                    result.success(granted)
                }
                "openAppSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.fromParts("package", packageName, null)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.w(TAG, "could not open app settings: $e")
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Device usage for the daily behavior row. Reads only the few event types
        // UsageCollector maps; the logic that reduces them lives in Dart.
        val usage = UsageCollector(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, USAGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasAccess" -> result.success(usage.hasAccess())
                "openAccessSettings" -> {
                    try {
                        startActivity(usage.accessSettingsIntent())
                        result.success(true)
                    } catch (e: Exception) {
                        Log.w(TAG, "could not open usage access settings: $e")
                        result.success(false)
                    }
                }
                "events" -> {
                    val from = call.argument<Number>("from")?.toLong()
                    val to = call.argument<Number>("to")?.toLong()
                    if (from == null || to == null) {
                        result.error("bad_args", "from and to are required", null)
                    } else {
                        // Off the main thread: a day of events can be thousands.
                        thread(start = true, name = "UsageEvents") {
                            val events = try {
                                usage.events(from, to)
                            } catch (e: Exception) {
                                Log.w(TAG, "usage events failed: $e")
                                emptyList()
                            }
                            mainHandler.post { result.success(events) }
                        }
                    }
                }
                "describeApps" -> {
                    val packages = call.argument<List<String>>("packages") ?: emptyList()
                    result.success(usage.describeApps(packages))
                }
                else -> result.notImplemented()
            }
        }

        // The three networks of the on-phone face reading. Everything around them is Dart; see FaceModels.kt.
        // MediaPipe needs Android 7.0 (API 24); on older phones the face reading is simply not available.
        val faceModels = if (Build.VERSION.SDK_INT >= 24) FaceModels(applicationContext) else null
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FACE_CHANNEL).setMethodCallHandler { call, result ->
            if (faceModels == null) {
                result.success(if (call.method == "load" || call.method == "isLoaded") false else null)
                return@setMethodCallHandler
            }
            // Off the main thread: a network run takes tens of milliseconds, loading takes a second or two.
            thread(start = true, name = "FaceModels") {
                val outcome: Any? = try {
                    when (call.method) {
                        "load" -> faceModels.load(call.argument<String>("dir") ?: "")
                        "isLoaded" -> faceModels.isLoaded()
                        "close" -> { faceModels.close(); true }
                        "decode" -> call.argument<ByteArray>("jpeg")?.let { faceModels.decode(it) }
                        "yunet" -> call.argument<ByteArray>("bgr")?.let { faceModels.runYuNet(it) }
                        "b0" -> call.argument<FloatArray>("input")?.let { faceModels.runB0(it) }
                        "landmarks" -> {
                            val rgb = call.argument<ByteArray>("rgb")
                            val w = call.argument<Int>("w")
                            val h = call.argument<Int>("h")
                            if (rgb != null && w != null && h != null) faceModels.runLandmarker(rgb, w, h) else null
                        }
                        else -> NOT_IMPLEMENTED
                    }
                } catch (t: Throwable) {
                    Log.w(TAG, "face call ${call.method} failed: ${t.javaClass.simpleName}")
                    null
                }
                mainHandler.post {
                    if (outcome === NOT_IMPLEMENTED) result.notImplemented() else result.success(outcome)
                }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            val pending = pendingCameraResult
            pendingCameraResult = null
            if (pending != null) {
                if (granted) camera.start { ok -> mainHandler.post { pending.success(ok) } } else pending.success(false)
            }
        }
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
        camera.stop() // the camera never keeps running in the background
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
            // Loudspeaker unless something is worn on the head: forcing the speaker
            // would override headphones, and the app treats "headset connected" as
            // "no echo", so the two must agree.
            audioManager.isSpeakerphoneOn = outputRoute()["headset"] != true

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

    /**
     * Is the audio going to something worn on the head rather than the phone's
     * loudspeaker? Only then can the microphone stay open while the assistant
     * talks: through a loudspeaker the phone hears its own voice a few
     * centimetres away and cannot tell it from the person.
     */
    private fun outputRoute(): Map<String, Any?> {
        val headsetTypes = mutableSetOf(
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_USB_HEADSET,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            headsetTypes.add(AudioDeviceInfo.TYPE_HEARING_AID)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            headsetTypes.add(AudioDeviceInfo.TYPE_BLE_HEADSET)
        }
        val headset = try {
            audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { it.type in headsetTypes }
        } catch (e: Exception) {
            Log.w(TAG, "output route probe failed: $e")
            false
        }
        return mapOf("headset" to headset)
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
        camera.release()
        super.onDestroy()
    }
}
