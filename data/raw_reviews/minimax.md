The file is complete. Now I deliver it as the final chat response.

---

# Multimodal Emotion Recognition for Mental-Health Monitoring: A Curated Literature Review

A requirement analysis and related-work map for a real-time, English-only, multimodal emotion recognition system that fuses facial expressions, voice, and (optionally) text to support a mental-health monitoring application.

---

## 1. Scope of This Review

The system being designed accepts a live webcam feed and microphone stream, segments the user's speech into utterances (handling silences and gaps), and outputs an emotional state per utterance (or per time window) along with a confidence score and short explanation. Three modalities are first-class:

1. **Visual** — facial expressions captured frame-by-frame from the webcam.
2. **Audio** — acoustic-prosodic features (MFCCs, log-mel spectrograms, pitch, energy) plus, when available, the spoken transcript.
3. **Text** — the ASR output, treated as a separate feature stream when a transcript is available.

The review is English-only by design, so multilingual datasets (Bengali, Hindi, Akan, Chinese-MER2023, etc.) are excluded from the curated baselines; they are mentioned only when they surface a methodological idea that transfers. Two further filters were applied: (a) preference for Q1/Q2 venues and top conference proceedings (CVPR, NeurIPS, ICCV/ECCV, ACL/EMNLP, AAAI, ACM MM, IEEE Trans. Affective Computing, INTERSPEECH/ICASSP, TPAMI), and (b) preference for work that uses at least one of facial/video and speech, since those are the project's primary streams.

The review is organised into seven blocks: (1) datasets, (2) architectural taxonomy of MER fusion, (3) in-the-wild ABAW/AVEC challenges, (4) speech-only backbones the multimodal pipeline reuses, (5) facial-only backbones, (6) LLM-based MER, (7) cross-cutting limitations and open gaps. A short final section translates the review into design choices and a defensible research-question for the project.

---

## 2. Datasets for English Multimodal and Affect Computing

The table below covers every benchmark that appears later in the review, plus DAIC-WOZ, which is the most common bridge between MER and clinical mental-health labels.

| Dataset | Year | Modalities | Size | English | Emotion labels | Setting | Access |
|---|---|---|---|---|---|---|---|
| FER2013 | 2013 | Static face (48×48 grayscale) | 35,887 images | Yes | 7 basic | Posed, lab | Public (Kaggle) [1] |
| AffectNet | 2017 | Static face, 1M+ | 1M images, ~450K annotated | Yes | 8 categorical + VA | In-the-wild | Application required [2] |
| DFEW | 2020 (ACM MM) | Dynamic face (video) | 16,372 clips from 1,500 films | Yes | 7 basic | In-the-wild | Application required [3] |
| IEMOCAP | 2008 | Audio + video + text | 10,039 utterances, 10 actors | Yes | 9 (commonly 4: hap/sad/ang/neu) | Acted dyadic | USC license [4] |
| MELD | 2019 (ACL) | Audio + video + text | 13,708 utterances, 1,433 dialogues (Friends) | Yes | 7 + sentiment | In-the-wild multi-party | Public (raw + features) [5] |
| CMU-MOSI | 2016 | Audio + video + text | 2,199 utterances | Yes | Sentiment (-3..+3) | YouTube monologues | CMU Multimodal SDK [6] |
| CMU-MOSEI | 2018 (ACL) | Audio + video + text | 23,453 utterances, 1,000 speakers | Yes | Sentiment + 6 emotions | YouTube monologues | CMU Multimodal SDK [6] |
| RAVDESS | 2018 (PLoS ONE) | Audio + video + song | 7,356 recordings, 24 actors | Yes (NA English) | 8 emotions | Acted, controlled | Zenodo (CC) [7] |
| CREMA-D | 2014/2017 | Audio + video | 7,442 clips, 91 actors | Yes | 6 emotions | Acted, diverse | Public [8] |
| Aff-Wild2 | 2019+ | Frame-level face video | ~3M frames, 594 videos | Yes | VA + 8 EXPR + 12 AU | In-the-wild | ABAW challenge [9] |
| Hume-Vidmimic2 | 2024 | Audio + video | ~75 hours, 2,222 subjects | Yes | 7 continuous emotional intensities | In-the-wild | ABAW 6 [9] |
| MERR (Emotion-LLaMA) | 2024 | Audio + video + text | 28,618 coarse + 4,487 fine | Yes | Multi-emotion + reasoning | In-the-wild | By application [10] |
| MER2023 / MER2024 | 2023 / 2024 | Audio + video + text | 4 tracks (SEMI, NOISE, OV, MULTI) | Chinese (mostly); English subset in OV | Multi-label / open-vocab | In-the-wild | MERTools baseline [11] |
| DAIC-WOZ | 2014 | Audio + video + text | 189 participants | Yes | PHQ-8 depression score | Semi-clinical interview | USC application [12] |

A few dataset-specific observations that matter for design choices:

- **DFEW** is the most direct benchmark for *dynamic* facial expressions in the wild; it is the closest existing analogue of what the project's webcam branch will see [3]. It is split into 5 folds, and most top results use leave-one-fold-out testing.
- **IEMOCAP** remains the canonical benchmark for *conversational* multimodal emotion because its 4-class protocol (happy/sad/angry/neutral) is widely adopted; the COSMIC and DialogueGCN results both use it [4][13][14].
- **MELD** is preferred when multi-party dialogue context matters, but it is heavily imbalanced toward "neutral" — class-imbalance handling is mandatory [5].
- **RAVDESS and CREMA-D** are the cleanest acted audio-visual datasets; they are useful for sanity-checking the audio branch on 6–8 emotions but will overestimate real-world performance [7][8].
- **Aff-Wild2 / Hume-Vidmimic2** are the in-the-wild dimensional benchmarks used by the ABAW challenges — the right benchmarks for the deployment scenario, but harder to use without challenge access [9].
- **DAIC-WOZ** is the bridge to mental-health labels; the PHQ-8 score lets you evaluate whether an MER-derived feature correlates with clinical severity, not just with categorical emotion [12].

---

## 3. Architectural Taxonomy of Multimodal Emotion Recognition

The MER literature has converged on a five-way taxonomy. The cleanest way to think about a new system is to pick one approach per axis:

1. **Feature extractor per modality** (CNN / ViT / MAE for face; SSL encoder for audio; BERT/RoBERTa/LLM for text).
2. **Fusion strategy** (early / late / tensor / attention-based / subspace).
3. **Context modelling** (utterance-level / dialogue-level with RNN or graph).
4. **Loss / supervision** (categorical cross-entropy / VA regression / multi-task / self-supervised unimodal labels).
5. **Robustness layer** (missing-modality / noisy-modality handling).

