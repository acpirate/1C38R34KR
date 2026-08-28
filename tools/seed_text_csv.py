"""Seeds the v0 text framework CSVs. ONE-SHOT.

    python tools/seed_text_csv.py [--force]

Object names and PASSIVE templates are read from the gameplay sheets so the
seed cannot disagree with them. UI copy is authored below, transcribed verbatim
from the shipped literals — beta 0.3.2 migrates text, it does not rewrite it.

## Why this refuses to overwrite

Authorization §15: once the director imports these into the master workbook,
the workbook is the authoring source and "do not create a second competing
source of truth". Re-running this after that point would silently clobber
authored copy with a regenerated approximation.

So it exists to record HOW v0 was derived, and it will not overwrite an
existing file without --force.
"""

import argparse
import csv
import io
import pathlib
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "data"

NAME_SHEETS = [
    ("prg_h.csv", "PROGRAM_NAME"),
    ("prg_s.csv", "PROGRAM_NAME"),
    ("sys.csv", "SYSTEM_NAME"),
    ("bos.csv", "BOSS_NAME"),
    ("hak.csv", "HACKER_NAME"),
    ("dek.csv", "DECK_NAME"),
    ("hst.csv", "HOST_NAME"),
    ("upg.csv", "UPGRADE_NAME"),
    ("fnc.csv", "FUNCTION_NAME"),
]

# ---------------------------------------------------------------------------
# UI copy, transcribed from the shipped build
# ---------------------------------------------------------------------------
#
# `%d`/`%s` become named tokens. The names describe the VALUE, not its position,
# which is the whole reason for the change: a positional swap is silent and a
# renamed token fails validation.
#
# NOT here, deliberately:
#   - the debug bar, seed field, and [debug] Skip  (§7.3, debug-only)
#   - graphics/palette loader errors               (developer-facing)
#   - the content-validation failure screen        (see NOTE below)
#
# NOTE on the validation screen: it renders when content loading FAILED, and
# text_content.csv loads through that same loader. Its strings must stay
# literals — it is the reporter of last resort and cannot depend on the thing it
# reports on.

