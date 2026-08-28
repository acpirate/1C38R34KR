# Concept art

Director-generated, 2026-08-28. Kept for posterity and as input to the first
real art direction. None of it is a specification.

## The four

| | Direction | Relationship to the current build |
| --- | --- | --- |
| `01-hud-wireframe.png` | Cyberpunk HUD — bracketed frames, wireframe glyphs, perspective data-grid | **Redesign.** Same game, different screen. |
| `02-neon-glow.jpg` | Neon on black, heavy bloom, glass board floating over a city grid | **Skin.** The current layout, restyled. |
| `03-terminal-phosphor.jpg` | Monochrome phosphor terminal, scanlines, pictographic Packets | **Skin.** The current layout, restyled. |
| `04-isometric-grid.jpg` | Board in perspective on an infinite tile field, chunky pixel Packets | **Redesign**, and the board's geometry too. |

**That split is the useful part.** Two of the four are asset swaps this
architecture already supports — build a bundle, edit the PNGs and the palette,
switch to it. The other two move UI elements around, add elements that do not
exist (an action bar, pip meters, a net-status panel), or change the board's
projection. Those are layout, and layout is code — a requirements-defined build,
not a skin.

Worth noticing that `02` and `03` are recognisably **the shipped game**: same
header, same two Program columns, same AGIMA row, same message stack, same debug
bar. That is the graphics layer doing its job — a skin changes how everything
looks without touching where anything is.

## What a skin can and cannot do today

**Can, with no code change:**

- every colour, including the six Packet colours via `packet_palette.svg`
- Packet glyph art, filled or outlined, and it need not stay geometric —
  `03`'s flask and flame are legal, because a Packet's identity is *which of
  six*, not what it depicts
- baked glow, scanlines, bevels, texture, wear — anything that is pixels
- frame styles, provided the 9-slice corners stay in the corners

**Cannot, without a code change:**

- **Glow that spills outside its cell.** A glyph is drawn at 0.92 of the cell,
  so a soft bloom has roughly 4% of margin before it clips. `02`'s bloom is
  wider than that. Fixable by drawing glyphs into a larger rect, but it is a
  renderer edit, not an art one.
- **A non-tiling background.** `screen_bg` is TILED so one image serves both a
  1080×2340 phone and a 1200×1920 tablet without distorting. `02` and `04` use
  a single perspective image, which needs a different stretch mode and a
  decision about what happens at other aspect ratios.
- **Anything in `01` or `04` that is not currently on screen.** New panels are
  new layout.
- **Motion.** No animation, particle or shader system exists — all explicitly
  out of scope in 0.3.1. Bloom, scanline shimmer and the board's floating tilt
  are motion, and no still can tell you whether they are right.

## The cheapest route to a shippable look

`02-neon-glow` is closest to the stated goal — something that reads as *cool* to
a prospective playtester — and it is a pure skin apart from the bloom margin and
the background. Both of those are small, bounded renderer edits that could be
folded into whichever build takes this on, rather than a redesign.

`03-terminal-phosphor` is the cheapest of all: monochrome, no bloom, and its
background is flat. It would need no renderer change whatsoever.
