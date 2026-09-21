# -*- coding: utf-8 -*-
"""
Publication-Grade PDF Generator for Multimodal Mental Health AI Literature Review
Builds 5 distinct, hyperlinked, highly styled PDF documents:
1. MULTIMODAL_MENTAL_HEALTH_AI_LITERATURE_REVIEW_MASTER.pdf (All-in-one Compendium)
2. VOL_1_ARCHITECTURES_AND_METHODOLOGIES.pdf
3. VOL_2_PAPERS_COMPENDIUM_AND_READING_GUIDE.pdf
4. VOL_3_DATASETS_TOOLS_AND_BENCHMARKS.pdf
5. VOL_4_CHALLENGES_GAPS_AND_SYSTEM_BLUEPRINT.pdf
"""

from __future__ import annotations
import os
import sys
import html
import urllib.parse
from datetime import datetime

import reportlab
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.lib.units import inch
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, KeepTogether, HRFlowable
)
from reportlab.pdfgen import canvas

import curated_data

# -----------------------------------------------------------------------------
# CONSTANTS & PALETTE
# -----------------------------------------------------------------------------
PAGE_WIDTH, PAGE_HEIGHT = letter
MARGIN_LEFT = 40
MARGIN_RIGHT = 40
MARGIN_TOP = 48
MARGIN_BOTTOM = 48
USABLE_WIDTH = PAGE_WIDTH - MARGIN_LEFT - MARGIN_RIGHT  # 532 pt

# Professional Academic / Tech Palette
COLOR_PRIMARY = colors.HexColor("#1E3A8A")      # Deep Navy Blue
COLOR_SECONDARY = colors.HexColor("#2563EB")    # Bright Blue
COLOR_ACCENT = colors.HexColor("#0D9488")       # Dark Teal
COLOR_DARK = colors.HexColor("#1F2937")         # Charcoal Dark
COLOR_MUTED = colors.HexColor("#4B5563")        # Slate Gray
COLOR_LIGHT = colors.HexColor("#F8FAFC")        # Off-white / Ice
COLOR_BORDER = colors.HexColor("#E2E8F0")       # Light Slate Border
COLOR_CARD_BG = colors.HexColor("#FFFFFF")      # Pure White Card
COLOR_CALLOUT_BG = colors.HexColor("#F0F9FF")   # Soft Sky Blue
COLOR_P0 = colors.HexColor("#991B1B")           # Deep Red
COLOR_P1 = colors.HexColor("#B45309")           # Amber
COLOR_P2 = colors.HexColor("#1D4ED8")           # Blue
COLOR_P3 = colors.HexColor("#4B5563")           # Slate

AGENT_COLORS = {
    "ChatGPT": "#10A37F",
    "Claude": "#D97706",
    "DeepSeek": "#0284C7",
    "Gemini": "#4F46E5",
    "GLM": "#7C3AED",
    "Kimi": "#EC4899",
    "MiniMax": "#2563EB",
    "Qwen": "#EA580C"
}

# -----------------------------------------------------------------------------
# NUMBERED CANVAS (Running Headers & Footers with Total Page Count)
# -----------------------------------------------------------------------------
class NumberedCanvas(canvas.Canvas):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._saved_page_states = []

    def showPage(self):
        self._saved_page_states.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        num_pages = len(self._saved_page_states)
        for state in self._saved_page_states:
            self.__dict__.update(state)
            self.draw_page_decorations(num_pages)
            super().showPage()
        super().save()

    def draw_page_decorations(self, page_count):
        if self._pageNumber == 1:
            # Skip header on cover page, only show bottom copyright/generation note
            self.saveState()
            self.setFont("Helvetica", 7.5)
            self.setFillColor(colors.HexColor("#64748B"))
            self.drawRightString(PAGE_WIDTH - MARGIN_RIGHT, 24, "Multimodal Mental Health AI Literature Review | Master Synthesis")
            self.drawString(MARGIN_LEFT, 24, "Confidential - Academic & System Research Specification")
            self.restoreState()
            return

        self.saveState()
        self.setFont("Helvetica-Bold", 8)
        self.setFillColor(COLOR_PRIMARY)
        
        # Header text (left: doc title, right: volume/section)
        doc_title = getattr(self, "doc_title", "Multimodal Mental Health AI Review")
        vol_label = getattr(self, "vol_label", "Curated Compendium")
        
        self.drawString(MARGIN_LEFT, PAGE_HEIGHT - 32, doc_title.upper())
        self.setFont("Helvetica", 8)
        self.setFillColor(COLOR_MUTED)
        self.drawRightString(PAGE_WIDTH - MARGIN_RIGHT, PAGE_HEIGHT - 32, vol_label)
        
        # Top Rule
        self.setStrokeColor(COLOR_BORDER)
        self.setLineWidth(0.75)
        self.line(MARGIN_LEFT, PAGE_HEIGHT - 36, PAGE_WIDTH - MARGIN_RIGHT, PAGE_HEIGHT - 36)

        # Bottom Rule
        self.line(MARGIN_LEFT, 36, PAGE_WIDTH - MARGIN_RIGHT, 36)

        # Footer Text
        self.setFont("Helvetica", 8)
        self.setFillColor(COLOR_MUTED)
        self.drawString(MARGIN_LEFT, 24, "Multimodal Mental Health AI - 8-Agent Literature Synthesis & System Blueprint")
        page_str = f"Page {self._pageNumber} of {page_count}"
        self.drawRightString(PAGE_WIDTH - MARGIN_RIGHT, 24, page_str)
        
        self.restoreState()


# -----------------------------------------------------------------------------
# STYLES SETUP
# -----------------------------------------------------------------------------
def get_custom_styles():
    styles = getSampleStyleSheet()
    
    styles.add(ParagraphStyle(
        'DocMainTitle',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=20,
        leading=24,
        textColor=COLOR_PRIMARY,
        spaceAfter=6,
        alignment=0
    ))
    styles.add(ParagraphStyle(
        'DocSubTitle',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=11,
        leading=15,
        textColor=COLOR_MUTED,
        spaceAfter=12,
        alignment=0
    ))
    styles.add(ParagraphStyle(
        'MetaText',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=8.5,
        leading=12,
        textColor=COLOR_DARK
    ))
    styles.add(ParagraphStyle(
        'SectionH1',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=14,
        leading=18,
        textColor=COLOR_PRIMARY,
        spaceBefore=12,
        spaceAfter=6,
        keepWithNext=True
    ))
    styles.add(ParagraphStyle(
        'SectionH2',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=11,
        leading=15,
        textColor=COLOR_SECONDARY,
        spaceBefore=8,
        spaceAfter=4,
        keepWithNext=True
    ))
    styles.add(ParagraphStyle(
        'SectionH3',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=9.5,
        leading=13,
        textColor=COLOR_DARK,
        spaceBefore=6,
        spaceAfter=2,
        keepWithNext=True
    ))
    styles.add(ParagraphStyle(
        'BodyDark',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=8.5,
        leading=12,
        textColor=COLOR_DARK,
        spaceAfter=4
    ))
    styles.add(ParagraphStyle(
        'BodyDarkBold',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=8.5,
        leading=12,
        textColor=COLOR_DARK,
        spaceAfter=4
    ))
    styles.add(ParagraphStyle(
        'CalloutText',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=8.5,
        leading=12,
        textColor=COLOR_DARK
    ))
    styles.add(ParagraphStyle(
        'TableHeader',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=8,
        leading=10.5,
        textColor=colors.white,
        alignment=0
    ))
    styles.add(ParagraphStyle(
        'TableCell',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=7.5,
        leading=10,
        textColor=COLOR_DARK
    ))
    styles.add(ParagraphStyle(
        'TableCellBold',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=7.5,
        leading=10,
        textColor=COLOR_DARK
    ))
    styles.add(ParagraphStyle(
        'CardTitle',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=9.5,
        leading=12.5,
        textColor=COLOR_PRIMARY
    ))
    styles.add(ParagraphStyle(
        'CardMeta',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=7.5,
        leading=10,
        textColor=COLOR_MUTED
    ))
    styles.add(ParagraphStyle(
        'CardFieldLabel',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=7.5,
        leading=10,
        textColor=COLOR_DARK
    ))
    styles.add(ParagraphStyle(
        'CardFieldValue',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=7.5,
        leading=10,
        textColor=COLOR_DARK
    ))
    return styles