The curated papers below are organised along this taxonomy. Per paper: venue, GitHub, problem solved, methodology, inputs/outputs, limitations, gap.

### 3.1 Tensor and Low-Rank Fusion (the 2017–2018 baseline family)

**Tensor Fusion Network (TFN)** — Zadeh et al., EMNLP 2017, Oral. Paper: arXiv:1707.07250; Code: github.com/hellozjj/TensorFusionNetwork [15].

- *Problem*: model the 3-way outer product between language, audio, and visual embeddings to capture unimodal, bimodal, and trimodal interactions.
- *Method*: 3-fold Cartesian product of modality embeddings (with a 1-augmented dimension) followed by a fully connected regressor. Trained end-to-end on CMU-MOSI.
- *Inputs/Outputs*: MOSI video clips → continuous sentiment score in [-3,+3] plus binary/5-class/7-class classification heads.
- *Limitations*: weight tensor scales exponentially with the number of modalities (3-fold Cartesian = O(dᵗ) parameters), heavy overfitting on small datasets, no mechanism for unaligned streams.
- *Gap addressed*: introduced explicit unimodal/bimodal/trimodal interaction modelling — the first clean formalism for fusion.

**Low-rank Multimodal Fusion (LMF)** — Liu et al., ACL 2018. Paper: aclanthology.org/P18-1209 [16].

- *Problem*: TFN is too expensive to scale beyond 3 modalities or large embedding dims.
- *Method*: factorises the TFN weight tensor into modality-specific low-rank factors; recovers the same interaction space at O(d) cost.
- *Limitation*: low-rank assumption can underfit high-order interactions; still requires pre-aligned modality embeddings.
- *Gap addressed*: brings the tensor-fusion family from research prototype to a usable training-time cost; ~1000× more efficient than TFN on MOSI.

**Multimodal Factorization Model (MFM)** — Tsai et al., ACL 2018. Cited in the LMF/DialogueRNN literature; predecessor to MulT for factorised learning of multimodal-discriminative and modality-specific generative factors.

### 3.2 Cross-Modal Transformer (MulT and descendants)

**Multimodal Transformer (MulT)** — Tsai et al., ACL 2019. Paper: arXiv:1906.00295; Code: github.com/yaohungt/Multimodal-Transformer [17].

- *Problem*: prior fusion assumes word-aligned streams; in practice language, audio, and video are sampled at different rates and not aligned.
- *Method*: each modality is encoded by a Transformer; then six directional pairwise cross-modal Transformers (one per ordered pair) attend from a target modality to a source modality's low-level features at every time step. Final per-modality representations feed a self-attention head.
- *Inputs/Outputs*: unaligned or aligned multimodal sequences; tested on CMU-MOSI (Acc-7 40.0, Acc-2 83.0), CMU-MOSEI (Acc-7 51.8, Acc-2 82.5), and IEMOCAP (weighted F1 ~84.8 across 6 classes).
- *Limitations*: 9 Transformers in total (3 self-attn + 6 cross-attn) is expensive; assumes all modalities are present (no missing-modality handling); gains over LMF/MFN are real but modest (~3–5%) on aligned MOSEI.
- *Gap addressed*: handles asynchronous streams, which matches the project's actual deployment (webcam frames vs. mic samples are not frame-aligned).

**MISA: Modality-Invariant and -Specific Representations** — Hazarika, Zimmermann, Poria, ACM MM 2020 (Oral). Paper: arXiv:2005.03545 [18].

- *Problem*: distribution gaps between modality embeddings cause simple concatenation to overfit one modality.
- *Method*: projects each modality into two subspaces — a *modality-invariant* subspace where text/audio/visual distributions are pulled together, and a *modality-specific* subspace where each modality's private signal is preserved. Four losses: similarity, orthogonal, reconstruction, task prediction.
- *Inputs/Outputs*: CMU-MOSI (Acc-2 83.4, MAE 0.783), CMU-MOSEI (Acc-2 85.5, MAE 0.555), UR_FUNNY (humour detection Acc-2 69.2).
- *Limitations*: subspace learning is sensitive to loss weighting; doesn't model temporal alignment (uses utterance-level features).
- *Gap addressed*: made "modality gap" an explicit objective rather than an emergent property.

**Self-MM: Self-Supervised Multi-Task Multimodal Sentiment Analysis** — Yu et al., AAAI 2021. Paper: ojs.aaai.org/AAAI/v35/12/17289; Code: github.com/thuiar/Self-MM [19].

- *Problem*: training MER/MSA models requires labelled multimodal data, but unimodal labels are expensive; existing methods treat multimodal labels as ground truth for unimodal subtasks.
- *Method*: a Unimodal Label Generation Module (ULGM) automatically generates unimodal pseudo-labels from the multimodal label and the current unimodal representations, using distance-to-class-centre offsets. Joint multi-task training of one multimodal task + three unimodal subtasks with a weight-adjustment strategy.
- *Inputs/Outputs*: CMU-MOSI (MAE 0.713, Corr 0.798, Acc-2 85.5), CMU-MOSEI (similar gains), SIMS (Chinese dataset, comparable to human-annotated unimodal labels).
- *Limitations*: pseudo-labels are inherently noisy; performance plateaus on harder benchmarks; relies on good unimodal representations to begin with.
- *Gap addressed*: removes the human-annotation bottleneck for unimodal subtasks, an early example of self-supervised multi-task learning that later inspired LLM-MER work.

**AVT-CA: Audio–Video Transformer with Cross-Attention** — arXiv:2407.18552, 2024 [20].

- *Problem*: existing AV-only systems struggle with temporal misalignment and weakly discriminative features.
- *Method*: hierarchical video encoder with channel + spatial attention; intermediate Transformer-based fusion; cross-attention module that selectively reinforces mutually consistent AV cues.
- *Inputs/Outputs*: CMU-MOSEI, RAVDESS, CREMA-D. Reports 96.11% accuracy and 93.78% F1 on RAVDESS, surpassing earlier AV baselines.
- *Limitations*: bimodal only (no text); relies on hand-tuned attention blocks.
- *Gap addressed*: shows that simple cross-attention, properly designed, can beat heavier pipelines on acted AV data.

**MemoCMT: Cross-Modal Transformer for Audio + Text** — Khan et al., *Scientific Reports* 2025. Paper: nature.com/articles/s41598-025-89202-x [21].

- *Problem*: bimodal A+T fusion underuses the long-range dependencies speech carries.
- *Method*: HuBERT for audio features, BERT for text, then a Cross-Modal Transformer (CMT) block that fuses them with min/max/mean aggregation variants.
- *Inputs/Outputs*: IEMOCAP (UW-Acc 81.33, W-Acc 81.85), ESD corpus.
- *Limitations*: tested only on bimodal A+T; generalisation to in-the-wild data is unverified.
- *Gap addressed*: lightweight, reproducible bimodal baseline that the project can use to isolate the contribution of the visual stream.

