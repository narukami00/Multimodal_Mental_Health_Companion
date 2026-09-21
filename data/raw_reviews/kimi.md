I have enough material for a comprehensive review. Here is the full literature review and requirement analysis.

---

# Literature Review: Multimodal Emotion Recognition (Video + Audio + Text)

**Context:** AI-based mental-health emotion monitoring app — user turns on camera + mic, speaks naturally; system segments speech into utterances (sentence-level, gap-based), and per utterance fuses **facial expression (video), tone of voice (audio), and spoken content (text, English only)** into an emotion label + confidence + explanation.

---

## Part 1 — How the Landscape Looks (Field Map)

The field has gone through four clear waves, and knowing them tells you which papers to trust and which to treat as history:

1. **Tensor/early fusion era (2017–2019):** TFN, LMF, MFN. Simple, interpretable, but shallow — modality interactions modeled with outer products; weak on unaligned streams.
2. **Cross-modal attention era (2019–2021):** MulT, MAG-BERT, MMIM, MISA. The dominant paradigm: each modality gets its own encoder; directional cross-attention lets one modality "query" another without forcing time alignment. MulT alone has ~1,800 citations .
3. **Context & robustness era (2019–2023):** DialogueRNN → DialogueGCN → COSMIC for conversational context; MMIN/IF-MMIN for missing or corrupted modalities — directly relevant to real-world deployment (occluded faces, ASR errors, silence) .
4. **Foundation-model era (2023–now):** wav2vec2/HuBERT/WavLM as audio encoders, ViT-MAE/VideoMAE as facial encoders, LLM backbones with instruction tuning — capped by **Emotion-LLaMA (NeurIPS 2024)**, which does exactly your task (video+audio+text → emotion label **and a natural-language explanation of why**) .

Multiple 2025–2026 surveys confirm the shift toward hybrid fusion (early+late), gating/reliability-aware fusion, generative missing-modality recovery, and LLM-based reasoning ; the most-cited recent survey is the EMNLP 2025 Findings MERC survey .

**⚠️ A caution for your related-work section:** there are low-quality venues publishing implausible numbers (e.g., a 2025 *Springer EPJ Data Science* paper claiming 99.8% accuracy on IEMOCAP where the credible SOTA ceiling is ~70–73% ). Stick to ACL/NeurIPS/AAAI/CVPR/ICASSP/IEEE TAC/TASLP papers.

---

## Part 2 — Curated Paper List

### A. Foundational Fusion (read for baseline design)

**1. TFN — Tensor Fusion Network (Zadeh et al., EMNLP 2017)**
- Problem: model uni-, bi-, and tri-modal interactions explicitly.
- Method: outer-product of modality embeddings (+ bias terms) → tensor → MLP.
- I/O: text+audio+video feature vectors → sentiment/emotion score.
- Limitations/gaps: exponential parameter growth; assumes aligned features; no temporal modeling. Superseded by LMF.

**2. LMF — Low-rank Multimodal Fusion (Liu et al., ACL 2018)** 
- Same idea as TFN but with CP low-rank decomposition — ~3× faster training with competitive accuracy (IEMOCAP, MOSI, POM).
- Gap: still sentence-bag fusion, no cross-modal dynamics. Still a **mandatory baseline** in the field.

### B. Cross-Modal Transformer Fusion (core methodology for your project)

**3. MulT — Multimodal Transformer (Tsai et al., ACL 2019)** — *the* landmark paper
- Problem: modalities have different sampling rates and are not time-aligned; forced word-level alignment loses information.
- Method: directional pairwise cross-modal attention — 6 crossmodal transformers (V→L, A→L, L→V, A→V, L→A, V→A) over low-level features; no explicit alignment needed.
- I/O: unaligned language/acoustic/visual sequences → sentiment (MOSI/MOSEI) or emotion (IEMOCAP).
- Gains: +10–15% over prior methods on unaligned data.
- Limitations: quadratic attention cost; uses hand-crafted features (GloVe, COVAREP, FACET) rather than learned ones; utterance-level, not streaming.
- Code: github.com/yaohungt/Multimodal-Transformer 