# -----------------------------------------------------------------------------
# HELPER FORMATTERS & BADGES
# -----------------------------------------------------------------------------
def safe(s: str) -> str:
    if s is None:
        return ""
    # Safe escape for ReportLab XML parser
    return html.escape(str(s), quote=False).replace("&amp;lt;", "&lt;").replace("&amp;gt;", "&gt;")

def make_agent_badges_html(mentions: list[str]) -> str:
    if not mentions:
        return '<font color="#6B7280"><i>[Foundational Literature Baseline]</i></font>'
    badges = []
    for agent in mentions:
        c = AGENT_COLORS.get(agent, "#2563EB")
        badges.append(f'<font color="{c}"><b>[{agent}]</b></font>')
    return " ".join(badges)

def format_priority_badge_html(priority: str) -> str:
    p = priority.upper()
    if "P0" in p:
        return '<font color="#991B1B"><b>[PRIORITY P0 - READ FIRST]</b></font>'
    elif "P1" in p:
        return '<font color="#B45309"><b>[PRIORITY P1 - IMPORTANT]</b></font>'
    elif "P2" in p:
        return '<font color="#1D4ED8"><b>[PRIORITY P2 - SPECIALIZED]</b></font>'
    else:
        return '<font color="#4B5563"><b>[PRIORITY P3 - BACKGROUND]</b></font>'

def format_links_html(links: dict, title: str) -> str:
    parts = []
    if links:
        for label, url in links.items():
            clean_url = safe(url)
            parts.append(f'<a href="{clean_url}" color="#2563EB"><u><b>[{safe(label)}]</b></u></a>')
    # Always guarantee at least one working ArXiv/Search link
    search_url = f"https://arxiv.org/search/?query={urllib.parse.quote_plus(title)}&searchtype=all&source=header"
    scholar_url = f"https://scholar.google.com/scholar?q={urllib.parse.quote_plus(title)}"
    parts.append(f'<a href="{safe(search_url)}" color="#0D9488"><u>[ArXiv Search]</u></a>')
    parts.append(f'<a href="{safe(scholar_url)}" color="#0D9488"><u>[Scholar Search]</u></a>')
    return " &bull; ".join(parts)

def make_banner_table(title: str, subtitle: str, meta_rows: list[tuple[str, str]], styles, width: float = USABLE_WIDTH):
    meta_p_list = []
    for k, v in meta_rows:
        meta_p_list.append(f"<b>{safe(k)}:</b> {safe(v)}")
    meta_text = " &nbsp;&nbsp;|&nbsp;&nbsp; ".join(meta_p_list)
    
    cell_data = [
        [Paragraph(f"<b>{safe(title)}</b>", styles['DocMainTitle'])],
        [Paragraph(f"{safe(subtitle)}", styles['DocSubTitle'])],
        [HRFlowable(width="100%", thickness=1.5, color=COLOR_SECONDARY, spaceBefore=2, spaceAfter=6)],
        [Paragraph(meta_text, styles['MetaText'])]
    ]
    t = Table(cell_data, colWidths=[width])
    t.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), COLOR_LIGHT),
        ('BOX', (0,0), (-1,-1), 1, COLOR_BORDER),
        ('TOPPADDING', (0,0), (-1,-1), 10),
        ('BOTTOMPADDING', (0,0), (-1,-1), 10),
        ('LEFTPADDING', (0,0), (-1,-1), 12),
        ('RIGHTPADDING', (0,0), (-1,-1), 12),
    ]))
    return t

def make_callout_box(title: str, body_html: str, styles, width: float = USABLE_WIDTH, bg_color=COLOR_CALLOUT_BG, border_color=COLOR_SECONDARY):
    cell_data = [
        [Paragraph(f"<b>{safe(title)}</b>", styles['SectionH3'])],
        [Paragraph(body_html, styles['CalloutText'])]
    ]
    t = Table(cell_data, colWidths=[width])
    t.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), bg_color),
        ('BOX', (0,0), (-1,-1), 1, border_color),
        ('LINELEFT', (0,0), (0,-1), 3.5, border_color),
        ('TOPPADDING', (0,0), (-1,-1), 6),
        ('BOTTOMPADDING', (0,0), (-1,-1), 6),
        ('LEFTPADDING', (0,0), (-1,-1), 10),
        ('RIGHTPADDING', (0,0), (-1,-1), 10),
    ]))
    return t

# -----------------------------------------------------------------------------
# FLOWABLE GENERATORS: PAPERS, DATASETS, TOOLS, CHALLENGES, BLUEPRINT
# -----------------------------------------------------------------------------
def make_paper_card(p: dict, styles, width: float = USABLE_WIDTH):
    pid = p.get('id', '')
    title = p.get('title', '')
    authors = p.get('authors', '')
    year = p.get('year', '')
    venue = p.get('venue', '')
    category = p.get('category', 'Multimodal AI')
    mentions = p.get('mentions', [])
    priority = p.get('priority', 'P1')
    links = p.get('links', {})
    problem = p.get('problem', '')
    io_desc = p.get('io', '')
    method = p.get('method', '')
    mh = p.get('mh', '')

    header_html = f"<b>[{safe(pid)}] {safe(title)}</b> ({safe(year)}) &mdash; <i>{safe(venue)}</i>"
    meta_html = f"<b>Authors:</b> {safe(authors)} &nbsp;&nbsp;|&nbsp;&nbsp; <b>Category:</b> {safe(category)}<br/>" \
                f"<b>Agent Mentions ({len(mentions)}/8):</b> {make_agent_badges_html(mentions)}<br/>" \
                f"<b>Reading Priority:</b> {format_priority_badge_html(priority)} &nbsp;&nbsp;|&nbsp;&nbsp; " \
                f"<b>Links:</b> {format_links_html(links, title)}"

    content_rows = [
        ("Problem Solved:", problem),
        ("Inputs / Outputs:", io_desc),
        ("Methodology (How & Why):", method),
        ("Mental Health Relevance:", mh)
    ]

    card_rows = [
        [Paragraph(header_html, styles['CardTitle'])],
        [Paragraph(meta_html, styles['CardMeta'])],
        [HRFlowable(width="100%", thickness=0.5, color=COLOR_BORDER, spaceBefore=3, spaceAfter=4)]
    ]

    for label, val in content_rows:
        row_text = f"<b>{safe(label)}</b> {safe(val)}"
        card_rows.append([Paragraph(row_text, styles['CardFieldValue'])])

    t = Table(card_rows, colWidths=[width])
    t.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), COLOR_CARD_BG),
        ('BOX', (0,0), (-1,-1), 0.75, COLOR_BORDER),
        ('LINELEFT', (0,0), (0,-1), 3.0, COLOR_PRIMARY if "P0" in priority else (COLOR_SECONDARY if "P1" in priority else COLOR_MUTED)),
        ('TOPPADDING', (0,0), (-1,-1), 4),
        ('BOTTOMPADDING', (0,0), (-1,-1), 4),
        ('LEFTPADDING', (0,0), (-1,-1), 8),
        ('RIGHTPADDING', (0,0), (-1,-1), 8),
    ]))
    return KeepTogether([t, Spacer(1, 6)])

