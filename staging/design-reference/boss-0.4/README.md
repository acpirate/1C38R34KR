# Beta 0.4.0 Boss content

Galaxy Tab A (1200×1920), `beta-0.4.0` debug build, 2026-09-02. The seed row and
the `1x / charge / ovl / win / lose / log / skin` bar are debug-only and would
not appear in a release.

| File | Shows |
| --- | --- |
| `00-title.png` | Boss Attack on the title; content fingerprint `83434613-96w` |
| `01-boss-attack-chooser.png` | All four Bosses from content at ICE 350, mode-specific prompt |
| `02-rahndahl-capacitors.png` | Two Capacitor badges; "2 damage to Hacker" — exact 2¹ |
| `03-nehbocyet-logic-bomb.png` | Bottom row cleared and refilled; Logic Bomb armed top-right |
| `04-echofall-colour-hidden.png` | Colour concealed — white shapes, outlines intact, neutrals still static |
| `05-echofall-overlays-visible.png` | Concealed board carrying SHIELD marks and armed countdown digits |
| `06-brainscramble.png` | Blind swap punished: 30 damage, board revealed, move not consumed |

## What these confirm

**The two new marks read.** CAPACITOR's plates and LOGIC BOMB's chevrons are
legible inside the badge at tablet density and are distinct from BOMB's circle,
BUFF's cross, SHIELD and OVERRIDE's slashed ring.

**Concealment masks the axis and nothing else.** `04` and `05` are the pair
worth looking at together: the base Packets lose their colour entirely, while
ownership badges, type marks and countdown digits stay exactly as legible as
they were. That is §8.2's requirement, and it is the part that would have been
easy to get wrong by masking the whole cell.

**The punishment reads as an action, not a dropped input.** `06` shows the log
naming ECHOFALL, the 30 damage, and the board back in colour — with the turn
still the Hacker's.

## Worth a person's judgement

**Shape concealment is not pictured.** The RNG chose COLOUR on every seed
played. Coloured static should be looked at before it is called good.

**RAHNDAHL's clock.** `02` is the second phase, at 2 damage. The curve reaches
256 by the eighth Capacitor against 150 LINK. Whether that is the intended
difficulty or only the intended shape is a tuning question this build did not
answer.
