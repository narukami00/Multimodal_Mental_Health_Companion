"""Face preprocessing constants and geometry, extracted from cache_faces_v2.py."""
import numpy as np
from runtime_config import MODELS

YUNET = str(MODELS / "face/face_detection_yunet_2023mar.onnx")
LANDMARKER = str(MODELS / "face/face_landmarker.task")
B0 = str(MODELS / "face/enet_b0_8_best_afew_tf_statedict.pt")
SIZE = 224
TEMPLATE = ((np.float32([[38.29,51.70],[73.53,51.50],[56.03,71.74],[41.55,92.37],[70.73,92.20]]) * 2 - 112) * 0.85 + 112)

def euler(m):
    """yaw, pitch, roll (deg) from a MediaPipe 4x4 facial transformation matrix."""
    r = np.asarray(m)[:3, :3]
    r = r / np.linalg.norm(r, axis=0, keepdims=True)
    pitch = np.degrees(np.arcsin(-np.clip(r[1, 2], -1, 1)))
    yaw = np.degrees(np.arctan2(r[0, 2], r[2, 2]))
    roll = np.degrees(np.arctan2(r[1, 0], r[1, 1]))
    return yaw, pitch, roll

def iou(a, b):
    ax2, ay2, bx2, by2 = a[0] + a[2], a[1] + a[3], b[0] + b[2], b[1] + b[3]
    iw, ih = max(0, min(ax2, bx2) - max(a[0], b[0])), max(0, min(ay2, by2) - max(a[1], b[1]))
    inter = iw * ih
    return inter / (a[2] * a[3] + b[2] * b[3] - inter + 1e-9)