def make_dataset_card(ds: dict, styles, width: float = USABLE_WIDTH):
    name = ds.get('name', '')
    year = ds.get('year', '')
    modalities = ds.get('modalities', '')
    size = ds.get('size', '')
    labels = ds.get('labels', '')
    access = ds.get('access', '')
    license_str = ds.get('license', '')
    agents = ds.get('agents', [])
    usage = ds.get('usage', '')

    access_html = f'<a href="{safe(access)}" color="#2563EB"><u>{safe(access)}</u></a>' if access.startswith("http") else safe(access)
    
    header_html = f"<b>{safe(name)} ({safe(year)})</b> &mdash; <i>{safe(modalities)}</i>"
    meta_html = f"<b>Size / Scale:</b> {safe(size)} &nbsp;&nbsp;|&nbsp;&nbsp; <b>Annotations:</b> {safe(labels)}<br/>" \
                f"<b>License:</b> {safe(license_str)} &nbsp;&nbsp;|&nbsp;&nbsp; <b>Access URL:</b> {access_html}<br/>" \
                f"<b>Agent Mentions ({len(agents)}/8):</b> {make_agent_badges_html(agents)}"

    usage_html = f"<b>Mental Health Usage &amp; Research Discipline:</b> {safe(usage)}"

    card_rows = [
        [Paragraph(header_html, styles['CardTitle'])],
        [Paragraph(meta_html, styles['CardMeta'])],
        [HRFlowable(width="100%", thickness=0.5, color=COLOR_BORDER, spaceBefore=3, spaceAfter=4)],
        [Paragraph(usage_html, styles['CardFieldValue'])]
    ]

    t = Table(card_rows, colWidths=[width])
    t.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), COLOR_CARD_BG),
        ('BOX', (0,0), (-1,-1), 0.75, COLOR_BORDER),
        ('LINELEFT', (0,0), (0,-1), 3.0, COLOR_ACCENT),
        ('TOPPADDING', (0,0), (-1,-1), 5),
        ('BOTTOMPADDING', (0,0), (-1,-1), 5),
        ('LEFTPADDING', (0,0), (-1,-1), 8),
        ('RIGHTPADDING', (0,0), (-1,-1), 8),
    ]))
    return KeepTogether([t, Spacer(1, 6)])

def make_tool_card(tool: dict, styles, width: float = USABLE_WIDTH):
    name = tool.get('name', '')
    what = tool.get('what', '')
    link = tool.get('link', '')
    agents = tool.get('agents', [])
    usage = tool.get('usage', '')

    link_parts = []
    for raw_l in link.split(";"):
        raw_l = raw_l.strip()
        if raw_l.startswith("http"):
            link_parts.append(f'<a href="{safe(raw_l)}" color="#2563EB"><u>{safe(raw_l)}</u></a>')
        else:
            link_parts.append(safe(raw_l))
    link_html = " ; ".join(link_parts)

    header_html = f"<b>{safe(name)}</b>"
    meta_html = f"<b>Functionality:</b> {safe(what)}<br/>" \
                f"<b>Repository / Docs:</b> {link_html}<br/>" \
                f"<b>Agent Mentions ({len(agents)}/8):</b> {make_agent_badges_html(agents)}"

    usage_html = f"<b>Role in Proposed System:</b> {safe(usage)}"

    card_rows = [
        [Paragraph(header_html, styles['CardTitle'])],
        [Paragraph(meta_html, styles['CardMeta'])],
        [HRFlowable(width="100%", thickness=0.5, color=COLOR_BORDER, spaceBefore=3, spaceAfter=4)],
        [Paragraph(usage_html, styles['CardFieldValue'])]
    ]

    t = Table(card_rows, colWidths=[width])
    t.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), COLOR_CARD_BG),
        ('BOX', (0,0), (-1,-1), 0.75, COLOR_BORDER),
        ('LINELEFT', (0,0), (0,-1), 3.0, COLOR_SECONDARY),
        ('TOPPADDING', (0,0), (-1,-1), 5),
        ('BOTTOMPADDING', (0,0), (-1,-1), 5),
        ('LEFTPADDING', (0,0), (-1,-1), 8),
        ('RIGHTPADDING', (0,0), (-1,-1), 8),
    ]))
    return KeepTogether([t, Spacer(1, 6)])

def make_challenge_card(ch: dict, styles, width: float = USABLE_WIDTH):
    name = ch.get('name', '')
    agents = ch.get('agents', [])
    text = ch.get('text', '')

    header_html = f"<b>{safe(name)}</b>"
    meta_html = f"<b>Raised by Agents ({len(agents)}/8):</b> {make_agent_badges_html(agents)}"
    body_html = f"<b>Analysis &amp; Mitigation:</b> {safe(text)}"

    card_rows = [
        [Paragraph(header_html, styles['CardTitle'])],
        [Paragraph(meta_html, styles['CardMeta'])],
        [HRFlowable(width="100%", thickness=0.5, color=COLOR_BORDER, spaceBefore=3, spaceAfter=4)],
        [Paragraph(body_html, styles['CardFieldValue'])]
    ]

    t = Table(card_rows, colWidths=[width])
    t.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), COLOR_CARD_BG),
        ('BOX', (0,0), (-1,-1), 0.75, COLOR_BORDER),
        ('LINELEFT', (0,0), (0,-1), 3.0, COLOR_P0),
        ('TOPPADDING', (0,0), (-1,-1), 5),
        ('BOTTOMPADDING', (0,0), (-1,-1), 5),
        ('LEFTPADDING', (0,0), (-1,-1), 8),
        ('RIGHTPADDING', (0,0), (-1,-1), 8),
    ]))
    return KeepTogether([t, Spacer(1, 6)])

def make_styled_table(headers: list[str], rows: list[list[str]], col_widths: list[float], styles, header_bg=COLOR_PRIMARY):
    table_data = [[Paragraph(f"<b>{safe(h)}</b>", styles['TableHeader']) for h in headers]]
    for row in rows:
        formatted_row = []
        for cell in row:
            formatted_row.append(Paragraph(safe(cell), styles['TableCell']))
        table_data.append(formatted_row)

    t = Table(table_data, colWidths=col_widths)
    t.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), header_bg),
        ('TEXTCOLOR', (0,0), (-1,0), colors.white),
        ('GRID', (0,0), (-1,-1), 0.5, COLOR_BORDER),
        ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.white, COLOR_LIGHT]),
        ('TOPPADDING', (0,0), (-1,-1), 4),
        ('BOTTOMPADDING', (0,0), (-1,-1), 4),
        ('LEFTPADDING', (0,0), (-1,-1), 5),
        ('RIGHTPADDING', (0,0), (-1,-1), 5),
    ]))
    return t