**HAEMSA: Hierarchical Adaptive Expert** — arXiv:2503.22715, 2025 [22].

- *Problem*: a single fusion architecture is rarely optimal for all modality availability / class combinations.
- *Method*: hierarchical mixture-of-experts with adaptive routing; each expert specialises on a sub-pattern (e.g., text-dominant, audio-dominant, all-modality).
- *Inputs/Outputs*: CMU-MOSEI (+2.6% Acc-7, −0.059 MAE over prior best), CMU-MOSI (+6.3% Acc-7), IEMOCAP (+2.84% wF1).
- *Limitations*: routing instability; higher training cost due to multiple experts.
- *Gap addressed*: gives the project a recipe for gracefully degrading when one modality (face, mic) is unavailable or low-quality.

**JOYFUL: Graph Contrastive Mid-Level Fusion** — *Information Fusion* / multimodal sentiment analysis, 2023. Cited in CMC survey [23].

- *Problem*: simple concatenation fuses too early; pure attention fuses too late.
- *Method*: mid-level (after unimodal encoding, before task-specific layers) graph contrastive alignment across audio, visual, and text embeddings.
- *Inputs/Outputs*: MELD (F1-macro 81.20%).
- *Limitations*: contrastive objectives need careful negative sampling.
- *Gap addressed*: shows that the "mid-level" position in the fusion pipeline is underexploited.

### 3.3 Conversational and Graph-Based MER

**DialogueGCN** — Ghosal et al., EMNLP-IJCNLP 2019. Code: github.com/declare-lab/conv-emotion (DialogueGCN branch) [14].

- *Problem*: prior ERC methods used RNNs with sequential context, which struggle with long dialogues and speaker-dependent context propagation.
- *Method*: build a graph where nodes are utterances and edges are (i) self-speaker, (ii) other-speaker, (iii) sequential. A relational GCN over the graph propagates context, then classifies each utterance.
- *Inputs/Outputs*: IEMOCAP (weighted F1 64.18, accuracy 65.25, 6-class), AVEC, SEMAINE.
- *Limitations*: text-only features; doesn't natively handle multimodal inputs (only the IEMOCAP text modality is used in the canonical setup).
- *Gap addressed*: replaces RNN-based context modelling with graph-based context modelling.

**COSMIC** — Ghosal et al., Findings of EMNLP 2020. Code: github.com/declare-lab/conv-emotion (COSMIC branch) [13].

- *Problem*: commonsense reasoning is missing from existing ERC models — context propagation alone doesn't explain *why* an emotion is inferred.
- *Method*: uses COMET (a BART-based commonsense transformer over the ATOMIC knowledge graph) to generate mental states, events, and causal relations for each utterance; these commonsense features are concatenated with RoBERTa utterance embeddings and fed to a GRU-based context model.
- *Inputs/Outputs*: IEMOCAP, MELD, DailyDialog, EmoryNLP. Achieved SOTA on all four at publication time.
- *Limitations*: depends on ATOMIC's coverage (limited to North-American English commonsense at the time); adds significant inference cost.
- *Gap addressed*: first ERC system to use external commonsense knowledge at training time.

**COGMEN: Contextualized GNN-based MER** — Joshi et al., 2022. Paper: arXiv:2205.02455 [24].

- *Problem*: capture both local (intra/inter-speaker) and global (long-range) dependencies in multimodal conversations.
- *Method*: GNN with GraphTransformer; uses modality-specific features (text/audio/visual) at each node, with relational GCN layers followed by a GraphTransformer.
- *Inputs/Outputs*: IEMOCAP (4-way +7.7% F1 over previous SOTA), CMU-MOSEI.
- *Limitations*: relies on pre-extracted features (FACET, COVAREP, GloVe); doesn't define its own end-to-end encoder.
- *Gap addressed*: shows the value of GraphTransformers over plain GCNs for multimodal dialogue.

**conER-GRL** — *Multimedia Systems* 2023 / 2024. arXiv:2310.18363 [25].

- *Problem*: real-time MER over streaming conversations.
- *Method*: GCN + reinforcement-learning agent; partitions the conversation into smaller groups of utterances for effective context extraction.
- *Inputs/Outputs*: IEMOCAP, +4.42% F1 over prior SOTA in the cited comparison.
- *Limitations*: RL training is unstable; evaluation only on IEMOCAP.
- *Gap addressed*: addresses the streaming/online inference setting that benchmark ERC papers usually ignore.

### 3.4 Hybrid-Attention and Bimodal Fusion

**MER-HAN: Multimodal Emotion Recognition based on Audio and Text by Hybrid Attention Networks** — Zhang et al., *Biomedical Signal Processing and Control* 2023 (vol. 85, 105052) [26].

- *Problem*: bimodal audio+text fusion is the most common MER sub-task; standard attention underuses temporal context.
- *Method*: Audio-Text Encoder (ATE) block with local intra-modal attention; Cross-Modal Attention (CMA) block for shared features; Multimodal Emotion Classification (MEC) block with global inter-modal attention.
- *Inputs/Outputs*: IEMOCAP, MELD; outperforms prior A+T baselines.
- *Limitations*: audio+text only; doesn't include the visual modality.
- *Gap addressed*: gives the project a clean bimodal baseline against which to measure the visual stream's marginal contribution.

### 3.5 Affective Behaviour in the Wild (ABAW) and Dimensional Emotion

The ABAW challenges (CVPR 2017–2025) and their predecessors at FG and ICCV are the closest existing analogue to the project's deployment: continuous webcam + mic, valence/arousal (continuous), basic expressions (categorical), action units, mimicry intensity.

**Aff-Wild / Aff-Wild2** — Kollias et al. The dataset used by ABAW 2–8. ~3M frames, 594 videos, in-the-wild [9].

**Hume-Vidmimic2** — Hume AI. ~75 hours, 2,222 subjects, 7 continuous emotional intensities. Used by ABAW 6's emotional mimicry intensity track [9].

**RJCMA: Recursive Joint Cross-Modal Attention** — Praveen & Alam, CVPR 2024 Workshop (ABAW 6), 2nd place in the VA challenge. Paper: openaccess.thecvf.com/CVPR2024W/ABAW; Code: github.com/praveena2j/RJCMA [27].

- *Problem*: capture both intra- and inter-modal relationships across audio, visual, and text for dimensional emotion recognition.
- *Method*: computes attention weights based on cross-correlation between a joint audio-visual-text feature representation and each individual modality's representation; recursively refines the joint representation.
- *Inputs/Outputs*: Aff-Wild2; CCC 0.585/0.674 for valence/arousal on validation (0.542/0.619 on test), 2nd place in ABAW6 VA.
- *Limitations*: only AVT triple; doesn't handle missing modalities.
- *Gap addressed*: demonstrates that recursive cross-attention can extract more nuanced dimensional affect than single-pass fusion.

