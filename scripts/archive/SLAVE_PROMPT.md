# TASK SPECIFICATION FOR CURATOR SLAVE

## Objective
Curate and synthesize all literature review findings from the 8 AI agents (ChatGPT, Claude, DeepSeek, Gemini, GLM, Kimi, MiniMax, Qwen) stored in F:\__Projects\_Research\Sys_Mental_health\litertature_review\ along with the project specification in F:\__Projects\_Research\Sys_Mental_health\idea.docx.

Produce publication-grade, hyperlinked, comprehensive PDF documents using Python's 'reportlab' library (installed in Python 3.13):
1. MULTIMODAL_MENTAL_HEALTH_AI_LITERATURE_REVIEW_MASTER.pdf (All-in-one Master Compendium)
2. VOL_1_ARCHITECTURES_AND_METHODOLOGIES.pdf
3. VOL_2_PAPERS_COMPENDIUM_AND_READING_GUIDE.pdf
4. VOL_3_DATASETS_TOOLS_AND_BENCHMARKS.pdf
5. VOL_4_CHALLENGES_GAPS_AND_SYSTEM_BLUEPRINT.pdf

All files must be saved in F:\__Projects\_Research\Sys_Mental_health\.

## Requirements:
1. Zero omissions: Include all papers, surveys, datasets, tools, challenges, and architectures mentioned across the 8 reviews.
2. Cross-referencing: Every paper and resource must state explicitly which agent(s) mentioned it (e.g. ChatGPT, Claude, DeepSeek, Gemini, GLM, Kimi, MiniMax, Qwen).
3. Detailed breakdown for each paper: Title, Authors, Year, Venue, Agent Citations, URLs (Paper, ArXiv, GitHub, Dataset), Problem Solved, Inputs/Outputs, Methodology (How & Why), Mental Health Applicability, Reading Priority.
4. Datasets: Complete directory with modalities, hours/samples, download links, licensing, and usage guide.
5. System Architecture Blueprint: Fully mapped to idea.docx with dual-head discriminative + explainable MLLM core, edge privacy, and streaming latency budget.
6. Execution: Write and run python scripts in F:\__Projects\_Research\Sys_Mental_health\ to generate the PDFs and verify their integrity.