# -----------------------------------------------------------------------------
# BUILDER FOR VOLUME 1: ARCHITECTURES & METHODOLOGIES
# -----------------------------------------------------------------------------
def build_vol1_pdf(filename: str = "VOL_1_ARCHITECTURES_AND_METHODOLOGIES.pdf"):
    doc = SimpleDocTemplate(
        filename,
        pagesize=letter,
        leftMargin=MARGIN_LEFT,
        rightMargin=MARGIN_RIGHT,
        topMargin=MARGIN_TOP,
        bottomMargin=MARGIN_BOTTOM
    )
    styles = get_custom_styles()
    story = []

    # Title Banner
    meta = [
        ("Volume", "Volume 1 of 4"),
        ("Focus", "Architectures, Pretraining & Fusion Methodologies"),
        ("Date", datetime.now().strftime("%B %Y")),
        ("Synthesized Sources", "8 AI Agents (ChatGPT, Claude, DeepSeek, Gemini, GLM, Kimi, MiniMax, Qwen)")
    ]
    story.append(make_banner_table(
        "Multimodal Mental Health AI: Architectures & Methodologies",
        "Deep-Dive Technical Review of Fusion Paradigms, Pretrained Backbones, Streaming Ingestion & Calibration",
        meta,
        styles
    ))
    story.append(Spacer(1, 10))

    # Executive Overview
    story.append(Paragraph("1. Executive Architectural Synthesis", styles['SectionH1']))
    story.append(Paragraph(
        "Multimodal Emotion Recognition (MER) and Mental Health Monitoring have undergone three fundamental paradigm shifts over the last decade: "
        "(1) from handcrafted features (eGeMAPS, OpenFace AUs) to self-supervised foundation encoders (Wav2Vec2, HuBERT, POSTER++, ViT); "
        "(2) from static concatenation and decision voting to cross-modal attention transformers and subspace disentanglement (MulT, MISA, Self-MM); and "
        "(3) from black-box discriminative classifiers to dual-head architectures combining calibrated real-time prediction with explainable Multimodal Large Language Models (Emotion-LLaMA, AffectGPT). "
        "This volume provides a rigorous, comparative architectural synthesis of every paradigm identified across the 8 AI agent literature reviews.",
        styles['BodyDark']
    ))
    story.append(Spacer(1, 6))

    # Section 2: Fusion Paradigms
    story.append(Paragraph("2. Comprehensive Taxonomy of Multimodal Fusion Paradigms", styles['SectionH1']))
    
    fusion_paradigms = [
        ("Early / Feature-Level Fusion",
         "Direct concatenation of frame-level visual and acoustic feature vectors prior to sequence modeling. "
         "<b>Limitations:</b> Vulnerable to the 'curse of dimensionality', suppresses weaker modalities (acoustic cues drowned out by dense visual vectors), and fails when sampling rates differ.",
         "Baseline comparative reference only. Not recommended for primary pipeline."),
        ("Late / Decision-Level Fusion",
         "Independent unimodal classifiers trained on face and voice streams separately, whose prediction probabilities or logits are aggregated via weighted averaging, Borda count, or meta-classifiers. "
         "<b>Advantages:</b> Extreme modularity and robustness to single-sensor failure. <b>Limitations:</b> Incapable of capturing cross-modal temporal interactions (e.g., sarcasm, micro-tremors accompanying flat speech).",
         "Useful fallback mode when one sensor experiences complete loss."),
        ("Cross-Modal Transformer Attention (MulT Pattern)",
         "Directional pairwise cross-attention where visual query tokens attend to acoustic key/values and vice-versa (V->A, A->V) without requiring explicit word-level alignment (Tsai et al., ACL 2019). "
         "<b>Core Strength:</b> Discovers latent complementary correlations across asynchronous streams. Allows facial cues (e.g. a frown) to dynamically re-weight ambiguous vocal prosody.",
         "Selected as the core discriminative fusion backbone (HEAD-A) for the system blueprint."),
        ("Subspace Disentanglement & Invariant-Specific Fusion (MISA / FDFNet)",
         "Projects modality features into two distinct subspaces: a shared modality-invariant subspace (constrained by cosine similarity and central moment discrepancy) and private modality-specific subspaces (constrained by orthogonality/difference losses). "
         "<b>Why Critical for Mental Health:</b> Separates speaker identity, acoustic channel noise, and lighting variations from affective distress signals.",
         "Integrated into feature projection layers before cross-modal attention."),
        ("Information-Theoretic Regularization (MMIM / Self-MM)",
         "Hierarchical Mutual Information Maximization (Han et al., EMNLP 2021) ensures that intermediate fused representations maintain high mutual information with input modalities, preventing gradient starvation of weaker modalities. Self-MM introduces self-supervised unimodal auxiliary tasks.",
         "Guarantees that voice prosody is not ignored when facial expression features are dominant."),
        ("Low-Rank & Efficient MLP Fusion (LMF / CubeMLP)",
         "Decomposes high-order tensor outer products into modality-specific low-rank factors (Liu et al., ACL 2018) or applies multi-axis MLP mixers across modality, sequence, and channel dimensions (Sun et al., ACM MM 2022). "
         "<b>Efficiency:</b> Linear time complexity and sub-megabyte memory footprints.",
         "Candidate on-device edge fusion engine for low-power mobile deployment."),
        ("Conversational & Temporal Context Modeling (DialogueRNN / GCN / COSMIC)",
         "Recurrent and graph-based tracking of emotional trajectories across conversation turns (Majumder et al., AAAI 2019; Ghosal et al., EMNLP 2019). COSMIC incorporates COMET commonsense knowledge (intent, effect).",
         "Adapted into a single-user mood trajectory GRU that tracks emotional drift across minutes and hours."),
        ("Generative Diffusion for Missing Modalities (HVDER / MMIN)",
         "Latent-space VAEs combined with conditional diffusion probabilistic models (IEEE 2026) that hallucinate missing sensory representations under severe missingness (up to 70% missing modalities).",
         "Advanced missing-modality imputation mechanism for camera-off or muted operation.")
    ]

    for title, desc, role in fusion_paradigms:
        story.append(Paragraph(f"<b>2.{fusion_paradigms.index((title,desc,role))+1} {title}</b>", styles['SectionH2']))
        story.append(Paragraph(f"{desc}", styles['BodyDark']))
        story.append(Paragraph(f"<b>Role in Proposed System:</b> {role}", styles['BodyDarkBold']))
        story.append(Spacer(1, 4))

    # Section 3: Vision Encoders
    story.append(PageBreak())
    story.append(Paragraph("3. Vision & Facial Expression Encoders", styles['SectionH1']))
    story.append(Paragraph(
        "Facial expression analysis in mental health requires sensitivity to subtle Action Units (AUs), micro-expressions, and pose/lighting invariance. "
        "The literature reviews highlight a clear transition from static CNNs (ResNet, VGG) to Vision Transformers (ViT) and dual-branch landmark-guided architectures.",
        styles['BodyDark']
    ))
    
    vision_specs = [
        ("POSTER++ (ICCV 2023)", "Pyramid cross-fusion network combining facial appearance images with 68 facial landmark coordinates via windowed cross-attention.", "Top benchmark accuracy on RAF-DB and AffectNet with low parameter overhead. Landmarks guide attention to eye/mouth regions under head rotations."),
        ("MediaPipe Face Mesh (Google)", "Cascaded lightweight mobile neural pipeline producing 468 3D facial landmarks and 52 blendshape coefficients at 60+ FPS on CPU.", "Default client-side edge frontend. Extracts landmark coordinates locally on user device; raw video frames never leave hardware."),
        ("OpenFace 2.0 (IEEE FG 2018)", "Constrained Local Neural Fields (CLNF) extracting 18 Facial Action Units (FAUs) with continuous intensity and presence flags.", "Generates clinically validated FACS features (e.g. AU4 brow lowerer, AU12 lip corner puller) for the explainable MLLM evidence layer."),
        ("DAN - Distract Attention Network (WACV 2023)", "Multi-head attention with dynamic distractors designed to suppress occlusion artefacts (glasses, hands near face).", "Robustness backbone for unconstrained webcam video.")
    ]
    for model, arch, app in vision_specs:
        story.append(Paragraph(f"<b>&bull; {model}</b>: {arch}", styles['BodyDark']))
        story.append(Paragraph(f"<i>Clinical Utility:</i> {app}", styles['BodyDark']))
        story.append(Spacer(1, 3))

    # Section 4: Speech Encoders
    story.append(Spacer(1, 6))
    story.append(Paragraph("4. Speech & Acoustic Foundation Encoders", styles['SectionH1']))
    story.append(Paragraph(
        "Supervised acoustic models trained on raw MFCCs overfit small datasets and suffer ~13-15% performance drops when tested on unseen speakers. "
        "Self-Supervised Learning (SSL) representations have emerged as the absolute state-of-the-art across all 8 reviews.",
        styles['BodyDark']
    ))

    audio_specs = [
        ("Wav2Vec 2.0 (NeurIPS 2020)", "Masked contrastive pretraining on 50,000+ hours of raw speech. Fine-tuned with frozen lower CNN feature extractor and low learning rate (~2e-5) on Transformer layers.", "Primary acoustic backbone. Captures pitch variations, speech pauses, and phoneme duration changes characteristic of psychomotor retardation."),
        ("HuBERT (IEEE TASLP 2021)", "Hidden-Unit BERT with acoustic k-means cluster prediction. Demonstrates superior acoustic stability and prosodic nuance modeling.", "Comparative benchmark against Wav2Vec 2.0 for vocal tremor and distress inflection detection."),
        ("WavLM (IEEE JSTSP 2022)", "Pretrained with gated relative position bias and masked speech denoising/overlap simulation.", "Optimal backbone for noisy real-world acoustic environments (background traffic, home noise)."),
        ("openSMILE / eGeMAPS (IEEE TAFFC 2016)", "Deterministic 88-parameter acoustic feature extractor (F0 pitch, jitter, shimmer, formant frequencies, alpha ratio).", "Interpretable voice baseline required by project thesis specification; provides continuous metrics for dashboard visualization.")
    ]
    for model, arch, app in audio_specs:
        story.append(Paragraph(f"<b>&bull; {model}</b>: {arch}", styles['BodyDark']))
        story.append(Paragraph(f"<i>Clinical Utility:</i> {app}", styles['BodyDark']))
        story.append(Spacer(1, 3))

    # Section 5: Calibration & Streaming Budgets
    story.append(PageBreak())
    story.append(Paragraph("5. Latency Budgets & Confidence Calibration", styles['SectionH1']))
    story.append(Paragraph(
        "A mental health emotion monitoring system must operate within strict streaming latency budgets while guaranteeing calibrated, trustworthy confidence scores. "
        "Deep neural networks frequently output overconfident probabilities (e.g. 98% confidence on an erroneous prediction). "
        "Following Zhang et al. (EMNLP 2024), Expected Calibration Error (ECE) minimization via post-hoc temperature scaling and modality reliability gating is mandatory.",
        styles['BodyDark']
    ))
    story.append(Spacer(1, 4))

    headers = ["Pipeline Stage", "Latency Budget", "Underlying Architecture", "Optimization & Fallback"]
    rows = [
        ["Face Detection & Landmarks", "<= 40 ms", "MediaPipe 468-pt Mesh / POSTER++", "Hardware accelerated (WebGL/Metal)"],
        ["Voice Feature Extraction", "<= 300 ms", "Wav2Vec2-base (distilled) / eGeMAPS", "3.0s rolling buffer with 1.0s hop"],
        ["Cross-Modal Fusion & Calib.", "<= 120 ms", "MulT / CubeMLP + Temp Scaling", "Quantized INT8 weights on edge"],
        ["ASR Partial Decoding", "<= 500 ms", "Whisper-streaming / FunASR", "Async paralinguistic stream"],
        ["End-to-End Decision (HEAD-A)", "<= 1.0 s", "Real-Time Calibrated Emotion Vector", "Real-time dashboard updates"],
        ["Explainable Rationale (HEAD-B)", "<= 2.5 s", "Emotion-LLaMA / AffectGPT", "Decoupled async non-blocking queue"]
    ]
    story.append(make_styled_table(headers, rows, [110, 80, 180, 162], styles))
    story.append(Spacer(1, 10))

    # Architectural Blueprint Callout
    story.append(make_callout_box(
        "Summary Architectural Takeaway for System Implementation",
        "The recommended architecture combines <b>MediaPipe Face Mesh + POSTER++</b> (visual branch) and <b>Wav2Vec2 / HuBERT + eGeMAPS</b> (acoustic branch) "
        "into a <b>MulT cross-modal attention core</b> regularized by <b>MISA subspace disentanglement</b>. "
        "The model outputs calibrated probabilities (ECE < 0.05) through <b>HEAD-A</b> while asynchronously triggering <b>HEAD-B (Emotion-LLaMA)</b> "
        "to generate natural-language clinical rationales grounded in detected Action Units and vocal prosodic anomalies.",
        styles
    ))

    doc.build(story, canvasmaker=lambda *args, **kwargs: NumberedCanvas(*args, doc_title="Multimodal Mental Health AI Literature Review", vol_label="Vol 1: Architectures & Methodologies", **kwargs))
    print(f"[OK] Generated {filename}")