**Joint Multimodal Transformer (JMT)** — Waligora et al., CVPR 2024 Workshop (ABAW 6). Paper: openaccess.thecvf.com/CVPR2024W/ABAW [28].

- *Method*: hierarchical fusion with transformer-based self-attention for intra-modal features and transformer-based cross-attention for cross-modal features; key-based cross-attention for inter-modality integration.
- *Inputs/Outputs*: BioVid (pain), Aff-Wild2 (VA).
- *Limitations*: depends on hand-designed key-attention modules.

**Improving VA Estimation with Spatiotemporal Relationship Learning and Multimodal Fusion** — Yu et al., CVPR 2024 Workshop (ABAW 6). Multimodal fusion approach with TCN-style spatiotemporal learning; CCC 0.5478 on the VA track using only visual+audio [29].

**Netease Fuxi AI Lab, ABAW6 winner** — total CCC 0.6721 on VA (V 0.6873, A 0.6569), 1st place [9].

**USTC-IAT-United, ABAW8 winner** — total CCC 0.600 on VA (V 0.577, A 0.623), 1st place [30].

The pattern: even at the top of ABAW, the dimensional CCC plateaus around **0.6–0.7** for the best systems, and the gap between top teams is <0.1 CCC. This is the most honest indicator of where the field actually is on in-the-wild dimensional emotion.

### 3.6 Robustness, Missing Modality, and Noise

**Analyzing Modality Robustness in Multimodal Sentiment Analysis** — Hazarika et al., NAACL 2022. Paper: aclanthology.org/2022.naacl-main.50 [31].

- *Problem*: are SOTA MSA models robust to missing or noisy modalities?
- *Method*: proposes two diagnostic checks (modality-drop, modality-noise) and finds that *language is highly sensitive* — removing or noising it causes catastrophic drops in 5 SOTA models (MulT, MISA, MAG-BERT, Self-MM, BBFN). Proposes modality-perturbation training as a regulariser.
- *Limitation*: focused on MSA benchmarks (MOSI/MOSEI), not MER.
- *Gap addressed*: quantified a previously unmeasured property of MER systems — the language modality's dominance and brittleness — and showed a simple training-time fix.

**M3S: Missing Modality meets Meta-Sampling** — AACL 2022. Paper: aclanthology.org/2022.aacl-main.10 [32].

- *Method*: MAML-style meta-sampling that augments training batches with random missing-modality patterns, so the model learns to handle any subset of modalities.
- *Inputs/Outputs*: CMU-MOSI / MOSEI; matches full-modality SOTA while tolerating missing modalities.

**MissModal** — TACL 2023. Paper: aclanthology.org/2023.tacl-1.94 [33].

- *Method*: geometric contrastive loss + distribution distance loss + sentiment semantic loss to align missing-modality and complete-modality representations.

**LNLN: Language-dominated Noise-resistant Learning Network** — NeurIPS 2024 [34].

- *Method*: dominant modality correction (DMC) + dominant modality based multimodal learning (DMML) to preserve language modality integrity under random missing data.
- *Inputs/Outputs*: MOSI, MOSEI, SIMS; outperforms prior missing-modality baselines under various missing rates.

These four papers form the canonical citation chain for missing-modality robustness and are the right ones to cite if the project's webcam branch occasionally fails (face out of frame) or the mic is muted.

---

## 4. Speech-Only Backbones the Multimodal Pipeline Reuses

For the audio branch, the field has converged on fine-tuned self-supervised speech encoders. They are technically "speech-only" but they appear in nearly every modern MER pipeline.

**Wav2Vec 2.0** — Baevski et al., NeurIPS 2020. SSL speech representation; the canonical English SER fine-tuning backbone. 95M–317M parameters depending on size [35].

**HuBERT** — Hsu et al., IEEE/ACM Trans. ASLP 2021. Clustering-based SSL; the most consistently strong SER backbone. Fine-tuned HuBERT-large achieves 88% accuracy on RAVDESS, 79.58% weighted accuracy on IEMOCAP (speaker-dependent), 73.01% (speaker-independent) [35].

**WavLM** — Chen et al., Microsoft / INTERSPEECH 2022. Adds pseudo-labelling on top of HuBERT-style SSL; stronger on noisy and multilingual data.

**Whisper** — Radford et al., OpenAI 2022. ASR-trained encoder that, surprisingly, often beats dedicated SSL encoders on cross-lingual SER (SER Evals benchmark, 2024) but is competitive on in-domain English SER. Whisper-medium reaches 85.4% accuracy on RAVDESS (faster training than Wav2Vec2/HuBERT) [36].

**MERT** — Li et al., 2023. Music + speech SSL; 330M parameters; used by the Emotion-LLaMA audio branch. On RAVDESS it sits between Wav2Vec2 and HuBERT [10].

The headline numbers from the SER Evals 2024 cross-lingual benchmark [36]:

| Model | In-Domain avg | Out-of-Domain avg |
|---|---|---|
| Whisper-Large-v2 | 0.782 | 0.194 |
| Whisper-Large-v3 | 0.777 | 0.193 |
| WavLM-Large | 0.765 | 0.161 |
| Hubert-Large | 0.733 | 0.157 |
| MERT-v1-330M | 0.708 | 0.127 |
| w2v-bert-2.0 | 0.668 | 0.141 |

Practical takeaway for the project: HuBERT-Large or WavLM-Large for in-domain English SER (RAVDESS, CREMA-D, IEMOCAP); Whisper-Large-v3 if cross-lingual generalisation or noise robustness matters more. The 2024 SER Evals paper is the strongest evidence that an ASR-trained model can match or beat dedicated SSL on SER when the evaluation is broad [36].

---

## 5. Facial-Only Backbones

**FER2013 baseline** — Goodfellow et al., 2013. The canonical CNN baseline; 7 classes, ~65–73% accuracy depending on protocol [1].

**AffectNet / Mollahosseini et al., IEEE Trans. Affective Computing 2019** — the most used in-the-wild facial affect benchmark; original AlexNet weighted-loss baseline reaches ~63% 8-class accuracy [2].

**FaceChannel** — Barros et al., FG 2020. Paper: doi.org/10.1109/FG47880.2020.00070; Code: github.com/pablovin/FaceChannel [37].