UI = [
    # --- title ---
    ("UI_BUTTON_TEXT", "GAME_UI_TITLE_NEW_RUN", "New Run"),
    ("UI_BUTTON_TEXT", "GAME_UI_TITLE_QUICK_CONSTRUCTED", "Constructed Quick Match"),
    ("UI_BUTTON_TEXT", "GAME_UI_TITLE_QUICK_RANDOM", "Random Quick Match"),
    ("UI_BUTTON_TEXT", "GAME_UI_TITLE_CONTINUE_SETUP", "Continue Run — {step} setup"),
    ("UI_BUTTON_TEXT", "GAME_UI_TITLE_CONTINUE_BOSS", "Continue Run — Boss route ready"),
    ("UI_BUTTON_TEXT", "GAME_UI_TITLE_CONTINUE_BATTLE", "Continue Run — battle {current} of {total}"),
    ("UI_BUTTON_TEXT", "GAME_UI_TITLE_CONTINUE_TURN", "Continue — turn {turn}"),
    ("UI_STATUS_TEXT", "GAME_UI_TITLE_CONTENT_STAMP", "content {fingerprint}"),

    # --- selection screens ---
    ("UI_SCREEN_TITLE", "GAME_UI_SYSTEM_SELECT_HEADING", "SELECT SYSTEM"),
    ("UI_SCREEN_PROMPT", "GAME_UI_SYSTEM_SELECT_PROMPT", "Choose the System you will breach"),
    ("UI_SCREEN_TITLE", "GAME_UI_HOST_SELECT_HEADING", "SELECT HOST"),
    ("UI_SCREEN_PROMPT", "GAME_UI_HOST_SELECT_PROMPT", "Choose the HOST you will run from"),
    ("UI_SCREEN_TITLE", "GAME_UI_BOSS_SELECT_HEADING", "SELECT BOSS"),
    ("UI_SCREEN_PROMPT", "GAME_UI_BOSS_SELECT_PROMPT", "The Run ends here. Chosen now, fought last."),
    ("UI_SCREEN_TITLE", "GAME_UI_HACKER_SELECT_HEADING", "SELECT HACKER"),
    ("UI_SCREEN_PROMPT", "GAME_UI_HACKER_SELECT_PROMPT", "Choose who runs this breach"),
    ("UI_SCREEN_TITLE", "GAME_UI_DECK_SELECT_HEADING", "SELECT DECK"),
    ("UI_SCREEN_PROMPT", "GAME_UI_DECK_SELECT_PROMPT", "Choose the Deck you carry"),
    ("UI_BUTTON_TEXT", "GAME_UI_CHOOSER_CONFIRM", "Choose"),
    ("UI_BUTTON_TEXT", "GAME_UI_CHOOSER_BACK", "Back"),

    # --- chooser card lines ---
    ("UI_STATUS_TEXT", "GAME_UI_CARD_ICE", "ICE {ice}"),
    ("UI_STATUS_TEXT", "GAME_UI_CARD_LINK", "LINK {link}"),
    ("UI_STATUS_TEXT", "GAME_UI_CARD_ADD_LINK", "+{link} LINK"),
    ("UI_STATUS_TEXT", "GAME_UI_CARD_FUNCTION", "Function: {function}"),
    ("UI_STATUS_TEXT", "GAME_UI_CARD_STRONG", "Strong: {colors}, {shapes}"),
    ("UI_STATUS_TEXT", "GAME_UI_CARD_WEAK", "Weak:   {colors}, {shapes}"),
    ("UI_STATUS_TEXT", "GAME_UI_CARD_NO_PASSIVES", "no PASSIVEs"),

    # --- build ---
    ("UI_SCREEN_TITLE", "GAME_UI_BUILD_HEADING", "BUILD"),
    ("UI_SCREEN_PROMPT", "GAME_UI_BUILD_PROMPT", "ACTIVE BUILD (top to bottom) — order is charge priority"),
    ("UI_BUTTON_TEXT", "GAME_UI_BUILD_BEGIN_RUN", "Begin battle {step}"),
    ("UI_BUTTON_TEXT", "GAME_UI_BUILD_BEGIN_QUICK", "Begin"),
    ("UI_STATUS_TEXT", "GAME_UI_BUILD_CONTEXT_BATTLE", "Battle {current} of {total}  ·  vs {opponent}  ·  ICE {ice}"),
    ("UI_STATUS_TEXT", "GAME_UI_BUILD_CONTEXT_HOST", "HOST {host}  ·  LINK {link}"),
    ("UI_STATUS_TEXT", "GAME_UI_BUILD_CONTEXT_UPGRADES_NONE", "UPGRADEs: none yet"),
    ("UI_STATUS_TEXT", "GAME_UI_BUILD_CONTEXT_UPGRADES", "UPGRADEs: {upgrades}"),
    ("UI_STATUS_TEXT", "GAME_UI_BUILD_CONTEXT_BOSS", "Boss: {boss}"),

    # --- path choice ---
    ("UI_SCREEN_TITLE", "GAME_UI_PATH_HEADING", "BATTLE {current} OF {total}"),
    ("UI_SCREEN_PROMPT", "GAME_UI_PATH_PROMPT", "Choose your route"),
    ("UI_SCREEN_PROMPT", "GAME_UI_PATH_PROMPT_EXHAUSTED", "Choose your route  ·  one UPGRADE remains, so both paths offer it"),
    ("UI_STATUS_TEXT", "GAME_UI_PATH_BOSS_TAG", "  ·  BOSS"),
    ("UI_STATUS_TEXT", "GAME_UI_PATH_HOST_LINE", "HOST: {host} — {effect}"),
    ("UI_STATUS_TEXT", "GAME_UI_PATH_UPGRADE_LINE", "UPGRADE: {upgrade} — {effect}"),

    # --- battle ---
    ("UI_STATUS_TEXT", "GAME_UI_BATTLE_HACKER", "HACKER"),
    ("UI_STATUS_TEXT", "GAME_UI_BATTLE_LINK", "LINK"),
    ("UI_STATUS_TEXT", "GAME_UI_BATTLE_ICE", "ICE"),
    ("UI_STATUS_TEXT", "GAME_UI_BATTLE_TURN", "Turn {turn}"),
    ("UI_STATUS_TEXT", "GAME_UI_BATTLE_BUFF_TOTAL", "B +{buff}"),
    ("UI_STATUS_TEXT", "GAME_UI_BATTLE_SHIELD_TOTAL", "S {shield}"),
    ("UI_STATUS_TEXT", "GAME_UI_BATTLE_STAT", "{stat} {value}/{maximum}"),
    ("UI_STATUS_TEXT", "GAME_UI_BATTLE_CHARGE", "{charge}/{cost}"),
    ("UI_STATUS_TEXT", "GAME_UI_BATTLE_DAMAGE_TAG", "-{amount}"),

    # --- battle messages ---
    ("UI_STATUS_TEXT", "GAME_UI_MSG_FIRES", "{who} fires {function}"),
    ("UI_STATUS_TEXT", "GAME_UI_MSG_LINE_CLEAR", "  line clear"),
    ("UI_STATUS_TEXT", "GAME_UI_MSG_WITHHELD", "  {who} withheld — {reason}"),
    ("UI_STATUS_TEXT", "GAME_UI_MSG_FIZZLED", "  fizzled"),
    ("UI_STATUS_TEXT", "GAME_UI_MSG_DAMAGE", "  {amount} damage to {target}"),
    ("UI_STATUS_TEXT", "GAME_UI_MSG_SHIELD_ABSORBED", "  shield absorbed {amount}"),
    ("UI_STATUS_TEXT", "GAME_UI_MSG_WINS", "{who} wins"),
    ("UI_STATUS_TEXT", "GAME_UI_MSG_TARGETING", "Choose a Packet — tap the Function again to cancel"),
    ("UI_STATUS_TEXT", "GAME_UI_MSG_TARGETING_CANCELLED", "Targeting cancelled"),
    ("UI_STATUS_TEXT", "GAME_UI_MSG_SAVE_FAILED", "Save failed"),
    ("UI_STATUS_TEXT", "GAME_UI_SIDE_HACKER", "Hacker"),

    # --- pause ---
    ("UI_SCREEN_TITLE", "GAME_UI_PAUSE_HEADING", "PAUSED"),
    ("UI_BUTTON_TEXT", "GAME_UI_PAUSE_RESUME", "Resume"),
    ("UI_BUTTON_TEXT", "GAME_UI_PAUSE_SAVE_QUIT", "Save and Quit"),
    ("UI_STATUS_TEXT", "GAME_UI_PAUSE_MODE_QUICK", "Quick Match"),
    ("UI_STATUS_TEXT", "GAME_UI_PAUSE_MODE_RUN", "Battle {current} of {total} · vs {opponent}"),
    ("UI_STATUS_TEXT", "GAME_UI_PAUSE_MODE_RUN_BOSS", "Battle {current} of {total} · {opponent}"),
    ("UI_STATUS_TEXT", "GAME_UI_SEED_STAMP", "seed {seed} · content {fingerprint}"),

    # --- results ---
    ("UI_SCREEN_TITLE", "GAME_UI_RESULT_VICTORY", "VICTORY"),
    ("UI_SCREEN_TITLE", "GAME_UI_RESULT_DEFEAT", "DEFEAT"),
    ("UI_SCREEN_PROMPT", "GAME_UI_RESULT_QUICK_WIN", "System ICE breached."),
    ("UI_SCREEN_PROMPT", "GAME_UI_RESULT_LOSS", "Hacker LINK severed."),
    ("UI_SCREEN_PROMPT", "GAME_UI_RESULT_RUN_WIN", "{opponent} breached — battle {current} of {total}."),
    ("UI_BUTTON_TEXT", "GAME_UI_RESULT_REPLAY_SEED", "Replay this seed"),
    ("UI_BUTTON_TEXT", "GAME_UI_RESULT_NEW_BATTLE", "New battle"),
    ("UI_BUTTON_TEXT", "GAME_UI_RESULT_BACK_TO_TITLE", "Back to title"),
    ("UI_BUTTON_TEXT", "GAME_UI_RESULT_CONTINUE_RUN", "Continue Run"),
    ("UI_BUTTON_TEXT", "GAME_UI_RESULT_COMPLETE_RUN", "Complete Run"),
    ("UI_BUTTON_TEXT", "GAME_UI_RESULT_RETRY", "Retry battle {step}"),
    ("UI_BUTTON_TEXT", "GAME_UI_RESULT_ABANDON", "Abandon Run"),

    # --- run complete ---
    ("UI_SCREEN_TITLE", "GAME_UI_RUN_COMPLETE_HEADING", "RUN COMPLETE"),
    ("UI_SCREEN_PROMPT", "GAME_UI_RUN_COMPLETE_PROMPT", "{opponent} is breached."),

    # --- pending boss route (beta 0.2 stop point, still reachable from an old save) ---
    # The shipped subheading reads "Boss battle port continues in Beta 0.3",
    # which stopped being true when 0.3 shipped the Boss battle. Replaced here
    # rather than transcribed: migrating a sentence that is now false would be
    # preserving a defect for the sake of fidelity.
    ("UI_SCREEN_TITLE", "GAME_UI_ROUTE_COMMITTED_HEADING", "ROUTE COMMITTED"),
    ("UI_SCREEN_PROMPT", "GAME_UI_ROUTE_COMMITTED_PROMPT", "The Boss route is set. Continue when you are ready."),

    # --- battle report (§1.4 — transcribed verbatim, must render identically) ---
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_BATTLE_HEADING", "BATTLE"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_TURNS", "Turns to resolution: {turns}"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_SYNC_LOCKS", "Sync-locks (auto-reshuffles): {count}"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_DETONATIONS", "Detonations: {count}"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_WITHHOLDS", "System withholds: {count}"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_SHIELDS", "System shields — created {created}, sliced {sliced}"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_SHIELDED_HITS", "Shielded hits: {hits}, damage prevented: {prevented}"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_SIDE_HACKER", "HACKER"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_SIDE_SYSTEM", "SYSTEM"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_TOTAL_DAMAGE", "Total damage dealt: {amount}"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_SYNC_DAMAGE", "Sync-caused (incl. its cascades): {amount}"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_BOMB_DAMAGE", "bomb-caused (incl. its cascades): {amount}"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_LINESLICE_DAMAGE", "line-slice-caused (incl. its cascades): {amount}"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_TRANSFORM_DAMAGE", "transform-caused (incl. its cascades): {amount}"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_FUNCTION_DAMAGE", "Function-caused (incl. its cascades): {amount}"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_PASSIVE_DAMAGE", "PASSIVE-caused: {amount}"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_BUFF_ADDED", "Buff added: {amount}"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_DEEPEST_CASCADE", "Deepest cascade: {rounds} RNG rounds"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_LINE_CLEARS", "Line clears: {count}"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_CONTESTED", "Opponent-bound Packets sliced: {contested} of {destroyed} ({percent}%)"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_CHARGE_WASTED", "Charge wasted (no Program could take it): {amount}"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_UNIT", "{name} [{id}]: fired {fires}, effect {effect}"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_DECK", "{name} [{id} deck]: fired {fires}, neutral charge {charge} (wasted {wasted})"),
    ("UI_STATUS_TEXT", "GAME_UI_REPORT_PASSIVE", "{passive} via {source}: {triggers} trigger(s), {damage} damage"),
]