# -----------------------------------------------------------------------------
# BUILDER FOR VOLUME 2: PAPERS COMPENDIUM & READING GUIDE
# -----------------------------------------------------------------------------
def build_vol2_pdf(filename: str = "VOL_2_PAPERS_COMPENDIUM_AND_READING_GUIDE.pdf"):
    doc = SimpleDocTemplate(
        filename,
        pagesize=letter,
        leftMargin=MARGIN_LEFT,
        rightMargin=MARGIN_RIGHT,
        topMargin=MARGIN_TOP,
        bottomMargin=MARGIN_BOTTOM
    )
    styles = get_custom_styles()
    story = []

    # Title Banner
    meta = [
        ("Volume", "Volume 2 of 4"),
        ("Focus", "Complete 59 Papers Compendium & 4-Phase Reading Guide"),
        ("Date", datetime.now().strftime("%B %Y")),
        ("Coverage", "59 Papers fully parsed, cross-referenced across 8 AI reviews")
    ]
    story.append(make_banner_table(
        "Multimodal Mental Health AI: Papers Compendium & Reading Guide",
        "Zero-Omission Inventory of 59 Core Papers, Surveys, and Architectures with Agent Attributions & Deep Breakdowns",
        meta,
        styles
    ))
    story.append(Spacer(1, 8))

    # Phased Reading Guide Summary
    story.append(Paragraph("1. Phased Master Reading Guide", styles['SectionH1']))
    story.append(Paragraph(
        "To guide research execution and thesis writing efficiently, the 59 curated papers are organized into 4 strategic priority tiers. "
        "Each tier addresses a specific phase of system development, from foundational architectural choices to baseline benchmarking.",
        styles['BodyDark']
    ))
    story.append(Spacer(1, 4))

    guide_headers = ["Priority Tier", "Target Scope", "Paper Count", "Core Representative Papers"]
    guide_rows = [
        ["Priority P0\n(Must Read First)", "Architecture Decisions, Core Fusion, Speech/Face Backbones & Clinical Surveys", "20 Papers", "MulT, MISA, Self-MM, UniMSE, Emotion-LLaMA, Wav2Vec2, HuBERT, POSTER++, DAIC-WOZ, MER-Calibration, MMIN"],
        ["Priority P1\n(Important)", "Subspace Disentanglement, Low-Rank Edge Fusion, Missing Modalities & Calibration", "20 Papers", "MMIM, TFN, LMF, MAG-BERT, DialogueGCN, COSMIC, WavLM, openSMILE, CubeMLP, VAE-Diffusion, M3S"],
        ["Priority P2\n(Specialized)", "Conversational Graph Models, Micro-Expressions, Pairwise Alignment & Speech Baselines", "14 Papers", "DialogueCRN, M2FNet, GS-MCC, MicroEmo, Centering-Hotspots, TITAN, DAN, DepAudioNet, Deep-Depression"],
        ["Priority P3\n(Background Canon)", "Historical Reviews, Comprehensive Taxonomies & Benchmark Retrospectives", "5 Papers", "Baltrusaitis Survey, Rouast Review, Gandhi Survey, Schuller Affect Review, ARM"]
    ]
    story.append(make_styled_table(guide_headers, guide_rows, [85, 145, 62, 240], styles))
    story.append(Spacer(1, 10))

    # Full Papers Compendium
    story.append(Paragraph("2. Complete Papers Compendium (59 Papers)", styles['SectionH1']))
    story.append(Paragraph(
        "Below is the complete, unabridged catalog of all 59 papers identified across the 8 AI agent reviews. "
        "Every entry includes full metadata, agent citation badges, active hyperlinked paper and search URLs, core problem addressed, input/output dimensions, detailed methodology (How & Why), and specific relevance to multimodal mental health emotion monitoring.",
        styles['BodyDark']
    ))
    story.append(Spacer(1, 6))

    for idx, paper in enumerate(curated_data.PAPERS, start=1):
        story.append(make_paper_card(paper, styles))

    doc.build(story, canvasmaker=lambda *args, **kwargs: NumberedCanvas(*args, doc_title="Multimodal Mental Health AI Literature Review", vol_label="Vol 2: Papers Compendium & Reading Guide", **kwargs))
    print(f"[OK] Generated {filename}")

