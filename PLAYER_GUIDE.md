# 1C38R34KR — Player Guide

Welcome to **1C38R34KR**, a mobile-first match-3 combat game with a cyberpunk hacking theme. You play as an elite **Hacker** breaching hostile **Systems** and fighting powerful **Bosses** in high-stakes Runs.

---

## 1. Objective & Game Flow

Your goal is to complete a **Run**: four consecutive battles against escalating security nodes, culminating in a final showdown against a major corporate Boss (**ODANSHAY**).

1. **Choose Your Loadout:** Select a **Hacker** (your combat archetype) and a **Deck** (your program and ability toolkit).
2. **The Route:** Before each battle, choose between two offered path packages containing target **Systems (SYS)**, **HOSTs (HST)**, and **UPGRADEs (UPG)**.
3. **The Build Phase:** Edit and optimize your program loadout against your chosen encounter.
4. **Combat:** Defeat the enemy system by matching tiles on the board, powering programs, and unleashing devastating functions before your ICE (health/integrity) drops to zero.

---

## 2. Core Mechanics: Match-3 & Combat

Battles take place on a grid filled with **Packets** (tiles) defined by two axes: **Color** and **Shape**.

* **Matching (Syncs):** Swap adjacent Packets to form lines of 3 or more matching tiles (either by color or shape). 
* **Charge & Firing:** Matching Packets sends energy and charge to your active **Programs**. When a program reaches full charge, it fires automatically or can be triggered to unleash attacks, shields, or utility effects.
* **ICE (Integrity):** Both you and your enemy have an ICE value (health). Reducing the enemy's ICE to 0 wins the battle. If your ICE hits 0, your run terminates.
* **Weaknesses & Strengths:** Packets and entities have specific strengths and weaknesses. Matching against an enemy's weakness deals extra damage and accelerates your progress.

---

## 3. Choose Your Operatives

### Hackers (Combat Archetypes)
* **CR45H:** Balanced baseline hacker, reliable across all situations.
* **VITRA:** Focuses on sustain, healing, and long-term survivability.
* **RAZE:** Weaponizes **LINK** as a dynamic offensive resource.
* **NEEDLE:** Utilizes tactical **Mines** with specialized trigger profiles for explosive control.

### Decks (Toolkits)
* **AGIMA:** Standard tactical deck for versatile operations.
* **BLEEDLINE:** High-risk offensive toolkit focused on bleeding down enemy defences.
* **BASTION:** Heavy defensive focus with strong shielding and survivability.
* **FUSEBOX:** Rapid charge and energy routing for fast-firing program combos.

---

## 4. Programs & The Build Phase

Programs are your tools in battle: they consume charge earned from **Syncs** (matches of their bound color or shape) and fire a **Function** when full. During the **Build Phase**, you pick your **4 active slots** from **6 candidates** — 3 from your Hacker, 3 from your Deck. Use this window to tailor your loadout to the upcoming System's weaknesses.

Two rules make slot order matter:

* **Charge routes top-to-bottom.** Energy from syncs fills your first slot first, flowing past Programs that are full or whose binding doesn't match. Overflow nothing can accept is wasted. Slot your cheapest or most important trigger on top if you want it to fire first.
* **Shared bindings can spill.** Two Programs bound to the same color make overflow likely — one Program can be full while the other still drinks the stream.

A Program displays its **binding** (color + shape) and its **Function cost** on the build screen — match those against the enemy's board colors and weaknesses.

### Hacker Programs (hacker candidates)

**CR45H** — the baseline kit: board pressure, amplification, precision.

| Program | Binding | Cost | What it does |
| --- | --- | --- | --- |
| BOMBER | RED / Triangle | 7 | Lays **2 bombs** on a 3×3 square with a short **countdown** (2) — delayed area blasts that clear obstacles and threaten the enemy board. |
| BUFFER | GREEN / Square | 8 | Applies **buffs (magnitude 5)** that boost your syncs and effect power — the offense multiplier of the kit. |
| NINJA | MAGENTA / Cross | 7 | **Line slice**: cuts an entire targeted row for direct damage. Grants no charge — it's a pure removal/pressure tool. |

**VITRA** — sustain: heal, shield, and a heal+buff chain.

| Program | Binding | Cost | What it does |
| --- | --- | --- | --- |
| MENDER | GREEN / Square | 6 | Restores your **LINK (ICE)** — 25 health per fire. |
| AEGIS | BLUE / Circle | 7 | Raises **2 shields (magnitude 3)** that absorb incoming damage. |
| SALVE | MAGENTA / Diamond | 8 | Chained: **heals 12** then applies a **small buff (3)** — sustain and amplification in one fire. |

**RAZE** — LINK-as-resource aggression: pay your own health, hurt them back harder.

| Program | Binding | Cost | What it does |
| --- | --- | --- | --- |
| OVERDRAW | RED / Triangle | 4 | Pays **12 of your LINK** (ignores shields!) for **2 strong buffs (magnitude 5)**. Cheap tempo — mind your health. |
| BLOODSPIKE | MAGENTA / Cross | 5 | Pays **15 LINK** to land a **40-damage direct hit**. Your big closer — and it can be lethal to you, so watch the countdown. |
| FLARE | YELLOW / Star | 6 | **2 pressure bombs** on 3×3 squares with a fast fuse (countdown 1) — no self-damage, aggressive board control. |

**NEEDLE** — mine warfare with two distinct trigger profiles.