- *Problem*: deep FER models are heavy to train and adapt.
- *Method*: lightweight CNN (~2M parameters) based on a pruned VGG-16 with inhibitory layers. Supports both 8-class categorical and dimensional (VA) heads.
- *Inputs/Outputs*: AffectNet-8, OMG-Emotion, FER+, FABO. CCC 0.31/0.46 for valence/arousal after AffectNet pre-training + OMG-Emotion fine-tune.
- *Limitation*: lower accuracy than ViT-based methods on AffectNet-8 (~58% vs ~64%); designed for deployability, not SOTA.

**EfficientFace** — Zhao et al., AAAI 2021. Code: github.com/zengqunzhao/EfficientFace [38].

- *Method*: lightweight face recognition backbone + channel-spatial modulator + label distribution learning. AffectNet-7 accuracy 63.70%, RAF-DB 88.36%, CAER-S 85.87%.

**DDAMFN: Dual-Direction Attention Mixed Feature Network** — Zhang et al., *Electronics* 2023. Code: github.com/SainingZhang/DDAMFN (+ DDAMFN++ fork) [39].

- *Method*: Mixed Feature Network backbone + Dual-Direction Attention head (vertical and horizontal attention maps) + attention loss. AffectNet-8 64.25%, AffectNet-7 67.03%, RAF-DB 91.35%, FERPlus 90.74%.
- *Limitation*: static-image only.

**MAE-DFER: Efficient Masked Autoencoder for DFER** — Sun et al., ACM MM 2023. Code: github.com/sunlicai/MAE-DFER [40].

- *Method*: self-supervised masked autoencoder on abundant *unlabelled* facial videos; LGI-Former encoder (local-global interaction) reduces ~38% FLOPs vs VideoMAE while matching accuracy. +5–8% UAR on three in-the-wild DFER datasets vs supervised SOTA at the time.
- *Gap addressed*: shows that *unlabelled* facial video data can outperform labelled supervised pre-training for dynamic FER — directly relevant if the project wants to bootstrap from YouTube/screencap data.

**DFEW baseline (EC-STFL)** — Jiang et al., ACM MM 2020. Code: github.com/jiangxingxun/DFEW [3].

- *Method*: Expression-Clustered Spatiotemporal Feature Learning on DFEW; the original DFEW benchmark paper's proposed baseline.

**HiCMAE** — Sun et al., 2024 (cited in MAE-DFER follow-ups). Hierarchical Contrastive Masked Autoencoder for self-supervised audio-visual emotion recognition; pre-trains on large unlabelled AV corpora.

For the project, the practical facial-branch choice is:

- **Static-image facial expression**: DDAMFN++ or FaceChannel (AffectNet-8 backbone).
- **Dynamic (video) facial expression**: MAE-DFER if you have unlabelled video data; DFEW baseline otherwise.

---

## 6. Text-Only and LLM-Based MER

**GoEmotions** — Demszky et al., ACL 2020. 58K English Reddit comments, 27 emotions + neutral, multi-label. BERT-base F1 ~0.46. Code: github.com/google-research/google-research/tree/master/goemotions [41].

**COSMIC** (already covered above) and the wider ERC literature handle MELD text-only emotion recognition at ~65–67% wF1.

**Emotion-LLaMA** — Cheng et al., NeurIPS 2024. Paper: arXiv:2406.15161; Code: github.com/ZebangCheng/Emotion-LLaMA; MERR dataset released [10].

- *Problem*: existing MLLMs (GPT-4V, Video-ChatGPT, Valley) underperform on emotion *reasoning* — they classify correctly but don't justify it.
- *Method*: HuBERT (audio) + EVA/MAE/VideoMAE (visual multi-view) encoders; multimodal features projected into a LLaMA-2 token space; coarse-to-fine instruction tuning with two tasks — emotion classification and emotion reasoning. Trained on the MERR dataset (28,618 coarse + 4,487 fine samples).
- *Inputs/Outputs*: F1 0.9036 on MER2023-SEMI; F1 0.8452 on MER2024-NOISE; DFEW zero-shot UAR 45.59 / WAR 59.37; surpasses ChatGPT-4V by +4.37% on DFEW and +8.52% on MER2024-OV.
- *Limitations*: 7B LLaMA backbone; ~50–100ms inference per short clip on an A100; not real-time on commodity hardware.

**AffectGPT** — Lian et al., ICML 2025 (Oral). Paper: arXiv:2501.16566; Code: github.com/zeroQiaoba/AffectGPT [42].

- *Problem*: a unified MLLM-based emotion understanding benchmark and model.
- *Method*: pre-fusion operations (projectors before tokenisation) to integrate A/V/T into a 7B LLM; trained on MER-Caption (115K samples, 2K+ fine-grained emotion categories — the largest descriptive emotion dataset to date). Evaluated on MER-UniBench (fine-grained + basic emotion + sentiment).
- *Inputs/Outputs*: MER2023 (78.54%), MER2024 (78.80%), MELD (55.65%), IEMOCAP (60.54%), MOSI (81.30%), MOSEI (80.90%) with all three modalities (A+V+T). +9% over prior MLLMs.
- *Limitations*: same latency class as Emotion-LLaMA; depends on the quality of the model-generated pseudo-labels used to build MER-Caption.

**MERBench** — Lian et al., TPAMI 2026 (extended version of arXiv:2401.03429) [43].

- *Problem*: different MER papers use inconsistent feature extractors and evaluation protocols, making comparisons unreliable.
- *Method*: unified evaluation benchmark across multiple MER tasks; systematically varies feature selection, multimodal fusion, robustness, fine-tuning, and pre-training choices.
- *Why it matters*: the right place to look for fair, head-to-head numbers when choosing between MER methods.

---

## 7. Real-Time Multimodal MER and Mental-Health Deployment

The deployment-side literature is much thinner than the benchmark-side literature, which is itself the gap your project can claim.

**FILTWAM (Framework for Improving Learning Through Webcams And Microphones)** — Bahreini, Nadolski, Westera, *International Journal of Human-Computer Interaction* 2016 (and earlier 2014 Interactive Learning Environments paper) [44].

- *Problem*: real-time, continuous, unobtrusive emotion recognition for an e-learning communication-skills trainer using only a consumer webcam and microphone.
- *Method*: separate facial and voice emotion recognition modules; hybrid (decision-level) fusion. Facial module: face detection → facial feature extraction → SMO classifier on Ekman-6 emotions. Voice module: microphone → vocal feature extraction → SMO classifier.
- *Inputs/Outputs*: 6 basic emotions (Ekman); accuracy 72% (face), 67% (voice), 98.6% (combined hybrid). Real-time on consumer hardware.
- *Limitation*: only Ekman-6; no dimensional affect; no learning of modality weights.

**DAIC-WOZ depression-detection papers** — multiple, including Stepanov et al. (multimodal PHQ-8 regression), SpeechFormer++ (Chen 2023), DALF (2023), MSCDR (2022), MFDCL (2024), Qwen2-Audio-based LLM (2025). All use the same corpus: 189 semi-clinical interviews, PHQ-8 labels at threshold 10. Reported F1 ranges 0.69–0.95 depending on modality and architecture [12][45].