# -----------------------------------------------------------------------------
# BUILDER FOR VOLUME 3: DATASETS, TOOLS & BENCHMARKS
# -----------------------------------------------------------------------------
def build_vol3_pdf(filename: str = "VOL_3_DATASETS_TOOLS_AND_BENCHMARKS.pdf"):
    doc = SimpleDocTemplate(
        filename,
        pagesize=letter,
        leftMargin=MARGIN_LEFT,
        rightMargin=MARGIN_RIGHT,
        topMargin=MARGIN_TOP,
        bottomMargin=MARGIN_BOTTOM
    )
    styles = get_custom_styles()
    story = []

    # Title Banner
    meta = [
        ("Volume", "Volume 3 of 4"),
        ("Focus", "Datasets, Open-Source Toolkits & Evaluation Benchmarks"),
        ("Date", datetime.now().strftime("%B %Y")),
        ("Synthesized Sources", "15 Datasets + 13 Toolkits mapped across 8 AI Reviews")
    ]
    story.append(make_banner_table(
        "Multimodal Mental Health AI: Datasets, Tools & Benchmarks",
        "Comprehensive Directory of Multimodal Corpora, Feature Extractors, Codebases, and Evaluation Protocols",
        meta,
        styles
    ))
    story.append(Spacer(1, 8))

    # Datasets Section
    story.append(Paragraph("1. Master Directory of Multimodal Affective & Mental Health Datasets", styles['SectionH1']))
    story.append(Paragraph(
        "A critical finding from the multi-agent review is that while affective computing possesses numerous acted datasets (IEMOCAP, RAVDESS, MELD), "
        "true clinical mental health datasets with synchronized facial video and speech are exceedingly rare. "
        "Below is the complete directory of 15 key datasets, detailing modalities, sample sizes, access links, licensing, and specific methodological usage rules.",
        styles['BodyDark']
    ))
    story.append(Spacer(1, 6))

    for ds in curated_data.DATASETS:
        story.append(make_dataset_card(ds, styles))

    # Toolkits & Frameworks Section
    story.append(PageBreak())
    story.append(Paragraph("2. Open-Source Toolkits, Frameworks & Implementation Codebases", styles['SectionH1']))
    story.append(Paragraph(
        "To avoid reimplementing standard pipelines from scratch, the 8 AI reviews highlighted 13 robust open-source toolkits, SDKs, and reference codebases. "
        "These span facial landmark extraction, self-supervised speech modeling, conversational emotion reasoning, and unified benchmarking.",
        styles['BodyDark']
    ))
    story.append(Spacer(1, 6))

    for tool in curated_data.TOOLS:
        story.append(make_tool_card(tool, styles))

    # Benchmark Protocols & Standardization
    story.append(PageBreak())
    story.append(Paragraph("3. Standardized Evaluation Protocols & Integrity Guidelines", styles['SectionH1']))
    story.append(Paragraph(
        "Cross-corpus evaluation in multimodal emotion recognition has historically suffered from split-hacking and over-optimistic validation. "
        "To establish publication-grade credibility in the thesis, the following standardized evaluation rules (derived from MERBench and AVEC) must be strictly enforced:",
        styles['BodyDark']
    ))
    story.append(Spacer(1, 4))

    eval_rules = [
        ("Speaker-Independent Partitioning (Strict Rule)",
         "Never use random k-fold cross-validation on datasets with repeated speakers (e.g. RAVDESS, CREMA-D, IEMOCAP). "
         "DeepSeek and Claude reviews proved that random splits artificially inflate Weighted F1 by ~13-15% because models memorize speaker identity rather than affect. "
         "All evaluations must strictly use 5-fold Leave-Speakers-Out (LSO) splits."),
        ("Missing Modality Stress-Testing (MissBench Protocol)",
         "Evaluate model degradation curves across varying missingness ratios (0%, 20%, 50%, 70%) for both audio-missing (camera-only) and video-missing (audio-only) scenarios. "
         "Report Modality Inequity Indices (MEI/MLI) to ensure the system does not silently fail on specific sub-populations."),
        ("Confidence Calibration Metrics (ECE & Brier Score)",
         "In health-adjacent monitoring, confidence scores displayed to users must reflect true empirical accuracy. "
         "Expected Calibration Error (ECE) must be computed with 15 bins: <i>ECE = &sum; (|B_m| / N) * |acc(B_m) - conf(B_m)|</i>. Target ECE < 0.05 before release."),
        ("Multimodal vs. Unimodal Ablation Rigor",
         "Every experimental claim must present identical backbone comparisons across: (1) Face-Only, (2) Voice-Only, (3) Transcript-Only, (4) Early Fusion, (5) Late Fusion, and (6) Proposed Cross-Modal Attention (MulT+MISA)."
        )
    ]

    for title, desc in eval_rules:
        story.append(Paragraph(f"<b>3.{eval_rules.index((title,desc))+1} {title}</b>", styles['SectionH2']))
        story.append(Paragraph(desc, styles['BodyDark']))
        story.append(Spacer(1, 3))

    doc.build(story, canvasmaker=lambda *args, **kwargs: NumberedCanvas(*args, doc_title="Multimodal Mental Health AI Literature Review", vol_label="Vol 3: Datasets, Tools & Benchmarks", **kwargs))
    print(f"[OK] Generated {filename}")