# ---------------------------------------------------------------------------
# text_style.csv
# ---------------------------------------------------------------------------
#
# NOMINAL_SIZE and MIN_SIZE are in ALPHA CSS PIXELS, scaled by UiTheme.px() at
# load — the unit every existing size in this project is authored in. Device
# pixels would silently pin the game to one viewport.

STYLES = [
    # STYLE_ID, FONT_ROLE, WEIGHT, NOMINAL, MIN, FIT, MAX_LINES, H_ALIGN, COLOR_ROLE
    ("SCREEN_HEADING",      "UI_SANS", "BOLD",    22, 22, "FIXED",  1, "CENTER", "HEADING"),
    ("SCREEN_PROMPT",       "UI_SANS", "REGULAR", 15, 15, "WRAP",   3, "CENTER", "SECONDARY"),
    ("BUTTON_LABEL",        "UI_SANS", "REGULAR", 19, 19, "WRAP",   2, "CENTER", "PRIMARY"),
    ("CARD_BODY",           "UI_SANS", "REGULAR", 19, 19, "WRAP",   6, "LEFT",   "PRIMARY"),
    ("BODY",                "UI_SANS", "REGULAR", 15, 15, "WRAP",   0, "LEFT",   "PRIMARY"),
    ("FOOTNOTE",            "UI_SANS", "REGULAR", 13, 13, "WRAP",   2, "CENTER", "FAINT"),
    ("BATTLE_MESSAGE",      "UI_SANS", "REGULAR", 15, 15, "WRAP",   3, "CENTER", "STATUS"),
    ("PROGRAM_NAME_BATTLE", "UI_SANS", "REGULAR", 11,  8, "SHRINK", 1, "LEFT",   "PRIMARY"),
    ("PROGRAM_CHARGE",      "UI_MONO", "REGULAR",  9,  9, "FIXED",  1, "LEFT",   "SECONDARY"),
    ("AVATAR_TITLE",        "UI_SANS", "REGULAR", 12,  8, "SHRINK", 1, "LEFT",   "PRIMARY"),
    ("AVATAR_STAT",         "UI_MONO", "REGULAR", 12,  8, "SHRINK", 1, "LEFT",   "HEADING"),
    ("AVATAR_TOTALS",       "UI_MONO", "REGULAR", 11, 11, "FIXED",  1, "RIGHT",  "EMPHASIS"),
    ("DAMAGE_TAG",          "UI_SANS", "BOLD",    13, 13, "FIXED",  1, "CENTER", "DAMAGE"),
    ("REPORT_LINE",         "UI_MONO", "REGULAR", 15, 15, "FIXED",  1, "LEFT",   "PRIMARY"),
]