**Smart Mirror for Emotion Monitoring** — Bianco et al., *Sensors* 2021. Real-time smart mirror combining facial affect (AffectNet-trained ResNet-50) and voice, plus Alexa integration [46].

**AI-Enabled Smart Mirror with MA-rPPG, Facial Affect, and GPT-4o** — Kasno & Jung, *Sensors* 2025, 25(18), 5831 [47].

- *Problem*: feasibility-stage integration of facial affect (DeepFace), remote photoplethysmography (MA-rPPG), and GPT-4o-based mental-health chatbot on a smart mirror.
- *Method*: two Flask microservices — one for rPPG and facial attributes, one for ASR → GPT-4o prompt generation → TTS synthesis.
- *Limitation*: single-subject validation; explicitly *not* a clinical diagnostic tool.

**Real-Time Multimodal AI for Continuous Mental Health Monitoring** — Amate, Master's thesis, National College of Ireland 2025 [48].

- *Method*: MobileNet-v2 (MELD-trained) + CNN-BiLSTM (RAVDESS-trained, 86.5% val acc on 8 classes) + MediaPipe FaceMesh blink/fatigue detection + transformer-based text pipeline.
- *Contribution*: documents the latency, hardware, and engineering tradeoffs for real-time multimodal MER on commodity hardware.

**A Multimodal Emotion Recognition System: Integrating Facial Expressions, Speech, Spoken Language, and Body Movement** — arXiv:2412.17907, 2024 [49].

- *Method*: integrates FER (Dlib face detector + frame-queue stabilisation), speech emotion recognition, spoken-language understanding (NLP), and body-movement analysis (MediaPipe pose); real-time on a webcam instance.
- *Reports*: 96.43% overall accuracy (their own evaluation).
- *Limitations*: dataset is private / not specified; unclear how "real-time" is measured.

The pattern: every paper that builds a *real* webcam+mic MER system reports >85% accuracy on its private evaluation, but **none of them report against a public benchmark, none validate against clinical labels, and none characterise latency under realistic conditions**. This is the gap.

---

## 8. Cross-Cutting Limitations and Open Gaps

The following are the limitations that recur across the curated papers, organised by axis. Each one is a potential contribution the project can claim.

**Acting vs in-the-wild.** RAVDESS, CREMA-D, IEMOCAP are all acted — actors are paid to express specific emotions. Real users don't behave like actors. The gap between acted-data accuracy (often >90% on RAVDESS) and in-the-wild accuracy on Aff-Wild2 / ABAW (CCC ~0.6, F1 ~50–60% on basic 7-class) is large and well-documented. *What this means*: any system that reports >85% accuracy on RAVDESS or CREMA-D without an in-the-wild evaluation is essentially telling you about a lab artefact.

**Class imbalance.** MELD (~50% neutral), AffectNet (~58% happy + neutral), IEMOCAP (varies), and ABAW (extreme skew toward neutral and positive valence) all have majority-class bias. Models that report accuracy without macro-F1 or weighted-F1 will look better than they are. *What this means*: design with class-weighted loss or focal loss as the default; report both accuracy and macro-F1.

**Modality robustness / missing modality.** NAACL 2022 Hazarika et al. showed that SOTA MSA models are catastrophically brittle when the language modality is removed or noised [31]. The same almost certainly holds for the project's facial and speech branches. *What this means*: train with modality-perturbation or meta-sampling augmentation; evaluate explicitly with missing-modality diagnostic checks (drop one modality at test time, report the drop).

**Asynchrony and segmentation.** Benchmarks assume word-aligned or pre-segmented utterances. A real webcam+mic stream needs: (i) Voice Activity Detection (VAD) for segmentation, (ii) face detection/tracking to decide whether a face is present in a window, (iii) re-alignment of frame-level features to utterance-level features. MulT handles (iii) at training time but assumes (i) and (ii) are solved [17]. *What this means*: the project needs an explicit segmentation/aggregation module, which is itself a contribution-worthy sub-system.

**Real-time latency.** Modern transformer-based fusion (MulT, MISA, Self-MM) and especially LLM-based fusion (Emotion-LLaMA, AffectGPT) are not real-time on consumer hardware. The deployment evidence is thin: the FILTWAM 2016 paper is still the cleanest webcam+mic system in the literature, and it uses pre-deep-learning features. *What this means*: a system that runs end-to-end at ≤500 ms per utterance on a mid-range laptop or phone is itself a non-trivial contribution.

**Clinical validation.** DAIC-WOZ is the closest bridge to clinical labels, and the multimodal LLM for depression detection paper (2025) is the most recent step in that direction. But the gap between "categorical emotion" and "depression severity" is not closed — no MER paper has demonstrated that mapping *emotion category trajectories over time* to PHQ-9/GAD-7 scores works at clinical-grade accuracy on a held-out population. *What this means*: this is the project's largest open opportunity.

**Cultural and demographic bias.** AffectNet's labels are noisy and its demographic distribution skews toward certain ages and ethnicities (the 2017 paper itself reports ~60.7% inter-annotator agreement). ABAW's continuous labels are even more subjective. *What this means*: if the system is deployed in a real-world mental-health context, demographic stratification is a research question of its own.

**English-only.** This is a constraint imposed by the project, not a limitation — but it means MER2023 (Chinese) is not a direct evaluation, and the user should not expect to reproduce Chinese MLLM numbers.

**Labelling cost.** MERR and AffectNet were both built with non-trivial annotation budgets. For a student project, the realistic choice is to train on existing public datasets (AffectNet + RAVDESS/CREMA-D for unimodal, IEMOCAP/MELD/DFEW for multimodal) and only collect a small custom dataset for *validation* under your deployment conditions. The recent shift toward self-supervised pretraining (MAE-DFER, MAE-DFER variants, HuBERT) reduces the labelling cost of any future extension.

---

## 9. Implications for the Project

A defensible research question for this system design, derived from the gaps above, is:

> *Can a real-time, in-the-wild multimodal emotion recognition system that fuses facial, vocal, and (optional) textual cues match or exceed the categorical-emotion accuracy of state-of-the-art benchmark models (e.g., MulT on IEMOCAP, MAE-DFER on DFEW) when deployed on a consumer webcam and microphone, while remaining robust to missing modalities and aligning its output with a continuous mental-health-relevant scale (valence-arousal, or longer-term PHQ-style severity proxies)?*

The literature review supports the following concrete design choices, listed as baseline + extension + claimed contribution.