**4. MAG-BERT — Integrating Multimodal Information in Large Pretrained Transformers (Rahman et al., ACL 2020)** 
- Problem: BERT can't natively consume nonverbal modalities.
- Method: a Multimodal Adaptation Gate generates a shift vector conditioned on visual+acoustic features that perturbs BERT's internal word representations; minimal parameter overhead, applied at early layers.
- Result: first "human-level" multimodal sentiment on CMU-MOSI; generalizes to MOSEI.
- Limitation: text-centric — audio/video only modulate language; weak when the spoken words are neutral but tone/face carry the emotion (a common mental-health case).
- Code available (linked in paper).

**5. MMIM — MultiModal InfoMax (Han et al., EMNLP 2021)** 
- Problem: fusion loses task-relevant information from the inputs.
- Method: hierarchically maximize mutual information (inter-modality pairs + fusion-result↔inputs) using BA lower bound + contrastive predictive coding; entropy-estimation module with memory.
- Gaps: MI estimation is approximate; computational overhead; still utterance-level.
- Code: github.com/declare-lab/Multimodal-Infomax 

**6. MISA — Modality-Invariant and -Specific Representations (Hazarika et al., ACM MM 2020)** 
- Problem: distributional "modality gap" between heterogeneous features.
- Method: project each modality into (a) a modality-invariant subspace (shared, similarity-regularized) and (b) a modality-specific subspace (private); concatenate all six for fusion.
- Influence: the representation-centric philosophy; ~900+ citations; the 2025 MISA-GMC extension adds reliability-aware gating for noisy/missing modalities .
- Gap: no temporal/context modeling; designed for sentiment more than fine-grained emotion.
- Code: github.com/declare-lab/MISA

### C. Emotion Recognition in Conversation (context modeling)

**7. DialogueRNN (Majumder et al., AAAI 2019)** 
- Problem: prior models ignored *who* said what.
- Method: three GRUs — party state (per-speaker emotional tracker), global context (attention over preceding utterances), emotion representation → softmax.
- Limitations: RNN long-range context propagation failure; text features only in the original (multimodal left to later work).

**8. DialogueGCN (Ghosal et al., EMNLP-IJCNLP 2019)** 
- Problem: RNNs can't propagate context across long conversations.
- Method: utterances = graph nodes; directed edges encode speaker dependency (self/inter-party) and relative position; 2-layer GCN. Beat DialogueRNN by ~2% F1 on IEMOCAP (64.18%).
- Limitation: original version is text-only; window-size sensitive; static graph.
- Code in declare-lab/conv-emotion repo .

**9. COSMIC (Ghosal et al., Findings of EMNLP 2020)** 
- Problem: emotions in conversation depend on implicit commonsense (intent, effect on listener).
- Method: COMET commonsense transformers generate intent/effect/reaction embeddings per utterance → DialogueGCN-style graph over them. Long-time SOTA on IEMOCAP/MELD/EmotionLines.
- Gap: commonsense models add latency; still no native multimodal encoders (features come from external extractors).

**10. GS-MCC (Ai et al., AAAI 2025)** — current graph-based SOTA class
- Re-analyzes ERC from graph-spectrum view; beats AdaIGN by ~3.2% W-F1 on IEMOCAP, ~2.2% on MELD .
- Relevance: shows GCN over-smoothing was the real bottleneck — useful if your app accumulates emotional state over a session (your "emotion trend" feature).

### D. Robustness / Missing Modalities (critical for real-world deployment)

**11. MMIN — Missing Modality Imagination Network (Zhao et al., ACL 2021)** 
- Problem: in the wild, faces get occluded, ASR fails, users go silent — fixed fusion collapses.
- Method: train one unified model across all 6 missing-modality combinations using Cascade Residual Autoencoders to *imagine* the missing modality's sentence-level representation from available ones + cycle-consistency loss.
- Result: beats both full-modality baseline and data-augmentation baseline under every missing-modality condition, and even under full-modality conditions.
- Why it matters for you: your app will *constantly* face partial inputs (user looks away, mic noise). Code: github.com/AIM3-RUC/MMIN .

**12. IF-MMIN (Zhao/Liu et al., arXiv 2022)** 
- Adds central-moment-discrepancy (CMD) invariant feature learning to close the modality gap during imagination; SOTA on missing-modality IEMOCAP. Open-source.

### E. Unimodal SOTA (your facial and voice encoders will likely come from here)

