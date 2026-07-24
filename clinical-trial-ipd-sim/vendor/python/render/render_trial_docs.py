"""render_trial_docs.py — render a {trial}_output/ run into ONE themed HTML page.

Produces a self-contained page with: a big interactive Cytoscape.js causal-DAG diagram (parsed from
DAG.md, or from an optional {trial}_output/dag.json override), then the rendered DAG.md, CRF_spec.md,
and README.md. Uses the repo's docs theme (the Keiji TrialMind dashboard palette — indigo #491eff
primary, teal accent, near-white base, dark-slate ink, native system-sans font), marked.js in-browser, and
base64-embedded markdown so this generator never parses/corrupts the prose.

    python3 .claude/skills/clinical-trial-ipd-sim/templates/render_trial_docs.py outputs/VAR05_output

Writes TWO identical files: {trial}_output/index.html (lives with the run) and
docs/trials/{TRIAL}.html (so the local docs dashboard, docs/serve.py, lists it). Both are
gitignored, regenerable scratch. Re-run to refresh; never hand-edit the HTML.

The DAG graph is edges-from-parents only (never the equation/evidence columns). If the parser
mishandles a trial's DAG.md, author {trial}_output/dag.json = {"nodes":[...],"edges":[...]} (the
Cytoscape elements shape) and it is used verbatim.

Diagram interactivity (two-way): it opens in the **layer-lanes** layout (left->right, one column per
DAG layer; Dagre / Breadthfirst / Force also selectable). Clicking a **node** — or an **arrow** (edge)
— jumps to that variable's row in the rendered DAG.md table (an arrow jumps to its child's equation
row); clicking a **variable id in the table** (Node or Parents column) jumps back to that node in the
graph. Structural equations in the Equation column are authored as inline LaTeX (`$...$`) and typeset
with KaTeX; the Evidence quote column is given extra width. A node with no arrows is an exogenous
variable no row names as a parent — faithful to DAG.md, not a bug.
"""
import base64
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))   # templates/->skill->skills->.claude->repo
DOCS_TRIALS = os.path.join(REPO, "docs", "trials")

# ---------------------------------------------------------------- DAG.md -> graph
NONE_TOKENS = {"—", "–", "-", "∅", ""}


def classify_layer(header):
    """Map a DAG.md H2 header to a DAG layer by its LEADING token (order matters: Lt before
    latent, because an Lt header may merely *mention* frailties in its parenthetical)."""
    t = header.strip().lower()
    if t.startswith("root"):
        return "root"
    if t.startswith("l0") or t.startswith("layer 0"):
        return "L0"
    if t.startswith("lt") or t.startswith("layer lt") or "time-varying" in t:
        return "Lt"
    if t.startswith("latent") or t.startswith("frailt"):
        return "latent"
    if t.startswith("layer a") or t.startswith("a ") or t.startswith("a—") or t.startswith("a –") \
       or (t.startswith("a") and "treatment" in t):
        return "A"
    if t.startswith("y") or "endpoint" in t:
        return "Yt"
    return "unknown"


def _norm(tok):
    """Canonicalize an id token: drop bold, backticks, trailing (annotation) and [index] suffixes."""
    t = tok.strip()
    t = re.sub(r"\*\*(.+?)\*\*", r"\1", t)          # unbold
    t = t.strip().strip("`").strip()
    t = re.sub(r"\s*\([^)]*\)\s*$", "", t)          # trailing (annotation)
    t = re.sub(r"\[[^\]]*\]", "", t)                # [t] / [t-1] / [gene] index suffixes
    return t.strip()


def _node_ids(cell):
    """(ids, annotation) from a node cell. Handles leading **TAG**, backtick spans, comma/slash."""
    cell = re.sub(r"^\*\*[A-Za-z0-9]{1,4}\*\*\s*", "", cell.strip())    # strip inline layer tag (CATH)
    spans = re.findall(r"`([^`]+)`", cell)
    ann = re.sub(r"`[^`]+`", "", cell)
    ann = re.sub(r"[,]+", " ", ann).strip(" .·`")                       # leftover -> annotation
    raw = []
    if spans:
        for sp in spans:
            raw += [p for p in sp.split(",")]                          # comma INSIDE a span (CATH)
    else:
        m = re.findall(r"\*\*(.+?)\*\*", cell)
        base = m[0] if m else re.split(r"\(", cell)[0]
        raw = base.split(",")
    ids = [i for i in (_norm(x) for x in raw) if i]
    return ids, ann


