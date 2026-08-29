# Asset bundle — `phosphor`

Everything in this folder is art. There is nothing here about the game
engine, and you do not need to know anything about it.

**To make a new skin:** edit the PNGs, and/or the six colours in
`packet_palette.svg`. Keep the file names and folder layout exactly as
they are — the game finds each asset by its path.

## The three rules

**1. Some art is TINTED by the game.** Those files must be authored
**white**, with the shape in the alpha channel. The game multiplies them
by a colour it chooses at runtime — a Packet's colour, or the readable
contrast against whatever it sits on. Authoring them in colour is the one
mistake that produces a wrong-looking game with no error anywhere,
because the file itself is perfectly valid.

Tinted assets are marked **TINT** in the table below.

**2. Keep the pixel dimensions** unless you have a reason. Sizes are
listed below. It matters most for anything marked **9-slice**: that art
has a fixed border and a stretchy middle, and the border width is
measured in source pixels. Double the image and you double the border.

**3. Transparency is real.** PNG alpha is used throughout — a shape on a
transparent ground, not a shape on a coloured square.

## Pairs that must stay different from each other

Some assets carry meaning only by CONTRAST with another asset. A recolour
that treats each file on its own can leave both valid and the game
unreadable — every check will pass and a player will not be able to tell
two states apart.

| These | Must differ because |
| --- | --- |
| `bar_fill_link` vs `bar_fill_ice` | They are the two sides' health, side by side in the header. Same colour means you cannot tell who is winning. |
| `badge_player` vs `badge_enemy` | The ONLY signal of who owns an overlay. One must read light, the other dark. |
| the four `program_box_*` | Idle, charged, yours-and-charged, armed. Four states of the same control. |
| `button_selected` vs `button_disabled` | Chosen versus unavailable. Differing only in brightness is what made this ambiguous before. |
| the six palette colours | Packet identity. Two that read alike make a match ambiguous. |

## The palette

`packet_palette.svg` holds the **six Packet colours** and opens in
Inkscape or any SVG editor. Change the fills; do not rename the swatch
IDs, and do not add or remove swatches. Their order is meaningful to the
game, so recolour in place rather than rearranging.

These six are the only colours the game reads from outside the images.
Every other colour lives in the PNG that uses it.

## The assets