**Facial (FER):**
- **DAN** (Wen et al., TPAMI 2023): ResNet-18 + multi-head cross-attention over facial regions ("distract your attention"); strong on RAF-DB/AffectNet. Recent 2025 CDAN variants beat it .
- **POSTER++** (Ma et al., ICCV 2023): two-stream landmark+image pyramid cross-fusion; SOTA at low cost — 92.21% RAF-DB, 67.49% AffectNet-7, only 8.4 GFLOPs . Good fit for a real-time app.
- **VTFF** (Ma et al., 2021): ViT + attentional selective fusion — 88.14% RAF-DB, 61.85% AffectNet-8 .
- **AffectNet+** (Fard et al., FG 2024): soft-label enrichment of AffectNet via ensemble-of-binary-classifiers + AU classifiers — shows label noise is AffectNet's real bottleneck .
- Note: AffectNet-8 SOTA is only ~63–67% — in-the-wild FER is far from solved; plan for it.

**Voice (SER):**
- **wav2vec 2.0 fine-tuning for SER (Chen et al., arXiv 2021)** 
  - Method: vanilla fine-tuning (V-FT), task-adaptive pretraining (TAPT), and pseudo-label TAPT; **+7.4% absolute UA over prior SOTA on IEMOCAP**. Public code. This is the standard modern audio encoder recipe.
- **WavFusion (2024/25)** 
  - Replaces self-attention inside wav2vec2 with gated cross-modal attention, adds margin-based discrepancy learning across modalities; SOTA on IEMOCAP/MELD. Directly relevant: it's essentially "MulT philosophy injected into wav2vec2."

### F. LLM / MLLM Era (closest match to your full product vision)

**13. Emotion-LLaMA (Cheng et al., NeurIPS 2024)** — **most important paper for your project** 
- Problem: MLLMs can't process audio and miss micro-expressions; and no dataset existed for emotion *reasoning*.
- Contributions: (1) **MERR dataset** — 28,618 coarse + 4,487 fine-grained multimodal emotion samples with LLM-generated descriptions; (2) model = HuBERT (audio) + MAE/VideoMAE/EVA three-view visual encoder + LLaMA-2-7B with linear-projection token fusion, LoRA instruction tuning.
- Output: emotion label **plus a natural-language rationale** ("the raised eyebrows, emphatic tone, and wording suggest surprise") — exactly your "what emotion + why" requirement.
- Results: F1 0.9036 on MER2023-SEMI; won MER2024-NOISE (WAF 84.52%); best zero-shot on DFEW .
- Limitations: 7B-parameter class — heavy for a mobile/web app; processes pre-segmented clips, not open streams; reasoning quality judged partly by LLM scoring.
- Code + demo: github.com/ZebangCheng/Emotion-LLaMA, zebangcheng.github.io/Emotion-LLaMA .

**14. MER Challenge series (ACM MM workshops 2023–2025)** — the field's living benchmark. MER2025 is themed "when affective computing meets large language models" . Tracks cover semi-supervised learning, noise robustness, and open-vocabulary emotion recognition — mirrors your deployment conditions.

**15. EmoS benchmark (2026)** — the first fine-grained **streaming** multimodal emotion benchmark: long-form monologues with timestamped utterance-level annotation (time range, transcript, primary 7-class emotion + GoEmotions multi-label, intensity 1–5, audio/visual cue evidence) . This is the closest published data model to *your* per-sentence emotion timeline. Gemini-3 gets 71% per-utterance accuracy in-stream — headroom exists for a trained model.

### G. Real-Time / Streaming

**16. KAMUH (Rasendrasoa et al., ICMI 2022)** 
- Explicitly designed for **real-time, no-future-access** ERC: RoBERTa + COVAREP/OpenSmile + 3D-CNN features → EmbraceNet fusion → memory banks with multi-head attention. Jointly predicts emotion + dialogue act + emotion shift. The "online ERC" formulation (no peeking at future utterances) is the one you must adopt for a live app.

---

## Part 3 — Dataset Landscape (what you'd train/evaluate on)

