# Tier 1 Shortlisted Papers: In-Depth Architecture & Technical Explanations
## Multimodal Emotion Recognition for Mental Health Monitoring

**Project Title:** AI-Based Mental Health Emotion Monitoring from Facial and Voice Features Using Multimodal Artificial Intelligence  
**Document Type:** Technical Paper Deconstructions & Comparative Engineering Guide  
**Source Catalog:** Tier 1 Must-Read / Must-Use Papers from `MLDLC_Plan_and_Curated_Papers.md`  
**Date:** September 2026  

---

## Executive Summary & Reading Guide

This document provides an exhaustive, engineering-level breakdown of the **Tier 1 (Must-Cite / Must-Use)** papers identified in our Machine Learning Development Lifecycle (MLDLC) literature review. 

The document is organized into three distinct parts:
1. **Part I: Deep Architectural Deconstructions (Papers 1 to 8):** For the primary core papers (Indices 1–8), this guide breaks down the precise mathematical mechanisms, input/output tensors, internal architectural blocks, loss formulations, training recipes, real-world failure gaps, and explicit links to our project requirements.
2. **Part II: Core Technical Overviews (Papers 9 to 20):** For the remaining Tier 1 papers (Indices 9–20), structured summaries distill the exact inputs, outputs, core innovations, research questions, and specific utility for our pipeline.
3. **Part III: Comparative Synthesis Matrix & System Integration:** A side-by-side engineering comparison contrasting the core architectures across fusion paradigms, temporal handling, missing-modality tolerance, computational footprint, and clinical mental health applicability.

---

## Table of Contents

