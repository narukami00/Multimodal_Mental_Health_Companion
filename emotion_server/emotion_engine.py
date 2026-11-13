"""Live emotion engine (demo model v0): raw waveform / text / webcam frames -> calibrated 7-class, valence and arousal estimates.

It reproduces the OFFLINE training features exactly (same code paths as embed_full.py and cache_faces_v2.py) so that the heads
trained on the cached features can be applied to a live user:
  audio : WavLM-large layers {12,16,19} + Whisper-small encoder layers {7,9,12}, mean+std over time  -> 10,752-d
  text  : EmbeddingGemma-2 text tower layers {16,18,21}, mean+std over tokens                          ->  3,072-d
  face  : per frame YuNet + alignment + EfficientNet-B0 logits/embedding + MediaPipe blendshapes/pose; pooled over the usable
          frames of a window: B0 logits mean+std, blendshapes mean+std, B0 embedding mean                ->  1,400-d
Per-corpus z-scoring was the training normalisation; live, a new user is normalised with REFERENCE statistics of one training
corpus (default 'mosei', the in-the-wild one), optionally with the mean replaced by the user's own calibration mean (Normaliser).
Heads: the 5 production nets (train_prod.py), logits averaged, divided by the per-pattern temperature (temps.json), softmax.
Classes: neutral, happy, sad, angry, fear, disgust, surprise | valence: negative, neutral, positive | arousal: low, mid, high.
"""
import json
import os

import cv2
import numpy as np
import torch

from runtime_config import MODELS, SERVICE
from face_runtime import B0, LANDMARKER, SIZE, TEMPLATE, YUNET, euler, iou
from heads import NetVA
CLASSES7 = ["neutral", "happy", "sad", "angry", "fear", "disgust", "surprise"]
VAL = ["negative", "neutral", "positive"]
ARO = ["low", "mid", "high"]
WAVLM_L, WHISPER_L, TEXT_L = [12, 16, 19], [7, 9, 12], [16, 18, 21]
MIN_USABLE = 3
dev = "cuda" if torch.cuda.is_available() else "cpu"
torch.set_num_threads(int(os.environ.get("EMOTION_THREADS", "2")))  # many tiny ops: more threads only spin (see demo_server.py)
cv2.setNumThreads(int(os.environ.get("EMOTION_THREADS", "2")))


# ------------------------------------------------------------------------------------------------------------------ audio / VAD
class Acc:
    """running per-layer mean / std over frames (same maths as embed_full.Acc)."""
    def __init__(self):
        self.s = self.q = None
        self.n = 0

    def add(self, hs):  # hs: list of [T, D] tensors
        s = torch.stack([h.sum(0) for h in hs])
        q = torch.stack([(h * h).sum(0) for h in hs])
        self.s = s if self.s is None else self.s + s
        self.q = q if self.q is None else self.q + q
        self.n += hs[0].shape[0]

    def flat(self):  # layer-major, [mean(D), std(D)] per layer: the order of the cached features
        mean = self.s / self.n
        std = (self.q / self.n - mean * mean).clamp_min(0).sqrt()
        return torch.cat([mean, std], 1).float().cpu().numpy().reshape(-1)


