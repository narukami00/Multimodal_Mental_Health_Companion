# AI-Based Mental Health Emotion Monitoring

Multimodal emotion recognition system combining facial, vocal, and textual analysis for mental health monitoring.

---

## Repository Structure

`
F:\__Projects\_Research\Sys_Mental_health\
├── docs/
│   ├── MLDLC_Plan_and_Curated_Papers.md    # Full ML Development Lifecycle plan + 59 paper mappings
│   ├── shortlisted_paper_explanations.md   # Exhaustive technical deconstruction of Tier 1 papers
│   ├── Research_Gap_Analysis.md            # 12 identified research gaps across 3 priority tiers
│   ├── idea.md                             # Extended system conceptualization & notes
│   ├── generated_reports/                  # Published PDF reports & volumes
│   │   ├── MULTIMODAL_MENTAL_HEALTH_AI_LITERATURE_REVIEW_MASTER.pdf
│   │   ├── VOL_1_ARCHITECTURES_AND_METHODOLOGIES.pdf
│   │   ├── VOL_2_PAPERS_COMPENDIUM_AND_READING_GUIDE.pdf
│   │   ├── VOL_3_DATASETS_TOOLS_AND_BENCHMARKS.pdf
│   │   └── VOL_4_CHALLENGES_GAPS_AND_SYSTEM_BLUEPRINT.pdf
│   └── specifications/                     # Core requirements and proposal sources
│       ├── Multimodal_Emotion_Pipeline_Requirements_Specification.docx
│       ├── requirements_spec_extracted.txt
│       ├── idea.docx
│       └── idea_extracted.txt
│
├── data/
│   ├── raw_reviews/                        # Original outputs from 8 AI agents (ChatGPT, Claude, DeepSeek, etc.)
│   ├── extracted_reviews/                  # Normalized text & markdown extractions with preserved hyperlinks
│   └── metadata/                           # JSON registries
│       ├── candidate_papers_matched.json   # 59-paper match matrix across all agents
│       └── extracted_urls.json             # Reference URL catalog
│
├── scripts/
│   ├── build_pdfs.py                       # ReportLab script compiling the 5 PDF report volumes
│   ├── curated_data.py                     # Programmatic dictionary of papers, datasets, tools & blueprint
│   ├── generate_shortlisted_docs.py        # Generator for shortlisted paper documentation
│   └── archive/                            # Deprecated orchestration prompts (SLAVE_PROMPT, PROMPT_BUILD_PDFS)
│
└── mobile_application/
    ├── design-documentation.md             # Mobile interface & UX specs
    └── features.md                         # Feature breakdown for the user app
```

---

## Core Documentation Index

- **Shortlisted Paper Explanations**: `docs/shortlisted_paper_explanations.md`
- **MLDLC Plan & Curated Papers**: `docs/MLDLC_Plan_and_Curated_Papers.md`
- **Research Gap Analysis**: `docs/Research_Gap_Analysis.md`
- **Requirements Specification**: `docs/specifications/requirements_spec_extracted.txt`
- **Curated Data Registry**: `scripts/curated_data.py`
