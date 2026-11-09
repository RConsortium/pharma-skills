#!/usr/bin/env python3
"""
gsDose Report Template - generates gsdose_report.docx from gsdose_results.json.
Pure template: ZERO hardcoded design values. Every number comes from the JSON.

Usage:
    python gsdose_report_template.py <output_dir>

The script expects:
    <output_dir>/gsdose_results.json
    (written by compute_boundary.R; compute_test.R merges its results into the
    same file under each endpoint's "test" field)

It produces:
    <output_dir>/gsdose_report.docx

Sections:
    1. Design Assumptions
    2. Interim/Final Analysis Plan
    3. Efficacy Boundaries
    4. Combination Test and Closed Testing   (only when an endpoint has test results)
"""

import json
import math
import os
import sys
from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH


# -- Parse CLI ----------------------------------------------------------------

out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
json_path = os.path.join(out_dir, "gsdose_results.json")
report_path = os.path.join(out_dir, "gsdose_report.docx")

with open(json_path) as f:
    r = json.load(f)

meta = r.get("meta", {})
endpoints = r.get("endpoints", [])


# -- Helpers ------------------------------------------------------------------

def pct(x, dec=1):
    v = x * 100 if x <= 1 else x
    return f"{v:.{dec}f}%"

def fmt(x, dec=3):
    try:
        return f"{float(x):.{dec}f}"
    except (TypeError, ValueError):
        return str(x)

def add_heading(doc, text, level=1):
    return doc.add_heading(text, level=level)

def add_para(doc, text="", bold=False, italic=False):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.bold = bold
    run.italic = italic
    return p

def add_table(doc, headers, rows):
    t = doc.add_table(rows=1 + len(rows), cols=len(headers))
    t.style = "Table Grid"
    t.alignment = WD_ALIGN_PARAGRAPH.CENTER
    hdr = t.rows[0]
    for i, h in enumerate(headers):
        cell = hdr.cells[i]
        cell.text = h
        for run in cell.paragraphs[0].runs:
            run.bold = True
    for ri, row in enumerate(rows):
        tr = t.rows[ri + 1]
        for ci, val in enumerate(row):
            tr.cells[ci].text = "" if val is None else str(val)
    return t

def m(key, default=""):
    return meta.get(key, default)

def spending_label(sf, sfpar):
    if sf == "OF":
        return "O'Brien-Fleming (Lan-DeMets)"
    if sf == "HSD":
        return f"Hwang-Shih-DeCani (gamma = {sfpar})"
    return str(sf)


# -- Build document -----------------------------------------------------------

doc = Document()

title_p = doc.add_paragraph()
title_run = title_p.add_run(
    f"Seamless Phase 2/3 Dose-Selection Design Report: {m('disease', '')}"
)
title_run.bold = True
title_run.font.size = Pt(16)
title_p.alignment = WD_ALIGN_PARAGRAPH.CENTER
doc.add_paragraph()


# ==============================================================================
# Section 1: Design Assumptions
# ==============================================================================

add_heading(doc, "1. Design Assumptions", 1)

rows = [
    ["Disease / Setting", str(m("disease"))],
    ["Endpoints", str(m("endpoints"))],
    ["Dose arms at start (plus control)", str(m("k_dose_arms"))],
    ["Doses selected at dose selection", "1 (single dose carried forward)"],
    ["Randomization (dose : control)", str(m("randomization_ratio"))],
    ["Patients per arm before dose selection (n1)", str(m("n1_per_arm"))],
    ["Patients per arm after dose selection (n2)", str(m("n2_per_arm"))],
]

if m("total_N"):
    rows.append(["Total N", str(m("total_N"))])
if m("ctrl_median"):
    rows.append(["Control median survival", f"{m('ctrl_median')} months"])
if m("hr"):
    rows.append(["Assumed hazard ratio (all dose arms)", str(m("hr"))])
if m("dropout_rate") not in ("", None):
    rows.append(["Annual dropout", str(m("dropout_rate"))])
if m("enroll_duration"):
    rows.append(["Enrollment duration", f"{m('enroll_duration')} months"])

