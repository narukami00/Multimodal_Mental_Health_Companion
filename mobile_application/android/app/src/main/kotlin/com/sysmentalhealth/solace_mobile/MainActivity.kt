package com.sysmentalhealth.solace_mobile

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
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

    private var eventSink: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var isRecording = false
    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null

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
                    val frameMs = call.argument<Int>("frameMs") ?: 100
                    val started = startPcmRecording(sampleRate, frameMs)
                    result.success(started)
                }
                "stopRecording" -> {
                    stopPcmRecording()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STREAM_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
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

    private fun startPcmRecording(sampleRate: Int, frameMs: Int): Boolean {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            return false
        }
        if (isRecording) {
            stopPcmRecording()
        }

        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        // 16-bit mono = 2 bytes per sample. For 100ms at 16000Hz = 1600 samples = 3200 bytes
        val frameBytes = (sampleRate * 2 * frameMs) / 1000
        val minBufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        val bufferSize = maxOf(minBufferSize, frameBytes * 2)

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                sampleRate,
                channelConfig,
                audioFormat,
                bufferSize
            )
            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                audioRecord?.release()
                audioRecord = null
                return false
            }

            isRecording = true
            audioRecord?.startRecording()

            recordingThread = thread(start = true, name = "PCM-AudioRecorder") {
                val buffer = ByteArray(frameBytes)
                while (isRecording) {
                    var totalRead = 0
                    while (totalRead < frameBytes && isRecording) {
                        val read = audioRecord?.read(buffer, totalRead, frameBytes - totalRead) ?: -1
                        if (read > 0) {
                            totalRead += read
                        } else {
                            break
                        }
                    }

                    if (totalRead > 0 && isRecording) {
                        val chunk = buffer.copyOf(totalRead)
                        mainHandler.post {
                            eventSink?.success(chunk)
                        }
                    }
                }

                try {
                    audioRecord?.stop()
                    audioRecord?.release()
                } catch (_: Exception) {}
                audioRecord = null
            }

            return true
        } catch (e: Exception) {
            isRecording = false
            audioRecord?.release()
            audioRecord = null
            return false
        }
    }

    private fun stopPcmRecording() {
        isRecording = false
        recordingThread?.join(500)
        recordingThread = null
    }

    override fun onDestroy() {
        stopPcmRecording()
        super.onDestroy()
    }
}