| Dataset | Modalities | Content | Role for you |
|---|---|---|---|
| **IEMOCAP** | A+V+T, 12h dyadic, 6 emotions | Acted + spontaneous dialogue | The standard ERC benchmark (WA ~70–73% credible SOTA) |
| **MELD** | A+V+T, 13k utterances, Friends TV, 7 emotions | Multi-party, noisy, naturalistic | Real-world robustness testing |
| **CMU-MOSI / MOSEI** | A+V+T, YouTube monologues | Sentiment (+MOSEI emotions) | Pretraining/fusion ablations |
| **RAVDESS / CREMA-D / SAVEE** | A(+V) | Acted sentences, English | Small SER/FER sanity checks (you already list RAVDESS, CREMA-D) |
| **FER2013 / AffectNet / RAF-DB** | V (images) | In-the-wild faces | Facial encoder pretraining (aligns with your proposal) |
| **DFEW / MER2023–25 / MERR** | A+V+T | In-the-wild video, LLM-annotated | Modern fine-grained evaluation; Emotion-LLaMA's home turf |
| **CMU-MOSEAS** | A+V+T | Elderly, multilingual | Cross-domain generalization test |

---

## Part 4 — Requirement Analysis for YOUR Pipeline

Mapping literature onto your described system (camera on, user talks freely, per-utterance emotion + explanation):

1. **Utterance segmentation.** Your "gap between consecutive sentences" intuition is exactly how the field does it: VAD (voice activity detection, e.g., Silero/WebRTC VAD) + ASR (Whisper) for text and boundaries, then align face tracks to each segment. EmoS's timestamp-JSON schema (start/end, transcript, slice filename) is a ready-made annotation format to copy . No major paper solves *segmentation quality*'s effect on MER — a genuine gap you can claim.

2. **"Face while silent" vs "face while speaking."** The literature treats silent facial expression as implicit context (DialogueRNN/GCN party states, VideoMAE temporal encoders) but **nobody explicitly conditions utterance emotion on the pre-utterance neutral/resting-face baseline**. This is a defensible novelty: resting-face-normalized facial features (e.g., subtract resting-face embedding, or feed both to cross-attention).

3. **Modality reliability gating.** Use the IF-MMIN / WavFusion / MISA-GMC lesson: per-utterance modality quality varies (lighting, occlusion, mic noise) — reliability-aware gating beats naive fusion and is currently the mainstream direction .

4. **"Why" output.** Emotion-LLaMA proved label + rationale is achievable , but at 7B scale. Gap: **lightweight explainable MER** — e.g., template rationale from per-modality confidences + attention maps, or a small LM student distilled from Emotion-LLaMA's reasoning.

5. **Online constraint.** Adopt KAMUH's no-future-information ERC formulation; most leaderboard models (GS-MCC, DialogueGCN) use future context and are unsuitable for live monitoring .

6. **Continual emotional-state tracking.** Your "emotion trend/history dashboard" maps to speaker-state tracking (DialogueRNN party GRU, GS-MCC's graph) — maintain a rolling emotional-state embedding per session rather than independent per-utterance predictions.

---

## Part 5 — Research Gaps You Can Claim (for your proposal's contribution section)

1. **Utterance-boundary sensitivity**: no study quantifies how VAD/ASR segmentation errors propagate into multimodal emotion accuracy.
2. **Resting-face-conditioned facial features**: unexploited signal in every monitoring scenario.
3. **Lightweight, on-device explainable MER**: Emotion-LLaMA-quality reasoning without a 7B model.
4. **Online (causal) multimodal fusion with reliability gating**: most gated-fusion papers assume all modalities present at inference.
5. **Cross-dataset/domain gap**: models trained on IEMOCAP/MELD degrade in-the-wild — your custom real-world evaluation dataset (already in your proposal) directly addresses this, and MER2024-NOISE/EmoS show the community cares.
6. **Mental-health-specific emotion taxonomies**: discrete 6–7 class labels may be too coarse for distress monitoring; open-vocabulary (MER-OV track) and fine-grained (MERR: doubt, contempt, worried) taxonomies are open problems.

**Recommended reading order:** MulT → MMIN → wav2vec2-SER → WavFusion → DialogueGCN/COSMIC → Emotion-LLaMA → EmoS → the EMNLP 2025 MERC survey for the connective tissue.

Want me to go deeper on any branch next — e.g., (a) a technical comparison table of fusion architectures with reported numbers, (b) available open-source repos ranked by stars/maintenance for a quick prototype, or (c) a first-pass system architecture sketch for your per-utterance pipeline?