def _parents(cell):
    c = re.sub(r"\s*\([^)]*\)\s*$", "", cell.strip())
    if c.strip("`").strip() in NONE_TOKENS:
        return []
    out = []
    for part in c.split(","):
        p = _norm(part)
        if p and p not in NONE_TOKENS and " " not in p:      # drop multiword prose (e.g. "nominal day")
            out.append(p)
    return out


def parse_dag(md):
    """DAG.md text -> {'nodes':[{data:{id,label,layer,role}}], 'edges':[{data:{source,target}}]}."""
    nodes, edges = {}, []
    lines = md.splitlines()
    layer = "unknown"

    def add(nid, label, lyr):
        if nid not in nodes:
            nodes[nid] = {"id": nid, "label": label or nid, "layer": lyr}
        elif nodes[nid]["layer"] == "unknown" and lyr != "unknown":
            nodes[nid]["layer"] = lyr

    i, n = 0, len(lines)
    while i < n:
        line = lines[i]
        if line.startswith("## ") and not line.startswith("### "):
            layer = classify_layer(line[3:])
            i += 1; continue
        # --- Node/Parents table ---
        if line.lstrip().startswith("|") and "Node" in line and "Parents" in line:
            j = i + 2                                                   # skip header + |---| separator
            while j < n and lines[j].lstrip().startswith("|"):
                cells = [c.strip() for c in lines[j].strip().strip("|").split("|")]
                if len(cells) >= 2:
                    ids, ann = _node_ids(cells[0])
                    pars = _parents(cells[1])
                    for nid in ids:
                        add(nid, (nid + " " + ann).strip() if ann else nid, layer)
                    for p in pars:
                        for nid in ids:
                            edges.append((p, nid))
                j += 1
            i = j; continue
        # --- arrow bullet (ARA06): "- **node(s)** <- parents. ..." possibly ;-joined ---
        if line.lstrip().startswith("- ") and "←" in line:
            for clause in line.lstrip()[2:].split(";"):
                if "←" not in clause:
                    continue
                lhs, rhs = clause.split("←", 1)
                rhs = re.split(r"\.", rhs, 1)[0]
                ids, _ = _node_ids(lhs)
                for nid in ids:
                    add(nid, nid, layer)
                for p in _parents(rhs):
                    for nid in ids:
                        edges.append((p, nid))
            i += 1; continue
        i += 1

    for s, t in edges:                                                 # stub phantom parents/targets
        add(s, s, "unknown"); add(t, t, "unknown")
    seen, E = set(), []
    for s, t in edges:
        if s != t and (s, t) not in seen:                              # drop self-loops + dups
            seen.add((s, t)); E.append({"source": s, "target": t})
    role = {"latent": "latent", "A": "treatment", "Yt": "endpoint"}
    return {
        "nodes": [{"data": {"id": v["id"], "label": v["label"], "layer": v["layer"],
                            "role": role.get(v["layer"], "observed")}} for v in nodes.values()],
        "edges": [{"data": e} for e in E],
    }


