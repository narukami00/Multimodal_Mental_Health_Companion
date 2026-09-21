# Multimodal Emotion Recognition: Literature Review & Research Gaps Analysis

Below is a curated landscape of the top-venue papers that form the methodological backbone of your project — a real-time, camera-on, three-modality (video-face, audio, text) emotion detection pipeline for mental-health monitoring. The field has settled on Transformer-based fusion over aligned features as the dominant recipe, with the most cited works (MulT, MISA, Self-MM, MMIM) all benchmarked on CMU-MOSI/MOSEI and IEMOCAP; the frontier is now moving toward LLM-based natural-language emotion reasoning (AffectGPT) and temporal, in-the-wild recognition【turn1search0】【turn0search8】.

## Comparison of Top-Venue Papers

| Paper | Venue / Year | Modalities | Input → Output | Core Method | Key Limitation |
|---|---|---|---|---|---|
| MulT | ACL 2019 | T, A, V | Unaligned multimodal sequences → sentiment/ emotion | Cross-modal attention (directional Transformers) | Heavy attention cost; no utterance-level emotion granularity【turn0search8】 |
| MISA | ACM MM 2020 | T, A, V | Aligned features → sentiment score | Modality-invariant + modality-specific representations | Only sentiment polarity, no discrete emotion classes【turn3search0】 |
| M³ER | AAAI 2020 | T, A, V (face) | Audio + face + text → emotion class | Multiplicative fusion + noise-robust autoencoder | Small emotion taxonomy; weak missing-modality handling【turn1search2】 |
| Self-MM | AAAI 2021 | T, A, V | Aligned features → sentiment | Self-supervised unimodal label generation + multitask | Needs pre-aligned features; sentiment-only output【turn2search1】 |
| MMIM | EMNLP 2021 | T, A, V | Aligned features → sentiment | Hierarchical mutual-information maximization | Sentiment-specific; no interpretability layer【turn1search0】 |
| M-SENA Platform | ACL 2022 | T, A, V | Raw video → sentiment | Integrated platform (feature extraction → training) | Platform, not a novel architecture【turn1search4】 |
| AffectGPT | ICML 2025 | T, A, V | Video → natural-language emotion description | LLM-based MER benchmark (MERR dataset) | Early-stage; benchmark, not yet real-time deployable【turn1search7】【turn1search9】 |
| Multi-Label MER w/ Transformer | IEEE 2023 | T, A, V | Raw video frames + audio + subtitles → multi-label emotions | Transformer fusion + emotion-level representation learning | Multi-label, but no temporal dynamics modeling【turn2search4】 |

---

## Detailed Paper Cards

### 1. MulT — Multimodal Transformer for Unaligned Multimodal Language Sequences
- **Venue:** ACL 2019 (3583+ citations)【turn0search8】
- **Problem addressed:** Earlier fusion models required explicit alignment (e.g., P2F, word-level) between text, audio, and visual streams. MulT removes that requirement entirely.
- **Method:** Cross-modal attention — one directional Transformer for each pair of modalities (e.g., V→T, A→T) that lets the target modality attend to the source modality's sequence without alignment. A final self-attention fusion network merges the outputs.
- **Input/Output:** Unaligned (T, A, V) sequences → sentiment score (CMU-MOSI) or emotion class (IEMOCAP).
- **Limitation & gap:** No utterance-level segmentation — treats the whole segment at once; attention cost grows quadratically; no interpretability of which modality drove the prediction.

### 2. MISA — Modality-Invariant and -Specific Representations
- **Venue:** ACM MM 2020【turn3search0】
- **Problem addressed:** Feature-level fusion is brittle because modalities carry both shared and modality-unique information. MISA decouples them.
- **Method:** Encodes each modality into (a) a modality-invariant subspace using adversarial-style domain similarity, and (b) a modality-specific subspace. Fusion uses translation-based (total translation) and similarity-based (weighted difference) metrics across all four (2×2) pairs of subspaces.
- **Input/Output:** Aligned text (BERT), audio (openSMILE/Covarep), visual (Facet/3D-CNN) features → sentiment score.
- **Limitation & gap:** Only sentiment intensity, not discrete emotions; relies on pre-extracted COVAREP/FACET features that are not open-source deployable for a live app; no handling of a modality being missing (e.g., camera off).