FONTS = [
    ("UI_SANS", "REGULAR", "assets/fonts/IBMPlexSans-Regular.ttf"),
    ("UI_SANS", "BOLD", "assets/fonts/IBMPlexSans-SemiBold.ttf"),
    ("UI_MONO", "REGULAR", "assets/fonts/IBMPlexMono-Regular.ttf"),
]


def object_rows():
    out = []
    for fname, category in NAME_SHEETS:
        rows = list(csv.DictReader(open(DATA / fname, encoding="utf-8")))
        if not rows:
            continue
        idcol = list(rows[0])[0]
        for r in rows:
            rid = (r.get(idcol) or "").strip()
            name = (r.get("name") or "").strip()
            if rid and name:
                out.append((category, rid, name))

    for r in csv.DictReader(open(DATA / "psv.csv", encoding="utf-8")):
        rid = (r.get("PASSIVE_ID") or "").strip()
        disp = (r.get("display") or "").strip()
        if rid and disp:
            out.append(("PASSIVE_TEXT", rid, disp))
    return out


def write(path, header, rows, force):
    if path.exists() and not force:
        print("  SKIP %s (exists; --force to overwrite)" % path.name)
        return False
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)
    print("  wrote %-18s %d rows" % (path.name, len(rows)))
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    content = object_rows() + [(c, r, e) for c, r, e in UI]
    seen = {}
    for cat, rid, _ in content:
        key = (cat, rid)
        if key in seen:
            print("  DUPLICATE %s / %s" % key)
            return 1
        seen[key] = True

    content.sort(key=lambda r: (r[0], r[1]))
    write(DATA / "text_content.csv", ["SEMANTIC_CATEGORY", "REF_ID", "EN"], content, args.force)
    write(
        DATA / "text_style.csv",
        ["STYLE_ID", "FONT_ROLE", "WEIGHT", "NOMINAL_SIZE", "MIN_SIZE", "FIT_MODE", "MAX_LINES", "H_ALIGN", "COLOR_ROLE"],
        STYLES,
        args.force,
    )
    write(DATA / "font_refs.csv", ["FONT_ROLE", "WEIGHT", "FONT_FILE"], FONTS, args.force)

    print("\n  %d content rows (%d object, %d UI)" % (len(content), len(content) - len(UI), len(UI)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
