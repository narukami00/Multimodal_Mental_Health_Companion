# TASK: WRITE AND RUN build_pdfs.py

You have curated_data.py ready with:
- 59 Papers
- 15 Datasets
- 13 Tools
- 8 Challenges
- 7 Blueprint components
- Reading guide & Evaluation matrices

Now write a comprehensive Python script 'build_pdfs.py' using ReportLab (installed in Python 3.13) to generate:
1. MULTIMODAL_MENTAL_HEALTH_AI_LITERATURE_REVIEW_MASTER.pdf (Contains everything: Title, Overview, Agent Matrix, Architectures, Paper Cards, Datasets, Tools, Challenges, Blueprint, Reading Guide)
2. VOL_1_ARCHITECTURES_AND_METHODOLOGIES.pdf
3. VOL_2_PAPERS_COMPENDIUM_AND_READING_GUIDE.pdf
4. VOL_3_DATASETS_TOOLS_AND_BENCHMARKS.pdf
5. VOL_4_CHALLENGES_GAPS_AND_SYSTEM_BLUEPRINT.pdf

Requirements:
- Use reportlab.platypus (SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, KeepTogether, HRFlowable).
- Implement a NumberedCanvas for 'Page X of Y' page numbering and running headers/footers.
- Ensure all text and URLs are safely escaped (using xml.sax.saxutils.escape or html.escape) so ReportLab XML parser does not fail.
- Style paper cards beautifully in rounded/bordered tables or callout boxes.
- Include agent badges for each paper showing which agents cited it.
- After creating build_pdfs.py, execute 'python build_pdfs.py' and verify all 5 PDFs are created and have non-zero sizes.