for ep in endpoints:
    label = f"Alpha (one-sided), {ep.get('name', '')}"
    rows.append([label, str(ep.get("alpha", ""))])
    rows.append([
        f"Efficacy spending, {ep.get('name', '')}",
        spending_label(ep.get("sf"), ep.get("sfpar")),
    ])
    fut = ep.get("futility") or {}
    if fut.get("enabled"):
        rows.append([
            f"Futility (lower) bound, {ep.get('name', '')}",
            (f"Null-based spending of {fut.get('total')} total, "
             f"{spending_label(fut.get('sf'), fut.get('sfpar'))}"),
        ])
    else:
        rows.append([f"Futility bound, {ep.get('name', '')}", "None (efficacy only)"])
    hrow = ep.get("h")
    if hrow:
        h1 = hrow[0][0] if isinstance(hrow[0], list) else hrow[0]
        h2 = hrow[0][1] if isinstance(hrow[0], list) else hrow[1]
        rows.append([
            f"Cohort weights h (cohort 1, cohort 2), {ep.get('name', '')}",
            f"({fmt(h1)}, {fmt(h2)})",
        ])

add_table(doc, ["Parameter", "Value"], rows)
add_para(
    doc,
    "Cohort 1 comprises patients enrolled before dose selection (all dose arms "
    "and control); cohort 2 comprises patients enrolled after dose selection "
    "(selected dose and control). Event counts below refer to the selected dose "
    "arm and control only. The hazard ratio assumption applies to all dose arms "
    "and affects efficiency only, not type I error control, because the "
    "combination weights are pre-specified.",
    italic=True,
)
doc.add_paragraph()


# ==============================================================================
# Section 2: Interim/Final Analysis Plan
# ==============================================================================

add_heading(doc, "2. Interim/Final Analysis Plan", 1)

for ep in endpoints:
    name = ep.get("name", "")
    stages = ep.get("stages", [])
    s_total = ep.get("s", len(stages))
    if len(endpoints) > 1:
        add_heading(doc, name, 2)

    add_para(
        doc,
        (f"{name} is tested at {s_total} analyses (dose-selection interim "
         f"excluded), with {ep.get('planD')} events planned from the selected "
         f"dose arm and control at the final analysis."),
    )

    has_time = any("expected_time" in st for st in stages)
    headers = ["Analysis", "Events (both cohorts)", "Cohort 1 events",
               "Cohort 2 events", "Information fraction"]
    if has_time:
        headers.append("Expected time (mo)")
    trows = []
    for st in stages:
        label = f"IA{st['stage']}" if st["stage"] < s_total else "FA"
        row = [label, st.get("d"), st.get("d1"), st.get("d2"),
               pct(st.get("info_frac", 0))]
        if has_time:
            row.append(st.get("expected_time", ""))
        trows.append(row)
    add_table(doc, headers, trows)
    doc.add_paragraph()


# ==============================================================================
# Section 3: Efficacy (and Futility) Boundaries — SAP-style per-analysis blocks
# ==============================================================================

def upper_tail_p(z):
    """One-sided upper-tail p for a standard normal z."""
    return 0.5 * math.erfc(z / math.sqrt(2.0))

def hr_at_bound(z, d, r):
    """Approximate HR required to achieve significance at the boundary z with
    d events and dose:control randomization ratio r (Schoenfeld)."""
    return math.exp(-z * (1.0 + r) / math.sqrt(d * r))

def parse_ratio(val):
    """'2:1' -> 2.0; '1:1'/missing -> 1.0; numbers pass through."""
    try:
        if isinstance(val, str) and ":" in val:
            a, b = val.split(":")
            return float(a) / float(b)
        return float(val)
    except (TypeError, ValueError):
        return 1.0

def sup_label(cell, base, sup):
    """Write 'base' with superscript 'sup' into a table cell."""
    p = cell.paragraphs[0]
    p.add_run(base)
    if sup:
        run = p.add_run(sup)
        run.font.superscript = True

any_lower = any(
    (ep.get("futility") or {}).get("enabled") and
    any("z_lower" in st for st in ep.get("stages", []))
    for ep in endpoints
)
add_heading(doc, "3. Efficacy and Futility Boundaries" if any_lower
            else "3. Efficacy Boundaries", 1)

r_ratio = parse_ratio(m("randomization_ratio", 1))
try:
    n_sel = (float(m("n1_per_arm")) * (1 + 1 / r_ratio)
             + float(m("n2_per_arm")) * (1 + 1 / r_ratio))
except (TypeError, ValueError):
    n_sel = None

