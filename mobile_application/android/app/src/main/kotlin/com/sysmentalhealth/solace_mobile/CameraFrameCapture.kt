package com.sysmentalhealth.solace_mobile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.SystemClock
import android.util.Log
import android.util.Size
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Front-camera frames for the optional emotion module: about five UPRIGHT JPEGs per second.
 *
 * Upright matters: the server only recognises a face in a frame whose face is the right way up, and the
 * sensor delivers frames rotated (the rotation is reported with each frame, never baked in), so every frame
 * is rotated here before it is sent. Frames live only in memory, are handed to [onFrame] and dropped; nothing
 * is written to storage. The camera is closed by [stop] (and by the activity when it pauses).
 */
class CameraFrameCapture(
    private val owner: LifecycleOwner,
    private val context: android.content.Context,
    private val onFrame: (ByteArray) -> Unit,
) {
    private companion object {
        const val TAG = "SolaceCamera"
        const val MIN_GAP_MS = 200L // ~5 frames per second
        const val SOURCE_W = 640
        const val SOURCE_H = 480
        const val JPEG_QUALITY = 70
    }

    private var provider: ProcessCameraProvider? = null
    private var analysis: ImageAnalysis? = null
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private var lastFrameAt = 0L

    @Volatile
    var running = false
        private set

    /** Opens the front camera. [done] gets true once frames are flowing, false when it could not be opened. */
    fun start(done: (Boolean) -> Unit) {
        if (running) {
            done(true)
            return
        }
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            try {
                val cameraProvider = future.get()
                val selector = ResolutionSelector.Builder()
                    .setResolutionStrategy(
                        ResolutionStrategy(
                            Size(SOURCE_W, SOURCE_H),
                            ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER,
                        ),
                    )
                    .build()
                val imageAnalysis = ImageAnalysis.Builder()
                    .setResolutionSelector(selector)
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                imageAnalysis.setAnalyzer(executor) { image -> analyze(image) }
                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(owner, CameraSelector.DEFAULT_FRONT_CAMERA, imageAnalysis)
                provider = cameraProvider
                analysis = imageAnalysis
                running = true
                done(true)
            } catch (e: Exception) {
                Log.w(TAG, "camera could not be opened: $e")
                running = false
                done(false)
            }
        }, ContextCompat.getMainExecutor(context))
    }

    fun stop() {
        running = false
        try {
            analysis?.clearAnalyzer()
            provider?.unbindAll()
        } catch (e: Exception) {
            Log.w(TAG, "stopping the camera: $e")
        }
        analysis = null
    }

    fun release() {
        stop()
        executor.shutdown()
    }

    private fun analyze(image: ImageProxy) {
        try {
            val now = SystemClock.elapsedRealtime()
            if (!running || now - lastFrameAt < MIN_GAP_MS) return
            lastFrameAt = now
            val jpeg = toUprightJpeg(image) ?: return
            onFrame(jpeg)
        } catch (e: Exception) {
            Log.w(TAG, "frame dropped: $e")
        } finally {
            image.close()
        }
    }

    private fun toUprightJpeg(image: ImageProxy): ByteArray? {
        val width = image.width
        val height = image.height
        val nv21 = yuv420ToNv21(image)
        val raw = ByteArrayOutputStream()
        YuvImage(nv21, ImageFormat.NV21, width, height, null)
            .compressToJpeg(Rect(0, 0, width, height), 90, raw)
        val rotation = image.imageInfo.rotationDegrees
        val bytes = raw.toByteArray()
        if (rotation == 0) return bytes
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        val matrix = Matrix().apply { postRotate(rotation.toFloat()) }
        val upright = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        val out = ByteArrayOutputStream()
        upright.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)
        bitmap.recycle()
        upright.recycle()
        return out.toByteArray()
    }

    /** YUV_420_888 (any row/pixel stride) -> NV21, the layout YuvImage understands. */
    private fun yuv420ToNv21(image: ImageProxy): ByteArray {
        val w = image.width
        val h = image.height
        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]
        val out = ByteArray(w * h * 3 / 2)
        val yBuf = yPlane.buffer
        for (row in 0 until h) {
            if (yPlane.pixelStride == 1) {
                yBuf.position(row * yPlane.rowStride)
                yBuf.get(out, row * w, w)
            } else {
                for (col in 0 until w) out[row * w + col] = yBuf.get(row * yPlane.rowStride + col * yPlane.pixelStride)
            }
        }
        var pos = w * h
        val uBuf = uPlane.buffer
        val vBuf = vPlane.buffer
        for (row in 0 until h / 2) {
            for (col in 0 until w / 2) {
                out[pos++] = vBuf.get(row * vPlane.rowStride + col * vPlane.pixelStride)
                out[pos++] = uBuf.get(row * uPlane.rowStride + col * uPlane.pixelStride)
            }
        }
        return out
    }
}