**Visual branch (baseline).** DDAMFN++ (Electronics 2023, AffectNet-8 64.25%) for static FER; MAE-DFER (ACM MM 2023) for dynamic facial video if unlabelled video data is available. Pre-train on AffectNet, fine-tune on DFEW for in-the-wild generalisation.

**Audio branch (baseline).** HuBERT-Large fine-tuned on RAVDESS (88% accuracy) or CREMA-D; Whisper-Large-v3 if cross-lingual or noisy-environment robustness is required. The 2024 SER Evals paper supports either choice.

**Text branch (optional, baseline).** RoBERTa fine-tuned on MELD text-only; or, for finer granularity, BERT-base on GoEmotions (F1 ~0.46 baseline — a deliberately modest number that motivates a custom fine-tune).

**Fusion module (baseline).** MISA (ACM MM 2020) as the strongest utterance-level fusion baseline; or MulT (ACL 2019) if alignment-free behaviour matters more than training cost.

**Robustness layer (extension).** Modality-perturbation training from NAACL 2022 [31] combined with M3S-style meta-sampling for missing-modality tolerance.

**Deployment and evaluation (claimed contribution).** Real-time inference on consumer hardware, validated against (a) a held-out test partition of an in-the-wild benchmark (DFEW, ABAW validation), and (b) a small custom dataset collected in the project's deployment conditions. Report macro-F1, weighted-F1, CCC for VA, and latency per utterance.

**LLM-based post-processing (optional).** Offline, end-of-session, use Emotion-LLaMA (NeurIPS 2024) or AffectGPT (ICML 2025) to summarise the session's emotion trajectory into natural-language explanations. Do *not* use them on the real-time path — latency is prohibitive.

**Mental-health bridge (longer-term contribution).** Once the real-time system has produced emotion trajectories over time, train a downstream regression model (PHQ-9 / GAD-7 style continuous severity) using a small labelled study. This is the path the 2025 multimodal LLM for depression detection paper is exploring on DAIC-WOZ [45]; the project can do the same on its own data.

---

## References

[1] Goodfellow, I. J., et al. (2013). *FER2013 dataset*. Kaggle. https://www.kaggle.com/datasets/msambare/fer2013

[2] Mollahosseini, A., Hasani, B., & Mahoor, M. H. (2017/2019). *AffectNet: A Database for Facial Expression, Valence, and Arousal Computing in the Wild*. IEEE Trans. Affective Computing. https://arxiv.org/abs/1708.03985

[3] Jiang, X., Zong, Y., Zheng, W., Tang, C., Xia, W., Lu, C., & Liu, J. (2020). *DFEW: A Large-Scale Database for Recognizing Dynamic Facial Expressions in the Wild*. ACM MM 2020. https://dfew-dataset.github.io/

[4] Busso, C., et al. (2008). *IEMOCAP: Interactive Emotional Dyadic Motion Capture Database*. Language Resources and Evaluation, 42(4). https://sail.usc.edu/iemocap/

[5] Poria, S., Hazarika, D., Majumder, N., Naik, G., Cambria, E., & Mihalcea, R. (2019). *MELD: A Multimodal Multi-Party Dataset for Emotion Recognition in Conversations*. ACL 2019. https://affective-meld.github.io/

[6] Zadeh, A., et al. (2018). *CMU-MOSEI: Dataset and Interpretable Dynamic Fusion Graph*. ACL 2018. https://github.com/CMU-MultiComp-Lab/CMU-MultimodalSDK

[7] Livingstone, S. R., & Russo, F. A. (2018). *RAVDESS: A dynamic, multimodal set of facial and vocal expressions in North American English*. PLoS ONE 13(5): e0196391. https://doi.org/10.5281/zenodo.1188976

[8] Cao, H., et al. (2014). *CREMA-D: Crowd-Sourced Emotional Multimodal Actors Dataset*. IEEE Trans. Affective Computing. https://github.com/CheyneyComputerScience/CREMA-D

[9] Kollias, D., et al. (2024). *The 6th Affective Behavior Analysis in-the-wild (ABAW) Competition*. CVPR 2024 Workshop. https://affective-behavior-analysis-in-the-wild.github.io/6th/

[10] Cheng, Z., et al. (2024). *Emotion-LLaMA: Multimodal Emotion Recognition and Reasoning with Instruction Tuning*. NeurIPS 2024. https://github.com/ZebangCheng/Emotion-LLaMA

[11] Lian, Z., et al. (2024). *MER 2024: Semi-Supervised Learning, Noise Robustness, and Open-Vocabulary Multimodal Emotion Recognition*. MRAC 2024. https://github.com/zeroQiaoba/MERTools/tree/master/MER2024

[12] Gratch, J., et al. (2014). *The Distress Analysis Interview Corpus (DAIC-WOZ)*. https://dcapswoz.ict.usC.edu/

[13] Ghosal, D., Majumder, N., Gelbukh, A., Mihalcea, R., & Poria, S. (2020). *COSMIC: COmmonSense knowledge for eMotion Identification in Conversations*. Findings of EMNLP 2020. https://github.com/declare-lab/conv-emotion

[14] Ghosal, D., Majumder, N., Poria, S., Chhaya, N., & Gelbukh, A. (2019). *DialogueGCN: A Graph Convolutional Neural Network for Emotion Recognition in Conversation*. EMNLP-IJCNLP 2019. https://github.com/declare-lab/conv-emotion

[15] Zadeh, A., Chen, M., Poria, S., Cambria, E., & Morency, L.-P. (2017). *Tensor Fusion Network for Multimodal Sentiment Analysis*. EMNLP 2017. https://github.com/hellozjj/TensorFusionNetwork

[16] Liu, Z., et al. (2018). *Efficient Low-rank Multimodal Fusion with Modality-Specific Factors*. ACL 2018. https://aclanthology.org/P18-1209.pdf

[17] Tsai, Y.-H. H., Bai, S., Liang, P. P., Kolter, J. Z., Morency, L.-P., & Salakhutdinov, R. (2019). *Multimodal Transformer for Unaligned Multimodal Language Sequences (MulT)*. ACL 2019. https://github.com/yaohungt/Multimodal-Transformer

[18] Hazarika, D., Zimmermann, R., & Poria, S. (2020). *MISA: Modality-Invariant and -Specific Representations for Multimodal Sentiment Analysis*. ACM MM 2020 (Oral). https://arxiv.org/abs/2005.03545

[19] Yu, W., Xu, H., Yuan, Z., & Wu, J. (2021). *Learning Modality-Specific Representations with Self-Supervised Multi-Task Learning for Multimodal Sentiment Analysis*. AAAI 2021. https://github.com/thuiar/Self-MM

[20] Anonymous. (2024). *Multimodal Emotion Recognition using Audio-Video Transformer Fusion with Cross Attention (AVT-CA)*. arXiv:2407.18552.

