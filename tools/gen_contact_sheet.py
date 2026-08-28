"""Builds the Gate-B contact sheet for Asset Pack v0.

    python tools/gen_contact_sheet.py <output.html>

Embeds every PNG as a data URI so the page is self-contained and can be
published for inspection on a device without a file browser. Reads the
manifest the Godot generator wrote, so the page cannot describe a pack
different from the one on disk.
"""

import base64
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PACK = ROOT / "assets" / "packs" / "v0"
SHEETS = ROOT / "staging" / "gate-b"

GROUPS = [
    ("chrome", "Screen chrome", "Panels, buttons, bars and scrollbars. Converting these five primitives converts all fifteen menu screens at once."),
    ("battle", "Battle chrome", "The Program and status boxes, the board surround, the cell a Packet sits on, and the Build slot."),
    ("packet", "Packet", "Six glyphs and two selection rings. Every glyph is monochrome and tinted at runtime — colour and shape stay independent."),
    ("overlay", "Overlays", "Ownership badges and the four type marks, which compose over a Packet rather than replacing it. The four ring_* textures are retained but NOT displayed — the type ring is suspended pending a designer decision, and &quot;not now&quot; is not &quot;never&quot;."),
    ("icon", "Icons", "Four marks that were characters in the whitebox."),
]

SHEET_NOTES = [
    ("sheet_packet_matrix.png", "The tint mechanism",
     "Six glyph textures × six palette entries = thirty-six Packets. If this needed thirty-six PNGs the architecture would be wrong. Each glyph carries a white core and a grey outline in one image, so a single multiply produces the fill and a proportionally darker edge."),
    ("sheet_overlay_composition.png", "Type, carried by the mark alone",
     "The type ring is suspended (D-037) — the alpha never had one, and it was widening the overlay by about a third, which is why a diamond used to disappear underneath it. Type now rides the centre mark, as in the alpha, and those four marks are art rather than font characters (D-038). Left column is Hacker-owned, right is System-owned; rows are BOMB, BUFF, SHIELD, OVERRIDE."),
    ("sheet_title_logo.png", "The wordmark",
     "Rasterised from IBM Plex Sans SemiBold at build time, tracked, cropped, and authored white with alpha so it can be tinted and composed over whatever background arrives later. It is art at runtime — the start screen loads no font to draw it."),
    ("sheet_countdown_digits.png", "Countdown digits, both polarities",
     "Ten individually addressable assets keyed by digit, rasterised from IBM Plex Mono so they ARE the game's own numerals rather than a lookalike. Shown at real badge size on a Packet: top row Hacker-owned, bottom row System-owned. After this the board depends on no typeface at all."),
    ("sheet_scale_check.png", "Two scales, one texture",
     "A glyph draws at ~118 px on the board and ~30 px as the binding swatch in a Program box. Top row is the board case, bottom is the swatch. Shape and colour survive the small case; the outline averages away."),
]


def data_uri(path):
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def palette():
    svg = (PACK / "packet_palette.svg").read_text(encoding="utf-8")
    out = []
    for name in ["red", "yellow", "magenta", "green", "cyan", "blue"]:
        m = re.search(r'id="packet_%s"[^>]*?fill="(#[0-9a-fA-F]{6})"' % name, svg)
        if not m:
            m = re.search(r'id="packet_%s"[^>]*?fill:\s*(#[0-9a-fA-F]{6})' % name, svg)
        out.append((name.upper(), m.group(1) if m else "??????"))
    return out


def card(asset):
    src = data_uri(PACK / asset["path"])
    slice_m = asset.get("slice", 0)
    stretch = asset.get("stretch", "") or ("9-slice %d" % slice_m if slice_m else "uniform")
    alpha = "alpha" if asset["alpha"] else "opaque"
    return f"""      <figure class="card" data-slice="{slice_m}" data-w="{asset['w']}" data-h="{asset['h']}">
        <div class="tile">
          <img src="{src}" alt="{asset['key']}">
          <span class="guide guide-v" style="left:0"></span><span class="guide guide-v" style="right:0"></span>
          <span class="guide guide-h" style="top:0"></span><span class="guide guide-h" style="bottom:0"></span>
        </div>
        <figcaption>
          <span class="key">{asset['key']}</span>
          <span class="meta">{asset['w']}×{asset['h']} · {alpha} · {stretch}</span>
        </figcaption>
      </figure>"""