### 3. M³ER — Multiplicative Multimodal Emotion Recognition
- **Venue:** AAAI 2020 (383+ citations)【turn1search2】
- **Problem addressed:** Emotional cues are often ambiguous and subject to noise; modalities can disagree. M³ER learns to down-weight unreliable modalities at the fusion stage.
- **Method:** A multiplicative gating mechanism: unimodal feature extractors (3D-CNN for face, ResNet for audio spectrogram, BERT for text) → multiplicative fusion network that dynamically modulates each modality's contribution → emotion classifier. A noise-robust autoencoder handles missing/noisy modalities.
- **Input/Output:** Audio, face image, text (from the IEMOCAP-style corpus) → emotion label among a small set (happy, sad, angry, etc.).
- **Limitation & gap:** Small emotion taxonomy (typically 4–7 classes); frame-level rather than sentence-level segmentation; tested only on acted data (IEMOCAP), not in-the-wild conversations.

### 4. Self-MM — Self-Supervised Multitask Learning for Multimodal Sentiment Analysis
- **Venue:** AAAI 2021 (1217+ citations)【turn2search1】
- **Problem addressed:** Multimodal fusion models under-perform because unimodal signals are weakly supervised when only a fused (multimodal) label exists. Self-MM generates unimodal pseudo-labels.
- **Method:** A label-generation module creates sentiment labels for each modality (T, A, V) separately via a Gaussian window over the fused label. A multitask learning framework trains each unimodal branch on its own pseudo-label while the shared fusion head learns the joint prediction.
- **Input/Output:** Aligned (T, A, V) features → sentiment score.
- **Limitation & gap:** Pseudo-labels can propagate errors; requires a fusion dataset with unimodal-correlated labels; sentiment-only, not emotion-class; no explanation of "why" an emotion was detected.

### 5. MMIM — Improving Multimodal Fusion with Hierarchical Mutual Information Maximization
- **Venue:** EMNLP 2021 (848+ citations)【turn1search0】
- **Problem addressed:** Fusion features often lose unimodal information; MMIM maximizes both unimodal and pair-wise cross-modal mutual information to retain richer fusion representations.
- **Method:** Two-level MI maximization — (1) MI between each unimodal feature and the fused feature, and (2) MI between pairs of modalities in the fused space. Uses the Barber-Agakov lower bound and contrastive predictive coding (with an entropy-estimation module and a memory of history data) as the objective.
- **Input/Output:** (T, A, V) features → sentiment score.
- **Limitation & gap:** Sentiment-specific; contrastive MI estimation is computationally expensive; no missing-modality robustness for a live app where a user may toggle the camera off mid-session.

### 6. M-SENA — An Integrated Platform for Multimodal Sentiment Analysis
- **Venue:** ACL 2022 (141+ citations)【turn1search4】
- **Problem addressed:** Research reproducibility; end-to-end pipeline from raw video to prediction.
- **Method:** A modular platform: data management (CMU-MOSI/MOSEI/IEMOCAP pre-loaded) → feature extraction (via MMSA-FET toolkit) → model training (includes Self-MM and other baselines) → result analysis with visualization.
- **Input/Output:** Raw video (frames + audio + transcript) → sentiment score.
- **Relevance to your project:** This is the closest open-source pipeline to what you are building. It handles the feature-extraction bottleneck (which private models like Facet and COVAREP create) by offering open alternatives.

### 7. AffectGPT — A New Dataset, Model, and Benchmark for Multimodal Emotion Recognition
- **Venue:** ICML 2025 (147+ citations)【turn1search7】【turn1search9】
- **Problem addressed:** Traditional MER outputs a single discrete emotion label, losing nuance. AffectGPT reframes MER as generating a natural-language description of the emotion and its causes.
- **Method:** Introduces MERR, a large-scale dataset of multimodal emotion reasoning; evaluates LLMs (e.g., GPT-4V, LLaVA) fine-tuned on MERR for zero-shot and in-context MER.
- **Input/Output:** Video (T, A, V) → a natural-language description such as "The speaker appears frustrated because of the interruption, showing tight lips and a raised voice."
- **Relevance to your project:** This is directly aligned with your "output about what kind of emotion I am conveying **and why**" requirement. It is the frontier direction.