for ep in endpoints:
    name = ep.get("name", "")
    stages = ep.get("stages", [])
    s_total = ep.get("s", len(stages))
    w_mat = ep.get("w") or []
    h_mat = ep.get("h") or []
    if len(endpoints) > 1:
        add_heading(doc, name, 2)

    add_para(
        doc,
        (f"{name} efficacy and futility boundaries for both individual and "
         f"intersection hypotheses of the selected dose, from spending "
         f"alpha = {ep.get('alpha')} with "
         f"{spending_label(ep.get('sf'), ep.get('sfpar'))} at the "
         f"observed/planned information fractions."),
    )

    fut = ep.get("futility") or {}
    has_lower = fut.get("enabled") and any("z_lower" in st for st in stages)

    # alpha groups: the assigned alpha first, then any sensitivity alphas
    groups = [{"alpha": ep.get("alpha"),
               "stages": {st["stage"]: st for st in stages}}]
    for sg in (ep.get("sensitivity") or []):
        groups.append({"alpha": sg.get("alpha"),
                       "stages": {st["stage"]: st for st in sg.get("stages", [])}})

    per_a = 2 if has_lower else 1
    n_cols = 2 + per_a * len(groups)
    t = doc.add_table(rows=2, cols=n_cols)
    t.style = "Table Grid"
    t.alignment = WD_ALIGN_PARAGRAPH.CENTER

    # header row 0: alpha labels spanning each Efficacy/Futility pair
    r0, r1 = t.rows[0], t.rows[1]
    for gi, g in enumerate(groups):
        c0 = 2 + gi * per_a
        cell = r0.cells[c0]
        if per_a > 1:
            cell = cell.merge(r0.cells[c0 + per_a - 1])
        cell.text = f"α = {g['alpha']}"
        for run in cell.paragraphs[0].runs:
            run.bold = True
    # header row 1: Analysis | Value | Efficacy [| Futility] per group
    r1.cells[0].text = "Analysis"
    r1.cells[1].text = "Value"
    for gi in range(len(groups)):
        c0 = 2 + gi * per_a
        r1.cells[c0].text = "Efficacy"
        if has_lower:
            r1.cells[c0 + 1].text = "Futility"
    for cell in list(r1.cells) + [r0.cells[0], r0.cells[1]]:
        for run in cell.paragraphs[0].runs:
            run.bold = True
    for ci in (0, 1):  # merge Analysis/Value cells over both header rows
        merged = r0.cells[ci].merge(r1.cells[ci])
        merged.text = "Analysis" if ci == 0 else "Value"
        for run in merged.paragraphs[0].runs:
            run.bold = True

    h_pair = h_mat[0] if (h_mat and isinstance(h_mat[0], list)) else h_mat
    h_txt = ", ".join(fmt(x, 2) for x in h_pair) if h_pair else ""

    for st in stages:
        k = st["stage"]
        is_fa = (k == s_total)
        label = "FA" if is_fa else f"IA{k}"
        label += f": {pct(st.get('info_frac', 0), 0)}"
        if n_sel:
            label += f"\nN = {n_sel:.0f}"
        label += f"\nEvents: {st.get('d')}"
        d_ev = st.get("d")

        first_row_idx = len(t.rows)

        # w and h rows span all alpha columns (same for every alpha)
        span_rows = []
        if k > 1 and len(w_mat) >= k:
            w_row = w_mat[k - 1][:k]
            span_rows.append((", ".join(f"w{j+1}" for j in range(k)), "a",
                              ", ".join(fmt(x, 2) for x in w_row)))
        span_rows.append(("h1, h2", "b", h_txt))
        for (lbl, sup, val) in span_rows:
            cells = t.add_row().cells
            sup_label(cells[1], lbl, sup)
            spanned = cells[2]
            if n_cols > 3:
                spanned = spanned.merge(cells[n_cols - 1])
            spanned.text = val

        # Z / p / HR rows: one Efficacy[,Futility] pair per alpha group
        def group_vals(kind):
            vals = []
            for g in groups:
                gst = g["stages"].get(k, {})
                zu = gst.get("z_upper")
                zl = gst.get("z_lower") if (has_lower and not is_fa) else None
                if kind == "z":
                    vals.append(fmt(zu, 4))
                    if has_lower:
                        vals.append(fmt(zl, 4) if zl is not None else "NA")
                elif kind == "p":
                    vals.append(fmt(gst.get("nominal_p_upper"), 4))
                    if has_lower:
                        vals.append(fmt(upper_tail_p(zl), 4)
                                    if zl is not None else "NA")
                else:  # hr
                    vals.append(fmt(hr_at_bound(zu, d_ev, r_ratio), 4))
                    if has_lower:
                        vals.append(fmt(hr_at_bound(zl, d_ev, r_ratio), 4)
                                    if zl is not None else "NA")
            return vals

        for (lbl, sup, kind) in [("Z", "", "z"), ("p (1-sided)", "c", "p"),
                                 ("HR at bound", "d", "hr")]:
            cells = t.add_row().cells
            sup_label(cells[1], lbl, sup)
            for ci, val in enumerate(group_vals(kind)):
                cells[2 + ci].text = val

        # merge the Analysis cell vertically over this block
        top = t.rows[first_row_idx].cells[0]
        for ri in range(first_row_idx + 1, len(t.rows)):
            top = top.merge(t.rows[ri].cells[0])
        top.text = label

    # footnotes
    foot = doc.add_paragraph()
    foot_runs = [
        ("a", " weights to combine the incremental test statistics for cohort 1: "
              "w1 is the weight for the data up to the first testing analysis, "
              "w2, w3, ... for each later increment. The weights are proportional "
              "to the expected events across analyses from cohort 1."),
        ("b", " weights to combine the cohort-1 and cohort-2 statistics, "
              "proportional to the expected sample sizes for cohorts 1 and 2."),
        ("c", " p (1-sided) is the nominal alpha for group sequential testing."),
        ("d", " HR at bound is the approximate hazard ratio required to achieve "
              "significance at the boundary, for reference purposes."),
    ]
    for supc, txt in foot_runs:
        run = foot.add_run(supc)
        run.font.superscript = True
        run.font.size = Pt(9)
        run2 = foot.add_run(txt + "\n")
        run2.font.size = Pt(9)

    if has_lower:
        add_para(
            doc,
            ("The futility (lower) boundary spends a total probability of "
             f"{fut.get('total')} under the null hypothesis across stages using "
             f"{spending_label(fut.get('sf'), fut.get('sfpar'))}; it is a "
             "null-based spending rule, not a beta-spending rule. The futility "
             "bound is shown as NA at the final analysis, where only the efficacy "
             "bound applies."),
            italic=True,
        )
    doc.add_paragraph()