class AudioEncoders:
    def __init__(self, load_asr=True):
        """load_asr=False keeps only the Whisper ENCODER (the features); the speech decoder (~0.4 GB) is skipped when the caller
        already has a transcript (the companion server's own STT)."""
        from transformers import AutoFeatureExtractor, AutoModel, WhisperFeatureExtractor, WhisperForConditionalGeneration, WhisperModel, WhisperTokenizer
        self.wfe = AutoFeatureExtractor.from_pretrained(str(MODELS / "wavlm-large"))
        self.wavlm = AutoModel.from_pretrained(str(MODELS / "wavlm-large"), dtype=torch.float32).to(dev).eval()
        self.sfe = WhisperFeatureExtractor.from_pretrained(str(MODELS / "whisper-small"))
        if load_asr:
            self.tok = WhisperTokenizer.from_pretrained(str(MODELS / "whisper-small"))
            self.asr = WhisperForConditionalGeneration.from_pretrained(str(MODELS / "whisper-small"), dtype=torch.float32).to(dev).eval()
            self.whisper = self.asr.model.encoder  # same weights as the encoder the heads were trained on; shared, not duplicated
        else:
            self.asr = None
            self.whisper = WhisperModel.from_pretrained(str(MODELS / "whisper-small"), dtype=torch.float32).encoder.to(dev).eval()

    @torch.no_grad()
    def transcribe(self, wav, language="en"):
        """speech-to-text with the same Whisper-small (greedy, <= 30 s)."""
        x = self.sfe(np.asarray(wav, np.float32)[:16000 * 30], sampling_rate=16000, return_tensors="pt").input_features.to(dev)
        ids = self.asr.generate(x, max_new_tokens=160, language=language, task="transcribe")
        return self.tok.batch_decode(ids, skip_special_tokens=True)[0].strip()

    @torch.no_grad()
    def features(self, wav):
        """wav: float32 mono 16 kHz, >= 0.1 s, at most 30 s are used. Returns the 10,752-d RAW audio vector."""
        wav = np.asarray(wav, np.float32)[:16000 * 30]
        C = 160000
        chunks = [wav[i:i + C] for i in range(0, len(wav), C)]
        if len(chunks) > 1 and len(chunks[-1]) < 8000:  # tiny tail merged into the previous chunk (as in embed_full)
            chunks[-2] = np.concatenate([chunks[-2], chunks[-1]])
            chunks.pop()
        a = Acc()
        for c in chunks:
            x = self.wfe(c, sampling_rate=16000, return_tensors="pt").input_values.to(dev)
            hs = self.wavlm(x, output_hidden_states=True).hidden_states
            a.add([hs[l][0].float() for l in WAVLM_L])
        w = a.flat()
        x = self.sfe(wav, sampling_rate=16000, return_tensors="pt").input_features.to(dev)
        hs = self.whisper(x, output_hidden_states=True).hidden_states
        n = max(1, min(1500, int(len(wav) / 16000 * 50)))
        b = Acc()
        b.add([hs[l][0, :n].float() for l in WHISPER_L])
        return np.concatenate([w, b.flat()])


class TextEncoder:
    def __init__(self):
        from sentence_transformers import SentenceTransformer
        self.m = SentenceTransformer(str(MODELS / "embeddinggemma-2"), model_kwargs={"torch_dtype": torch.float32}, device=dev)
        self.store = {}
        for i, layer in enumerate(self.m[0].auto_model.language_model.layers):
            if i in TEXT_L:
                layer.register_forward_hook(self._hook(i))

    def _hook(self, i):
        def h(mod, inp, out):
            o = out[0] if isinstance(out, tuple) else out
            self.store[i] = o.detach().float().reshape(-1, o.shape[-1])
        return h

    @torch.no_grad()
    def features(self, text):
        self.store.clear()
        self.m.encode("task: classification | query: " + (text.strip() or "."), normalize_embeddings=True)
        a = Acc()
        a.add([self.store[i] for i in TEXT_L])
        return a.flat()  # 3,072-d RAW


class SileroVAD:
    """speech probability per 512-sample (32 ms) chunk, stateful (TorchScript model from the local torch-hub cache)."""
    def __init__(self):
        p = os.path.expanduser("~/.cache/torch/hub/snakers4_silero-vad_master/src/silero_vad/data/silero_vad.jit")
        self.m = torch.jit.load(p).eval()
        self.m.reset_states()

    def reset(self):
        self.m.reset_states()

    @torch.no_grad()
    def probs(self, pcm):  # pcm float32, length a multiple of 512
        x = torch.tensor(np.asarray(pcm, np.float32)).reshape(-1, 512)
        return np.array([float(self.m(x[i], 16000)) for i in range(len(x))], np.float32)