| Program | Binding | Cost | What it does |
| --- | --- | --- | --- |
| SEEDMINE | GREEN / Star | 6 | Plants **3 mines (18 damage)** that detonate when they are **sliced** — line-clear rewards. |
| TRIPWIRE | YELLOW / Circle | 7 | Plants **2 heavier mines (28 damage)** that detonate when they are **destroyed** (bombs, 4-matches, specials) — **not** slices. Choose your removal deliberately. |
| STAIN | BLUE / Triangle | 5 | Paints **4 packets GREEN**, feeding charge color to SEEDMINE (and other GREEN-bound programs). |

### Deck Programs (deck candidates)

**AGIMA** — the tactical baseline plus a control closer.

| Program | Binding | Cost | What it does |
| --- | --- | --- | --- |
| ATTACKER | YELLOW / Star | 10 | **30 direct damage** to the opponent — your most expensive and most reliable closer, no board dependence. |
| DISABLER | BLUE / Circle | 9 | **Drains every point of charge** from one enemy Program — denies it its firing turn. |
| WEASEL | RED / Circle | 5 | Cheap **cross slice** centered on your target — the cheapest Program in the game, ideal for sniping problem tiles. |

**BLEEDLINE** — direct damage plus shields to keep you in range.

| Program | Binding | Cost | What it does |
| --- | --- | --- | --- |
| LANCET | RED / Triangle | 7 | **22 direct damage** — steady offensive tempo. |
| CLOT | GREEN / Square | 6 | **1 shield (magnitude 4)** — tank a hit to stay in bleeding range. |
| SURGE | YELLOW / Star | 6 | **2 short-fuse buffs (magnitude 4)** — builds match pressure. |

**BASTION** — heavy sustain and control.

| Program | Binding | Cost | What it does |
| --- | --- | --- | --- |
| MENDKIT | GREEN / Square | 5 | Restores **18 LINK**. |
| BULWARK | BLUE / Circle | 8 | **2 heavy shields (magnitude 4)** — the strongest defensive Program in the kit. |
| DAMPEN | MAGENTA / Diamond | 9 | Disables an enemy Program by **removing all its charge** (drain-style control). |

**FUSEBOX** — bombs and charge routing.

| Program | Binding | Cost | What it does |
| --- | --- | --- | --- |
| CHARGEPACK | RED / Triangle | 7 | **2 bombs** on 3×3 squares with countdown 2, that **grant charge when sliced** — damage that still feeds your programs. |
| LONGFUSE | YELLOW / Star | 9 | **1 long-fuse bomb (countdown 4)** detonating across a huge **5×5 square** — telegraphed devastation; plan ahead. |
| CUTTER | BLUE / Circle | 7 | **Line slice** through a targeted row — the same row-cutting power as NINJA. |

### Deck Actives (free at the start)

The deck also provides one **Deck Active** — separate from the four battlefield slots, using pre-charged starting behavior:

* **SCRAMBLE** (AGIMA): rearranges packets across the whole board.
* **TRANSFUSE** (BLEEDLINE): pays LINK, then charges all your other Programs.
* **REINFORCE** (BASTION): bursts 3 quick shields, starting charged.
* **SPARK** (FUSEBOX): instant small bomb that damages *and* charges — fires right away.

### System Programs (what the enemy runs)

Enemies fire the same kinds of tools — worth knowing before you build:

| Program | Binding | What it does |
| --- | --- | --- |
| E-BOMBER | RED / Triangle | Enemy bombs: larger blast ring, slower fuse. |
| SHIELDER | GREEN / Square | Pairs of shields protect the enemy ICE. |
| ATTACKER | YELLOW / Star | 30 direct damage to **your** LINK — same closer you can run yourself. |
| DISABLER | BLUE / Circle | Drains **your** Programs — strips one of your slots of all charge to deny its firing turn. |
| MUSCLE | BLUE / Cross | Converts neutral junk into its own attack axes (feeds the enemy ATTACKER). |
| ENHANCE | MAGENTA / Triangle | Armed bombs that detonate into *buffs* on the enemy's other packets. |
| SPAMBOT | YELLOW / Circle | Swarms 3 small bombs (countdown 1) that also charge the enemy. |
| THROWER | BLUE / Star | Bombs on a 3×3 square with ring spill. |
| PROXMINE | GREEN / Star | Enemy mines that only hurt **you** when they expire. |
| SMOGGER | BLUE / Diamond | **Pollutes 5 packets to neutral junk** — strips your usable syncs. Clear the smog. |

Bosses run bespoke loadouts on top of these (e.g. **MAMMOTH's** TUSK/STOMP direct-pressure kit with FORAGE self-feeding, **ARCHON's** long-fuse SHELLER artillery backed by SIGHT painting and JAMMER drains, **ODANSHAY's** DISABLER/SMOGGER/SHIELDER/ATTACKER overload with an Override threshold that triggers a reboot). Build phase is the time to answer theirs before they answer yours.

---

## 5. Tips for Survival

* **Prep Before You Fight:** Use the Build phase after choosing your path package to tailor your program setup specifically to the upcoming HOST or System weakness.
* **Watch Your Charge:** Don't let excess charge go to waste. Manage your active programs so energy routes efficiently during matching cascades.
* **Beware the Boss:** When you reach Battle 4 against ODANSHAY, watch out for **Overrides** cluttering the board. Clear them out and manage your health before the threshold triggers a system reboot!

*Jack in, match fast, and breach the core.*