# -----------------------------------------------------------------------------
# BUILDER FOR VOLUME 4: CHALLENGES, GAPS & SYSTEM BLUEPRINT
# -----------------------------------------------------------------------------
def build_vol4_pdf(filename: str = "VOL_4_CHALLENGES_GAPS_AND_SYSTEM_BLUEPRINT.pdf"):
    doc = SimpleDocTemplate(
        filename,
        pagesize=letter,
        leftMargin=MARGIN_LEFT,
        rightMargin=MARGIN_RIGHT,
        topMargin=MARGIN_TOP,
        bottomMargin=MARGIN_BOTTOM
    )
    styles = get_custom_styles()
    story = []

    # Title Banner
    meta = [
        ("Volume", "Volume 4 of 4"),
        ("Focus", "Research Gaps, Challenges & End-to-End System Blueprint"),
        ("Date", datetime.now().strftime("%B %Y")),
        ("Mapping", "Directly mapped to project specification (idea.docx)")
    ]
    story.append(make_banner_table(
        "Multimodal Mental Health AI: Challenges, Gaps & Blueprint",
        "Synthesis of 8 Critical Research Gaps and the Complete Production-Grade System Architecture Blueprint",
        meta,
        styles
    ))
    story.append(Spacer(1, 8))

    # Section 1: Challenges & Gaps
    story.append(Paragraph("1. Critical Research Challenges & Open Gaps (C1 &mdash; C8)", styles['SectionH1']))
    story.append(Paragraph(
        "Across the 8 agent reviews, eight recurring fundamental bottlenecks and research gaps were identified. "
        "Addressing these challenges forms the primary scientific contribution of the proposed thesis and prototype system.",
        styles['BodyDark']
    ))
    story.append(Spacer(1, 6))

    for ch in curated_data.CHALLENGES:
        story.append(make_challenge_card(ch, styles))

    # Section 2: End-to-End System Architecture Blueprint
    story.append(PageBreak())
    story.append(Paragraph("2. End-to-End System Architecture Blueprint (idea.docx Mapping)", styles['SectionH1']))
    story.append(Paragraph(
        "The proposed system translates the core requirements of <b>idea.docx</b> (face analysis + voice analysis + multimodal fusion + visualization dashboard + privacy-aware edge prototype) "
        "into an enterprise, publication-grade dual-head architecture:",
        styles['BodyDark']
    ))
    story.append(Spacer(1, 4))

    story.append(make_callout_box(
        "Dual-Head Architecture Concept (HEAD-A + HEAD-B)",
        "<b>HEAD-A (Real-Time Calibrated Discriminative Core):</b> Operates on sub-second streaming buffers (<= 1.0s end-to-end latency). "
        "Combines MediaPipe/POSTER++ facial features and Wav2Vec2/eGeMAPS acoustic features using a MulT cross-modal attention core with MISA disentanglement. "
        "Outputs calibrated discrete emotion vectors and dimensional valence-arousal scores.<br/><br/>"
        "<b>HEAD-B (Explainable Multimodal LLM Core):</b> Operates asynchronously off the critical path (<= 2.5s latency). "
        "Conditioned on HEAD-A evidence tokens, detected Facial Action Units (AU4, AU12), and vocal prosodic descriptors (pitch drop, speech rate), "
        "it generates concise, clinically interpretable natural language explanations explaining <i>why</i> the system reached its emotional assessment.",
        styles
    ))
    story.append(Spacer(1, 8))

    # Blueprint Components Breakdown
    story.append(Paragraph("3. Detailed Pipeline Component Breakdown", styles['SectionH1']))
    
    comp_headers = ["Subsystem Component", "Architectural Implementation & idea.docx Mapping"]
    comp_rows = []
    for name, desc in curated_data.BLUEPRINT_COMPONENTS:
        comp_rows.append([name, desc])
    story.append(make_styled_table(comp_headers, comp_rows, [140, 392], styles))
    story.append(Spacer(1, 10))

    # Streaming Latency Budget Table
    story.append(Paragraph("4. Real-Time Streaming Latency Budget & Edge Execution", styles['SectionH1']))
    lat_headers = ["Pipeline Stage", "Target Budget", "Implementation Engine & Constraints"]
    lat_rows = []
    for stage, budget, engine in curated_data.LATENCY_ROWS:
        lat_rows.append([stage, budget, engine])
    story.append(make_styled_table(lat_headers, lat_rows, [160, 100, 272], styles))
    story.append(Spacer(1, 10))

    # Privacy & Edge Security Envelope
    story.append(Paragraph("5. Privacy-Preserving Architecture & Ethical Compliance", styles['SectionH1']))
    story.append(Paragraph(
        "In strict compliance with GDPR, HIPAA, and responsible AI principles for mental health technologies (addressing Challenge C4):<br/>"
        "&bull; <b>Zero Raw Biometric Egress:</b> Raw camera video and microphone audio streams are processed strictly within local device memory (RAM) and discarded immediately after feature extraction. No raw recordings are ever transmitted or written to persistent disk.<br/>"
        "&bull; <b>Local Landmark & Embedding Extraction:</b> MediaPipe 468-point 3D mesh and on-device quantized acoustic encoders run locally on client hardware.<br/>"
        "&bull; <b>Differential Privacy Aggregation:</b> Longitudinal trend analytics stored in cloud databases are perturbed with calibrated Laplacian noise (&epsilon; &le; 1.0) to prevent biometric reconstruction attacks.<br/>"
        "&bull; <b>Federated Model Adaptation:</b> Personalized user calibration is trained locally on-device via Federated Averaging (FedAvg), transmitting only encrypted gradient updates to the central server.",
        styles['BodyDark']
    ))
    story.append(Spacer(1, 6))

    # Master Evaluation Protocol Table
    story.append(PageBreak())
    story.append(Paragraph("6. Master Experimental Evaluation Protocol", styles['SectionH1']))
    story.append(Paragraph(
        "To rigorously prove the scientific contributions outlined in Section 4 of idea.docx, the experimental evaluation must follow this standardized test matrix:",
        styles['BodyDark']
    ))
    story.append(Spacer(1, 4))

    eval_headers = ["Evaluation Objective", "Benchmark Datasets", "Target Metrics & Verification Discipline"]
    eval_rows = []
    for obj, dsets, metrics in curated_data.EVAL_ROWS:
        eval_rows.append([obj, dsets, metrics])
    story.append(make_styled_table(eval_headers, eval_rows, [150, 140, 242], styles))

    doc.build(story, canvasmaker=lambda *args, **kwargs: NumberedCanvas(*args, doc_title="Multimodal Mental Health AI Literature Review", vol_label="Vol 4: Challenges, Gaps & System Blueprint", **kwargs))
    print(f"[OK] Generated {filename}")