# ---------------------------------------------------------------- render
def render(trial_dir):
    trial_dir = os.path.abspath(trial_dir.rstrip("/"))
    base = os.path.basename(trial_dir)
    trial = base[:-len("_output")] if base.endswith("_output") else base

    def read(name):
        p = os.path.join(trial_dir, name)
        return open(p, encoding="utf-8").read() if os.path.exists(p) else None

    dag_md, crf_md, readme_md = read("DAG.md"), read("CRF_spec.md"), read("README.md")

    dag_json = os.path.join(trial_dir, "dag.json")
    if os.path.exists(dag_json):
        elements = json.load(open(dag_json, encoding="utf-8"))
    elif dag_md:
        elements = parse_dag(dag_md)
        if not elements["nodes"]:
            elements = None
    else:
        elements = None

    nav, sections = [], []
    if elements:
        nav.append('<a href="#diagram">DAG diagram</a>')
    for sid, label, md in (("dag", "DAG — detail", dag_md),
                           ("crf", "CRF spec", crf_md),
                           ("readme", "README", readme_md)):
        if md:
            sections.append((sid, label, base64.b64encode(md.encode("utf-8")).decode("ascii")))
            nav.append(f'<a href="#{sid}">{label}</a>')

    stage = DIAGRAM_SECTION.replace("__TRIAL__", trial) if elements else ""
    secs_html = "\n".join(
        f'<section id="{sid}"><h2 class="sec">{label}</h2>'
        f'<article class="doc" data-md="{sid}">loading…</article></section>'
        for sid, label, _ in sections)

    data = {"trial": trial, "md": {sid: b64 for sid, label, b64 in sections}, "elements": elements}

    page = (PAGE
            .replace("__TITLE__", f"{trial} — DAG &amp; CRF")
            .replace("__TRIAL__", trial)
            .replace("__NAV__", "\n".join(nav))
            .replace("__STAGE__", stage)
            .replace("__SECTIONS__", secs_html)
            .replace("__DATA__", json.dumps(data)))

    out_run = os.path.join(trial_dir, "index.html")
    out_dash = os.path.join(DOCS_TRIALS, f"{trial}.html")
    os.makedirs(DOCS_TRIALS, exist_ok=True)
    for p in (out_run, out_dash):
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(page)
    ne = len(elements["nodes"]) if elements else 0
    ee = len(elements["edges"]) if elements else 0
    print(f"wrote {out_run}\n      {out_dash}")
    print(f"  trial={trial}  graph={'yes' if elements else 'skipped'} ({ne} nodes, {ee} edges)  "
          f"sections={[s[0] for s in sections]}")


DIAGRAM_SECTION = """<section id="diagram" class="stage">
  <div class="figbar">
    <div class="controls">
      <span class="ctl-lbl">__TRIAL__ causal DAG</span>
      <select id="layoutSel" title="Layout">
        <option value="lanes">Layer lanes</option>
        <option value="dagre">Layered ↓ (Dagre)</option>
        <option value="breadthfirst">Breadthfirst</option>
        <option value="cose">Force</option>
      </select>
      <button id="btnFit" title="Fit to view">Fit</button>
      <button id="btnZout" title="Zoom out">−</button>
      <button id="btnZin" title="Zoom in">+</button>
      <button id="btnFull" title="Fullscreen">⤢ Full</button>
      <button id="btnPng" title="Download PNG">PNG</button>
      <input id="nodeSearch" type="search" placeholder="Search nodes…" autocomplete="off" spellcheck="false"
             title="Highlight nodes whose name matches as you type">
      <span id="searchCount" class="scount"></span>
    </div>
    <div class="legend" id="legend"></div>
  </div>
  <div id="cy"></div>
  <div id="axis"></div>
</section>"""


PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>__TITLE__</title>
<script src="https://cdn.jsdelivr.net/npm/marked@12/marked.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/cytoscape/3.33.2/cytoscape.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/dagre@0.8.5/dist/dagre.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/cytoscape-dagre@2.5.0/cytoscape-dagre.min.js"></script>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
<script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.min.js"></script>
<style>
  /* Keiji TrialMind dashboard palette (ga.trialmindapis.com): indigo #491eff primary,
     teal accent, near-white base, dark-slate ink, native system-sans font. Var NAMES kept from the old
     paper theme so the rest of the stylesheet re-themes automatically. */
  :root{--bg:#fafafa;--bg-band:#f1f2f5;--panel:#f4f5f7;--card:#ffffff;--card-2:#f4f5f7;--ink:#2b3440;
        --muted:#5b6675;--faint:#99a1af;--line:#e3e6eb;--sage:#491eff;--sage-deep:#2f14c9;
        --clay:#0e9384;--chip:#eef0ff;--chip-ink:#3712c9;--radius:1rem;}
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--ink);display:grid;grid-template-columns:270px 1fr;
    font:16.5px/1.72 ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,sans-serif;-webkit-font-smoothing:antialiased}
  aside{position:sticky;top:0;align-self:start;height:100vh;overflow-y:auto;background:var(--panel);
    border-right:1px solid var(--line);padding:30px 22px}
  aside .tag{color:var(--muted);font-size:13px;margin:3px 0 18px}
  #nav a{display:block;color:var(--muted);text-decoration:none;font-size:14.5px;line-height:1.4;
    padding:8px 12px;border-radius:.5rem;border-left:2px solid transparent;transition:.15s}
  #nav a:hover{color:var(--ink);background:var(--card)}
  #nav a.active{color:var(--sage-deep);border-left-color:var(--sage);background:var(--chip);font-weight:600}
  main{min-width:0}
  /* ---- big graph stage (full width of the main column) ---- */
  .stage{margin:0}
  .figbar{display:flex;justify-content:space-between;align-items:center;gap:16px;flex-wrap:wrap;
    padding:12px 40px;background:var(--bg-band);border-bottom:1px solid var(--line);position:sticky;top:0;z-index:6}
  .controls{display:flex;align-items:center;gap:8px;flex-wrap:wrap}
  .ctl-lbl{font-family:ui-sans-serif,system-ui,sans-serif;font-weight:600;font-size:18px;margin-right:6px}
  /* DaisyUI-style controls: .5rem radius (--rounded-btn), weight 600, hairline border,
     hair-thin shadow, indigo focus ring — matching the TrialMind dashboard. */
  .controls select,.controls button{font:600 14px ui-sans-serif,system-ui,sans-serif;color:var(--ink);background:var(--card);
    border:1px solid var(--line);border-radius:.5rem;padding:9px 14px;cursor:pointer;transition:.15s;
    box-shadow:0 1px 2px rgba(20,22,45,.06)}
  .controls select:hover,.controls button:hover{background:var(--card-2);border-color:var(--sage)}
  .controls button:active{background:var(--card-2);transform:translateY(.5px)}
  .controls select:focus-visible,.controls button:focus-visible{outline:none;border-color:var(--sage);box-shadow:0 0 0 3px rgba(73,30,255,.18)}
  .controls input[type=search]{font:500 14px ui-sans-serif,system-ui,sans-serif;color:var(--ink);background:var(--card);
    border:1px solid var(--line);border-radius:.5rem;padding:9px 12px;width:180px;transition:.15s}
  .controls input[type=search]:focus{outline:none;border-color:var(--sage);box-shadow:0 0 0 3px rgba(73,30,255,.18)}
  .scount{font-size:12.5px;color:var(--muted);min-width:70px}
  #diagram{position:relative}
  #cy{width:100%;height:calc(100vh - 66px);min-height:560px;background:var(--card);display:block}
  #axis{position:absolute;left:0;right:0;bottom:0;height:30px;pointer-events:none;overflow:hidden;z-index:5;
    border-top:1px solid var(--line);background:linear-gradient(to top,rgba(247,244,237,.94),rgba(247,244,237,0))}
  #axis .axlabel{position:absolute;bottom:6px;transform:translateX(-50%);white-space:nowrap;
    font:700 12px ui-sans-serif,system-ui,sans-serif;color:var(--sage-deep);text-transform:uppercase;letter-spacing:.05em;
    background:var(--card);border:1px solid var(--line);border-radius:6px;padding:2px 9px}
  #diagram:fullscreen{background:var(--bg)}
  #diagram:fullscreen #cy{height:calc(100vh - 66px)}
  .legend{display:flex;gap:14px;flex-wrap:wrap;font-size:12.5px;color:var(--muted)}
  .legend .lg{display:inline-flex;align-items:center;gap:6px}
  .legend .sw{width:13px;height:13px;border-radius:3px;border:2px solid}
  /* ---- text column ---- */
  .wrap{max-width:1080px;margin:0 auto;padding:40px 44px 140px}
  h1{font-family:ui-sans-serif,system-ui,sans-serif;font-weight:600;font-size:38px;letter-spacing:-.015em;margin:0 0 6px}
  .cap{color:var(--muted);font-size:14px;margin:0 0 8px}
  section{scroll-margin-top:76px}
  h2.sec{font-size:12px;text-transform:uppercase;letter-spacing:.09em;color:var(--clay);font-weight:700;
    margin:44px 0 12px;padding-bottom:8px;border-bottom:1px solid var(--line)}
  .doc h1{font-size:26px;margin:8px 0 8px}
  .doc h2{font-family:ui-sans-serif,system-ui,sans-serif;font-weight:600;font-size:21px;margin:26px 0 6px;text-transform:none;
    letter-spacing:-.005em;color:var(--ink);border:none;padding:0}
  .doc h3{font-size:16px;margin:20px 0 4px}
  .doc p{margin:10px 0}.doc strong{color:var(--ink);font-weight:600}
  .doc a{color:var(--sage-deep);text-decoration:none;border-bottom:1px solid var(--line)}
  .doc code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.84em;background:var(--chip);
    color:var(--chip-ink);padding:1.5px 6px;border-radius:5px}
  .doc code.nodelink{cursor:pointer;border-bottom:1px dashed var(--sage);color:var(--sage-deep)}
  .doc code.nodelink:hover{background:#e7ead9;color:var(--ink)}
  .doc pre{background:#1e2634;border-radius:var(--radius);padding:16px 18px;overflow-x:auto;margin:14px 0}
  .doc pre code{background:none;color:#e6e1d5;padding:0}
  .doc ul{margin:8px 0;padding-left:22px}.doc li{margin:5px 0}
  .doc table{border-collapse:collapse;width:100%;font-size:13.5px;margin:14px 0;display:block;overflow-x:auto}
  .doc th,.doc td{border:1px solid var(--line);padding:8px 11px;text-align:left;vertical-align:top}
  .doc th{background:var(--card);color:var(--sage-deep);font-size:11.5px;text-transform:uppercase;letter-spacing:.04em}
  .doc td{color:var(--muted)}
  .doc tr.dagrow-hl td{background:#eef0ff;box-shadow:inset 3px 0 0 var(--sage);transition:background .3s}
  /* give the DAG table's Evidence quote column (always the last col) more room */
  article[data-md="dag"] table{table-layout:auto}
  article[data-md="dag"] td:last-child,article[data-md="dag"] th:last-child{min-width:400px;width:46%}
  .doc .katex{font-size:1.02em}
  @media(max-width:960px){body{grid-template-columns:1fr}
    aside{position:static;height:auto;border-right:none;border-bottom:1px solid var(--line)}
    #cy{height:70vh}.figbar{padding:12px 22px}.wrap{padding:28px 22px 80px}}
</style></head>
<body>
<aside>
  <div class="tag">__TRIAL__ · trial docs</div>
  <nav id="nav">
__NAV__
  </nav>
</aside>
<main>
__STAGE__
<div class="wrap">
  <h1>__TRIAL__ — DAG &amp; CRF</h1>
  <p class="cap">Interactive causal DAG above (drag = pan · scroll = zoom · hover to focus a node's
    ancestors + descendants · <b>click a node or an arrow to jump to its row in the table below, and
    click any variable id in the table to jump back to its node</b> · switch layout / fullscreen with
    the bar). Structural equations in the table are typeset math.</p>
__SECTIONS__
</div>
</main>
<script type="application/json" id="data">__DATA__</script>
<script>
  const DATA = JSON.parse(document.getElementById('data').textContent);
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const dec = (b64) => new TextDecoder('utf-8').decode(Uint8Array.from(atob(b64), c => c.charCodeAt(0)));

  // ---- rendered markdown sections (protect $…$ math from marked, then KaTeX-typeset it) ----
  const mathStore = [];
  const protectMath = (md) => md
    .replace(/\$\$([\s\S]+?)\$\$/g, (m) => `@@M${mathStore.push(m) - 1}@@`)
    .replace(/\$([^$\\n]+?)\$/g,    (m) => `@@M${mathStore.push(m) - 1}@@`);
  for (const [id, b64] of Object.entries(DATA.md || {})) {
    const el = document.querySelector(`article[data-md="${id}"]`);
    if (!el) continue;
    const html = marked.parse(protectMath(dec(b64)), { gfm: true });
    el.innerHTML = html.replace(/@@M(\d+)@@/g, (_, i) => mathStore[i]);   // restore raw $…$ into the DOM
  }
  if (window.renderMathInElement) document.querySelectorAll('article.doc').forEach((a) => {
    try { renderMathInElement(a, { delimiters: [{ left: '$$', right: '$$', display: true },
                                                 { left: '$', right: '$', display: false }], throwOnError: false }); }
    catch (e) { console.warn('katex render skipped', e); }
  });

  // node id -> its <tr> in the rendered DAG table (so clicking a graph node jumps to its row)
  const normId = (s) => s.trim().replace(/^\*\*.+?\*\*\s*/, '').replace(/\s*\([^)]*\)\s*$/, '').replace(/\[[^\]]*\]/g, '').trim();
  const dagRows = {};
  {
    const art = document.querySelector('article[data-md="dag"]');
    if (art) art.querySelectorAll('table tbody tr').forEach(tr => {
      const first = tr.querySelector('td'); if (!first) return;               // first cell = the node cell
      first.querySelectorAll('code').forEach(c => c.textContent.split(',').forEach(part => {
        const k = normId(part); if (k && !(k in dagRows)) dagRows[k] = tr;
      }));
    });
  }
  // ---- scroll-spy ----
  const links = new Map([...document.querySelectorAll('#nav a')].map(a => [a.getAttribute('href').slice(1), a]));
  document.querySelectorAll('section[id]').forEach(s => new IntersectionObserver(es => es.forEach(e => {
    if (e.isIntersecting) { links.forEach(a => a.classList.remove('active')); links.get(s.id)?.classList.add('active'); }
  }), { rootMargin: '-6% 0px -80% 0px' }).observe(s));

  // ---- Cytoscape DAG ----
  const LC = { root:'#7c8698', L0:'#0e9384', A:'#491eff', latent:'#9b8cff', Lt:'#0891b2', Yt:'#00a878', unknown:'#aab2bd' };
  const ORDER = ['root','L0','A','latent','Lt','Yt','unknown'];
  const LANE_X = 380;                                        // px between layer columns (lanes mode + bottom axis)
  const LABELS = { root:'Root', L0:'L₀ baseline', A:'A treatment', latent:'Latent frailty', Lt:'Lₜ time-varying', Yt:'Yₜ endpoint', unknown:'Other' };

  if (DATA.elements && document.getElementById('cy')) {
    const cy = cytoscape({
      container: document.getElementById('cy'),
      elements: DATA.elements,
      minZoom: 0.08, maxZoom: 4, wheelSensitivity: 0.3,
      style: [
        { selector:'node', style:{
            'label':'data(label)', 'text-wrap':'wrap', 'text-max-width':170, 'font-size':16, 'font-weight':600,
            'text-valign':'center', 'text-halign':'center', 'color':'#2b3440',
            'width':'label', 'height':'label', 'padding':'16px', 'shape':'round-rectangle',
            'background-color':(n)=>LC[n.data('layer')]||LC.unknown, 'background-opacity':0.22,
            'border-width':2.5, 'border-color':(n)=>LC[n.data('layer')]||LC.unknown }},
        { selector:'node[role="treatment"]', style:{ 'shape':'diamond', 'padding':'28px' }},
        { selector:'node[role="latent"]',    style:{ 'shape':'ellipse', 'border-style':'dashed' }},
        { selector:'node[role="endpoint"]',  style:{ 'border-width':4 }},
        { selector:'edge', style:{
            'width':2, 'line-color':'#b9c0cc', 'curve-style':'bezier', 'opacity':0.85,
            'target-arrow-shape':'triangle', 'target-arrow-color':'#b9c0cc', 'arrow-scale':1.1 }},
        { selector:'.faded', style:{ 'opacity':0.08, 'text-opacity':0.08 }},
        { selector:'node.hl', style:{ 'border-width':4, 'border-color':'#2b3440', 'z-index':10 }},
        { selector:'edge.hl', style:{ 'line-color':'#491eff', 'target-arrow-color':'#491eff', 'width':3, 'opacity':1, 'z-index':10 }},
        { selector:'.search-dim', style:{ 'opacity':0.10, 'text-opacity':0.10 }},
        { selector:'node.search-hit', style:{ 'border-width':5, 'border-color':'#ff41c7', 'text-opacity':1,
          'z-index':20, 'overlay-color':'#ff41c7', 'overlay-opacity':0.18, 'overlay-padding':5 }},
      ],
    });

    const fitv = () => cy.animate({ fit:{ padding:60 } }, { duration: reduce?0:300 });
    const lanes = () => {                                   // zero-dep preset: one COLUMN per DAG layer (left -> right)
      const by = {}; cy.nodes().forEach(n => (by[n.data('layer')] ||= []).push(n));
      let col = 0;
      ORDER.forEach(L => { const arr = by[L]; if (!arr || !arr.length) return;
        arr.forEach((n, i) => n.position({ x: col*LANE_X, y:(i-(arr.length-1)/2)*130 })); col++; });
      cy.fit(undefined, 60);
    };
    const roots = () => cy.nodes().filter(n => n.indegree(false) === 0);
    const run = (kind) => {
      if (kind === 'lanes') { lanes(); return; }
      const base = { animate: !reduce, animationDuration: reduce?0:500, fit: true, padding: 60 };
      let o;
      if (kind === 'dagre') o = { ...base, name:'dagre', rankDir:'TB', nodeSep:55, rankSep:95, edgeSep:15 };
      else if (kind === 'breadthfirst') o = { ...base, name:'breadthfirst', directed:true, spacingFactor:1.4, roots: roots() };
      else o = { ...base, name:'cose', idealEdgeLength:150, nodeRepulsion:16000, gravity:0.3, nestingFactor:1.1 };
      try { cy.layout(o).run(); }
      catch (e) { console.warn('layout', kind, 'unavailable, using breadthfirst', e);
                  cy.layout({ name:'breadthfirst', directed:true, fit:true, padding:60 }).run(); }
    };

    // bottom axis: a label under each layer column (lanes mode only), re-aligned on pan/zoom
    const axisEl = document.getElementById('axis');
    const drawAxis = () => {
      if (document.getElementById('layoutSel').value !== 'lanes') { axisEl.style.display = 'none'; return; }
      axisEl.style.display = 'block';
      const by = {}; cy.nodes().forEach(n => (by[n.data('layer')] ||= []).push(n));
      const z = cy.zoom(), px = cy.pan().x; let col = 0, html = '';
      ORDER.forEach(L => { if (!by[L] || !by[L].length) return;
        html += `<span class="axlabel" style="left:${col*LANE_X*z + px}px">${LABELS[L]}</span>`; col++; });
      axisEl.innerHTML = html;
    };
    cy.on('pan zoom', drawAxis);

    const $ = (id) => document.getElementById(id);
    $('layoutSel').onchange = () => { run($('layoutSel').value); drawAxis(); };
    $('btnFit').onclick = fitv;
    $('btnZin').onclick  = () => cy.zoom({ level: Math.min(cy.maxZoom(), cy.zoom()*1.3), renderedPosition:{ x:cy.width()/2, y:cy.height()/2 } });
    $('btnZout').onclick = () => cy.zoom({ level: Math.max(cy.minZoom(), cy.zoom()/1.3), renderedPosition:{ x:cy.width()/2, y:cy.height()/2 } });
    $('btnPng').onclick  = () => { const a=document.createElement('a');
      a.href = cy.png({ scale:2, full:true, bg:'#fafafa' }); a.download = DATA.trial + '_dag.png'; a.click(); };
    $('btnFull').onclick = () => { const s = $('diagram');
      if (!document.fullscreenElement) s.requestFullscreen?.(); else document.exitFullscreen?.(); };
    document.addEventListener('fullscreenchange', () => setTimeout(() => { cy.resize(); fitv(); }, 90));
    window.addEventListener('resize', () => { cy.resize(); drawAxis(); });

    // live node search: highlight every node whose id/label matches the query as you type,
    // fade the rest. Empty query clears it. Persists under hover (hover restores it on mouseout).
    const searchEl = $('nodeSearch'), countEl = $('searchCount');
    const applySearch = () => {
      const q = searchEl.value.trim().toLowerCase();
      cy.elements().removeClass('search-hit search-dim');
      if (!q) { countEl.textContent = ''; return; }
      const hits = cy.nodes().filter(n => (n.data('id') + ' ' + (n.data('label') || '')).toLowerCase().includes(q));
      cy.elements().addClass('search-dim');
      hits.removeClass('search-dim').addClass('search-hit');
      hits.edgesWith(hits).removeClass('search-dim');            // keep edges between two hits visible
      countEl.textContent = hits.length + (hits.length === 1 ? ' match' : ' matches');
    };
    searchEl.addEventListener('input', applySearch);             // fires on every keystroke (progressive)
    searchEl.addEventListener('search', applySearch);            // fires when the field's ✕ clears it

    const cont = cy.container();
    cy.on('mouseover', 'node', (e) => {
      cont.style.cursor = 'pointer';
      const n = e.target, hood = n.predecessors().union(n.successors()).union(n);
      cy.elements().addClass('faded'); hood.removeClass('faded'); hood.addClass('hl');
    });
    cy.on('mouseout', 'node', () => { cont.style.cursor = ''; cy.elements().removeClass('faded hl'); applySearch(); });
    const jumpToRow = (id) => {                               // scroll to + highlight a DAG-table row
      const tr = dagRows[id]; if (!tr) return;
      document.querySelectorAll('tr.dagrow-hl').forEach(r => r.classList.remove('dagrow-hl'));
      tr.classList.add('dagrow-hl');
      tr.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'center' });
    };
    cy.on('tap', 'node', (e) => jumpToRow(e.target.data('id')));       // click a node  -> its row
    cy.on('tap', 'edge', (e) => jumpToRow(e.target.data('target')));   // click an arrow -> the child's equation row
    cy.on('mouseover', 'edge', () => { cont.style.cursor = 'pointer'; });
    cy.on('mouseout',  'edge', () => { cont.style.cursor = ''; });

    // reverse link: click a variable id in the DAG table -> focus that node in the graph (+ its arrows).
    // covers the Node column AND the Parents column (the arrows into a node).
    const nodeSet = new Set(cy.nodes().map(n => n.data('id')));
    const focusNode = (id) => {
      const n = cy.getElementById(id); if (n.empty()) return;
      document.getElementById('diagram').scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' });
      const hood = n.predecessors().union(n.successors()).union(n);
      cy.elements().addClass('faded'); hood.removeClass('faded'); hood.addClass('hl');
      cy.animate({ center: { eles: n }, zoom: Math.min(cy.maxZoom(), Math.max(cy.zoom(), 1)) },
                 { duration: reduce ? 0 : 450 });
    };
    const artDag = document.querySelector('article[data-md="dag"]');
    if (artDag) artDag.querySelectorAll('table code').forEach(c => {
      const cand = c.textContent.split(',').map(normId).find(k => nodeSet.has(k));
      if (!cand) return;
      c.classList.add('nodelink');
      c.addEventListener('click', () => focusNode(cand));
    });

    const present = new Set(cy.nodes().map(n => n.data('layer')));
    $('legend').innerHTML = ORDER.filter(L => present.has(L))
      .map(L => `<span class="lg"><span class="sw" style="border-color:${LC[L]};background:${LC[L]}33"></span>${LABELS[L]}</span>`).join('');

    run('lanes');                                            // default = layer lanes (left->right by DAG layer)
    setTimeout(() => { fitv(); drawAxis(); }, 120);
  }
</script>
</body></html>"""


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("usage: render_trial_docs.py <trial_output_dir>")
    render(sys.argv[1])
