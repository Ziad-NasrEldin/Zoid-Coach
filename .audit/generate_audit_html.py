from pathlib import Path
import html
import json
import re


ROOT = Path(__file__).resolve().parent.parent
TRACKER = ROOT / "docs" / "zoid-coach-product-scenario-tracker.md"
OUTPUT = ROOT / ".lavish" / "zoid-coach-scenario-audit.html"

STATUS_ORDER = [
    "Fully implemented",
    "Touches remaining",
    "Frontend only left",
    "Partially implemented",
    "Barely started",
    "Not implemented",
    "Blocked from verification",
]

rows = []
section = ""
for line in TRACKER.read_text().splitlines():
    heading = re.match(r"^## (\d+)\. (.+)", line)
    if heading:
        section = f"{heading.group(1)}. {heading.group(2)}"
        continue
    item = re.match(
        r"^- \[([ x])\] (.*?) \*\*Status: (.*?)\.\*\* (.*)$",
        line,
    )
    if item:
        rows.append(
            {
                "checked": item.group(1) == "x",
                "section": section,
                "scenario": item.group(2),
                "status": item.group(3),
                "evidence": item.group(4),
            }
        )

counts = {status: sum(row["status"] == status for row in rows) for status in STATUS_ORDER}
rows_json = json.dumps(rows).replace("</", "<\\/")
cards = "".join(
    f'<button class="metric" data-filter="{html.escape(status)}"><strong>{counts[status]}</strong><span>{html.escape(status)}</span></button>'
    for status in STATUS_ORDER
)

document = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Zoid Coach Scenario Audit</title>
  <style>
    :root {{ --paper:#f7f4ed; --soft:#eee9de; --ink:#171411; --muted:#6f6960; --rule:#cfc7ba; --seal:#9d2f25; --wash:#f1ddd7; --ok:#315d48; }}
    * {{ box-sizing:border-box; }}
    body {{ margin:0; background:var(--paper); color:var(--ink); font-family:ui-serif, Georgia, serif; }}
    header {{ padding:42px clamp(20px,5vw,72px) 30px; border-bottom:2px solid var(--ink); }}
    .eyebrow, th, .status, button, input {{ font-family:ui-monospace, SFMono-Regular, Menlo, monospace; text-transform:uppercase; letter-spacing:.08em; }}
    .eyebrow {{ color:var(--seal); font-size:12px; font-weight:700; }}
    h1 {{ max-width:980px; margin:12px 0 8px; font-size:clamp(40px,6vw,76px); line-height:.94; letter-spacing:-.045em; font-weight:600; }}
    .lede {{ max-width:850px; color:var(--muted); font-size:18px; line-height:1.55; }}
    main {{ padding:28px clamp(20px,5vw,72px) 72px; }}
    .critical {{ padding:18px 20px; background:var(--wash); border:1px solid var(--seal); border-left:8px solid var(--seal); margin-bottom:24px; line-height:1.5; }}
    .critical strong {{ color:var(--seal); }}
    .metrics {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); border:1px solid var(--rule); margin-bottom:24px; }}
    .metric {{ min-width:0; padding:18px; text-align:left; border:0; border-right:1px solid var(--rule); border-bottom:1px solid var(--rule); background:var(--paper); color:var(--ink); cursor:pointer; }}
    .metric:hover, .metric.active {{ background:var(--ink); color:var(--paper); }}
    .metric strong {{ display:block; font-family:ui-serif,Georgia,serif; font-size:34px; letter-spacing:-.04em; }}
    .metric span {{ display:block; margin-top:5px; font-size:9px; line-height:1.35; }}
    .controls {{ display:grid; grid-template-columns:minmax(0,1fr) auto; gap:12px; margin:20px 0; }}
    input {{ min-width:0; width:100%; padding:13px 14px; border:1px solid var(--ink); background:white; font-size:12px; }}
    .clear {{ border:1px solid var(--ink); background:var(--ink); color:var(--paper); padding:0 16px; cursor:pointer; }}
    .result-count {{ color:var(--muted); margin:0 0 10px; }}
    .table-wrap {{ overflow:auto; border:1px solid var(--ink); background:white; }}
    table {{ width:100%; border-collapse:collapse; table-layout:fixed; }}
    th {{ position:sticky; top:0; z-index:2; padding:12px; text-align:left; background:var(--ink); color:var(--paper); font-size:9px; }}
    th:nth-child(1) {{ width:19%; }} th:nth-child(2) {{ width:28%; }} th:nth-child(3) {{ width:17%; }} th:nth-child(4) {{ width:36%; }}
    td {{ padding:14px 12px; vertical-align:top; border-bottom:1px solid var(--rule); line-height:1.42; overflow-wrap:anywhere; }}
    tr:hover td {{ background:var(--soft); }}
    .section {{ color:var(--muted); font-size:12px; }}
    .scenario {{ font-weight:650; }}
    .status {{ display:inline-block; padding:5px 7px; border:1px solid currentColor; font-size:9px; line-height:1.3; }}
    .fully-implemented {{ color:var(--ok); background:#e7efe9; }}
    .not-implemented {{ color:var(--seal); background:var(--wash); }}
    .blocked-from-verification {{ color:#6e4c14; background:#f4ead1; }}
    .evidence {{ color:#47423c; font-size:13px; }}
    .empty {{ display:none; padding:40px; text-align:center; border:1px solid var(--rule); }}
    footer {{ margin-top:20px; color:var(--muted); font-size:13px; }}
    @media (max-width:800px) {{ .controls {{ grid-template-columns:1fr; }} .clear {{ min-height:42px; }} table,thead,tbody,tr,th,td {{ display:block; }} thead {{ display:none; }} tr {{ border-bottom:2px solid var(--ink); }} td {{ border:0; padding:8px 12px; }} td:first-child {{ padding-top:14px; }} td:last-child {{ padding-bottom:16px; }} }}
  </style>
</head>
<body>
  <header>
    <div class="eyebrow">Zoid Coach / End-user usability audit / 12 July 2026</div>
    <h1>{counts['Fully implemented']} of {len(rows)} scenarios are fully usable end to end.</h1>
    <p class="lede">Every scenario was checked against branch <code>codex/remove-atoll-integration</code> at <code>f519b2bd28ce</code>, 188 passing Swift tests, a successful release build, installed version 0.1.0 Build 8, the running agent, live accessibility state, connected local sources, and persistence. Code presence alone never qualified as complete.</p>
  </header>
  <main>
    <div class="critical"><strong>Persistence recovered; behavior freshness later regressed.</strong> The agent restarted onto a healthy 7.99 MB canonical database with the expected schema and no Trash handles. One background verification passed fully after recovery. A later recheck still passed package, signing, LaunchAgent, and Mach-service validation but failed Screenwatch freshness with both Screenwatch processes still running. Untested restart, sleep, crash, outage, and week-long journeys remain incomplete or blocked.</div>
    <div class="metrics">{cards}</div>
    <div class="controls">
      <input id="search" type="search" placeholder="Search scenarios, sections, status, or evidence">
      <button class="clear" id="clear">Clear filters</button>
    </div>
    <p class="result-count" id="count"></p>
    <div class="table-wrap">
      <table>
        <thead><tr><th>Section</th><th>User scenario</th><th>Status</th><th>Evidence and remaining gap</th></tr></thead>
        <tbody id="rows"></tbody>
      </table>
    </div>
    <div class="empty" id="empty">No scenarios match the current filters.</div>
    <footer>The authoritative checklist is <code>docs/zoid-coach-product-scenario-tracker.md</code>. Only “Fully implemented” rows are checked there.</footer>
  </main>
  <script>
    const data = {rows_json};
    const body = document.getElementById('rows');
    const search = document.getElementById('search');
    const count = document.getElementById('count');
    const empty = document.getElementById('empty');
    let active = '';
    const esc = value => value.replace(/[&<>"']/g, char => ({{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}}[char]));
    const slug = value => value.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/(^-|-$)/g,'');
    function render() {{
      const query = search.value.trim().toLowerCase();
      const visible = data.filter(row => (!active || row.status === active) && (!query || Object.values(row).join(' ').toLowerCase().includes(query)));
      body.innerHTML = visible.map(row => `<tr><td class="section">${{esc(row.section)}}</td><td class="scenario">${{row.checked ? '✓ ' : ''}}${{esc(row.scenario)}}</td><td><span class="status ${{slug(row.status)}}">${{esc(row.status)}}</span></td><td class="evidence">${{esc(row.evidence)}}</td></tr>`).join('');
      count.textContent = `${{visible.length}} of ${{data.length}} scenarios shown`;
      empty.style.display = visible.length ? 'none' : 'block';
      document.querySelectorAll('.metric').forEach(button => button.classList.toggle('active', button.dataset.filter === active));
    }}
    document.querySelectorAll('.metric').forEach(button => button.addEventListener('click', () => {{ active = active === button.dataset.filter ? '' : button.dataset.filter; render(); }}));
    search.addEventListener('input', render);
    document.getElementById('clear').addEventListener('click', () => {{ active=''; search.value=''; render(); }});
    render();
  </script>
</body>
</html>
"""

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
OUTPUT.write_text(document)
print(f"Wrote {OUTPUT} with {len(rows)} scenarios")