### 8. CMU-MOSEI — Multimodal Language Analysis in the Wild
- **Venue:** ACL 2018 (dataset paper; 3600+ citations)【turn1search6】
- **Problem addressed:** Prior datasets (IEMOCAP) were acted and small. CMU-MOSEI provides 23,453 annotated sentences from 1,000 monologue videos, with continuous sentiment ([-3, +3]) and emotion (6 Ekman classes) labels.
- **Key detail:** The dataset also introduced the Graph-MFN (gated multimodal fusion) baseline.
- **Why it matters:** Almost every top-venue fusion paper (MISA, Self-MM, MMIM, MulT) benchmarks on CMU-MOSEI; aligning with it means you can directly compare against SOTA.

### 9. IEMOCAP — Interactive Emotional Dyadic Motion Capture Database
- **Venue:** LREC 2008 (5733+ citations)【turn4search2】【turn4search3】
- **Problem addressed:** The standard dyadic (two-person) multimodal emotion corpus: 12 hours of audio, video, facial motion-capture from 10 actors in scripted and improvised dyadic sessions, labeled with 9 emotion categories (anger, happiness, sadness, neutral, excitement, frustration, fear, surprise, disgust) plus dimensional valence/arousal.
- **Why it matters:** For emotion **classes** (not just sentiment), IEMOCAP is the reference dataset.

### 10. MELD — Multimodal Multi-Party Dataset for Emotion Recognition in Conversations
- **Venue:** EMNLP 2019 (dataset)【turn0search7】【turn0search8】
- **Problem addressed:** Extends EmotionLines to multimodal (T, A, V), with 13,000 utterances from 1,433 dialogues of Friends (TV series), annotated for 7 emotions + sentiment.
- **Why it matters:** Models conversational context (multi-party, multi-turn), closer to your use case of a user speaking over time.