| File | Size | Notes | What it is |
| --- | --- | --- | --- |
| `chrome/screen_bg.png` | 256×256 | — | Full-screen ground. TILED, so it must be seamless. |
| `chrome/panel.png` | 48×48 | 9-slice 16 | The box every menu and the pause menu sit in. |
| `chrome/button_normal.png` | 48×48 | 9-slice 16 | Button, at rest. |
| `chrome/button_pressed.png` | 48×48 | 9-slice 16 | Button, held down. |
| `chrome/button_selected.png` | 48×48 | 9-slice 16 | Button, chosen. Must differ from disabled by more than brightness. |
| `chrome/button_disabled.png` | 48×48 | 9-slice 16 | Button, unavailable. |
| `chrome/rule.png` | 64×8 | — | Horizontal divider. Stretched across, drawn ~2px tall. |
| `chrome/scroll_track.png` | 32×32 | 9-slice 12 | Scrollbar groove. |
| `chrome/scroll_thumb.png` | 32×32 | 9-slice 12 | Scrollbar handle. |
| `chrome/bar_track.png` | 32×16 | 9-slice 6 | Empty part of any meter. |
| `chrome/bar_fill_link.png` | 32×16 | 9-slice 6 | The Hacker's LINK meter fill. |
| `chrome/bar_fill_ice.png` | 32×16 | 9-slice 6 | The opponent's ICE meter fill. |
| `chrome/bar_fill_charge.png` | 32×16 | 9-slice 6 | A Program's charge fill, still filling. |
| `chrome/bar_fill_charge_ready.png` | 32×16 | 9-slice 6 | A Program's charge fill, full. |
| `chrome/title_logo.png` | 1114×130 | **TINT** | The wordmark on the start screen. Any size; aspect is preserved. |
| `battle/avatar_box.png` | 48×48 | 9-slice 16 | Frame around HACKER / opponent name and meter. |
| `battle/program_box_idle.png` | 48×48 | 9-slice 16 | Program control, not yet charged. |
| `battle/program_box_charged.png` | 48×48 | 9-slice 16 | Program charged — the opponent's, or not yours to fire. |
| `battle/program_box_ready.png` | 48×48 | 9-slice 16 | Program charged AND yours to fire. The strongest of the four. |
| `battle/program_box_armed.png` | 48×48 | 9-slice 16 | Program armed, waiting for you to pick a target. |
| `battle/board_surround.png` | 64×64 | — | Behind the board. TILED, and shows through the gaps — this IS the grid. |
| `battle/packet_cell.png` | 64×64 | 9-slice 16 | The cell a Packet sits on. Drawn even when the cell is empty. |
| `battle/build_slot.png` | 48×48 | 9-slice 16 | Active Build slot. The accent bar down its left edge is load-bearing. |
| `packet/glyph_circle.png` | 128×128 | **TINT** | Packet shape. See TINTED note. |
| `packet/glyph_square.png` | 128×128 | **TINT** | Packet shape. |
| `packet/glyph_triangle.png` | 128×128 | **TINT** | Packet shape. |
| `packet/glyph_diamond.png` | 128×128 | **TINT** | Packet shape. |
| `packet/glyph_star.png` | 128×128 | **TINT** | Packet shape. |
| `packet/glyph_cross.png` | 128×128 | **TINT** | Packet shape. |
| `packet/ring_selected.png` | 64×64 | 9-slice 12 | Ring around the Packet you tapped. |
| `packet/ring_targeting.png` | 64×64 | 9-slice 12 | Ring around a Packet you may target. |
| `overlay/badge_player.png` | 128×128 | — | Ownership disc, Hacker. LIGHT fill, dark ring. Not tinted. |
| `overlay/badge_enemy.png` | 128×128 | — | Ownership disc, opponent. DARK fill, light ring. Not tinted. |
| `overlay/mark_bomb.png` | 64×64 | **TINT** | Bomb, inside the badge. |
| `overlay/mark_buff.png` | 64×64 | **TINT** | Buff, inside the badge. |
| `overlay/mark_shield.png` | 64×64 | **TINT** | Shield, inside the badge. |
| `overlay/mark_override.png` | 64×64 | **TINT** | Boss Override, inside the badge. |
| `overlay/ring_bomb.png` | 128×128 | **TINT** | SUSPENDED — retained, not drawn. See D-037. |
| `overlay/ring_buff.png` | 128×128 | **TINT** | SUSPENDED — retained, not drawn. |
| `overlay/ring_shield.png` | 128×128 | **TINT** | SUSPENDED — retained, not drawn. |
| `overlay/ring_override.png` | 128×128 | **TINT** | SUSPENDED — retained, not drawn. |
| `overlay/digit_0.png` | 96×96 | **TINT** | Countdown numeral, inside the badge. |
| `overlay/digit_1.png` | 96×96 | **TINT** | Countdown numeral. |
| `overlay/digit_2.png` | 96×96 | **TINT** | Countdown numeral. |
| `overlay/digit_3.png` | 96×96 | **TINT** | Countdown numeral. |
| `overlay/digit_4.png` | 96×96 | **TINT** | Countdown numeral. |
| `overlay/digit_5.png` | 96×96 | **TINT** | Countdown numeral. |
| `overlay/digit_6.png` | 96×96 | **TINT** | Countdown numeral. |
| `overlay/digit_7.png` | 96×96 | **TINT** | Countdown numeral. |
| `overlay/digit_8.png` | 96×96 | **TINT** | Countdown numeral. |
| `overlay/digit_9.png` | 96×96 | **TINT** | Countdown numeral. |
| `icon/menu.png` | 64×64 | — | Pause control in the battle header. |
| `icon/arrow_up.png` | 64×64 | — | Move a Build slot earlier. |
| `icon/arrow_down.png` | 64×64 | — | Move a Build slot later. |
| `icon/cancel.png` | 64×64 | — | Cancel targeting, on an armed Program. |

## Sending it back

Zip the folder and return it whole. Nothing else is needed — no export
settings, no manifest, no naming convention beyond keeping the paths.