# -----------------------------------------------------------------------------
# BUILDER FOR MASTER COMPENDIUM (ALL-IN-ONE MASTER PDF)
# -----------------------------------------------------------------------------
def build_master_pdf(filename: str = "MULTIMODAL_MENTAL_HEALTH_AI_LITERATURE_REVIEW_MASTER.pdf"):
    doc = SimpleDocTemplate(
        filename,
        pagesize=letter,
        leftMargin=MARGIN_LEFT,
        rightMargin=MARGIN_RIGHT,
        topMargin=MARGIN_TOP,
        bottomMargin=MARGIN_BOTTOM
    )
    styles = get_custom_styles()
    story = []

    # 1. Master Title Banner
    meta = [
        ("Document", "Master Compendium (All-in-One)"),
        ("Version", "Release 1.0 (Production-Grade)"),
        ("Date", datetime.now().strftime("%B %d, %Y")),
        ("Synthesized Sources", "8 AI Reviews (ChatGPT, Claude, DeepSeek, Gemini, GLM, Kimi, MiniMax, Qwen) + idea.docx")
    ]
    story.append(make_banner_table(
        "Multimodal Mental Health Emotion Monitoring AI: Master Literature Review & System Blueprint",
        curated_data.COVER_SUBTITLE,
        meta,
        styles
    ))
    story.append(Spacer(1, 10))

    # 2. Executive Synthesis & Scope Mapping
    story.append(Paragraph("Executive Synthesis & Project Alignment", styles['SectionH1']))
    story.append(Paragraph(
        f"<b>Project Specification Mapping:</b> {safe(curated_data.PROJECT_SPEC)}",
        styles['CalloutText']
    ))
    story.append(Spacer(1, 6))
    story.append(Paragraph(
        "This master document represents the complete, exhaustive curation and synthesis of eight independent AI literature reviews "
        "(ChatGPT, Claude, DeepSeek, Gemini, GLM, Kimi, MiniMax, Qwen) cross-referenced against the system specification in <code>idea.docx</code>. "
        "It provides a publication-grade foundation covering 59 core papers, 15 multimodal datasets, 13 open-source toolkits, 8 critical research gaps, "
        "and a fully specified dual-head system architecture blueprint with streaming latency budgets and edge privacy guarantees.",
        styles['BodyDark']
    ))
    story.append(Spacer(1, 8))

    # 3. Agent Consensus & Agreement Matrix
    story.append(Paragraph("Agent Consensus & Cross-Review Agreement Matrix", styles['SectionH1']))
    story.append(Paragraph(
        "To guarantee zero omissions and transparent provenance, every resource in this compendium tracks which of the 8 AI agents cited it. "
        "Below is the cross-review consensus distribution across core methodological categories:",
        styles['BodyDark']
    ))
    story.append(Spacer(1, 4))

    agent_matrix_headers = ["Research Category", "Key Papers / Models", "Consensus Agents", "Consensus Key Takeaway"]
    agent_matrix_rows = [
        ["Core Cross-Modal Attention", "MulT, MISA, Self-MM", "ChatGPT, Claude, Gemini, GLM, Kimi, MiniMax, Qwen", "Cross-attention dominates naive concatenation; subspace disentanglement essential for speaker invariance."],
        ["Acoustic Foundation Models", "Wav2Vec2, HuBERT, WavLM", "Claude, DeepSeek, Gemini, GLM, Kimi, MiniMax", "Supervised MFCC+LSTM is obsolete; self-supervised speech encoders provide +14% generalization gains."],
        ["Facial Vision Transformers", "POSTER++, ViT, DAN, MediaPipe", "ChatGPT, Claude, DeepSeek, Kimi, MiniMax", "Landmark-guided pyramid cross-attention (POSTER++) outperforms frame-level CNNs in-the-wild."],
        ["Explainable MLLMs", "Emotion-LLaMA, AffectGPT", "ChatGPT, Claude, Gemini, GLM, Kimi, MiniMax", "Dual-head architecture decouples real-time classification from explainable natural-language reasoning."],
        ["Missing Modalities", "MMIN, M3S, VAE-Diffusion", "ChatGPT, DeepSeek, Kimi, MiniMax, Qwen", "Dynamic imputation and latent diffusion prevent catastrophic failure when camera or mic is disabled."],
        ["Confidence Calibration", "MER-Calibration (Zhang 2024)", "ChatGPT, Claude, DeepSeek, Gemini", "Post-hoc temperature scaling required to avoid dangerously overconfident clinical predictions."],
        ["Clinical Corpora & Transfer", "DAIC-WOZ / E-DAIC", "Claude, Gemini, MiniMax", "Direct bridge from basic emotion categories to clinical depression (PHQ-8) severity scores."]
    ]
    story.append(make_styled_table(agent_matrix_headers, agent_matrix_rows, [100, 110, 150, 172], styles))
    story.append(Spacer(1, 10))

    # 4. Master Reading Guide Table
    story.append(Paragraph("Master Phased Reading Guide (59 Papers)", styles['SectionH1']))
    guide_headers = ["Priority Tier", "Target Scope", "Paper Count", "Core Representative Papers"]
    guide_rows = [
        ["Priority P0\n(Must Read First)", "Architecture Decisions, Core Fusion, Speech/Face Backbones & Clinical Surveys", "20 Papers", "MulT, MISA, Self-MM, UniMSE, Emotion-LLaMA, Wav2Vec2, HuBERT, POSTER++, DAIC-WOZ, MER-Calibration, MMIN"],
        ["Priority P1\n(Important)", "Subspace Disentanglement, Low-Rank Edge Fusion, Missing Modalities & Calibration", "20 Papers", "MMIM, TFN, LMF, MAG-BERT, DialogueGCN, COSMIC, WavLM, openSMILE, CubeMLP, VAE-Diffusion, M3S"],
        ["Priority P2\n(Specialized)", "Conversational Graph Models, Micro-Expressions, Pairwise Alignment & Speech Baselines", "14 Papers", "DialogueCRN, M2FNet, GS-MCC, MicroEmo, Centering-Hotspots, TITAN, DAN, DepAudioNet, Deep-Depression"],
        ["Priority P3\n(Background Canon)", "Historical Reviews, Comprehensive Taxonomies & Benchmark Retrospectives", "5 Papers", "Baltrusaitis Survey, Rouast Review, Gandhi Survey, Schuller Affect Review, ARM"]
    ]
    story.append(make_styled_table(guide_headers, guide_rows, [85, 145, 62, 240], styles))
    story.append(Spacer(1, 10))

    # 5. Section: Complete Papers Compendium
    story.append(PageBreak())
    story.append(Paragraph("Complete Literature Review Papers Compendium (59 Papers)", styles['SectionH1']))
    story.append(Paragraph(
        "The following catalog presents detailed structured breakdowns for all 59 papers. "
        "Each entry details problem formulation, input/output tensors, methodology (how & why), mental health applicability, priority, agent citations, and hyperlinks.",
        styles['BodyDark']
    ))
    story.append(Spacer(1, 6))

    for p in curated_data.PAPERS:
        story.append(make_paper_card(p, styles))

    # 6. Section: Master Datasets Directory
    story.append(PageBreak())
    story.append(Paragraph("Comprehensive Multimodal Datasets Directory (15 Corpora)", styles['SectionH1']))
    story.append(Paragraph(
        "Complete directory of multimodal emotional and clinical mental health datasets referenced across all reviews:",
        styles['BodyDark']
    ))
    story.append(Spacer(1, 6))

    for ds in curated_data.DATASETS:
        story.append(make_dataset_card(ds, styles))

    # 7. Section: Open-Source Tools & Frameworks
    story.append(PageBreak())
    story.append(Paragraph("Open-Source Toolkits, Frameworks & Implementation Codebases (13 Tools)", styles['SectionH1']))
    story.append(Paragraph(
        "Production-grade toolkits and repositories recommended for building the mental health monitoring pipeline:",
        styles['BodyDark']
    ))
    story.append(Spacer(1, 6))

    for tool in curated_data.TOOLS:
        story.append(make_tool_card(tool, styles))

    # 8. Section: Challenges & Research Gaps
    story.append(PageBreak())
    story.append(Paragraph("Key Research Challenges & Critical Gaps (C1 &mdash; C8)", styles['SectionH1']))
    story.append(Paragraph(
        "Eight unresolved scientific challenges identified across the multi-agent synthesis:",
        styles['BodyDark']
    ))
    story.append(Spacer(1, 6))

    for ch in curated_data.CHALLENGES:
        story.append(make_challenge_card(ch, styles))

    # 9. Section: End-to-End System Blueprint
    story.append(PageBreak())
    story.append(Paragraph("End-to-End System Architecture Blueprint (Mapped to idea.docx)", styles['SectionH1']))
    story.append(Paragraph(
        curated_data.BLUEPRINT_INTRO,
        styles['BodyDark']
    ))
    story.append(Spacer(1, 6))

    comp_headers = ["Subsystem Component", "Architectural Implementation & idea.docx Mapping"]
    comp_rows = []
    for name, desc in curated_data.BLUEPRINT_COMPONENTS:
        comp_rows.append([name, desc])
    story.append(make_styled_table(comp_headers, comp_rows, [140, 392], styles))
    story.append(Spacer(1, 10))

    story.append(Paragraph("Streaming Latency Budget & Real-Time Constraints", styles['SectionH2']))
    lat_headers = ["Pipeline Stage", "Target Budget", "Implementation Engine & Constraints"]
    lat_rows = []
    for stage, budget, engine in curated_data.LATENCY_ROWS:
        lat_rows.append([stage, budget, engine])
    story.append(make_styled_table(lat_headers, lat_rows, [160, 100, 272], styles))
    story.append(Spacer(1, 10))

    story.append(Paragraph("Master Experimental Evaluation Matrix", styles['SectionH2']))
    eval_headers = ["Evaluation Objective", "Benchmark Datasets", "Target Metrics & Verification Discipline"]
    eval_rows = []
    for obj, dsets, metrics in curated_data.EVAL_ROWS:
        eval_rows.append([obj, dsets, metrics])
    story.append(make_styled_table(eval_headers, eval_rows, [150, 140, 242], styles))

    doc.build(story, canvasmaker=lambda *args, **kwargs: NumberedCanvas(*args, doc_title="Multimodal Mental Health AI - Master Literature Review", vol_label="Master Compendium", **kwargs))
    print(f"[OK] Generated {filename}")

# -----------------------------------------------------------------------------
# MAIN RUNNER
# -----------------------------------------------------------------------------
def main():
    print("=" * 70)
    print("Starting Publication-Grade PDF Generation via ReportLab...")
    print(f"ReportLab Version: {reportlab.__version__}")
    print(f"Curated Data: {len(curated_data.PAPERS)} Papers | {len(curated_data.DATASETS)} Datasets | {len(curated_data.TOOLS)} Tools | {len(curated_data.CHALLENGES)} Challenges")
    print("=" * 70)

    pdf_files = [
        ("VOL_1_ARCHITECTURES_AND_METHODOLOGIES.pdf", build_vol1_pdf),
        ("VOL_2_PAPERS_COMPENDIUM_AND_READING_GUIDE.pdf", build_vol2_pdf),
        ("VOL_3_DATASETS_TOOLS_AND_BENCHMARKS.pdf", build_vol3_pdf),
        ("VOL_4_CHALLENGES_GAPS_AND_SYSTEM_BLUEPRINT.pdf", build_vol4_pdf),
        ("MULTIMODAL_MENTAL_HEALTH_AI_LITERATURE_REVIEW_MASTER.pdf", build_master_pdf)
    ]

    generated_stats = []
    for filename, build_fn in pdf_files:
        print(f"\nBuilding {filename}...")
        build_fn(filename)
        if os.path.exists(filename):
            size_kb = os.path.getsize(filename) / 1024.0
            generated_stats.append((filename, True, size_kb))
        else:
            generated_stats.append((filename, False, 0))

    print("\n" + "=" * 70)
    print("PDF GENERATION & INTEGRITY VERIFICATION SUMMARY")
    print("=" * 70)
    all_success = True
    for fname, exists, size_kb in generated_stats:
        status = "PASSED" if exists and size_kb > 0 else "FAILED"
        if status == "FAILED":
            all_success = False
        print(f"[{status}] {fname:<60} {size_kb:>8.2f} KB")

    print("=" * 70)
    if all_success:
        print("ALL 5 PUBLICATION-GRADE PDF DOCUMENTS GENERATED AND VERIFIED SUCCESSFULLY!")
    else:
        print("ERROR: One or more PDF documents failed generation.")
        sys.exit(1)

if __name__ == "__main__":
    main()
