"""Inference network extracted unchanged from research modeling/va_head.py."""
import torch
from torch import nn

class NetVA(nn.Module):
    def __init__(self, dims, h=256):
        super().__init__()
        self.proj = nn.ModuleList(nn.Sequential(nn.Dropout(0.3), nn.Linear(d, h), nn.GELU(), nn.LayerNorm(h)) for d in dims)
        self.fuse = nn.Sequential(nn.Linear(len(dims) * (h + 1), h), nn.GELU(), nn.Dropout(0.3))
        self.h7, self.hv, self.ha = nn.Linear(h, 7), nn.Linear(h, 3), nn.Linear(h, 3)
        self.aux = nn.ModuleList(nn.Linear(h, 3) for _ in dims)  # per-modality valence heads

    def forward(self, xs, ms):
        hs = [p(x) * m[:, None] for p, x, m in zip(self.proj, xs, ms)]
        z = self.fuse(torch.cat(hs + [m[:, None] for m in ms], 1))
        return self.h7(z), self.hv(z), self.ha(z), [a(h) for a, h in zip(self.aux, hs)]
