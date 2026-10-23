package com.sysmentalhealth.solace_mobile

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import java.io.File
import java.nio.ByteBuffer
import java.nio.FloatBuffer

/**
 * The three neural networks of the on-phone face reading, as thin adapters. ALL the maths around them (finding the face
 * in YuNet's output, aligning it, choosing frames, pooling the 1,400 numbers) is Dart, tested against the server's own
 * code. Here: decode a picture, run YuNet, run EfficientNet-B0, run MediaPipe's face landmarker. Nothing is saved, and
 * no picture leaves this class except as the numbers the networks produce.
 */
class FaceModels(private val context: Context) {
    private companion object {
        const val TAG = "SolaceFace"
        const val YUNET_SIZE = 640
        const val B0_SIZE = 224
        val YUNET_OUTPUTS = listOf(
            "cls_8", "cls_16", "cls_32", "obj_8", "obj_16", "obj_32",
            "bbox_8", "bbox_16", "bbox_32", "kps_8", "kps_16", "kps_32",
        )
    }

    private var env: OrtEnvironment? = null
    private var yunet: OrtSession? = null
    private var b0: OrtSession? = null
    private var landmarker: FaceLandmarker? = null

    /** Loads the three models from [dir]. False (and nothing left half-loaded) when any of them cannot be opened. */
    @Synchronized
    fun load(dir: String): Boolean {
        close()
        return try {
            val environment = OrtEnvironment.getEnvironment()
            val options = OrtSession.SessionOptions().apply { setIntraOpNumThreads(2) }
            yunet = environment.createSession(File(dir, "face_detection_yunet_2023mar.onnx").absolutePath, options)
            b0 = environment.createSession(File(dir, "b0_fp32.onnx").absolutePath, options)
            val task = File(dir, "face_landmarker.task").readBytes()
            val buffer = ByteBuffer.allocateDirect(task.size).apply { put(task); rewind() }
            landmarker = FaceLandmarker.createFromOptions(
                context,
                FaceLandmarker.FaceLandmarkerOptions.builder()
                    .setBaseOptions(BaseOptions.builder().setModelAssetBuffer(buffer).build())
                    .setRunningMode(RunningMode.IMAGE)
                    .setNumFaces(1)
                    .setOutputFaceBlendshapes(true)
                    .setOutputFacialTransformationMatrixes(true)
                    .build(),
            )
            env = environment
            true
        } catch (t: Throwable) {
            Log.w(TAG, "could not load the face models: ${t.javaClass.simpleName}: ${t.message}", t)
            close()
            false
        }
    }

    @Synchronized
    fun isLoaded(): Boolean = yunet != null && b0 != null && landmarker != null

    @Synchronized
    fun close() {
        try { yunet?.close() } catch (_: Throwable) {}
        try { b0?.close() } catch (_: Throwable) {}
        try { landmarker?.close() } catch (_: Throwable) {}
        yunet = null; b0 = null; landmarker = null; env = null
    }

    /** A JPEG to raw BGR bytes (width * height * 3). */
    fun decode(jpeg: ByteArray): Map<String, Any>? {
        val bmp = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size) ?: return null
        val w = bmp.width
        val h = bmp.height
        val px = IntArray(w * h)
        bmp.getPixels(px, 0, w, 0, 0, w, h)
        bmp.recycle()
        val bgr = ByteArray(w * h * 3)
        for (i in px.indices) {
            val p = px[i]
            bgr[i * 3] = (p and 0xFF).toByte()
            bgr[i * 3 + 1] = ((p shr 8) and 0xFF).toByte()
            bgr[i * 3 + 2] = ((p shr 16) and 0xFF).toByte()
        }
        return mapOf("w" to w, "h" to h, "bgr" to bgr)
    }

    /** YuNet on a zero-padded 640x640 BGR frame: its twelve output groups by name, each flattened. */
    @Synchronized
    fun runYuNet(padded: ByteArray): Map<String, FloatArray>? {
        val session = yunet ?: return null
        val environment = env ?: return null
        require(padded.size == YUNET_SIZE * YUNET_SIZE * 3)
        val plane = YUNET_SIZE * YUNET_SIZE
        val floats = FloatArray(3 * plane)
        for (i in 0 until plane) {
            floats[i] = (padded[i * 3].toInt() and 0xFF).toFloat()                 // B
            floats[plane + i] = (padded[i * 3 + 1].toInt() and 0xFF).toFloat()     // G
            floats[2 * plane + i] = (padded[i * 3 + 2].toInt() and 0xFF).toFloat() // R
        }
        OnnxTensor.createTensor(environment, FloatBuffer.wrap(floats), longArrayOf(1, 3, YUNET_SIZE.toLong(), YUNET_SIZE.toLong())).use { input ->
            session.run(mapOf(session.inputNames.first() to input)).use { out ->
                val result = HashMap<String, FloatArray>()
                for (name in YUNET_OUTPUTS) {
                    val tensor = out.get(name).get() as OnnxTensor
                    val fb = tensor.floatBuffer
                    val arr = FloatArray(fb.remaining())
                    fb.get(arr)
                    result[name] = arr
                }
                return result
            }
        }
    }

    /** EfficientNet-B0 on one aligned 224x224 crop (3x224x224 floats): 8 scores then the 1,280-number embedding. */
    @Synchronized
    fun runB0(input: FloatArray): FloatArray? {
        val session = b0 ?: return null
        val environment = env ?: return null
        require(input.size == 3 * B0_SIZE * B0_SIZE)
        OnnxTensor.createTensor(environment, FloatBuffer.wrap(input), longArrayOf(1, 3, B0_SIZE.toLong(), B0_SIZE.toLong())).use { x ->
            session.run(mapOf("x" to x)).use { out ->
                val logits = (out.get("logits").get() as OnnxTensor).floatBuffer
                val emb = (out.get("emb").get() as OnnxTensor).floatBuffer
                val result = FloatArray(logits.remaining() + emb.remaining())
                val l = logits.remaining()
                logits.get(result, 0, l)
                emb.get(result, l, emb.remaining())
                return result
            }
        }
    }

    /**
     * MediaPipe's face landmarker on an RGB crop: 1 (a face was found) + 52 expression values (in the order of their
     * index) + the 16 numbers of the face transformation matrix as MediaPipe hands them over. Null when no face.
     */
    @Synchronized
    fun runLandmarker(rgb: ByteArray, w: Int, h: Int): FloatArray? {
        val detector = landmarker ?: return null
        val pixels = IntArray(w * h)
        for (i in pixels.indices) {
            val r = rgb[i * 3].toInt() and 0xFF
            val g = rgb[i * 3 + 1].toInt() and 0xFF
            val b = rgb[i * 3 + 2].toInt() and 0xFF
            pixels[i] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
        }
        val bitmap = Bitmap.createBitmap(pixels, w, h, Bitmap.Config.ARGB_8888)
        val result = try {
            detector.detect(BitmapImageBuilder(bitmap).build())
        } finally {
            bitmap.recycle()
        }
        val blend = result.faceBlendshapes()
        if (!blend.isPresent || blend.get().isEmpty()) return null
        val out = FloatArray(1 + 52 + 16)
        out[0] = 1f
        for (c in blend.get()[0]) {
            if (c.index() in 0 until 52) out[1 + c.index()] = c.score()
        }
        val matrices = result.facialTransformationMatrixes()
        if (matrices.isPresent && matrices.get().isNotEmpty()) {
            val m = matrices.get()[0]
            for (i in 0 until minOf(16, m.size)) out[53 + i] = m[i]
        }
        return out
    }
}