### 11. MER Challenges (MER2023 @ ACM MM, MER2024 @ IJCAI/ACM MM)
- **Venue:** ACM MM 2023, IJCAI 2024【turn3search2】【turn3search3】
- **Problem addressed:** Community benchmarks for robust MER, missing-modality recognition, and semi-supervised emotion recognition.
- **Why it matters:** The challenge tracks (especially MER2023's missing-modality track) directly mirror your scenario of a user toggling camera/mic on and off.

---

## Datasets & Resource Repositories (Practical Foundation)

- **CMU-MOSI** and **CMU-MOSEI** — 2,199 and 23,453 aligned sentence-level tri-modal (T/A/V) utterances. Features available via MMSA-FET (open-source tool in the M-SENA platform)【turn1search6】【turn0search0】.
- **IEMOCAP** — Dyadic, acted, 12 hours, 9 emotion classes; the reference for discrete emotion recognition【turn4search3】.
- **MELD** — Conversational, multi-party (Friends dialogues), 7 emotions; tests context modeling【turn0search7】.
- **M-SENA Platform** (GitHub: M-SENA) — open-source end-to-end pipeline with data loading, feature extraction, model training, and visualization; runs Self-MM and other baselines out of the box【turn1search4】【turn0search0】.
- **MMSA GitHub repo (THUIAR)** — a unified framework for multimodal sentiment analysis, designed for fair and reproducible experiments; includes MMSA-FET for feature extraction【turn0search0】.

---

## Research Gaps & Open Problems

| Gap | Current State | Why It Matters for Your Project |
|---|---|---|
| **Discrete emotion classes (not just sentiment)** | Most top-venue fusion papers (MISA, Self-MM, MMIM) optimize for sentiment intensity (-3 to +3) rather than emotion labels. Only M³ER and AffectGPT handle discrete emotions. | Your mental-health use case requires "anxiety," "depression," "sadness," not just "negative sentiment." You will need to adapt these architectures to emotion-class output or use IEMOCAP/MELD-style labels. |
| **Missing-modality robustness** | Most models assume all three modalities are present. M³ER and MER2023's missing-modality track are early attempts. | In a real app, the camera may be off, the mic may fail, or the user may be silent. You need a fusion mechanism that gracefully degrades. |
| **Temporal modeling within and between utterances** | Most papers treat each utterance as a static segment. Only MMDFN (ICASSP 2022) and conversational-ERC models (e.g., DialogueRNN) model temporal dynamics. | Your project explicitly needs "facial expression while speaking" vs. "while silent" — i.e., intra-utterance temporal segmentation. |
| **Explainability ("why this emotion")** | Almost none of the fusion papers provide rationale. AffectGPT is the first to explicitly address it via LLM-generated natural-language explanations. | Your requirement — "give me an output about what kind of emotion I am conveying and why" — is still an open problem. This is your project's biggest novelty opportunity. |
| **In-the-wild vs. acted data** | IEMOCAP and CMU-MOSEI are acted/monologue. MELD is TV-series. Few papers test on spontaneous webcam data. | A mental-health monitoring app will see unconstrained, low-quality webcam input. You will likely need domain adaptation or fine-tuning. |
| **Real-time inference** | All papers evaluate offline on pre-extracted features. No paper benchmarks end-to-end latency on live video. | A monitoring app needs <500ms per utterance. This forces you to choose lightweight feature extractors and efficient fusion. |

---

## Actionable Recommendations for Your Project

1. **For modality encoding:** Use open, lightweight extractors — for text, a BERT/DeBERTa encoder; for audio, wav2vec 2.0 or HuBERT embeddings; for visual, a lightweight 3D-CNN or OpenFace-derived facial action units (FAUs). The M-SENA platform's MMSA-FET provides open implementations of these.

2. **For fusion:** Start with the Self-MM or MMIM architecture (both have public code in the THUIAR and declare-lab repos, respectively) and adapt them from sentiment to emotion-class output by retraining on IEMOCAP or MELD labels. M³ER's multiplicative gating is a strong candidate for missing-modality robustness.

3. **For the "why" explanation:** Layer an LLM (or a smaller distilled model) on top of the fusion output that generates a natural-language rationale. AffectGPT's MERR dataset is the training resource for this. This is where your project can make a genuine contribution, since none of the top-venue fusion papers address it.

4. **For temporal handling:** Segment your input stream (audio + video + text) by silence gaps (e.g., >500ms) into utterance windows, similar to how CMU-MOSEI sentence segmentation works. Then, for intra-utterance dynamics, consider a lightweight recurrent layer (GRU) on top of per-frame features before fusion.

5. **For baselines to beat:** On CMU-MOSEI (sentiment), the SOTA is approximately Acc-2 ≈ 88%, F1 ≈ 88.4 (Self-MM, MMIM). On IEMOCAP (4-class emotion), the SOTA is approximately Acc ≈ 78–82% (MulT, M³ER). Your emotion-class system should target this range to be competitive.

---

## Suggested Paper Stack (Reading Order)

1. **MulT (ACL 2019)** — foundational cross-modal attention, no alignment required.
2. **MISA (ACM MM 2020)** — decoupling modality-invariant/specific representations.
3. **M³ER (AAAI 2020)** — emotion-specific (not sentiment) and noise-robust fusion.
4. **Self-MM (AAAI 2021)** — self-supervised pseudo-labels; the most-cited recent fusion baseline.
5. **MMIM (EMNLP 2021)** — information-theoretic fusion; the current best non-LLM approach on CMU-MOSEI.
6. **AffectGPT (ICML 2025)** — the frontier: LLM-generated natural-language emotion reasoning; directly aligned with your "why" requirement.
7. **MELD, IEMOCAP, CMU-MOSEI dataset papers** — the benchmarks you must evaluate on.

---

## Key GitHub Repositories

- **declare-lab/Multimodal-Infomax** (MMIM) — https://github.com/declare-lab/Multimodal-Infomax【turn0search1】
- **declare-lab/MISA** — https://github.com/declare-lab/MISA【turn3search0】
- **THUIAR (Self-MM, MMSA, M-SENA)** — https://github.com/thuiar【turn0search0】【turn1search4】
- **pliang279/awesome-multimodal-ml** — a curated reading list that includes the above papers and more, organized by fusion/representation/alignment topics【turn0search2】

The short version: the field has converged on Transformer-based cross-modal fusion over pre-extracted (T, A, V) features, benchmarked on CMU-MOSEI and IEMOCAP. Your project's novelty lies in (a) adapting these architectures to discrete emotion classes, (b) handling missing modalities and temporal dynamics, and (c) layering an LLM-based explanation module on top — the direction AffectGPT just opened up.