# ==============================================================================
# Section 4: Combination Test and Closed Testing (workflow B, optional)
# ==============================================================================

tested = [ep for ep in endpoints if ep.get("test")]
if tested:
    add_heading(doc, "4. Combination Test and Closed Testing", 1)

    for ep in tested:
        t = ep["test"]
        if len(tested) > 1 or len(endpoints) > 1:
            add_heading(doc, ep.get("name", ""), 2)

        add_para(
            doc,
            (f"Analysis at testing stage {t.get('stage')} for {ep.get('name', '')}: "
             f"dose {t.get('sid')} was selected at dose selection. Each intersection "
             f"hypothesis containing the selected dose is tested with the inverse "
             f"normal combination of the cohort-1 Dunnett statistic and the cohort-2 "
             f"log-rank statistic, against the efficacy boundary "
             f"Z = {fmt(t.get('zbound'), 3)} computed at the actual event counts."),
        )

        headers = ["Intersection", "Doses included", "Dunnett Z (cohort 1)",
                   "Cohort-2 Z", "Combination Z", f"Reject (Z > {fmt(t.get('zbound'), 3)})"]
        trows = []
        for it in t.get("intersections", []):
            doses = it.get("doses")
            if isinstance(doses, list):
                doses_str = ", ".join(str(x) for x in doses)
            else:
                doses_str = str(doses)
            trows.append([
                it.get("hypothesis", ""),
                doses_str,
                fmt(it.get("dunnett_z1"), 3),
                fmt(it.get("logrank_z2"), 3),
                fmt(it.get("combo_z"), 3),
                "Yes" if it.get("reject") else "No",
            ])
        add_table(doc, headers, trows)

        add_para(doc, t.get("decision", ""), bold=True)

        fut = t.get("futility")
        if fut:
            crossed = "crossed" if fut.get("crossed") else "did not cross"
            add_para(
                doc,
                (f"Futility check (informational): the selected dose's combination "
                 f"Z of {fmt(fut.get('individual_combo_z'), 3)} {crossed} the futility "
                 f"boundary Z = {fmt(fut.get('z_lower'), 3)}."),
                italic=True,
            )
        doc.add_paragraph()


# -- Save ----------------------------------------------------------------------

doc.save(report_path)
print(f"WROTE: {report_path}")