- [Part I: Deep Architectural Deconstructions (Papers 1 to 8)](#part-i-deep-architectural-deconstructions-papers-1-to-8)
  - [1. MulT: Multimodal Transformer for Unaligned Multimodal Language Sequences](#1-mult-multimodal-transformer-for-unaligned-multimodal-language-sequences)
  - [2. M3ER: Multiplicative Multimodal Emotion Recognition Using Facial, Textual, and Speech Cues](#2-m3er-multiplicative-multimodal-emotion-recognition-using-facial-textual-and-speech-cues)
  - [3. MISA: Modality-Invariant and -Specific Representations for Multimodal Sentiment Analysis](#3-misa-modality-invariant-and--specific-representations-for-multimodal-sentiment-analysis)
  - [4. Self-MM: Learning Modality-Specific Representations with Self-Supervised Multi-Task Learning](#4-self-mm-learning-modality-specific-representations-with-self-supervised-multi-task-learning)
  - [5. UniMSE: Towards Unified Multimodal Sentiment Analysis and Emotion Recognition](#5-unimse-towards-unified-multimodal-sentiment-analysis-and-emotion-recognition)
  - [6. DialogueRNN: An Attentive RNN for Emotion Detection in Conversation](#6-dialoguernn-an-attentive-rnn-for-emotion-detection-in-conversation)
  - [7. Emotion-LLaMA: Multimodal Emotion Recognition and Reasoning with Instruction Tuning](#7-emotion-llama-multimodal-emotion-recognition-and-reasoning-with-instruction-tuning)
  - [8. AffectGPT: A New Dataset, Model, and Benchmark for Multimodal Emotion Understanding](#8-affectgpt-a-new-dataset-model-and-benchmark-for-multimodal-emotion-understanding)
- [Part II: Core Technical Overviews (Papers 9 to 20)](#part-ii-core-technical-overviews-papers-9-to-20)
  - [9. MERBench: Unified Benchmark & Toolkit for MER in the Wild](#9-merbench-unified-benchmark--toolkit-for-mer-in-the-wild)
  - [10. KAMUH: Real-Time Online Audiovisual Emotion Recognition System](#10-kamuh-real-time-online-audiovisual-emotion-recognition-system)
  - [11. Wav2Vec 2.0: Self-Supervised Learning of Speech Representations](#11-wav2vec-20-self-supervised-learning-of-speech-representations)
  - [12. HuBERT: Hidden-Unit BERT for Speech Processing](#12-hubert-hidden-unit-bert-for-speech-processing)
  - [13. Whisper: Robust Speech Recognition via Large-Scale Weak Supervision](#13-whisper-robust-speech-recognition-via-large-scale-weak-supervision)
  - [14. POSTER++: Simpler & Stronger Facial Expression Recognition Network](#14-poster-simpler--stronger-facial-expression-recognition-network)
  - [15. MMIN: Missing Modality Imagination Network for Incomplete Audio-Visual Data](#15-mmin-missing-modality-imagination-network-for-incomplete-audio-visual-data)
  - [16. MER-Calibration: Multimodal Emotion Recognition Calibration in Conversations](#16-mer-calibration-multimodal-emotion-recognition-calibration-in-conversations)
  - [17. DAIC-WOZ: The Distress Analysis Interview Corpus](#17-daic-woz-the-distress-analysis-interview-corpus)
  - [18. Mental-Health-Distress-Review: Systematic Review on Multimodal Distress Detection](#18-mental-health-distress-review-systematic-review-on-multimodal-distress-detection)
  - [19. MER-Mega-Survey-2026: Comprehensive Survey on Multimodal Emotion Recognition](#19-mer-mega-survey-2026-comprehensive-survey-on-multimodal-emotion-recognition)
  - [20. SER-Mega-Review-2026: Comprehensive Survey of Modern Speech Emotion Architectures](#20-ser-mega-review-2026-comprehensive-survey-of-modern-speech-emotion-architectures)
- [Part III: Comparative Synthesis Matrix & System Blueprint](#part-iii-comparative-synthesis-matrix--system-blueprint)

---

## Part I: Deep Architectural Deconstructions (Papers 1 to 8)

### 1. MulT: Multimodal Transformer for Unaligned Multimodal Language Sequences

* **Full Citation:** Yao-Hung Hubert Tsai, Shaojie Bai, Paul Pu Liang, J. Zico Kolter, Louis-Philippe Morency, and Ruslan Salakhutdinov. *"Multimodal Transformer for Unaligned Multimodal Language Sequences."* In **Proceedings of the 57th Annual Meeting of the Association for Computational Linguistics (ACL 2019)**, pages 6558–6569.
* **Paper Link:** [arXiv:1906.00295](https://arxiv.org/abs/1906.00295) | [Direct PDF](https://arxiv.org/pdf/1906.00295.pdf)
* **Official Code Repository:** [GitHub - yaohungt/Multimodal-Transformer](https://github.com/yaohungt/Multimodal-Transformer)

#### 1.1 Research Question Answered
> *How can an end-to-end deep learning architecture directly model complex, bidirectional cross-modal interactions across unaligned text, visual, and acoustic streams operating at disparate temporal frequencies, without requiring monotonic word-level forced alignment or manual feature resampling?*

#### 1.2 Plain-Language Explanation (What It Aims To Do)
In natural human communication, our modalities do not emit signals on the same clock. A webcam captures video frames at 30 frames per second (fps), audio processors compute spectrogram frames at 50 Hz or 100 Hz, and words in speech are spoken at irregular phonetic intervals. Prior to MulT, almost all multimodal models relied on external "forced aligners" (such as P2FA) to artificially slice video and audio frames into rigid word intervals. This artificial alignment discarded non-verbal pauses, broke down during disfluencies, and caused catastrophic information loss when word boundaries were imperfect.

MulT eliminates forced alignment entirely. It introduces an architecture where every modality sequence is preserved in its native sampling rate. It allows one modality (e.g., spoken language) to continuously "look over" at another modality (e.g., facial video or voice tone) across time and pull in relevant contextual cues. For example, if an utterance contains the ambiguous phrase *"Oh, fantastic,"* the language stream directly queries the video sequence; detecting a furrowed brow or a sneer in the visual stream re-weights the text tokens toward a sarcastic, negative sentiment.

#### 1.3 Exact Inputs & Outputs
* **Inputs:** Three unaligned temporal feature matrices:
  1. **Language ($X_L$):** $X_L \in \mathbb{R}^{T_L \times d_L}$, where $T_L$ is the number of text tokens (words), and $d_L$ is the word embedding dimension (e.g., 300 for GloVe or 768 for BERT).
  2. **Audio ($X_A$):** $X_A \in \mathbb{R}^{T_A \times d_A}$, where $T_A$ is the number of acoustic frames (extracted via COVAREP or openSMILE at ~50 Hz, meaning $T_A \gg T_L$), and $d_A$ is the acoustic feature dimension (e.g., 74 or 88 eGeMAPS parameters).
  3. **Visual ($X_V$):** $X_V \in \mathbb{R}^{T_V \times d_V}$, where $T_V$ is the number of video frames (extracted via Facet/OpenFace at ~30 Hz, meaning $T_V \neq T_A \neq T_L$), and $d_V$ is the visual feature dimension (e.g., 35 facial action units + head pose).
* **Outputs:**
  * **Continuous Regression:** Continuous affective intensity score $\hat{y} \in \mathbb{R}$ (e.g., sentiment on $[-3, +3]$ for CMU-MOSEI).
  * **Categorical Classification:** Probability distribution over emotional classes $\hat{y} \in \Delta^{C-1}$ (e.g., Happy, Sad, Angry, Fearful, Neutral).

#### 1.4 Approach & Internal Mechanics (How It Works Under the Hood)
MulT operates through a four-stage sequential pipeline:

```
[Raw Modalities]        [1D Temporal Conv]      [Cross-Modal Attention (CMA)]        [Self-Attention & Fusion]
  X_L (T_L x d_L) ----> Conv1D -> H_L (T_L x d) ---> V->L Cross-Transformer (T_L x d) --\
                                               ---> A->L Cross-Transformer (T_L x d) ----+-> Concatenate [H_L; H_V; H_A]
  X_V (T_V x d_V) ----> Conv1D -> H_V (T_V x d) ---> L->V Cross-Transformer (T_V x d) --|       (Sequence Length T_m)
                                               ---> A->V Cross-Transformer (T_V x d) --+--> Self-Attention Transformer
  X_A (T_A x d_A) ----> Conv1D -> H_A (T_A x d) ---> L->A Cross-Transformer (T_A x d) --|       (Temporal Pooling)
                                               ---> V->A Cross-Transformer (T_A x d) --/            |
                                                                                                    v
                                                                                           Linear Prediction Head
```

##### Step 1: 1D Temporal Convolutions for Common Dimensionality
Because $d_L, d_A,$ and $d_V$ differ, MulT first applies a 1D temporal convolution with kernel size $k_m$ to project each modality into a shared hidden dimension $d$ while capturing local temporal neighborhoods:
$$\hat{X}_m = \text{Conv1D}(X_m, k_m) \in \mathbb{R}^{T_m \times d}, \quad \forall m \in \{L, V, A\}$$
To preserve temporal order without recurrent recurrence, 1D sinusoidal positional embeddings are added:
$$H_m = \hat{X}_m + \text{PositionalEncoding}(T_m, d)$$

##### Step 2: Directional Cross-Modal Attention Blocks (CMA)
The central breakthrough of MulT is **Directional Cross-Modal Attention**. For any pair of modalities—a target modality $\alpha$ and a source modality $\beta$ (denoted $\beta \to \alpha$)—the target modality $\alpha$ serves as the **Query ($Q$)**, while the source modality $\beta$ serves as the **Key ($K$)** and **Value ($V$)**:
$$Q_\alpha = H_\alpha W_{Q}, \quad K_\beta = H_\beta W_{K}, \quad V_\beta = H_\beta W_{V}$$
where $W_Q, W_K, W_V \in \mathbb{R}^{d \times d}$. The cross-attention weights are computed via scaled dot-product:
$$\text{Attention}_{\beta \to \alpha} = \text{softmax}\left(\frac{Q_\alpha K_\beta^T}{\sqrt{d_k}}\right) \in \mathbb{R}^{T_\alpha \times T_\beta}$$
$$\text{CMA}_{\beta \to \alpha} = \text{Attention}_{\beta \to \alpha} V_\beta \in \mathbb{R}^{T_\alpha \times d}$$

**Crucial Mathematical Insight:** Notice the output dimension of $\text{CMA}_{\beta \to \alpha}$ is $T_\alpha \times d$. The sequence length is dictated entirely by the **Query modality $\alpha$**! The cross-attention matrix $\mathbb{R}^{T_\alpha \times T_\beta}$ effectively maps and interpolates features from the time base of $\beta$ onto the time base of $\alpha$.

##### Step 3: Multi-Layer Cross-Modal Transformers
This cross-attention is wrapped in a multi-head transformer block containing Layer Normalization ($\text{LN}$) and Position-wise Feed-Forward Networks ($\text{FFN}$):
$$Z_{\beta \to \alpha}^{(1)} = \text{LN}\left(H_\alpha + \text{MultiHeadCMA}_{\beta \to \alpha}(H_\alpha, H_\beta)\right)$$
$$H_{\beta \to \alpha} = \text{LN}\left(Z_{\beta \to \alpha}^{(1)} + \text{FFN}(Z_{\beta \to \alpha}^{(1)})\right)$$
MulT stacks $D$ such cross-modal layers in sequence. For 3 modalities, there are 6 pairwise cross-modal streams:
* $\{V \to L, A \to L\}$ producing representations of length $T_L$
* $\{L \to V, A \to V\}$ producing representations of length $T_V$
* $\{L \to A, V \to A\}$ producing representations of length $T_A$

##### Step 4: Self-Attention Fusion & Prediction
For each target modality $\alpha$, the incoming cross-modal features are concatenated:
$$H_\alpha^{\text{fused}} = [H_{\beta_1 \to \alpha}; H_{\beta_2 \to \alpha}] \in \mathbb{R}^{T_\alpha \times 2d}$$
This concatenated sequence is passed through standard self-attention Transformer blocks. The final temporal sequence is pooled (typically taking the representation of the final time step or mean-pooling over $T_\alpha$), concatenated across all three target modalities into a single global vector $h \in \mathbb{R}^{6d}$, and fed to a multi-layer perceptron (MLP) for prediction:
$$\hat{y} = W_{\text{out}} \cdot \text{ReLU}(W_h h + b_h) + b_{\text{out}}$$

##### Step 5: Optimization Objective
For regression (sentiment intensity):
$$\mathcal{L}_{\text{MulT}} = \frac{1}{N} \sum_{i=1}^N |y_i - \hat{y}_i| \quad (\text{Mean Absolute Error / } L_1 \text{ Loss})$$
For discrete emotion classification:
$$\mathcal{L}_{\text{MulT}} = -\frac{1}{N} \sum_{i=1}^N \sum_{c=1}^C y_{i,c} \log \hat{y}_{i,c} \quad (\text{Cross-Entropy Loss})$$

#### 1.5 Implementation Details
* **Hyperparameters:** Common hidden dimension $d = 40$ or $50$; number of attention heads $h = 4$ or $8$; cross-modal layers $D = 4$ to $6$; self-attention layers = $2$.
* **Optimization:** Adam optimizer with initial learning rate $\eta = 10^{-3}$ for acoustic/visual features, $\eta = 10^{-4}$ or $2 \times 10^{-5}$ when fine-tuning BERT; batch size 24 or 32; gradient clipping at norm 0.8.
* **Temporal Convolutions:** Kernel sizes $k_L = 1, k_V = 3, k_A = 3$.
* **Hardware & Datasets:** Trained on single NVIDIA Titan X / V100 GPU in PyTorch. Evaluated on CMU-MOSI, CMU-MOSEI, and UR-FUNNY.

#### 1.6 Gaps & Limitations (What MulT Does NOT Address)
1. **Quadratic Complexity:** MulT computes 6 pairwise cross-attention matrices, each requiring $\mathcal{O}(T_\alpha T_\beta)$ operations. For long streaming sessions (minutes of video), memory blows up quadratically unless hard sequence truncation is applied.
2. **Missing Modality Fragility:** MulT strictly requires all three modalities to be present. If the webcam is turned off ($X_V = \emptyset$), cross-attention mechanisms $V \to L, V \to A, L \to V,$ and $A \to V$ divide by zero or multiply against empty matrices, crashing inference.
3. **Vulnerability to Noise:** Cross-attention indiscriminately aggregates features across time. If the audio stream is corrupted by background street noise, cross-attention will faithfully inject that acoustic noise into the text and visual representations.

#### 1.7 Research Direction & Evolution
MulT established cross-modal attention as the gold standard. Later works extended it by:
* Adding low-rank approximations (LMF, Linformer-style attention) to drop complexity from $\mathcal{O}(T^2)$ to $\mathcal{O}(T)$.
* Incorporating missing-modality imagination (MMIN) so that missing keys/values can be synthesized before cross-attention.
* Adding modality gating (M3ER) to suppress corrupted cross-modal attention weights.

#### 1.8 Why MulT Was Selected for THIS Project
* **Direct Blueprint Role:** MulT serves as the foundational mathematical template for **HEAD-A (Discriminative Fusion Core)** in our system blueprint.
* **Requirement Alignment:** Directly satisfies **Requirement R2.1–R2.4** and **R4.2** by handling video frames (30 fps) and audio frames (16 kHz / 50 Hz spectrogram windows) without forcing artificial word alignment or dropping non-verbal frames during user pauses.

### 2. M3ER: Multiplicative Multimodal Emotion Recognition Using Facial, Textual, and Speech Cues

* **Full Citation:** Trisha Mittal, Uttaran Bhattacharya, Rohan Chandra, Aniket Bera, and Dinesh Manocha. *"M3ER: Multiplicative Multimodal Emotion Recognition Using Facial, Textual, and Speech Cues."* In **Proceedings of the Thirty-Fourth AAAI Conference on Artificial Intelligence (AAAI 2020)**, Vol. 34, No. 07, pages 1359–1367.
* **Paper Link:** [arXiv:2005.03545](https://arxiv.org/abs/2005.03545) | [Direct PDF](https://arxiv.org/pdf/2005.03545.pdf)
* **Code / Reference:** Supported under ACM/AAAI affective libraries.

#### 2.1 Research Question Answered
> *How can an affective computing model dynamically detect, downweight, or reject sensor modalities that are corrupted by environmental noise (e.g., poor lighting, background babble) on a per-utterance basis, and why does multiplicative feature combination outperform traditional additive concatenation under noisy conditions?*

#### 2.2 Plain-Language Explanation (What It Aims To Do)
In laboratory benchmarks, datasets are clean. But in a real-world mental health monitoring app, recording conditions fluctuate wildly: a user might speak in a room with a blaring television, walk outside into heavy traffic, or sit in a dark room where the camera captures only a grainy silhouette.

Standard multimodal architectures rely on **Additive Fusion** (such as concatenation: $[f_{\text{face}}; f_{\text{voice}}; f_{\text{text}}]$ or vector addition $f_{\text{face}} + f_{\text{voice}} + f_{\text{text}}$). The authors of M3ER prove that addition is inherently vulnerable to corruption: if the microphone captures pure noise, that noise vector is added directly into the classifier, corrupting the prediction even if the face is perfectly clear.

M3ER solves this with two innovations:
1. It adds a **Modality Check** (a diagnostic filter) that inspects each incoming modality and asks: *"Does this stream contain coherent emotional information, or is it uninformative noise?"*
2. It switches from addition to **Multiplicative Combination**. In multiplication, if a corrupted modality is assigned a near-zero reliability score, its corrupting noise is effectively zeroed out, allowing the remaining clean modalities to drive the emotional classification.

#### 2.3 Exact Inputs & Outputs
* **Inputs:** Utterance-level features across three modalities:
  1. **Text ($f_t$):** Lexical representation $f_t \in \mathbb{R}^{d_t}$ extracted via word embeddings / fine-tuned BERT representations for the spoken utterance.
  2. **Speech/Acoustic ($f_s$):** Acoustic feature vector $f_s \in \mathbb{R}^{d_s}$ (pitch, energy, zero-crossing rate, MFCCs, and mel-spectrogram embeddings).
  3. **Visual/Facial ($f_v$):** Visual feature vector $f_v \in \mathbb{R}^{d_v}$ representing facial expressions, action units (AUs), and landmark displacements across the utterance.
* **Outputs:**
  * Categorical emotion probability vector $\hat{y} \in \Delta^{C-1}$ across emotional classes (Happy, Sad, Angry, Neutral).
  * Explicit per-modality reliability / confidence weights $w_t, w_s, w_v \in [0, 1]$.

#### 2.4 Approach & Internal Mechanics (How It Works Under the Hood)

```
[Text Stream]  f_t ---------\
                             +--> [Modality Check Stage] ---> Computes Reliability Weights (w_t, w_s, w_v)
[Audio Stream] f_s ---------+    (Checks feature efficacy)                   |
                             |                                                v
[Visual Stream] f_v --------/                                    [Gated Projections]
                                                                  h_t = sigma(W_t f_t) * w_t
                                                                  h_s = sigma(W_s f_s) * w_s
                                                                  h_v = sigma(W_v f_v) * w_v
                                                                              |
                                                                              v
                                                               [Multiplicative Interaction]
                                                                H_mult = h_t (x) h_s (x) h_v
                                                                              |
                                                                              v
                                                                     [Classification Head]
                                                                   Emotion Distribution y_hat
```

##### Step 1: Feature Extraction & Dimensional Alignment
Each raw modality is processed by its respective unimodal encoder to produce fixed-dimensional utterance embeddings:
$$f_t \in \mathbb{R}^{d_t}, \quad f_s \in \mathbb{R}^{d_s}, \quad f_v \in \mathbb{R}^{d_v}$$
Linear projection layers project them into a shared affective representation space $\mathbb{R}^d$:
$$\tilde{f}_m = \text{ReLU}(W_m f_m + b_m), \quad \forall m \in \{t, s, v\}$$

##### Step 2: The Modality Check Stage
The modality check evaluates whether a modality $m$ is carrying useful affective signal or corrupt noise. It evaluates inter-modality correlation using a learned projection that estimates canonical correlation:
$$c_{m_1, m_2} = \frac{\tilde{f}_{m_1}^T \tilde{f}_{m_2}}{\|\tilde{f}_{m_1}\|_2 \|\tilde{f}_{m_2}\|_2}$$
If one modality is corrupted with random noise (e.g., Gaussian visual static), its directional correlation with the semantic and prosodic streams drops toward zero. The modality check computes an adaptive reliability weight $w_m \in [0, 1]$:
$$w_m = \sigma\left(W_{\text{check}, m} \cdot [\tilde{f}_m; \bar{c}_m] + b_{\text{check}, m}\right)$$
where $\bar{c}_m$ is the mean cross-correlation of modality $m$ with all other available modalities.

##### Step 3: Multiplicative Fusion vs. Additive Fusion
Instead of concatenating features $[\tilde{f}_t; \tilde{f}_s; \tilde{f}_v]$, M3ER computes an element-wise multiplicative tensor product:
$$H_{\text{mult}} = (w_t \cdot \tilde{f}_t) \odot (w_s \cdot \tilde{f}_s) \odot (w_v \cdot \tilde{f}_v) \in \mathbb{R}^d$$
where $\odot$ denotes the Hadamard (element-wise) product.

**The Mathematical Rationale:**
Consider a corrupted audio stream where $\tilde{f}_s = \text{clean}_s + \text{noise}_s$.
* Under Additive Concatenation:
  $$H_{\text{add}} = W_t \tilde{f}_t + W_s (\text{clean}_s + \text{noise}_s) + W_v \tilde{f}_v$$
  The noise term $W_s \cdot \text{noise}_s$ is linearly injected into the classifier. If $\|\text{noise}_s\|$ is large, it dominates the logits.
* Under Multiplicative Gating:
  The modality check detects low correlation and sets $w_s \to 0$. Then:
  $$H_{\text{mult}} = (w_t \tilde{f}_t) \odot (w_s \tilde{f}_s) \odot (w_v \tilde{f}_v) \to \text{suppressed or bypassed to clean 2-modality product}$$
  The corrupted channel is prevented from flipping the sign of the emotional prediction.

##### Step 4: Classification & Multi-Task Loss
The multiplicative representation $H_{\text{mult}}$ is fed through a softmax layer:
$$\hat{y} = \text{softmax}(W_{\text{out}} H_{\text{mult}} + b_{\text{out}})$$
The training loss combines the task classification loss with a regularization penalty on the modality check weights:
$$\mathcal{L}_{\text{M3ER}} = \mathcal{L}_{\text{CE}}(y, \hat{y}) + \lambda \sum_{m \in \{t,s,v\}} (1 - w_m)^2$$
The second term prevents the network from taking the trivial shortcut of setting all $w_m = 0$.

#### 2.5 Implementation Details
* **Encoders:** Text: Word2Vec + BiLSTM / pre-trained BERT; Audio: openSMILE extracting 65 low-level acoustic descriptors + BiLSTM; Video: 3D-CNN / ResNet pre-trained on FER+ extracting facial features.
* **Controlled Noise Injections:** Evaluated by synthetically injecting:
  1. Additive white Gaussian noise (AWGN) and babble noise into audio at various signal-to-noise ratios (SNR from 0 dB to 20 dB).
  2. Gaussian blur, illumination reduction (darkening), and salt-and-pepper noise into video frames.
* **Datasets:** Tested on IEMOCAP, CMU-MOSEI, and RAVDESS.

#### 2.6 Gaps & Limitations (What M3ER Does NOT Address)
1. **Utterance Pooling Requirement:** M3ER assumes all modalities have already been pooled or averaged into static vectors $f_t, f_s, f_v$ per utterance. It does not handle streaming unaligned temporal frame sequences directly (unlike MulT).
2. **Double Corruption Collapse:** If *two* modalities are simultaneously noisy (e.g., dark room AND loud room), multiplicative gating $w_s \to 0, w_v \to 0$ can cause the entire product vector $H_{\text{mult}}$ to vanish to zero, leading to underflow or erratic classification.
3. **Incongruence Treated as Noise:** M3ER assumes that when modalities disagree, one of them must be "corrupted." It does not recognize that in mental health, disagreement can be psychological (e.g., masking: smiling face with depressed voice).

#### 2.7 Research Direction & Evolution
M3ER demonstrated that multiplicative fusion provides natural noise resistance. Later researchers combined M3ER's gating principles with transformer attention layers (e.g., Noise-Resistant Multimodal Transformer, Li et al., 2023) to achieve both unaligned sequence modeling and noise resilience simultaneously.

#### 2.8 Why M3ER Was Selected for THIS Project
* **Direct Requirement Mapping:** Perfectly implements **Requirement R4.3** (independent per-modality confidence reporting), **Requirement R4.4** (exposing modality contribution weights on user dashboards), and **Requirement R5.3** (coping with transient sensor degradation).
* **Auditability:** M3ER's $w_t, w_s, w_v$ weights give us a mathematically principled way to show the user or clinician: *"This emotional reading relied 80% on facial cues because acoustic noise was high."*

### 3. MISA: Modality-Invariant and -Specific Representations for Multimodal Sentiment Analysis

* **Full Citation:** Devamanyu Hazarika, Yingting Li, Soujanya Poria, and Roger Zimmermann. *"MISA: Modality-Invariant and -Specific Representations for Multimodal Sentiment Analysis."* In **Proceedings of the 28th ACM International Conference on Multimedia (ACM MM 2020)**, pages 741–749.
* **Paper Link:** [arXiv:2006.12906](https://arxiv.org/abs/2006.12906) | [Direct PDF](https://arxiv.org/pdf/2006.12906.pdf)
* **Official Code Repository:** [GitHub - declare-lab/MISA](https://github.com/declare-lab/MISA)

#### 3.1 Research Question Answered
> *How can multimodal representations be formally factorized into two orthogonal subspaces—a modality-invariant subspace that captures cross-modal consensus and a modality-specific subspace that preserves private, non-redundant nuances—so that identity bias and channel noise do not corrupt affective prediction?*

#### 3.2 Plain-Language Explanation (What It Aims To Do)
When someone expresses emotion across language, voice, and facial gestures, their features contain an entangled mixture of two things:
1. **Shared Affective Information (Modality-Invariant):** The underlying emotional state that manifests across all modalities simultaneously (e.g., distress causes negative lexical sentiment, higher acoustic pitch jitter, and facial AU4 brow furrowing).
2. **Private Characteristic Information (Modality-Specific):** Information unique to a single modality that has nothing to do with shared affect (e.g., the speaker's vocal accent, their facial bone structure, the specific room reverberation, or syntactic grammar quirks).

Standard multimodal fusion merges raw feature embeddings directly. Because private noise (like speaker identity or lighting) is often statistically prominent, standard models overfit to specific speakers or environments. MISA solves this by performing mathematical **subspace disentanglement**. It takes each modality and cleanly separates it into two distinct vectors: an *Invariant* vector (capturing what all modalities agree on) and a *Specific* vector (capturing private nuances). By learning clean boundaries between these spaces, MISA achieves superior generalization across unseen speakers.

#### 3.3 Exact Inputs & Outputs
* **Inputs:** Utterance-level feature representations across three modalities:
  * $u_l \in \mathbb{R}^{d_l}$: Spoken text sequence encoded via pre-trained BERT ($d_l = 768$).
  * $u_a \in \mathbb{R}^{d_a}$: Acoustic sequence extracted via openSMILE ($d_a = 74$).
  * $u_v \in \mathbb{R}^{d_v}$: Facial visual sequence extracted via OpenFace/Facet ($d_v = 35$).
* **Outputs:**
  * Sentiment score $\hat{y} \in \mathbb{R}$ or emotion class probabilities $\hat{y} \in \Delta^{C-1}$.
  * Disentangled feature representations: three invariant vectors $\{S_l, S_a, S_v\}$ and three private vectors $\{P_l, P_a, P_v\}$.

#### 3.4 Approach & Internal Mechanics (How It Works Under the Hood)

```
[Modality Inputs]            [Disentanglement Projections]         [Loss Constraints]             [Fusion & Output]
   u_l (Text)  --------> Invariant Encoder E_s -> S_l (dim d) <---+-- Similarity Loss (CMD) ------\
                     --> Specific Encoder E_p -> P_l (dim d) <-+--+-- Diff Loss (S_l . P_l = 0)   |
                                                               |  |                               |
   u_a (Audio) --------> Invariant Encoder E_s -> S_a (dim d) <---+  |   Reconstruction Loss      +--> Concatenate
                     --> Specific Encoder E_p -> P_a (dim d) <-+--+-- (Decoder D(S_m, P_m))        |    [S_l; S_a; S_v;
                                                               |  |                               |     P_l; P_a; P_v]
   u_v (Vision) -------> Invariant Encoder E_s -> S_v (dim d) <---+  |                               |          |
                     --> Specific Encoder E_p -> P_v (dim d) <----+                               /          v
                                                                                                        Task MLP Head
                                                                                                              |
                                                                                                              v
                                                                                                         Prediction y
```

##### Step 1: Subspace Projection Encoders
For each modality $m \in \{l, a, v\}$, MISA uses two dedicated neural networks:
* **Shared Invariant Encoder ($E_s$):** A single, weight-shared projection network mapping all modalities into a common space:
  $$S_m = E_s(u_m; \theta_s) \in \mathbb{R}^d$$
* **Private Specific Encoders ($E_{p,m}$):** Modality-specific networks with distinct parameters:
  $$P_m = E_{p,m}(u_m; \theta_{p,m}) \in \mathbb{R}^d$$

##### Step 2: Similarity Loss ($\mathcal{L}_{\text{sim}}$) — Enforcing Invariance
To force $S_l, S_a,$ and $S_v$ to live in the exact same distribution and capture only shared affective concepts, MISA minimizes the **Central Moment Discrepancy (CMD)** across all modality pairs:
$$\mathcal{L}_{\text{sim}} = \sum_{(m_1, m_2) \in \{(l,a), (l,v), (a,v)\}} \text{CMD}(S_{m_1}, S_{m_2})$$
Where $\text{CMD}(X, Y)$ matches both the empirical mean vectors and higher-order central moments:
$$\text{CMD}(X, Y) = \frac{1}{|b - a|} \|E(X) - E(Y)\|_2 + \sum_{k=2}^K \frac{1}{|b - a|^k} \|C_k(X) - C_k(Y)\|_2$$
where $C_k(X) = E((X - E(X))^k)$ is the vector of $k$-th central moments. This forces the invariant representations to share identical probability distributions regardless of whether they came from pixels, sound waves, or text tokens.

##### Step 3: Difference Loss ($\mathcal{L}_{\text{diff}}$) — Enforcing Orthogonality
To ensure that the private specific vector $P_m$ does not contain redundant information already captured by $S_m$, MISA enforces a soft orthogonality constraint using the squared Frobenius norm of their cross-correlation:
$$\mathcal{L}_{\text{diff}} = \sum_{m \in \{l, a, v\}} \left\| \frac{S_m^T P_m}{\|S_m\|_F \|P_m\|_F} \right\|_F^2$$
This drives the dot product between $S_m$ and $P_m$ to zero, mathematically guaranteeing that the specific subspace contains only information orthogonal to the shared space.

##### Step 4: Reconstruction Loss ($\mathcal{L}_{\text{recon}}$) — Preventing Information Collapse
Without a reconstruction constraint, the encoders could minimize $\mathcal{L}_{\text{diff}}$ trivially by setting $P_m = \mathbf{0}$. To prevent information loss, a shared decoder $D(\cdot; \theta_d)$ must reconstruct the original input from the concatenated representations:
$$\hat{u}_m = D([S_m; P_m]; \theta_d)$$
$$\mathcal{L}_{\text{recon}} = \sum_{m \in \{l, a, v\}} \frac{1}{d_m} \|u_m - \hat{u}_m\|_2^2$$

##### Step 5: Fusion & Task Objective
All six disentangled representations are concatenated into a global feature vector $H$:
$$H = [S_l; S_a; S_v; P_l; P_a; P_v] \in \mathbb{R}^{6d}$$
The prediction is generated via an MLP: $\hat{y} = \text{MLP}(H)$. The total objective is minimized end-to-end:
$$\mathcal{L}_{\text{total}} = \mathcal{L}_{\text{task}}(y, \hat{y}) + \alpha \mathcal{L}_{\text{sim}} + \beta \mathcal{L}_{\text{diff}} + \gamma \mathcal{L}_{\text{recon}}$$

#### 3.5 Implementation Details
* **Hyperparameters:** Disentangled subspace dimension $d = 128$; loss weights $\alpha = 0.8, \beta = 0.3, \gamma = 1.0$; optimizer: Adam with learning rate $10^{-5}$ for BERT and $10^{-3}$ for project heads.
* **Evaluation:** Benchmark numbers established state-of-the-art results on CMU-MOSI (Acc-2: 83.4%) and CMU-MOSEI (Acc-2: 85.5%).

#### 3.6 Gaps & Limitations (What MISA Does NOT Address)
1. **Utterance Pooling Loss:** MISA operates on fixed-length, pre-pooled utterance vectors. It does not model fine-grained sub-second temporal variations across continuous time.
2. **Equal Capacity Assumption:** MISA allocates identical subspace dimensions ($d = 128$) to both invariant and specific representations. In reality, visual face streams often carry far more identity-specific noise than acoustic streams, making symmetric dimension allocation sub-optimal.
3. **Hyperparameter Tuning Burden:** Balancing four competing loss terms ($\mathcal{L}_{\text{task}}, \mathcal{L}_{\text{sim}}, \mathcal{L}_{\text{diff}}, \mathcal{L}_{\text{recon}}$) is notoriously delicate; poor tuning causes the reconstruction loss to overpower task gradients.

#### 3.7 Research Direction & Evolution
MISA proved that disentanglement enhances generalization. Later research extended MISA by replacing CMD with Mutual Information neural estimators (MMIM) and applying subspace disentanglement to conversational and missing-modality scenarios (FDFNet).

#### 3.8 Why MISA Was Selected for THIS Project
* **Speaker-Independence Solution:** Challenge C3 in our review notes a **~13% accuracy drop** when testing models on unseen speakers. MISA's subspace disentanglement isolates speaker identity noise into $P_a$ and $P_v$, ensuring our mental health monitoring system evaluates *affective distress*, not the user's personal vocal timbre or facial structure.

### 4. Self-MM: Learning Modality-Specific Representations with Self-Supervised Multi-Task Learning

* **Full Citation:** Wei Han, Hui Chen, Alexander Gelbukh, Amir Zadeh, Louis-Philippe Morency, and Soujanya Poria. *"Learning Modality-Specific Representations with Self-Supervised Multi-Task Learning for Multimodal Sentiment Analysis."* In **Proceedings of the Thirty-Fifth AAAI Conference on Artificial Intelligence (AAAI 2021)**, Vol. 35, No. 14, pages 12917–12925.
* **Paper Link:** [arXiv:2102.04830](https://arxiv.org/abs/2102.04830) | [Direct PDF](https://arxiv.org/pdf/2102.04830.pdf)
* **Official Code Repository:** [GitHub - thuiar/Self-MM](https://github.com/thuiar/Self-MM)

#### 4.1 Research Question Answered
> *How can multimodal encoders learn robust, discriminative unimodal representations when datasets provide only a single joint multimodal label per sample, without requiring labor-intensive and subjective manual unimodal annotations?*

#### 4.2 Plain-Language Explanation (What It Aims To Do)
In every standard multimodal dataset (such as CMU-MOSEI or IEMOCAP), human annotators watch a video and give **one single label** for the whole sample (e.g., *"Overall, this person is sad"*). Human annotators are almost never asked to label the transcript in isolation, the silent facial video in isolation, and the audio recording in isolation.

This creates a serious machine learning defect called **Modality Laziness / Modality Domination**. During joint training, the model quickly realizes that text transcripts are much easier to classify than subtle facial twitches or acoustic pitch shifts. The text encoder does all the heavy lifting, while the facial and acoustic encoders receive tiny gradient updates and remain under-trained. If a user turns off their microphone or speaks ambiguously, the entire system collapses because the non-verbal encoders were never trained to be self-sufficient.

Self-MM solves this by inventing a **Self-Supervised Label Generation Module (ULGM)**. During training, the model dynamically generates artificial "pseudo-labels" for each unimodal branch by measuring feature distances to learned class centers. It then trains the face, voice, and text branches as independent auxiliary tasks alongside the main multimodal task.

#### 4.3 Exact Inputs & Outputs
* **Inputs:** Multimodal sequential inputs for text tokens ($X_m$), audio frames ($X_a$), and visual frames ($X_v$).
* **Outputs:**
  * Joint multimodal prediction $\hat{y}_m \in \mathbb{R}$.
  * Three unimodal predictions: text prediction $\hat{y}_l$, audio prediction $\hat{y}_a$, and visual prediction $\hat{y}_v$.
  * Generated unimodal pseudo-labels $y_l^*, y_a^*, y_v^*$.

#### 4.4 Approach & Internal Mechanics (How It Works Under the Hood)

```
[Raw Modalities]        [Unimodal Encoders]        [Feature Distances to Centers]     [Multi-Task Loss]
  Text X_l   ------> E_l -> Repr h_l ------------> ULGM computes pseudo-label y_l* ---> Loss L_l(y_l*, y_hat_l) ---\
  Audio X_a  ------> E_a -> Repr h_a ------------> ULGM computes pseudo-label y_a* ---> Loss L_a(y_a*, y_hat_a) ---+-> Total L
  Vision X_v ------> E_v -> Repr h_v ------------> ULGM computes pseudo-label y_v* ---> Loss L_v(y_v*, y_hat_v) ---/     |
                               \                                                                                   |
                                +--> Concatenate [h_l; h_a; h_v] -> Predict y_hat_m ---> Loss L_m(y_true, y_hat_m) /
```

##### Step 1: Unimodal Encoders & Joint Prediction
Each modality stream is processed by a dedicated feature extractor:
$$h_l = \text{BERT}(X_l) \in \mathbb{R}^{d_l}, \quad h_a = \text{LSTM}_a(X_a) \in \mathbb{R}^{d_a}, \quad h_v = \text{LSTM}_v(X_v) \in \mathbb{R}^{d_v}$$
The multimodal representation concatenates all three: $h_m = [h_l; h_a; h_v]$. A joint prediction head outputs the multimodal prediction:
$$\hat{y}_m = W_m h_m + b_m$$
Meanwhile, each unimodal branch has its own independent prediction head:
$$\hat{y}_l = W_l h_l + b_l, \quad \hat{y}_a = W_a h_a + b_a, \quad \hat{y}_v = W_v h_v + b_v$$

##### Step 2: Unimodal Label Generation Module (ULGM)
How does Self-MM obtain supervision for $\hat{y}_l, \hat{y}_a, \hat{y}_v$ without human labels?
ULGM maintains dynamic class center representations in each unimodal feature space. For binary or continuous sentiment, it maintains a positive center $C_m^+$ and a negative center $C_m^-$ for modality $m$:
1. For any sample, it computes the Euclidean distance from unimodal feature $h_m$ to both centers:
   $$d_m^+ = \|h_m - C_m^+\|_2, \quad d_m^- = \|h_m - C_m^-\|_2$$
2. It calculates a relative shift score:
   $$\alpha_m = \frac{d_m^- - d_m^+}{d_m^- + d_m^+}$$
   If $h_m$ is much closer to the positive center than the negative center, $\alpha_m > 0$.
3. It anchors this shift to the ground-truth joint multimodal label $y_{\text{joint}}$:
   $$y_m^* = y_{\text{joint}} + \beta_m \cdot \alpha_m$$
   The pseudo-label $y_m^*$ reflects whether this specific modality was expressing positive or negative emotion relative to the overall session label.
4. Centers are updated dynamically during training via momentum moving averages:
   $$C_m^{+, (t)} = \mu C_m^{+, (t-1)} + (1 - \mu) \bar{h}_{m, \text{pos}}^{(t)}$$

##### Step 3: Multi-Task Training Formulation
The entire system is trained end-to-end under a combined multi-task loss function:
$$\mathcal{L}_{\text{Self-MM}} = \mathcal{L}_{\text{task}}(y_{\text{joint}}, \hat{y}_m) + \sum_{m \in \{l, a, v\}} w_m \mathcal{L}_{\text{task}}(y_m^*, \hat{y}_m)$$
where $w_m$ is an adaptive weight balancing the unimodal auxiliary tasks.

#### 4.5 Implementation Details
* **Backbones:** Text: BERT-base-uncased ($d=768$); Audio: sBoW / openSMILE features processed by a 2-layer LSTM ($d=64$); Video: Facet features processed by a 2-layer LSTM ($d=32$).
* **Optimizer & Schedule:** AdamW with learning rate $5 \times 10^{-5}$ for BERT and $10^{-3}$ for LSTMs and classification heads; momentum coefficient $\mu = 0.9$.
* **Datasets:** CMU-MOSI and CMU-MOSEI benchmarks.

#### 4.6 Gaps & Limitations (What Self-MM Does NOT Address)
1. **Unimodal Convexity Assumption:** The label generation module assumes that unimodal emotional clusters are convex spheres around single center points ($C_m^+, C_m^-$). In mental health contexts, emotions like anxiety or melancholic depression exhibit complex multi-modal manifolds that a single center cannot capture.
2. **Vulnerability to Early Training Noise:** In early training epochs, the unimodal representations are unformed and random. If pseudo-labels $y_m^*$ are generated from noisy initial centers, they can reinforce incorrect bias (confirmation bias in self-supervision).
3. **Absence of Cross-Modal Attention:** Self-MM uses simple concatenation for multimodal fusion ($[h_l; h_a; h_v]$). It does not employ cross-modal attention to discover fine-grained interactions.

#### 4.7 Research Direction & Evolution
Self-MM demonstrated that forcing encoders to perform well unimodally dramatically improves overall multimodal robustness. Later researchers combined Self-MM's multi-task supervision with cross-attention networks (like MulT) and information-theoretic regularizers (MMIM).

#### 4.8 Why Self-MM Was Selected for THIS Project
* **Direct Pipeline Requirement (R1.1, R1.3, R5.1):** Our project requires the system to support **voice+text mode** and **text-only mode** as first-class citizens. Self-MM guarantees that the voice encoder and text encoder are trained to be independently competent, ensuring the model does not degrade when camera tracking is disabled by the user.
* **Custom Dataset Adaptation:** Because our custom mental-health dataset will have limited clinical annotations, Self-MM's pseudo-label generation allows us to squeeze maximum supervision out of every session recording.

### 5. UniMSE: Towards Unified Multimodal Sentiment Analysis and Emotion Recognition

* **Full Citation:** Guimin Hu, Ting-En Lin, Yi Zhao, Guangming Lu, Yuchao Liu, and Yongbin Li. *"UniMSE: Towards Unified Multimodal Sentiment Analysis and Emotion Recognition."* In **Proceedings of the 2022 Conference on Empirical Methods in Natural Language Processing (EMNLP 2022)**, pages 7837–7849.
* **Paper Link:** [arXiv:2205.02616](https://arxiv.org/abs/2205.02616) | [Direct PDF](https://arxiv.org/pdf/2205.02616.pdf)
* **Official Code Repository:** [GitHub - DAMO-ConvAI/UniMSE](https://github.com/AlibabaResearch/DAMO-ConvAI/tree/main/UniMSE)

#### 5.1 Research Question Answered
> *How can continuous Multimodal Sentiment Analysis (predicting dimensional valence intensity) and categorical Multimodal Emotion Recognition (classifying discrete affective labels) be unified into a single shared generative representation space, enabling cross-task knowledge transfer between intensity and emotional category?*

#### 5.2 Plain-Language Explanation (What It Aims To Do)
In affective computing, researchers have historically split the field into two competing camps:
1. **Sentiment Analysis (Dimensional):** Predicts a continuous scalar number from negative to positive (e.g., $-2.4$ indicates strong distress, $+1.2$ indicates mild happiness).
2. **Emotion Recognition (Categorical):** Predicts discrete labels (e.g., Happy, Sad, Angry, Anxious).

Historically, separate models were engineered for each task. But clinically and psychologically, these tasks are two sides of the same coin: knowing that an utterance contains high negative intensity directly constrains the emotion to *Sadness, Anger,* or *Anxiety* (eliminating *Joy*). Conversely, knowing the emotion is *Severe Grief* tells you the continuous valence must be deeply negative.

UniMSE bridges this divide. Built on a unified sequence-to-sequence Transformer (T5), it formulates both tasks into a unified representation space. A single multimodal model simultaneously predicts the continuous sentiment score and generates the discrete emotional label, using shared cross-task contrastive learning to make both predictions more accurate.

#### 5.3 Exact Inputs & Outputs
* **Inputs:** Multimodal sequences accompanied by task-specific instructional prompts:
  * $T$: Spoken text tokens (words).
  * $A$: Acoustic feature sequence extracted via WavLM / openSMILE.
  * $V$: Visual facial feature sequence extracted via MANet / OpenFace.
  * Task prompt prefix: e.g., `"sentiment:"` or `"emotion:"`.
* **Outputs:**
  * **Categorical Generation:** Discrete emotion class tokens generated by the T5 decoder (e.g., `"sad"`, `"neutral"`, `"anxious"`).
  * **Continuous Regression:** Scaled dimensional sentiment score $\hat{y}_{\text{sent}} \in [-3.0, +3.0]$.

#### 5.4 Approach & Internal Mechanics (How It Works Under the Hood)

```
[Prompt + Text]  "emotion: " + Tokens ----\
[Audio Features] WavLM -> Linear Adapter -+-> Unified T5 Encoder ---> [Cross-Task Contrastive Loss]
[Visual Features] MANet -> Linear Adapter /             |             (Pulls same emotion + sentiment together)
                                                        |
                               +------------------------+------------------------+
                               |                                                 |
                               v                                                 v
                       [T5 Generative Decoder]                         [Linear Regression Head]
                               |                                                 |
                               v                                                 v
                 Emotion Text Token ("sad")                         Continuous Sentiment (-2.1)
```

##### Step 1: Multimodal Tokenization & Embedding Projection
To feed continuous acoustic and visual signals into a language model (T5), UniMSE projects acoustic and visual features into the exact embedding dimension of T5 ($d_{\text{model}} = 768$):
$$\tilde{A} = \text{LinearAdapter}_A(A) \in \mathbb{R}^{T_A \times d_{\text{model}}}, \quad \tilde{V} = \text{LinearAdapter}_V(V) \in \mathbb{R}^{T_V \times d_{\text{model}}}$$
The input to the T5 encoder is a concatenated sequence:
$$X_{\text{input}} = [\text{Task Prompt Tokens}; \text{Word Tokens}; \tilde{A}; \tilde{V}]$$

##### Step 2: Inter-Task Contrastive Learning
To ensure that categorical representations and dimensional representations inform each other, UniMSE introduces an affective contrastive learning objective. Samples that share identical emotion labels (e.g., both labeled *Sadness*) and similar sentiment polarity are pulled together in the latent space, while samples with divergent emotional categories are pushed apart:
$$\mathcal{L}_{\text{contrast}} = -\sum_{i=1}^B \log \frac{\sum_{j \in P(i)} \exp\left(\text{sim}(h_i, h_j) / \tau\right)}{\sum_{k \neq i} \exp\left(\text{sim}(h_i, h_k) / \tau\right)}$$
where $h_i$ is the mean-pooled representation from the T5 encoder for sample $i$, $P(i)$ is the set of positive samples sharing affective properties with sample $i$, and $\tau$ is a temperature hyperparameter.

##### Step 3: Dual-Head Decoding
UniMSE generates predictions through two complementary pathways:
1. **Generative Emotion Head:** The T5 autoregressive decoder generates the target emotion label token-by-token:
   $$\mathcal{L}_{\text{gen}} = -\sum_{t=1}^{|Y_{\text{emo}}|} \log P(w_t | w_{<t}, X_{\text{input}})$$
2. **Dimensional Sentiment Regression Head:** A linear layer applied directly to the pooled encoder representation $h$:
   $$\hat{y}_{\text{sent}} = W_{\text{reg}} h + b_{\text{reg}}$$
   $$\mathcal{L}_{\text{reg}} = \frac{1}{B} \sum_{i=1}^B (\hat{y}_{\text{sent}, i} - y_{\text{sent}, i})^2$$

##### Step 4: Total Joint Objective
The entire unified model is trained end-to-end:
$$\mathcal{L}_{\text{UniMSE}} = \mathcal{L}_{\text{gen}} + \lambda_1 \mathcal{L}_{\text{reg}} + \lambda_2 \mathcal{L}_{\text{contrast}}$$

#### 5.5 Implementation Details
* **Base Model:** T5-base ($d_{\text{model}} = 768, 12$ layers in encoder, 12 in decoder).
* **Audio/Visual Backbones:** Acoustic features from WavLM-base+ ($d=768$); Visual features from MANet pre-trained on AffectNet ($d=512$).
* **Optimization:** AdamW with learning rate $5 \times 10^{-5}$, linear warmup for 10% of steps, weight decay 0.01, batch size 16.
* **Datasets Evaluated:** MOSI, MOSEI, and MELD. Achieved top-tier rankings on both sentiment accuracy and emotion F1 scores.

#### 5.6 Gaps & Limitations (What UniMSE Does NOT Address)
1. **Computational Footprint:** Because it relies on a full T5 encoder-decoder backbone, generating emotion tokens autoregressively is computationally heavy. It cannot run on low-power mobile edge devices without aggressive quantization or pruning.
2. **Fixed Label Text Generation:** Generating emotion labels as text strings ("happy", "sad") introduces token-parsing overhead; if the decoder generates unexpected text, post-processing heuristics are required.
3. **Single-Utterance Scope:** UniMSE evaluates individual utterances in isolation; it lacks recurrent memory to track how sentiment shifts over a 15-minute dialogue.

#### 5.7 Research Direction & Evolution
UniMSE proved that unifying dimensional and categorical tasks produces mutual performance gains. Subsequent works adapted this concept to lightweight encoder-only architectures (e.g., DeBERTa) and extended it to multimodal conversational memory.

#### 5.8 Why UniMSE Was Selected for THIS Project
* **Direct Blueprint Role:** Provides the foundational architecture for the **Dual Prediction Head** in our system blueprint.
* **Requirement Alignment:** Directly satisfies **Requirement R4.1** and **Requirement R6.4** (simultaneously outputting categorical mental health emotion classes like *Anxious/Depressed* alongside a continuous *Valence-Arousal trend score* for long-term clinical mood tracking).

### 6. DialogueRNN: An Attentive RNN for Emotion Detection in Conversation

* **Full Citation:** Navonil Majumder, Soujanya Poria, Devamanyu Hazarika, Rada Mihalcea, Alexander Gelbukh, and Erik Cambria. *"DialogueRNN: An Attentive RNN for Emotion Detection in Conversation."* In **Proceedings of the Thirty-Third AAAI Conference on Artificial Intelligence (AAAI 2019)**, Vol. 33, No. 01, pages 6818–6825.
* **Paper Link:** [arXiv:1811.00405](https://arxiv.org/abs/1811.00405) | [Direct PDF](https://arxiv.org/pdf/1811.00405.pdf)
* **Official Code Repository:** [GitHub - declare-lab/conv-emotion](https://github.com/declare-lab/conv-emotion)

#### 6.1 Research Question Answered
> *How can an affective sequential model maintain persistent, individualized emotional states for speakers across time while dynamically factoring in external conversational context, emotional inertia, and speaker-to-speaker turn transitions?*

#### 6.2 Plain-Language Explanation (What It Aims To Do)
Most emotion recognition systems operate in a vacuum: they look at one sentence or one 3-second video clip and make a prediction. But in real life, human emotion is continuous and sticky:
1. **Emotional Inertia:** If you are deeply depressed or furious, your internal emotional state doesn't instantly vanish to zero because you uttered a neutral word like *"Yes"*. Your emotional state persists across time.
2. **Context vs. Internal State:** There is a fundamental difference between *what happened in the conversation* (the context) and *how a specific person reacts to it* (their personal emotional state).

DialogueRNN models this by creating three distinct recurrent memory banks (GRUs) working in harmony:
1. One GRU tracks the **Global Conversation Context** (what was said across the dialogue).
2. A second GRU tracks the **Speaker's Internal Mental State** (updating only when that specific person speaks or pauses).
3. A third GRU tracks the **Emotion Output** by attending to previous moments in the conversation.

#### 6.3 Exact Inputs & Outputs
* **Inputs:** A chronological sequence of $N$ utterance representations $u_1, u_2, \dots, u_N$, where each utterance $u_t \in \mathbb{R}^d$ is accompanied by speaker identity $p_t \in \{1, 2, \dots, M\}$ and timestamp $t$.
* **Outputs:** Emotional state category $\hat{y}_t \in \Delta^{C-1}$ for each utterance $t$, tracking emotional transitions across the entire session.

#### 6.4 Approach & Internal Mechanics (How It Works Under the Hood)

```
[Utterance u_t, Speaker p] 
            |
            +------------------------------------+
            |                                    |
            v                                    v
[Global Context GRU (g_t)]              [Context Attention Module]
 g_t = GRU_G(g_{t-1}, u_t)               c_t = Sum a_{t,i} * g_i (over i < t)
            |                                    |
            \----------------+-------------------/
                             |
                             v
                 [Speaker State GRU (q_t)]
                  Updates ONLY for speaker p:
                  q_t^(p) = GRU_P(q_{t-1}^(p), [u_t; c_t])
                             |
                             v
                    [Emotion GRU (e_t)]
                     e_t = GRU_E(e_{t-1}, q_t^(p))
                             |
                             v
                   [Softmax Prediction]
                     Emotion Class y_t
```

##### Step 1: Global Context Tracking ($\text{GRU}_G$)
The global state represents the thematic progression of the session. Given incoming utterance embedding $u_t$:
$$g_t = \text{GRU}_G(g_{t-1}, u_t)$$
where $g_t \in \mathbb{R}^{d_g}$ stores the overall conversational history up to step $t$.

##### Step 2: Contextual Attention Mechanism
To determine which past events triggered the current emotion, DialogueRNN computes attention weights over all previous global states $g_1, \dots, g_{t-1}$:
$$\alpha_{t, i} = \text{softmax}\left(u_t^T W_a g_i\right), \quad \forall i \in \{1, \dots, t-1\}$$
$$c_t = \sum_{i=1}^{t-1} \alpha_{t, i} g_i \in \mathbb{R}^{d_g}$$
Here, $c_t$ is a dynamic summary of relevant past context (e.g., recalling that the user mentioned a death in the family 5 minutes earlier).

##### Step 3: Party/Speaker State Updating ($\text{GRU}_P$)
DialogueRNN maintains an internal state vector $q^{(p)}$ for each individual speaker $p$. At step $t$, if participant $p$ produced utterance $u_t$, their state updates by combining their prior personal state with the new utterance and the attended context:
$$q_t^{(p)} = \text{GRU}_P\left(q_{\text{prev}}^{(p)}, [u_t; c_t]\right)$$
For all other non-speaking participants $k \neq p$, their state remains unchanged: $q_t^{(k)} = q_{t-1}^{(k)}$. This separates the speaker's emotional inertia from other participants.

##### Step 4: Emotion Decoding ($\text{GRU}_E$) & Classification
The updated personal state is passed to the Emotion GRU:
$$e_t = \text{GRU}_E\left(e_{t-1}, q_t^{(p)}\right)$$
The final emotion distribution is calculated via linear projection and softmax:
$$\hat{y}_t = \text{softmax}\left(W_e e_t + b_e\right)$$
Trained via standard cross-entropy loss across all conversational turns.

#### 6.5 Implementation Details
* **Recurrent Units:** Bidirectional or unidirectional GRUs with hidden dimension 100–300.
* **Dropout & Regularization:** Dropout rate 0.4 applied to utterance embeddings and recurrent layers.
* **Datasets Evaluated:** IEMOCAP, SEMAINE, and DailyDialog. Outperformed static baselines by 4–8% in F1 score.

#### 6.6 Gaps & Limitations (What DialogueRNN Does NOT Address)
1. **Multi-Party Bias:** DialogueRNN was strictly engineered for multi-speaker dialogues (Speaker A $\leftrightarrow$ Speaker B). In a single-user mental health journaling app, there is no second speaker to provide turn-taking transitions.
2. **Ignores Non-Verbal Silences:** In the original formulation, $u_t$ only exists when the user speaks. If the user stops speaking and sits in distressed silence for 30 seconds, DialogueRNN's time step halts, ignoring non-verbal facial affect during pauses.
3. **Sequential Latency:** Because of recurrence ($t-1 \to t$), it cannot be fully parallelized across time like a Transformer.

#### 6.7 Research Direction & Evolution
Later works replaced the GRUs with Graph Convolutional Networks (DialogueGCN, Ghosal et al., 2019) to capture non-sequential long-range dependencies, and injected commonsense knowledge graphs (COSMIC, Ghosal et al., 2020).

#### 6.8 Why DialogueRNN Was Selected for THIS Project
* **Single-User Mental Health Adaptation:** In our project, we adapt DialogueRNN's party-state GRU into a **Single-User Persistent Mood GRU** (see System Blueprint Component 1 & 5).
* **Requirement Alignment:** Directly satisfies **Requirement R2.5–R2.6** (Episode Linking across mid-thought pauses) and **Requirement R2.8** (modeling session-level emotional volatility and tracking whether a user's mood is spiraling over time).

### 7. Emotion-LLaMA: Multimodal Emotion Recognition and Reasoning with Instruction Tuning

* **Full Citation:** Zebang Cheng, et al. *"Emotion-LLaMA: Multimodal Emotion Recognition and Reasoning with Instruction Tuning."* In **Advances in Neural Information Processing Systems (NeurIPS 2024 / arXiv:2406.11161)**.
* **Paper Link:** [arXiv:2406.11161](https://arxiv.org/abs/2406.11161) | [Direct PDF](https://arxiv.org/pdf/2406.11161.pdf)
* **Official Code Repository:** [GitHub - ZebangCheng/Emotion-LLaMA](https://github.com/ZebangCheng/Emotion-LLaMA)

#### 7.1 Research Question Answered
> *How can an open-weight Multimodal Large Language Model (MLLM) be instruction-tuned to simultaneously achieve state-of-the-art multimodal emotion classification and generate grounded, natural-language behavioral rationales explaining WHY an emotion occurred, without suffering from affective hallucination?*

#### 7.2 Plain-Language Explanation (What It Aims To Do)
Traditional machine learning classifiers are black boxes: they output a categorical index or a probability score (e.g., `Class 3: Severe Distress (0.89)`). In clinical mental health applications, this is unacceptable. A user or a supervising therapist will immediately ask: *"Why did the AI decide I was distressed? What behavioral cues did it observe?"* If the AI cannot explain its reasoning, users lose trust, and clinicians cannot audit its safety.

Emotion-LLaMA bridges the gap between deep multimodal feature extractors and Large Language Models. It connects foundation video encoders and speech encoders to LLaMA through lightweight projection adapters. The model is instruction-tuned on specialized affective reasoning datasets. When fed a video clip and asked to analyze it, Emotion-LLaMA doesn't just output `"Depressed"`; it outputs a coherent, clinically grounded explanation:
> *"The user exhibits symptoms of acute anxiety. While their words express superficial calm ('I am doing fine with the workload'), their acoustic pitch exhibits significant high-frequency jitter and vocal tremors, accompanied by recurrent Action Unit 4 (brow furrowing) and avoidance of eye contact."*

#### 7.3 Exact Inputs & Outputs
* **Inputs:**
  1. **Visual Stream ($V$):** Raw video frames processed by visual foundation models (e.g., Video-MAE or CLIP-ViT).
  2. **Audio Stream ($A$):** Continuous speech audio waveform processed by speech foundation models (e.g., Whisper-encoder or HuBERT).
  3. **Text / Instructions ($T$):** Natural language user instruction (e.g., `"Analyze the emotional state of the speaker in this clip and describe the visual and vocal evidence supporting your diagnosis."`)
* **Outputs:** Natural language text sequence containing:
  * Discrete Emotion Classification / Polarity Verdict.
  * Evidence-Grounded Behavioral Rationale citing specific vocal and facial cues.

#### 7.4 Approach & Internal Mechanics (How It Works Under the Hood)

```
[Video Frames] -> Video-MAE / CLIP -> Visual Features Z_v --\
                                                             +-> [Q-Former / Linear Projectors] -> Visual Tokens H_v --\
[Speech Audio] -> Whisper / HuBERT  -> Audio Features Z_a --/                                                           +-> Concatenate
                                                                                                                         |   Tokens
[User Text Instruction] -> LLaMA Tokenizer -----------------------------------------------------> Text Tokens H_t ---/      |
                                                                                                                             v
                                                                                                                 [LLaMA Base LLM (Frozen)]
                                                                                                                 + LoRA Adapter Tuning
                                                                                                                             |
                                                                                                                             v
                                                                                                                 Autoregressive Generation:
                                                                                                                 "Label: Anxious. Rationale:
                                                                                                                  Vocal pitch drops and AU4..."
```

##### Step 1: Multimodal Foundation Encoders
* Video frames are downsampled and passed through Video-MAE / CLIP-ViT to yield frame-level visual embeddings $Z_v \in \mathbb{R}^{T_v \times d_v}$.
* Audio is transformed into 16 kHz log-mel spectrograms and passed through Whisper-large encoder to yield acoustic embeddings $Z_a \in \mathbb{R}^{T_a \times d_a}$.

##### Step 2: Modality Alignment Projectors
To feed $Z_v$ and $Z_a$ into the text token space of LLaMA, lightweight projection modules (linear layers or multi-head Q-Formers) project them to the hidden dimension $d_{\text{LLM}}$:
$$H_v = \text{Projector}_v(Z_v) \in \mathbb{R}^{N_v \times d_{\text{LLM}}}, \quad H_a = \text{Projector}_a(Z_a) \in \mathbb{R}^{N_a \times d_{\text{LLM}}}$$
where $N_v$ and $N_a$ are compressed sequence lengths (using temporal pooling or learnable queries to prevent token bloat).

##### Step 3: Affective Instruction Formatting
The input prompt to the LLM is structured as a unified token sequence:
$$\mathbf{H}_{\text{input}} = [H_v; H_a; \text{Embedding}(T_{\text{instruction}})]$$

##### Step 4: Parameter-Efficient Fine-Tuning (PEFT / LoRA)
To prevent catastrophic forgetting of language capabilities while adapting to affective reasoning, the foundation encoders and the base LLaMA weights $\theta_0$ are frozen. Low-Rank Adaptation (LoRA) matrices are injected into the transformer query and value projection weights:
$$W = W_0 + \Delta W = W_0 + B \cdot A$$
where $B \in \mathbb{R}^{d \times r}, A \in \mathbb{R}^{r \times k}$ with rank $r \ll d$. The model is trained autoregressively using standard causal language modeling loss over the rationale tokens:
$$\mathcal{L}_{\text{IT}} = -\sum_{i=1}^L \log P_\theta(y_i | y_{<i}, \mathbf{H}_{\text{input}})$$

#### 7.5 Implementation Details
* **Backbones:** LLaMA-2-7B / LLaMA-3-8B; Whisper-large-v3 for speech; Video-MAE-large for video.
* **LoRA Parameters:** Rank $r = 16$ or $32$; $\alpha = 64$; target modules: `q_proj`, `v_proj`, `k_proj`, `o_proj`.
* **Hardware:** Trained using DeepSpeed ZeRO-3 on 8 $\times$ NVIDIA A100 (80GB) GPUs.
* **Datasets Evaluated:** MER2023 Challenge dataset, MELD, and IEMOCAP for classification accuracy, and GPT-4 evaluated rationale quality.

#### 7.6 Gaps & Limitations (What Emotion-LLaMA Does NOT Address)
1. **Severe Latency & Compute Footprint:** Running an 8-billion-parameter MLLM requires 16GB+ of VRAM and takes 1.5 to 3.5 seconds per forward pass. It **cannot run in real-time on client edge devices** (violating sub-second streaming constraints).
2. **Risk of Hallucinatory Rationales:** If cross-modal alignment is imperfect, the LLM may generate convincing-sounding rationales citing non-existent facial cues (e.g., claiming the user smiled when they did not).
3. **No Continuous Streaming Memory:** Designed for single clip-level question-answering; lacks recurrent mechanisms to maintain an ongoing mental health state across a 30-minute rambling session.

#### 7.7 Research Direction & Evolution
Emotion-LLaMA pioneered multimodal affective reasoning. Current research is focusing on distilling Emotion-LLaMA's reasoning capabilities into compact 1B–3B Small Language Models (SLMs) and implementing decoupled architectures where a lightweight classifier acts immediately while the LLM generates rationales asynchronously.

#### 7.8 Why Emotion-LLaMA Was Selected for THIS Project
* **Direct Blueprint Role:** Represents the definitive architectural template for **HEAD-B (Explainable MLLM Head)** in our system blueprint.
* **Requirement Alignment:** Directly satisfies **Requirement R4.7** (generating human-readable explanations of detected cross-modal incongruence, e.g., explaining why a cheerful transcript masked an underlying vocal distress signal).

### 8. AffectGPT: A New Dataset, Model, and Benchmark for Multimodal Emotion Understanding

* **Full Citation:** Zheng Lian, Haoyu Chen, Lan Chen, Haiyang Sun, Licai Sun, Yong Ren, Zebang Cheng, Bin Liu, Rui Liu, Xiaojiang Peng, Jiangyan Yi, and Jianhua Tao. *"AffectGPT: A New Dataset, Model, and Benchmark for Emotion Understanding with Multimodal Large Language Models."* In **Proceedings of the 42nd International Conference on Machine Learning (ICML 2025)**, PMLR Vol. 267, pages 36993–37014.
* **Paper Link:** [PMLR Proceedings](https://proceedings.mlr.press/v267/lian25a.html)
* **Official Code Repository:** [GitHub - zeroQiaoba/AffectGPT](https://github.com/zeroQiaoba/AffectGPT)

#### 8.1 Research Question Answered
> *How can multimodal Large Language Models be prevented from hallucinating affective explanations, and what standardized benchmark protocol can rigorously evaluate both open-vocabulary emotion classification and the factual grounding of generated affective reasoning?*

#### 8.2 Plain-Language Explanation (What It Aims To Do)
While models like Emotion-LLaMA showed that MLLMs *can* output explanations, the affective computing community faced a critical dilemma: **How do we evaluate whether an AI's explanation is truthful?** If an MLLM outputs *"The user is angry because their voice raised by 10 dB,"* but in reality the user was whispering, standard language metrics like BLEU or ROUGE still give high scores if the grammar looks fluent.

AffectGPT delivers a complete scientific framework to solve this:
1. **MER-Caption Dataset:** A massive dataset of **115,000 video samples** annotated with over 2,000 fine-grained descriptive emotion categories and verifiable behavioral ground-truth descriptions.
2. **AffectGPT Model:** An MLLM architecture featuring specialized **Pre-Fusion Operations** that extract emotionally concentrated "hotspots" before feeding features to the language model.
3. **MER-UniBench:** The first standardized evaluation benchmark that evaluates not only whether the model got the emotion right, but whether its explanation is mathematically grounded in the actual acoustic and visual evidence.

#### 8.3 Exact Inputs & Outputs
* **Inputs:** Multimodal video, audio, and transcript streams + open-ended natural language affective prompts.
* **Outputs:**
  * Open-vocabulary emotion classifications (selecting from over 2,000 fine-grained categories).
  * Structurally grounded emotional captions and reasoning chains.
  * Evaluated scores across traditional metrics (Acc, UAR, F1) and generative metrics (Grounding Faithfulness, Emotional Wheel Distance).

#### 8.4 Approach & Internal Mechanics (How It Works Under the Hood)

```
[Raw Multimodal Streams]
  Video Frames  -----> Spatial ViT ----\
                                        +--> [Affective Pre-Fusion Module]
  Speech Audio  -----> Audio ViT ------/     (Extracts Emotional Hotspots via Local-Global Attention)
                                                         |
                                                         v
                                                [Compressed Tokens]
                                                         |
[Task Instruction Prompts] ------------------------------+
                                                         |
                                                         v
                                             [Multimodal LLM Backbone]
                                                         |
                                                         v
                                              [Grounded Outputs]
                                              - Open-Vocabulary Emotion Label
                                              - Factual Affective Rationale
                                              - Evaluated via MER-UniBench
```

##### Step 1: Affective Pre-Fusion Operations
Standard MLLMs project hundreds of raw video and audio frames into the LLM, diluting brief affective cues (like a 200ms micro-expression or vocal tremor). AffectGPT introduces a pre-fusion module that performs temporal local-global attention to locate **Affective Hotspots** (moments of peak emotional intensity) and compresses the sequence into emotionally dense tokens before feeding them to the LLM.

##### Step 2: Large-Scale Descriptive Pre-Training (MER-Caption)
AffectGPT is trained on the MER-Caption dataset, which contains 115k samples annotated with:
* Coarse basic emotions (Ekman 6).
* Fine-grained nuanced states (over 2,000 psychological descriptors like *Apprehensive, Resentful, Melancholic*).
* Verifiable physical evidence descriptions (e.g., *AU12 lip corner puller active, fundamental frequency shifted upward by 40 Hz*).

##### Step 3: MER-UniBench Grounding Evaluation Suite
To measure explanation factuality without relying on human evaluators, AffectGPT introduces a three-tiered metric suite:
1. **Emotion Wheel Distance (EWD):** Measures semantic distance on Plutchik's / Schlosberg's emotional wheel between predicted and true states.
2. **Grounding Factuality Ratio (GFR):** Automatically parses the generated rationale to extract cited facial action units and acoustic cues, checking whether those specific AUs or acoustic shifts were objectively detected by low-level feature extractors (OpenFace / openSMILE).
3. **Reasoning Completeness Score:** Evaluates whether the generated text covers trigger, internal state, and behavioral manifestation.

#### 8.5 Implementation Details
* **MLLM Backbone:** Built on Qwen-VL-Chat / LLaMA-3-Instruct.
* **Feature Extractors:** CLIP-ViT-L/14 for vision; Whisper-large-v3 for audio.
* **Training Pipeline:** Two-stage training: (1) Pre-fusion adapter pre-training on MER-Caption; (2) Supervised instruction fine-tuning using LoRA.
* **Open Source:** Full code, evaluation benchmarks, and dataset access open-sourced under the `zeroQiaoba/AffectGPT` repository.

#### 8.6 Gaps & Limitations (What AffectGPT Does NOT Address)
1. **Clinical Mental Health Domain Gap:** MER-Caption consists primarily of media, film, and interview clips. It does not reflect naturalistic, private, unscripted mental health journaling sessions.
2. **Non-Real-Time Execution:** Like Emotion-LLaMA, forward inference takes seconds, precluding it from operating on streaming 3-second audio buffers.
3. **Heavy Pre-Training Resource Requirements:** Reproducing the full pre-fusion training requires multi-node GPU clusters.

#### 8.7 Research Direction & Evolution
AffectGPT set the benchmark standard for multimodal affective reasoning. Recent iterations (AffectGPT-R1) incorporate reinforcement learning (Group Relative Policy Optimization - GRPO) to directly optimize reasoning chains using reward models based on emotion wheel distances.

#### 8.8 Why AffectGPT Was Selected for THIS Project
* **Evaluation Framework for Explainability:** Provides the exact evaluation methodology needed for **Phase 6** of our MLDLC plan.
* **Requirement Alignment:** Directly satisfies **Requirement R8.5** and **Research Gap GAP-05** by providing the scientific tools to prove to supervisors and reviewers that our system's generated mental-health rationales are objectively grounded in real vocal and facial data.

## Part II: Core Technical Overviews (Papers 9 to 20)

For the remaining twelve Tier 1 papers, the following structured summaries distill their inputs, outputs, core innovations, research angles, and specific relevance to our mental health monitoring pipeline.

---

### 9. MERBench: Unified Benchmark & Toolkit for MER in the Wild
* **Full Citation:** Zheng Lian, et al. *"MERBench: A Unified Evaluation Benchmark for Multimodal Emotion Recognition in the Wild."* ACM MM 2024 / IEEE TAFFC 2024. [GitHub - zeroQiaoba/MERTools](https://github.com/zeroQiaoba/MERTools)
* **Inputs & Outputs:** Input: Raw multimodal video/audio/text clips across multiple public datasets. Output: Standardized benchmark performance metrics (Acc, F1, UAR, cross-corpus generalization).
* **Core Idea & What It Does:** Prior to MERBench, multimodal emotion research suffered from a severe reproducibility crisis: different research labs used incompatible train/val/test splits, arbitrary evaluation metrics, and conflicting feature extractors, making it impossible to tell which architecture was genuinely superior. MERBench solves this by providing a unified benchmarking codebase with fixed speaker-independent splits, standardized pre-extracted feature banks, and open evaluation harnesses.
* **Research Question / Angle Addressed:** Addresses the fundamental evaluation integrity question: *How can multimodal affective architectures be fairly and reproducibly compared across diverse in-the-wild corpora under identical experimental conditions?*
* **Relevance to Our Project:** Directly dictates the **Phase 6 Evaluation Protocol** in our MLDLC plan (Requirement R8.5). Adopting MERBench's standardized splits and evaluation scripts ensures that our single-modal vs. multimodal ablation tables in the final thesis are methodologically unassailable.

---

### 10. KAMUH: Real-Time Online Audiovisual Emotion Recognition System
* **Full Citation:** Rasendrasoa, et al. *"KAMUH: A Real-Time Online Audiovisual Emotion Recognition System."* In Proceedings of ACM ICMI 2022.
* **Inputs & Outputs:** Input: Live continuous webcam video stream (30 fps) and microphone audio stream (16 kHz). Output: Real-time, continuous online emotion predictions emitted under streaming latency constraints.
* **Core Idea & What It Does:** Proves that multimodal emotion recognition can transition from offline, pre-cut video clips to a true real-time, low-latency deployment. KAMUH implements an online sliding-window buffer for audio (accumulating 3-second rolling audio segments) paired with per-frame facial expression analysis, synchronizing them at runtime with sub-second latency.
* **Research Question / Angle Addressed:** Addresses the streaming deployment problem: *How can asynchronous video and audio streams be buffered, segmented, and fused online in real time without waiting for full session completion?*
* **Relevance to Our Project:** Serves as the primary operational architecture reference for our **Streaming Pipeline (Phase 5)**. Directly satisfies **Requirement R8.1–R8.2** (sub-second per-utterance latency budgets) and proves that rolling 3-second audio windows coupled with frame-level face tracking can run in a live app without server lags.

---

### 11. Wav2Vec 2.0: Self-Supervised Learning of Speech Representations
* **Full Citation:** Alexei Baevski, et al. *"wav2vec 2.0: A Framework for Self-Supervised Learning of Speech Representations."* NeurIPS 2020. [arXiv:2006.11477](https://arxiv.org/abs/2006.11477)
* **Inputs & Outputs:** Input: Raw speech audio waveform sampled at 16 kHz. Output: Dense contextualized latent representations ($\mathbb{R}^{T \times 768}$).
* **Core Idea & What It Does:** Solves the acute scarcity of labeled speech data by pre-training on 50,000+ hours of unlabeled speech. It masks raw audio latent vectors and solves a contrastive task over a quantized codebook (via Gumbel-Softmax), learning deep acoustic structures that generalize across speakers, accents, and recording environments.
* **Research Question / Angle Addressed:** *How can raw, unlabeled speech audio be leveraged via self-supervised contrastive learning to build universal acoustic representations that transfer to downstream tasks with minimal fine-tuning?*
* **Relevance to Our Project:** Serves as the **Primary Speech Feature Encoder** for our voice analysis branch (Phase 3 & Requirement R4.1). Replacing handcrafted MFCCs with a fine-tuned Wav2Vec 2.0 backbone significantly mitigates the 13% speaker-independence drop identified in Challenge C3.

---

### 12. HuBERT: Hidden-Unit BERT for Speech Processing
* **Full Citation:** Wei-Ning Hsu, et al. *"Hidden-Unit BERT for Speech (HuBERT)."* IEEE TASLP 2021. [arXiv:2106.07447](https://arxiv.org/abs/2106.07447)
* **Inputs & Outputs:** Input: Raw 16 kHz speech audio waveforms. Output: Discrete-unit contextualized hidden representations ($\mathbb{R}^{T \times 768}$).
* **Core Idea & What It Does:** While Wav2Vec 2.0 uses contrastive learning, HuBERT uses an acoustic BERT-style masked prediction objective. It clusters acoustic features offline into discrete units using k-means, and forces a transformer encoder to predict those masked cluster IDs. This BERT-like masked language modeling objective captures longer prosodic contours and fundamental frequency trends more stably than contrastive models.
* **Research Question / Angle Addressed:** *Can acoustic masked unit prediction overcome the hyperparameter instability of contrastive speech pre-training while capturing richer prosodic and paralinguistic structure?*
* **Relevance to Our Project:** Acts as the **Direct Acoustic Ablation Alternative** to Wav2Vec 2.0 in Phase 3. Because HuBERT excels at long-range prosodic tracking, it is particularly sensitive to vocal flat affect, psychomotor slowing, and intonation shifts characteristic of depression.

---

### 13. Whisper: Robust Speech Recognition via Large-Scale Weak Supervision
* **Full Citation:** Alec Radford, et al. *"Robust Speech Recognition via Large-Scale Weak Supervision."* ICML 2023. [arXiv:2212.04356](https://arxiv.org/abs/2212.04356)
* **Inputs & Outputs:** Input: Raw audio containing continuous speech. Output: High-accuracy text transcripts with word-level start/end timestamps (via WhisperX).
* **Core Idea & What It Does:** An encoder-decoder Transformer trained on 680,000 hours of weakly supervised multilingual audio scraped from the web. Unlike traditional ASR models trained on pristine speech, Whisper is exceptionally resilient to background chatter, heavy accents, mumbling, and colloquial phrasing.
* **Research Question / Angle Addressed:** *Does extreme dataset scale and diversity in weakly supervised pre-training solve the out-of-domain generalization problem in automated speech recognition?*
* **Relevance to Our Project:** Powers the automated **Transcript Stream and Utterance Boundary Segmenter (Phase 5)**. Paired with WhisperX, it directly satisfies **Requirements R2.1–R2.4** by extracting exact word-level pause durations to segment the user's natural rambling without manual intervention.

---

### 14. POSTER++: Simpler & Stronger Facial Expression Recognition Network
* **Full Citation:** Jiawei Mao, et al. *"POSTER++: A Simpler and Stronger Facial Expression Recognition Network."* ICCV 2023. [arXiv:2304.06334](https://arxiv.org/abs/2304.06334)
* **Inputs & Outputs:** Input: Cropped face image ($224 \times 224$) and extracted facial landmarks. Output: Emotion classification logits and spatial feature maps.
* **Core Idea & What It Does:** Traditional Facial Expression Recognition (FER) models either rely purely on image pixels (which get distracted by background, hair, and lighting) or purely on landmarks (which miss subtle skin wrinkles). POSTER++ introduces a dual-stream pyramid cross-fusion vision transformer that uses facial landmarks to steer windowed cross-attention directly toward emotionally expressive zones (eyes, brow, mouth corners) while pruning redundant background tokens.
* **Research Question / Angle Addressed:** *How can facial landmarks guide visual transformer attention mechanisms to focus on salient expression regions under severe pose and lighting variations?*
* **Relevance to Our Project:** Default backbone for the **Facial Analysis Branch (Phase 3 & Requirement R4.1)**. Its landmark-guided attention provides high robustness to user head movements and uneven webcam lighting while maintaining a compact parameter footprint suitable for real-time inference.

---

### 15. MMIN: Missing Modality Imagination Network for Incomplete Audio-Visual Data
* **Full Citation:** Jiandian Zhao, et al. *"Missing Modality Imagination Network for Emotion Recognition with Incomplete Audio-Visual Data."* ACL 2021.
* **Inputs & Outputs:** Input: Multimodal sequences with one modality missing at test time (e.g., audio present, camera blocked). Output: Emotion classification utilizing hallucinated latent features.
* **Core Idea & What It Does:** Standard multimodal architectures crash or experience severe performance collapse when a modality is missing at test time. MMIN introduces an **Imagination Network** based on cycle consistency: it trains an autoencoder to translate available acoustic features into the latent visual feature space (and vice-versa). If the webcam drops, MMIN "imagines" the missing facial representations from the audio, allowing the fusion classifier to operate uninterrupted.
* **Research Question / Angle Addressed:** *How can a multimodal system maintain high classification accuracy when test-time sensors unexpectedly drop, without retraining separate models for every missing-data permutation?*
* **Relevance to Our Project:** Core technical blueprint for **Missing-Modality Handling (Requirements R1.1, R5.1–R5.4)**. Allows our app to gracefully handle camera-off sessions or transient webcam coverage without crashing or generating empty readings.

---

### 16. MER-Calibration: Multimodal Emotion Recognition Calibration in Conversations
* **Full Citation:** Zhang, et al. *"Multimodal Emotion Recognition Calibration in Conversations."* EMNLP 2024.
* **Inputs & Outputs:** Input: Raw uncalibrated emotion prediction probability distributions from multimodal models. Output: Statistically calibrated posterior probabilities where confidence accurately reflects empirical accuracy.
* **Core Idea & What It Does:** Demonstrates that modern deep multimodal models suffer from severe overconfidence: when a model outputs 95% confidence on an emotion label, its real-world empirical accuracy is often below 70%. In health-adjacent applications, uncalibrated confidence can mislead users into believing they are severely anxious when the AI is simply guessing. MER-Calibration applies temperature scaling and Dirichlet calibration tailored to multimodal conversational dynamics.
* **Research Question / Angle Addressed:** *How can confidence calibration be formalized and corrected for multimodal conversational emotion classifiers to ensure trustworthy uncertainty estimation?*
* **Relevance to Our Project:** Provides the **Calibration Layer (Requirement R4.3, R6.5, and Research Gap GAP-09)**. Guarantees that the confidence scores displayed on the user's dashboard reflect genuine statistical trustworthiness, defaulting safely to "Insufficient Signal" (R6.5) when ambiguity is detected.

---

### 17. DAIC-WOZ: The Distress Analysis Interview Corpus
* **Full Citation:** Jonathan Gratch, et al. *"The Distress Analysis Interview Corpus (DAIC): Architecture and Pre-Validation."* LREC 2014. [Dataset Portal](https://dcapswoz.ict.usc.edu/)
* **Inputs & Outputs:** Input: Synchronized audiovisual recordings and transcripts of semi-structured clinical interviews conducted by an avatar (Ellie). Output: Validated psychometric depression and PTSD severity scores (PHQ-8).
* **Core Idea & What It Does:** The canonical clinical research dataset that bridges computer science emotion recognition with clinical psychology. Unlike acted emotion datasets (IEMOCAP, RAVDESS), DAIC-WOZ records actual patients suffering from clinical depression and PTSD, linking observable non-verbal behaviors (downward gaze, speech latency, smile duration) to clinically validated PHQ-8 depression scores.
* **Research Question / Angle Addressed:** *Can standardized virtual agent clinical interviews reliably elicit and capture quantifiable non-verbal behavioral markers correlated with diagnostic psychiatric scores?*
* **Relevance to Our Project:** Acts as the **Clinical Grounding Bridge (Requirement R6.2–R6.3)** for our Two-Stage Labeling pipeline. Allows us to evaluate whether the acoustic and facial representations learned by our models correlate with real clinical depression indicators.

---

### 18. Mental-Health-Distress-Review: Systematic Review on Multimodal Distress Detection
* **Full Citation:** Systematic Review Authors. *"A Systematic Review on Automated Multimodal Mental Health and Distress Detection."* Springer Nature 2026. [Nature Article](https://www.nature.com/articles/s44184-024-00112-8)
* **Inputs & Outputs:** Input: Meta-analysis of over 100 clinical multimodal emotion recognition studies. Output: Comprehensive taxonomy of sensing technologies, validation pitfalls, and deployment architectures.
* **Core Idea & What It Does:** Synthesizes the clinical affective computing landscape, establishing that while multimodal sensing significantly outperforms unimodal screening, the entire field is bottlenecked by privacy risks and lack of in-the-wild generalization. It concludes that on-device inference, federated learning, and differential privacy constitute the only ethically viable stack for real-world deployment.
* **Research Question / Angle Addressed:** *What are the validated sensing modalities, architectural bottlenecks, and regulatory privacy constraints governing the translation of automated distress detection from labs to clinical practice?*
* **Relevance to Our Project:** The **Primary Theoretical Citation for Chapter 1 & Chapter 4** of the thesis. Directly validates our privacy-first system design (Requirement R8.3–R8.4 and Research Gap GAP-01), formally defending our decision to keep all raw biometric video/audio strictly on-device.

---

### 19. MER-Mega-Survey-2026: Comprehensive Survey on Multimodal Emotion Recognition
* **Full Citation:** Survey Authors. *"A Survey on Multimodal Emotion Recognition: Methods, Datasets, and Future Directions."* Information Fusion / ScienceDirect 2026.
* **Inputs & Outputs:** Input: Broad analysis of multimodal emotion recognition literature from early rule-based systems to modern generative MLLMs. Output: Comprehensive architectural taxonomy (Early, Late, Hybrid, Cross-Modal, Graph, and Foundation model fusion).
* **Core Idea & What It Does:** An authoritative survey synthesizing over 200 modern papers. It mathematically establishes that simple concatenation and late majority voting fail to exploit cross-modal complementarity, formally declaring cross-attention and selective gating as the state-of-the-art paradigm.
* **Research Question / Angle Addressed:** *How has the multimodal affective fusion landscape evolved, and what are the open frontiers regarding temporal dynamics, noisy environments, and foundation model adaptation?*
* **Relevance to Our Project:** Core backbone citation for **Chapter 2 (Literature Review)** of the thesis. Provides the peer-reviewed justification for choosing MulT-style attention over obsolete concatenation or decision-level voting (Requirement R4.2).

---

### 20. SER-Mega-Review-2026: Comprehensive Survey of Modern Speech Emotion Architectures
* **Full Citation:** Survey Authors. *"Speech Emotion Recognition: A Comprehensive Survey of Modern Architectures."* Information Fusion 2026.
* **Inputs & Outputs:** Input: Meta-analysis of acoustic feature representations, deep architectures, and cross-lingual speech emotion benchmarks. Output: Definitive findings answering 11 foundational research questions in speech affect.
* **Core Idea & What It Does:** An exhaustive acoustic review that formally settles the representation debate in speech emotion: it demonstrates that self-supervised foundation representations (Wav2Vec 2.0, HuBERT, WavLM) decisively outperform classical handcrafted acoustic features (MFCCs, eGeMAPS) on in-the-wild speech, while warning that models evaluated on random splits overfit by ~13% compared to speaker-independent splits.
* **Research Question / Angle Addressed:** *What architectural paradigms and feature representations definitively maximize generalization in Speech Emotion Recognition across diverse speakers and acoustic noise?*
* **Relevance to Our Project:** Serves as the definitive academic defense for our **Voice Branch Design (Phase 3)**, validating our choice to use fine-tuned self-supervised representations as the primary voice model while retaining eGeMAPS solely as an interpretable baseline.

## Part III: Comparative Synthesis Matrix & System Blueprint

To assist in architectural decision-making and thesis presentation, the table below compares the core architectural designs across all key engineering dimensions.

### Comparative Engineering Matrix

| Paper ID | Primary Architectural Innovation | Temporal Handling | Noise & Reliability Handling | Missing Modality Handling | Compute Footprint & Edge Feasibility | Mental Health Utility |
|---|---|---|---|---|---|---|
| **1. MulT** | Pairwise Directional Cross-Modal Attention | Fully unaligned continuous sequences (native rates) | Vulnerable (aggregates noise indiscriminately) | None (crashes if stream is missing) | Moderate ($\mathcal{O}(T^2)$ attention, server/PC GPU) | Core fusion template for asynchronous video & audio |
| **2. M3ER** | Modality Check filter + Multiplicative Fusion | Utterance-level pooled features | Outstanding (dynamically downweights noisy streams) | Graceful (gates out corrupted modality) | Very Lightweight (fast MLP, edge/mobile viable) | Auditability (exposes modality contribution weights) |
| **3. MISA** | Subspace Disentanglement (Invariant vs. Specific) | Utterance-level pooled representations | Robust to identity bias & acoustic channel noise | Moderate (specific subspaces help) | Lightweight (projection heads, edge viable) | Eliminates speaker identity bias across patients |
| **4. Self-MM** | Self-Supervised Unimodal Label Generation (ULGM) | Sequence-level (LSTMs + BERT) | High (encoders trained independently) | Excellent (unimodal heads fully functional) | Lightweight (standard BERT/LSTM, edge viable) | Guarantees text-only & voice-only modes operate independently |
| **5. UniMSE** | Unified Generative & Contrastive Affective Framework | Sequence-level multimodal tokenization | Moderate | Moderate (prompts can adapt) | Heavy (full T5 encoder-decoder backbone) | Dual head: outputs discrete emotion + continuous valence |
| **6. DialogueRNN** | Tripartite GRU (Global, Speaker State, Emotion) | Multi-turn conversational sequence | Moderate | None (halts during silent pauses) | Very Lightweight (recurrent GRU, highly edge viable) | Tracks patient emotional inertia & mood trajectory over time |
| **7. Emotion-LLaMA** | Multimodal Instruction-Tuned MLLM (LoRA) | Downsampled video & audio tokens | High (instruction context filters cues) | High (can prompt on available streams) | Extremely Heavy (7B/8B LLM, cloud GPU required) | Generates grounded natural-language rationales for clinicians |
| **8. AffectGPT** | Affective Pre-Fusion + Grounding Benchmarking | Pre-fusion temporal hotspot compression | High (hotspot attention isolates peaks) | Moderate | Extremely Heavy (MLLM backbone, cloud GPU required) | Evaluates explanation factuality without hallucination |

---

## Architectural Synthesis: The Unified Mental Health Blueprint

By deconstructing these papers, we arrive at the unified system design for our mental health emotion monitoring pipeline:

```
[Camera Video Frames] -----> Face Branch (POSTER++) ---------\
                                                              +--> MISA Disentanglement Layer
[Microphone Audio]    -----> Voice Branch (Wav2Vec 2.0) -----+    (Separates Speaker Identity from Affect)
                                                              |                 |
[WhisperX Transcripts] ----> Text Branch (BERT / RoBERTa) ---/                 v
                                                                   MulT Cross-Modal Attention
                                                                  (Directional Asynchronous Alignment)
                                                                                |
                                                                                v
                                                                      M3ER Reliability Gating
                                                                  (Suppresses Sensor Noise & Drops)
                                                                                |
                                                                                v
                                                                 DialogueRNN Persistent Mood GRU
                                                              (Tracks Single-User Mood Volatility Across Time)
                                                                                |
                                                                                v
                                                                   MER-Calibration Safety Layer
                                                               (Aligns Probabilities with Empirical Truth)
                                                                                |
                                                                                v
                                                                      [Dual Output Verdict]
                                                      Categorical Mental Health State + Continuous Valence Trend
```

* **Ingestion & Alignment:** Handled asynchronously via **WhisperX** pause detection (Paper 13) and **MulT** cross-attention (Paper 1).
* **Identity Removal:** Handled via **MISA** invariant subspace projection (Paper 3).
* **Sensor Noise & Dropout:** Handled via **M3ER** multiplicative gating (Paper 2) and **MMIN** imagination (Paper 15).
* **Self-Sufficient Branches:** Handled via **Self-MM** multi-task training (Paper 4).
* **Continuous Tracking:** Handled via **DialogueRNN** state memory (Paper 6).
* **Clinical Safety & Grounding:** Calibrated via **MER-Calibration** (Paper 16) and explained asynchronously via **Emotion-LLaMA** (Paper 7).

---
*End of Shortlisted Paper Explanations Document.*
