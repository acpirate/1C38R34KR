# Bundled fonts

**Empty pending Gate B.** The director supplies the binaries; this file records
what they have to satisfy so the requirement is not re-derived.

## What is needed

| Role | Weights | Used by |
| --- | --- | --- |
| `UI_SANS` | Regular + Bold (or SemiBold) | all prose — headings, prompts, buttons, object names, battle messages, result copy |
| `UI_MONO` | Regular | data readouts — charge counters, LINK/ICE, battle-report values, the debug seed row |

Two roles, not three: the title logo and the countdown digits become **art** in
beta 0.3.2, so no display or numeric typeface is required.

## Requirements

- **Format:** `.ttf` or `.otf`, static weights. Not variable — that would add an
  axis question v0 does not need to answer.
- **Licence:** SIL OFL 1.1 or Apache 2.0. Must permit embedding in a distributed
  binary. Anything "free for personal use" is unusable.
- **Coverage:** printable ASCII `U+0020`–`U+007E`, plus exactly three more:

  | Char | Code | Where it appears |
  | --- | --- | --- |
  | `·` | U+00B7 | context separators, seed row |
  | `—` | U+2014 | HOST/UPGRADE card separators, report, targeting prompt |
  | `→` | U+2192 | one battle message |

  The content CSVs are pure ASCII, so that is the entire corpus.

  **`→` is the one likely to be missing.** Many text faces omit arrows. It is
  used once; if a chosen font lacks it the mark gets substituted rather than the
  font rejected.

## Recommended v0

**IBM Plex Sans** (Regular, SemiBold) + **IBM Plex Mono** (Regular) — both SIL
OFL 1.1, one superfamily so the metrics are designed to sit together, both
covering all three non-ASCII characters. Barlow, Inter, JetBrains Mono and Space
Mono are equally acceptable.

The v0 choice is **not** final art direction (authorization §6.2). Its job is to
prove the bundled-font path and give the fitting system real metrics to work
against.

## Dropping them in

Put the files in this directory. `font_refs.csv` maps roles to paths, so nothing
else needs editing when a face is swapped later — that is the point of §6.3.

Coverage is checked mechanically at Gate B: a validator opens each font and
asserts every corpus character resolves to a glyph, so a missing `→` fails on a
build machine rather than on a device.