def build():
    manifest = json.loads((PACK / "manifest.json").read_text(encoding="utf-8"))
    assets = manifest["assets"]

    sheets = "\n".join(
        f"""      <figure class="sheet">
        <img src="{data_uri(SHEETS / fn)}" alt="{title}">
        <figcaption><h3>{title}</h3><p>{note}</p></figcaption>
      </figure>"""
        for fn, title, note in SHEET_NOTES
        if (SHEETS / fn).exists()
    )

    swatches = "\n".join(
        f"""        <div class="swatch"><span class="chip" style="background:{hexv}"></span>
          <span class="key">{i} · {name}</span><span class="meta">{hexv}</span></div>"""
        for i, (name, hexv) in enumerate(palette())
    )

    groups = []
    for folder, title, note in GROUPS:
        rows = [a for a in assets if a["path"].startswith(folder + "/")]
        if not rows:
            continue
        cards = "\n".join(card(a) for a in rows)
        groups.append(f"""    <section class="group">
      <div class="group-head">
        <h3>{title}</h3><span class="count">{len(rows)}</span>
        <p>{note}</p>
      </div>
      <div class="grid">
{cards}
      </div>
    </section>""")

    html = TEMPLATE.format(
        count=manifest["count"],
        build=manifest["build"],
        sheets=sheets,
        swatches=swatches,
        groups="\n".join(groups),
    )
    out = pathlib.Path(sys.argv[1])
    out.write_text(html, encoding="utf-8")
    print("wrote %s (%.1f KB)" % (out, out.stat().st_size / 1024))