[21] Khan, M., Tran, P. N., & Pham, N. T. (2025). *MemoCMT: multimodal emotion recognition using cross-modal transformer-based feature fusion*. Scientific Reports 15, 5473.

[22] Anonymous. (2025). *Hierarchical Adaptive Expert for Multimodal Sentiment Analysis (HAEMSA)*. arXiv:2503.22715.

[23] Lian, Z., Sun, L., Ren, H., Gu, H., Sun, L., Chen, L., Liu, B., & Tao, J. (2023). *Multimodal Emotion Recognition based on Audio and Text by Using Hybrid Attention Networks (MER-HAN)*. Biomedical Signal Processing and Control, 85, 105052.

[24] Joshi, A., et al. (2022). *COGMEN: COntextualized GNN based Multimodal Emotion recognitioN*. arXiv:2205.02455.

[25] Anonymous. (2023). *A Contextualized Real-Time Multimodal Emotion Recognition for Conversational Agents using Graph Convolutional Networks in Reinforcement Learning (conER-GRL)*. arXiv:2310.18363.

[26] Zhang, S., Yang, Y., Chen, C., Liu, R., Tao, X., Guo, W., Xu, Y., & Zhao, X. (2023). *Multimodal Emotion Recognition based on Audio and Text by Using Hybrid Attention Networks (MER-HAN)*. Biomedical Signal Processing and Control, 85, 105052.

[27] Praveen, R. G., & Alam, J. (2024). *Recursive Joint Cross-Modal Attention for Multimodal Fusion in Dimensional Emotion Recognition (RJCMA)*. CVPR 2024 Workshop (ABAW 6), 2nd place. https://github.com/praveena2j/RJCMA

[28] Waligora, T., et al. (2024). *Joint Multimodal Transformer for Emotion Recognition in the Wild (JMT)*. CVPR 2024 Workshop (ABAW 6).

[29] Yu, et al. (2024). *Improving Valence-Arousal Estimation with Spatiotemporal Relationship Learning and Multimodal Fusion*. CVPR 2024 Workshop (ABAW 6).

[30] Kollias, D., et al. (2025). *The 8th Affective & Behavior Analysis in-the-Wild (ABAW) Workshop at CVPR 2025*. https://affective-behavior-analysis-in-the-wild.github.io/8th/

[31] Hazarika, D., Li, Y., Cheng, B., Zhao, S., Zimmermann, R., & Poria, S. (2022). *Analyzing Modality Robustness in Multimodal Sentiment Analysis*. NAACL 2022. https://aclanthology.org/2022.naacl-main.50.pdf

[32] Anonymous. (2022). *Missing Modality meets Meta Sampling (M3S): An Efficient Universal Approach for Multimodal Sentiment Analysis with Missing Modality*. AACL 2022.

[33] Wang, H., et al. (2023). *Increasing Robustness to Missing Modality in Multimodal Sentiment Analysis (MissModal)*. TACL 2023.

[34] Anonymous. (2024). *Towards Robust Multimodal Sentiment Analysis with Incomplete Data (LNLN)*. NeurIPS 2024.

[35] Wang, Y., et al. (2021). *A Fine-tuned Wav2vec 2.0/HuBERT Benchmark For Speech Emotion Recognition, Speaker Verification and Spoken Language Understanding*. arXiv:2111.02735.

[36] Anonymous. (2024). *SER Evals: In-domain and Out-of-domain Benchmarking for Speech Emotion Recognition*. arXiv:2408.07851.

[37] Barros, P., Churamani, N., & Sciutti, A. (2020). *The FaceChannel: A Light-weight Deep Neural Network for Facial Expression Recognition*. FG 2020. https://github.com/pablovin/FaceChannel

[38] Zhao, Z., et al. (2021). *EfficientFace: Robust Lightweight Facial Expression Recognition Network*. AAAI 2021. https://github.com/zengqunzhao/EfficientFace

[39] Zhang, S., Wang, Y., Zhang, Y., & Zhang, S. (2023). *A Dual-Direction Attention Mixed Feature Network for Facial Expression Recognition (DDAMFN)*. Electronics 12(17), 3595. https://github.com/SainingZhang/DDAMFN

[40] Sun, L., Lian, Z., Liu, B., & Tao, J. (2023). *MAE-DFER: Efficient Masked Autoencoder for Self-supervised Dynamic Facial Expression Recognition*. ACM MM 2023. https://github.com/sunlicai/MAE-DFER

[41] Demszky, D., Movshovitz-Attias, D., Ko, J., Cowen, A., Nemade, G., & Ravi, S. (2020). *GoEmotions: A Dataset of Fine-Grained Emotions*. ACL 2020. https://github.com/google-research/google-research/tree/master/goemotions

[42] Lian, Z., et al. (2025). *AffectGPT: A New Dataset, Model, and Benchmark for Emotion Understanding with Multimodal Large Language Models*. ICML 2025 (Oral). https://github.com/zeroQiaoba/AffectGPT

[43] Lian, Z., Sun, L., Ren, Y., Gu, H., Sun, H., Chen, L., Liu, B., & Tao, J. (2026). *MERBench: A Unified Evaluation Benchmark for Multimodal Emotion Recognition*. IEEE TPAMI 48, 5793–5810 (extended version of arXiv:2401.03429).

[44] Bahreini, K., Nadolski, R., & Westera, W. (2016). *Data Fusion for Real-time Multimodal Emotion Recognition through Webcams and Microphones in E-Learning (FILTWAM)*. International Journal of Human-Computer Interaction.

[45] Anonymous. (2025). *Multi-Modal LLM for Depression Detection By Integrating Audio, Visual and Textual Features*. arXiv:2511.19877.

[46] Bianco, S., Celona, L., Ciocca, G., Marelli, D., Napoletano, P., Yu, S., & Schettini, R. (2021). *A Smart Mirror for Emotion Monitoring in Home Environments*. Sensors 21(22), 7453.

[47] Kasno, M. A., & Jung, J.-W. (2025). *Feasibility of an AI-Enabled Smart Mirror Integrating MA-rPPG, Facial Affect, and Conversational Guidance in Realtime*. Sensors 25(18), 5831. https://doi.org/10.3390/s25185831

[48] Amate, R. R. (2025). *Real-Time Multimodal AI for Continuous Mental Health Monitoring*. Master's thesis, National College of Ireland. https://norma.ncirl.ie/9494/

[49] Anonymous. (2024). *A Multimodal Emotion Recognition System: Integrating Facial Expressions, Speech, Spoken Language, and Body Movement Analysis*. arXiv:2412.17907.

---

The literature review is complete. If you'd like to go deeper on any specific area — for example, picking a baseline architecture for your project, or mapping out the experimental design that would close the "deployment + clinical validation" gap — just say the word and we can pick that up next.