# -------------------------------------------------------------------------------------------------------------------------- face
class FaceStream:
    """Per-session face tracker. process(frame_bgr, t) -> (record dict, B0 embedding or None). Mirrors cache_faces_v2.one_clip
    for one frame: YuNet (largest x continuity x centrality), a miss is bridged by the last face for <= 2 frames (tracked=1),
    5-point alignment to 224, B0 logits+embedding on the aligned crop, MediaPipe blendshapes + pose on a margin crop.
    usable = detected (not tracked) & MediaPipe ok & face height >= min_h & |yaw| <= 45 & |pitch| <= 35."""
    def __init__(self, min_h=64):
        import timm
        import mediapipe as mp
        from mediapipe.tasks import python as mpt
        from mediapipe.tasks.python import vision
        self.mp = mp
        self.min_h = min_h
        self.det = cv2.FaceDetectorYN.create(YUNET, "", (320, 320), 0.6, 0.3, 5000)
        net = timm.create_model("tf_efficientnet_b0", pretrained=False, num_classes=8)
        net.load_state_dict(torch.load(B0, map_location="cpu"))
        self.b0 = net.to(dev).eval()
        self.lm = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
            base_options=mpt.BaseOptions(model_asset_path=LANDMARKER), running_mode=vision.RunningMode.IMAGE, num_faces=1,
            output_face_blendshapes=True, output_facial_transformation_matrixes=True))
        self.reset()

    def reset(self):
        self.prev, self.miss = None, 99

    @torch.no_grad()
    def process(self, fr, t):
        h, w = fr.shape[:2]
        self.det.setInputSize((w, h))
        _, fs = self.det.detect(fr)
        rec = dict(t=t, found=0, tracked=0, usable=0, mp_ok=0, n_faces=0 if fs is None else len(fs), face_h=np.nan, det_score=np.nan,
                   yaw=np.nan, pitch=np.nan, roll=np.nan, blur=np.nan, bright=np.nan, box=None,
                   logits=np.full(8, np.nan, np.float32), bs=np.full(52, np.nan, np.float32))
        face = None
        if fs is not None and len(fs):
            def key(f):
                b = f[:4]
                cen = 1 - 0.5 * np.hypot((b[0] + b[2] / 2) / w - 0.5, (b[1] + b[3] / 2) / h - 0.5)
                return b[2] * b[3] * (0.5 + (iou(self.prev[:4], b) if self.prev is not None else 0.5)) * cen
            face = max(fs, key=key)
            rec.update(found=1, det_score=float(face[14]))
            self.prev, self.miss = face, 0
        elif self.prev is not None and self.miss < 2:
            face, self.miss = self.prev, self.miss + 1
            rec["tracked"] = 1
        else:
            self.miss += 1
        emb = None
        if face is not None:
            x, y, bw, bh = [float(v) for v in face[:4]]
            rec.update(face_h=bh, box=[x / w, y / h, bw / w, bh / h])
            M, _ = cv2.estimateAffinePartial2D(face[4:14].reshape(5, 2).astype(np.float32), TEMPLATE, method=cv2.LMEDS)
            if M is not None:
                al = cv2.warpAffine(fr, M, (SIZE, SIZE), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
                g = cv2.cvtColor(al, cv2.COLOR_BGR2GRAY)
                rec.update(blur=float(cv2.Laplacian(g, cv2.CV_64F).var()), bright=float(g.mean()))
                cx, cy, s = x + bw / 2, y + bh / 2, max(bw, bh) * 1.5
                x0, y0, x1, y1 = int(max(0, cx - s / 2)), int(max(0, cy - s / 2)), int(min(w, cx + s / 2)), int(min(h, cy + s / 2))
                sub = np.ascontiguousarray(cv2.cvtColor(fr[y0:y1, x0:x1], cv2.COLOR_BGR2RGB))
                if sub.size:
                    res = self.lm.detect(self.mp.Image(image_format=self.mp.ImageFormat.SRGB, data=sub))
                    if res.face_blendshapes:
                        rec["bs"] = np.array([c.score for c in res.face_blendshapes[0]], np.float32)
                        yaw, pitch, roll = euler(res.facial_transformation_matrixes[0])
                        rec.update(mp_ok=1, yaw=yaw, pitch=pitch, roll=roll)
                if not rec["tracked"] and rec["mp_ok"] and bh >= self.min_h and abs(rec["yaw"]) <= 45 and abs(rec["pitch"]) <= 35:
                    rec["usable"] = 1
                x_in = torch.tensor(cv2.cvtColor(al, cv2.COLOR_BGR2RGB), dtype=torch.float32, device=dev).permute(2, 0, 1)[None] / 255.0
                x_in = (x_in - torch.tensor([0.485, 0.456, 0.406], device=dev).view(1, 3, 1, 1)) / torch.tensor([0.229, 0.224, 0.225], device=dev).view(1, 3, 1, 1)
                e = self.b0.forward_head(self.b0.forward_features(x_in), pre_logits=True)
                rec["logits"] = self.b0.classifier(e)[0].float().cpu().numpy()
                emb = e[0].float().cpu().numpy()
        return rec, emb


from pipeline_utils import pool_face_with_quality


def pool_face(frames):
    """frames: list of (record, embedding). Quality-weighted 1,400-d RAW face vector or None (< 3 usable frames)."""
    vec, _ = pool_face_with_quality(frames, min_usable=MIN_USABLE)
    return vec


# ---------------------------------------------------------------------------------------------------------------- normalise / heads
class Normaliser:
    """x_norm = (x - mu) / sd with the statistics of ONE reference training corpus (training z-scored per corpus).  mu can be
    replaced by the user's own calibration mean (set_user_mean) - sd always stays the reference."""
    def __init__(self, ref="mosei"):
        self.S = np.load(SERVICE / "ref_stats.npz")
        self.user_mu = {}
        self.set_ref(ref)

    def set_ref(self, ref):
        self.ref = ref
        S = self.S

        def g(m, k):
            return S[f"{m}_{ref}_{k}"] if f"{m}_{ref}_{k}" in S.files else S[f"{m}_mosei_{k}"]
        self.mu = {"A": np.concatenate([g("wavlm", "mu"), g("whisper", "mu")]), "T": g("text", "mu"), "V": g("face", "mu")}
        self.sd = {"A": np.concatenate([g("wavlm", "sd"), g("whisper", "sd")]), "T": g("text", "sd"), "V": g("face", "sd")}

    def set_user_mean(self, mod, mu):
        self.user_mu[mod] = None if mu is None else np.asarray(mu, np.float32)

    def __call__(self, mod, x):
        mu = self.user_mu.get(mod)
        mu = self.mu[mod] if mu is None else mu
        return ((x - mu) / self.sd[mod]).astype(np.float32)


class Heads:
    def __init__(self, n_seeds=5):
        self.nets = []
        for s in range(n_seeds):
            ck = torch.load(SERVICE / f"heads_s{s}.pt", map_location="cpu")
            net = NetVA(ck["dims"])
            net.load_state_dict(ck["state"])
            self.nets.append(net.to(dev).eval())
        self.dims = ck["dims"]
        self.temps = json.loads((SERVICE / "temps.json").read_text())

    @torch.no_grad()
    def predict(self, xa=None, xt=None, xv=None):
        """normalised vectors (None = modality absent). Returns calibrated probabilities for the present pattern."""
        present = "".join(m for m, x in zip("ATV", (xa, xt, xv)) if x is not None)
        if not present:
            return None
        xs = [torch.tensor(x if x is not None else np.zeros(d, np.float32), device=dev)[None] for x, d in zip((xa, xt, xv), self.dims)]
        ms = [torch.full((1,), 1.0 if x is not None else 0.0, device=dev) for x in (xa, xt, xv)]
        outs = [net(xs, ms)[:3] for net in self.nets]
        T = self.temps[present]
        names = {"l7": CLASSES7, "lv": VAL, "la": ARO}
        res = {"pattern": present}
        for j, h in enumerate(("l7", "lv", "la")):
            lg = torch.stack([o[j][0] for o in outs]).mean(0)
            res[h] = dict(zip(names[h], torch.softmax(lg / T[h], -1).cpu().numpy().tolist()))
        return res


class Engine:
    def __init__(self, load_text=True, load_audio=True, load_face=True, load_asr=True):
        self.audio = AudioEncoders(load_asr=load_asr) if load_audio else None
        self.text = TextEncoder() if load_text else None
        self.face = FaceStream() if load_face else None
        self.vad = None  # HTTP service consumes finished turns; it does not run VAD.
        self.norm = Normaliser()
        self.heads = Heads()