TEMPLATE = """<title>Asset Pack v0</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo:wght@500;600;700&family=JetBrains+Mono:wght@400;500;700&display=swap">
<style>
/* Single visual world, deliberately: these assets are authored for a dark
   ground and judging them on a light page would misrepresent them. Every
   colour is taken from the game's own presentation registry. */
:root {{
  --ground: #111118;
  --surface: #1b1b22;
  --raised: #26262e;
  --edge: #3a3a48;
  --edge-bright: #555560;
  --text: #eeeeee;
  --dim: #9a9aa8;
  --faint: #6b6b78;
  --accent: #e0a040;
  --ok: #58c06a;
  --warn: #c05858;
  --ui: 'Archivo', 'Helvetica Neue', Arial, sans-serif;
  --mono: 'JetBrains Mono', ui-monospace, 'Cascadia Code', Consolas, monospace;
}}

* {{ box-sizing: border-box; }}

body {{
  margin: 0;
  background: var(--ground);
  color: var(--text);
  font-family: var(--ui);
  font-size: 15px;
  line-height: 1.55;
  -webkit-font-smoothing: antialiased;
}}

.wrap {{ max-width: 1180px; margin: 0 auto; padding: 0 24px 96px; }}

/* ---- header ---- */
header {{ padding: 56px 0 28px; border-bottom: 1px solid var(--edge); }}
h1 {{
  font-size: clamp(30px, 5vw, 44px);
  font-weight: 700; letter-spacing: -0.02em; margin: 0 0 8px;
  text-wrap: balance;
}}
.lede {{ color: var(--dim); max-width: 62ch; margin: 0 0 22px; }}
.facts {{ display: flex; flex-wrap: wrap; gap: 10px; }}
.fact {{
  font-family: var(--mono); font-size: 12px; letter-spacing: 0.04em;
  background: var(--surface); border: 1px solid var(--edge);
  padding: 5px 11px; color: var(--dim);
}}
.fact b {{ color: var(--accent); font-weight: 500; }}

/* ---- controls ---- */
.controls {{
  position: sticky; top: 0; z-index: 10;
  display: flex; flex-wrap: wrap; gap: 22px; align-items: center;
  background: rgba(17,17,24,0.94);
  backdrop-filter: blur(8px);
  border-bottom: 1px solid var(--edge);
  padding: 12px 0; margin-bottom: 36px;
}}
.ctl {{ display: flex; align-items: center; gap: 8px; }}
.ctl-label {{
  font-family: var(--mono); font-size: 11px; letter-spacing: 0.11em;
  text-transform: uppercase; color: var(--faint);
}}
.seg {{ display: flex; border: 1px solid var(--edge); }}
.seg button {{
  font-family: var(--mono); font-size: 12px;
  background: transparent; color: var(--dim);
  border: 0; padding: 6px 13px; cursor: pointer;
}}
.seg button + button {{ border-left: 1px solid var(--edge); }}
.seg button:hover {{ color: var(--text); background: var(--surface); }}
.seg button[aria-pressed="true"] {{ background: var(--accent); color: #1b1b22; font-weight: 700; }}
.seg button:focus-visible {{ outline: 2px solid var(--accent); outline-offset: 2px; }}

/* ---- sections ---- */
section {{ margin-bottom: 56px; }}
h2 {{
  font-size: 13px; font-family: var(--mono); font-weight: 700;
  letter-spacing: 0.16em; text-transform: uppercase;
  color: var(--accent); margin: 0 0 6px;
}}
.section-note {{ color: var(--dim); max-width: 68ch; margin: 0 0 26px; }}

/* ---- composition sheets ---- */
.sheets {{ display: grid; gap: 30px; }}
.sheet {{
  margin: 0; display: grid; gap: 20px; align-items: start;
  grid-template-columns: minmax(0, 1fr) minmax(0, 300px);
  background: var(--surface); border: 1px solid var(--edge); padding: 20px;
}}
.sheet img {{ display: block; width: 100%; height: auto; }}
.sheet figcaption h3 {{ font-size: 18px; margin: 0 0 8px; letter-spacing: -0.01em; }}
.sheet figcaption p {{ color: var(--dim); font-size: 14px; margin: 0; }}
@media (max-width: 760px) {{ .sheet {{ grid-template-columns: 1fr; }} }}

/* ---- palette ---- */
.palette {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 12px; }}
.swatch {{ display: grid; gap: 6px; background: var(--surface); border: 1px solid var(--edge); padding: 12px; }}
.chip {{ display: block; height: 62px; border: 1px solid rgba(0,0,0,0.45); }}

/* ---- catalog ---- */
.group {{ margin-bottom: 44px; }}
.group-head {{ border-left: 3px solid var(--accent); padding-left: 14px; margin-bottom: 18px; }}
.group-head h3 {{ display: inline; font-size: 19px; margin: 0; letter-spacing: -0.01em; }}
.count {{
  font-family: var(--mono); font-size: 11px; color: var(--faint);
  border: 1px solid var(--edge); padding: 2px 7px; margin-left: 10px;
  vertical-align: 3px;
}}
.group-head p {{ color: var(--dim); font-size: 14px; margin: 6px 0 0; max-width: 70ch; }}

.grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(168px, 1fr)); gap: 14px; }}
.card {{ margin: 0; background: var(--surface); border: 1px solid var(--edge); }}
.tile {{
  position: relative; height: 132px;
  display: flex; align-items: center; justify-content: center;
  background: var(--raised);
  border-bottom: 1px solid var(--edge);
  overflow: hidden;
}}
.tile img {{ max-width: 108px; max-height: 108px; }}

/* Backdrop modes. The alpha checker is the only way to judge a transparent
   edge; the light ground catches a mark authored assuming a dark one. */
body[data-bg="light"] .tile {{ background: #d8d8e2; }}
body[data-bg="alpha"] .tile {{
  background-color: #7a7a86;
  background-image:
    linear-gradient(45deg, #56565f 25%, transparent 25%, transparent 75%, #56565f 75%),
    linear-gradient(45deg, #56565f 25%, transparent 25%, transparent 75%, #56565f 75%);
  background-size: 16px 16px;
  background-position: 0 0, 8px 8px;
}}

body[data-px="on"] .tile img {{ image-rendering: pixelated; }}

/* 9-slice guides sit where the stretchable region begins, so a border that
   would smear under stretching is visible before the renderer depends on it. */
.guide {{ position: absolute; display: none; background: var(--accent); opacity: 0.75; }}
.guide-v {{ top: 0; bottom: 0; width: 1px; }}
.guide-h {{ left: 0; right: 0; height: 1px; }}
body[data-guides="on"] .card[data-slice]:not([data-slice="0"]) .guide {{ display: block; }}

figcaption {{ padding: 10px 12px; display: grid; gap: 2px; }}
.key {{ font-family: var(--mono); font-size: 12.5px; font-weight: 500; color: var(--text); word-break: break-all; }}
.meta {{ font-family: var(--mono); font-size: 11px; color: var(--faint); font-variant-numeric: tabular-nums; }}

footer {{ border-top: 1px solid var(--edge); padding-top: 22px; color: var(--dim); font-size: 14px; }}
footer strong {{ color: var(--accent); font-weight: 600; }}

@media (prefers-reduced-motion: reduce) {{ * {{ transition: none !important; }} }}
</style>

<div class="wrap">
  <header>
    <h1>Asset Pack v0</h1>
    <p class="lede">Every generated asset for the 1C38R34KR graphics layer, shown against the ground it will actually be drawn on. Inspect before the renderer is made to depend on it.</p>
    <div class="facts">
      <span class="fact"><b>{count}</b> PNGs</span>
      <span class="fact">pack <b>v0</b></span>
      <span class="fact">build <b>{build}</b></span>
      <span class="fact">lossless · linear filter</span>
      <span class="fact">Gate <b>B</b></span>
      <span class="fact">4 rings <b>suspended</b></span>
    </div>
  </header>

  <div class="controls">
    <div class="ctl">
      <span class="ctl-label">Backdrop</span>
      <div class="seg" id="bg">
        <button data-v="game" aria-pressed="true">Game</button>
        <button data-v="light" aria-pressed="false">Light</button>
        <button data-v="alpha" aria-pressed="false">Alpha</button>
      </div>
    </div>
    <div class="ctl">
      <span class="ctl-label">Rendering</span>
      <div class="seg" id="px">
        <button data-v="off" aria-pressed="true">Smooth</button>
        <button data-v="on" aria-pressed="false">Pixels</button>
      </div>
    </div>
    <div class="ctl">
      <span class="ctl-label">9-slice guides</span>
      <div class="seg" id="guides">
        <button data-v="off" aria-pressed="true">Off</button>
        <button data-v="on" aria-pressed="false">On</button>
      </div>
    </div>
  </div>

  <section>
    <h2>Composition</h2>
    <p class="section-note">Three things a directory listing cannot show. Each was composited in the engine using the same multiply the renderer will use at runtime, so what is below is what the game will draw.</p>
    <div class="sheets">
{sheets}
    </div>
  </section>

  <section>
    <h2>Palette</h2>
    <p class="section-note">The only externally configurable colours in the game, read from <span class="key">packet_palette.svg</span> at startup. Shown in enum order, which is gameplay identity: a System's weak set is derived as the enum-order complement of its strong set, so an index is not a label. Recolour in place; never reorder.</p>
    <div class="palette">
{swatches}
    </div>
  </section>

  <section>
    <h2>Catalog</h2>
    <p class="section-note">Grouped by the folder each asset lives in. Tiles scale assets to fit — true source dimensions are in each caption.</p>
{groups}
  </section>

  <footer>
    <p><strong>Gate B.</strong> Nothing in the renderer depends on these yet. Approval moves the build to the catalog and conversion phases; rejection means editing <span class="key">tools/gen_assets.gd</span> and regenerating, which is why the pack is generated rather than hand-drawn.</p>
  </footer>
</div>

<script>
(function () {{
  var map = {{ bg: 'bg', px: 'px', guides: 'guides' }};
  Object.keys(map).forEach(function (id) {{
    var group = document.getElementById(id);
    if (!group) return;
    group.addEventListener('click', function (e) {{
      var btn = e.target.closest('button');
      if (!btn) return;
      Array.prototype.forEach.call(group.querySelectorAll('button'), function (b) {{
        b.setAttribute('aria-pressed', String(b === btn));
      }});
      document.body.setAttribute('data-' + map[id], btn.dataset.v);
    }});
  }});
  document.body.setAttribute('data-bg', 'game');
  document.body.setAttribute('data-px', 'off');
  document.body.setAttribute('data-guides', 'off');

  // Place the 9-slice guides from each asset's own margin and source size, so
  // they land where the stretchable region truly begins rather than at a
  // guessed fraction of the tile.
  Array.prototype.forEach.call(document.querySelectorAll('.card'), function (card) {{
    var m = parseInt(card.dataset.slice, 10);
    if (!m) return;
    var img = card.querySelector('img');
    var place = function () {{
      var r = img.getBoundingClientRect();
      var t = card.querySelector('.tile').getBoundingClientRect();
      var sx = r.width / parseInt(card.dataset.w, 10);
      var sy = r.height / parseInt(card.dataset.h, 10);
      var ox = r.left - t.left, oy = r.top - t.top;
      var g = card.querySelectorAll('.guide');
      g[0].style.left = (ox + m * sx) + 'px';
      g[1].style.right = (t.right - r.right + m * sx) + 'px';
      g[2].style.top = (oy + m * sy) + 'px';
      g[3].style.bottom = (t.bottom - r.bottom + m * sy) + 'px';
    }};
    if (img.complete) place(); else img.addEventListener('load', place);
    window.addEventListener('resize', place);
  }});
}})();
</script>
"""

if __name__ == "__main__":
    build()
